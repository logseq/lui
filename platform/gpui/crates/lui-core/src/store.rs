//! The retained node tree: applies wire ops, tracks which nodes changed so the
//! renderer can redraw exactly the dirty entities — never the whole tree.

use std::collections::{BTreeMap, BTreeSet};
use std::fmt;

use crate::wire::{Batch, Op, Value};
use crate::wire_schema::{NodeKind, Property};
use crate::{order::Order, protocol_rules, validation};

/// What a node is: a standard schema kind, or an app-registered extension
/// (`create-extension` op; identifier + fingerprint come from ADR 0002).
#[derive(Debug, Clone)]
pub enum NodeIdentity {
    Standard(NodeKind),
    Extension {
        identifier: String,
        fingerprint: String,
    },
}

impl NodeIdentity {
    pub fn kind(&self) -> Option<NodeKind> {
        match self {
            NodeIdentity::Standard(kind) => Some(*kind),
            _ => None,
        }
    }

    /// Extensions behave like opaque containers unless their spec narrows
    /// children; the store treats every extension as child-capable.
    pub fn accepts_children(&self) -> bool {
        match self {
            NodeIdentity::Standard(kind) => protocol_rules::container_supported(*kind),
            NodeIdentity::Extension { .. } => true,
        }
    }

    pub fn label(&self) -> String {
        match self {
            NodeIdentity::Standard(kind) => kind.wire_name().to_string(),
            NodeIdentity::Extension { identifier, .. } => format!("ext:{identifier}"),
        }
    }
}

/// Standard-schema props (`set-prop`/`remove-prop`).
pub type NodeProps = BTreeMap<Property, Value>;
/// Extension props (`set-extension-prop`/`remove-extension-prop`).
pub type NodeExtensionProps = BTreeMap<String, Value>;

#[derive(Debug, Clone)]
pub struct Node {
    pub id: i64,
    pub identity: NodeIdentity,
    pub props: NodeProps,
    pub extension_props: NodeExtensionProps,
    pub children: Vec<i64>,
    pub parent: Option<i64>,
    /// Explicit model writes to text/value, including equal-value writes.
    /// Renderers use this revision to preserve edits across unrelated redraws.
    pub value_revision: u64,
}

impl Node {
    pub fn prop(&self, property: Property) -> Option<&Value> {
        self.props.get(&property)
    }

    pub fn string_prop(&self, property: Property) -> Option<&str> {
        self.prop(property).and_then(Value::as_str)
    }

    pub fn bool_prop(&self, property: Property) -> Option<bool> {
        self.prop(property).and_then(Value::as_bool)
    }

    pub fn int_prop(&self, property: Property) -> Option<i64> {
        self.prop(property).and_then(Value::as_int)
    }

    pub fn float_prop(&self, property: Property) -> Option<f64> {
        self.prop(property).and_then(Value::as_float)
    }

    /// `true` when the prop exists and is `BoolValue true`.
    pub fn flag(&self, property: Property) -> bool {
        self.bool_prop(property) == Some(true)
    }

    pub fn enabled(&self) -> bool {
        self.bool_prop(Property::Enabled).unwrap_or(true)
    }

    pub fn is_treeitem(&self) -> bool {
        self.string_prop(Property::RoleValue) == Some("treeitem")
    }
}

#[derive(Debug, Clone)]
pub struct BackendError(pub String);

impl fmt::Display for BackendError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for BackendError {}

/// Result of applying one batch: which existing node entities must re-render
/// (`dirty`) and which node ids vanished (`dropped`) so the renderer can
/// release their entities.
#[derive(Debug, Default)]
pub struct Applied {
    pub generation: i64,
    /// Nodes whose props or child list changed — notify their entities.
    pub dirty: BTreeSet<i64>,
    /// Parents whose child sequence changed, distinct from property updates.
    pub structural: BTreeSet<i64>,
    /// Subtree roots + descendants removed by `drop-node`.
    pub dropped: Vec<i64>,
}

#[derive(Default)]
pub struct Store {
    pub nodes: BTreeMap<i64, Node>,
    pub root: Option<i64>,
    pub generation: i64,
}

fn err(message: impl Into<String>) -> BackendError {
    BackendError(message.into())
}

impl Store {
    pub fn node(&self, id: i64) -> Option<&Node> {
        self.nodes.get(&id)
    }

    /// Drop the mirror so the next batch may adopt any positive generation.
    /// Hosts call this before applying a resync snapshot.
    pub fn reset(&mut self) {
        self.nodes.clear();
        self.root = None;
        self.generation = 0;
    }

    /// Apply one runtime batch atomically and advance its generation.
    pub fn apply(&mut self, batch: &Batch) -> Result<Applied, BackendError> {
        if batch.generation <= 0 {
            return Err(err(format!(
                "patch generation {} is not positive",
                batch.generation
            )));
        }
        if self.generation != 0 && batch.generation != self.generation + 1 {
            return Err(err(format!(
                "patch generation {} is not contiguous with {}",
                batch.generation, self.generation
            )));
        }
        let applied = self.apply_ops(&batch.ops, batch.generation)?;
        self.generation = batch.generation;
        Ok(applied)
    }

    /// Apply host DOM mutations atomically without advancing the runtime stream.
    pub fn apply_local(&mut self, ops: &[Op]) -> Result<Applied, BackendError> {
        self.apply_ops(ops, self.generation)
    }

    fn apply_ops(&mut self, ops: &[Op], generation: i64) -> Result<Applied, BackendError> {
        let mut applied = Applied {
            generation,
            ..Applied::default()
        };
        // Keep only the first before-image of each touched node. Property
        // patches stay local while a rejected batch restores every link.
        let root = self.root;
        let mut undo = BTreeMap::new();
        let mut orders = BTreeMap::new();
        let result = (|| {
            for op in ops {
                self.record_before(op, &mut undo, &orders);
                self.apply_op(op, &mut applied, &mut orders)?;
            }
            for (id, order) in &orders {
                if let Some(node) = self.nodes.get_mut(id) {
                    node.children = order.ids();
                }
            }
            let mut affected = BTreeSet::new();
            let mut descend = Vec::new();
            for (&id, previous) in &undo {
                affected.insert(id);
                if let Some(parent) = self.node(id).and_then(|n| n.parent) {
                    if self.node(parent).and_then(|n| n.identity.kind())
                        == Some(NodeKind::ContextMenu)
                    {
                        affected.insert(parent);
                    }
                }
                if self.node(id).and_then(|n| n.parent) != previous.as_ref().and_then(|n| n.parent)
                {
                    descend.push(id);
                }
            }
            let mut visited = BTreeSet::new();
            while let Some(id) = descend.pop() {
                if visited.insert(id) {
                    affected.insert(id);
                    if let Some(node) = self.node(id) {
                        descend.extend(node.children.iter().copied());
                    }
                }
            }
            for id in affected {
                if let Some(node) = self.node(id) {
                    validation::node(self, node)?;
                }
            }
            Ok(())
        })();
        if let Err(error) = result {
            for (id, node) in undo {
                match node {
                    Some(node) => {
                        self.nodes.insert(id, node);
                    }
                    None => {
                        self.nodes.remove(&id);
                    }
                }
            }
            self.root = root;
            return Err(error);
        }
        Ok(applied)
    }

    fn record_before(
        &self,
        op: &Op,
        undo: &mut BTreeMap<i64, Option<Node>>,
        orders: &BTreeMap<i64, Order>,
    ) {
        let mut ids = Vec::new();
        match op {
            Op::CreateNode { id, .. }
            | Op::CreateExtension { id, .. }
            | Op::SetProp { id, .. }
            | Op::RemoveProp { id, .. }
            | Op::SetExtensionProp { id, .. }
            | Op::RemoveExtensionProp { id, .. } => ids.push(*id),
            Op::InsertChild { parent, child, .. } => {
                ids.extend([*parent, *child]);
                ids.extend(self.node(*child).and_then(|node| node.parent));
            }
            Op::RemoveChild { parent, child } => ids.extend([*parent, *child]),
            Op::MoveChild { parent, .. } => ids.push(*parent),
            Op::DropNode { id } | Op::DetachSubtree { id } => {
                ids.extend(self.node(*id).and_then(|node| node.parent));
                let mut stack = vec![*id];
                while let Some(id) = stack.pop() {
                    ids.push(id);
                    if let Some(node) = self.node(id) {
                        stack.extend(
                            orders
                                .get(&id)
                                .map_or_else(|| node.children.clone(), Order::ids),
                        );
                    }
                }
            }
        }
        for id in ids {
            undo.entry(id).or_insert_with(|| self.node(id).cloned());
        }
    }

    fn apply_op(
        &mut self,
        op: &Op,
        applied: &mut Applied,
        orders: &mut BTreeMap<i64, Order>,
    ) -> Result<(), BackendError> {
        match op {
            Op::CreateNode { id, kind } => {
                let kind = NodeKind::from_wire(kind)
                    .ok_or_else(|| err(format!("create-node {id}: unknown kind '{kind}'")))?;
                self.create_node(*id, NodeIdentity::Standard(kind), applied)?;
                if kind == NodeKind::Root {
                    self.root = Some(*id);
                }
            }
            Op::CreateExtension {
                id,
                identifier,
                fingerprint,
            } => {
                self.create_node(
                    *id,
                    NodeIdentity::Extension {
                        identifier: identifier.clone(),
                        fingerprint: fingerprint.clone(),
                    },
                    applied,
                )?;
            }
            // drop_node already unlinks the root from its parent and
            // removes the whole subtree recursively — exactly the
            // detach-subtree contract.
            Op::DropNode { id } | Op::DetachSubtree { id } => {
                self.drop_node(*id, applied, orders)?
            }
            Op::SetProp {
                id,
                property,
                value,
            } => {
                let property = Property::from_wire(property)
                    .ok_or_else(|| err(format!("set-prop {id}: unknown property '{property}'")))?;
                let node = self
                    .nodes
                    .get_mut(id)
                    .ok_or_else(|| err(format!("set-prop: unknown node {id}")))?;
                validation::property(
                    node.identity
                        .kind()
                        .ok_or_else(|| err("standard property targets extension node"))?,
                    property,
                    Some(value),
                )?;
                node.props.insert(property, value.clone());
                if matches!(property, Property::TextValue | Property::ProgressValue) {
                    node.value_revision = node.value_revision.wrapping_add(1);
                }
                applied.dirty.insert(*id);
            }
            Op::RemoveProp { id, property } => {
                let property = Property::from_wire(property).ok_or_else(|| {
                    err(format!("remove-prop {id}: unknown property '{property}'"))
                })?;
                let node = self
                    .nodes
                    .get_mut(id)
                    .ok_or_else(|| err(format!("remove-prop: unknown node {id}")))?;
                validation::property(
                    node.identity
                        .kind()
                        .ok_or_else(|| err("standard property targets extension node"))?,
                    property,
                    None,
                )?;
                node.props.remove(&property);
                if matches!(property, Property::TextValue | Property::ProgressValue) {
                    node.value_revision = node.value_revision.wrapping_add(1);
                }
                applied.dirty.insert(*id);
            }
            Op::SetExtensionProp {
                id,
                property,
                value,
            } => {
                let node = self
                    .nodes
                    .get_mut(id)
                    .ok_or_else(|| err(format!("set-extension-prop: unknown node {id}")))?;
                if node.identity.kind().is_some() {
                    return Err(err("extension property targets standard node"));
                }
                node.extension_props.insert(property.clone(), value.clone());
                if matches!(property.as_str(), "text" | "value") {
                    node.value_revision = node.value_revision.wrapping_add(1);
                }
                applied.dirty.insert(*id);
            }
            Op::RemoveExtensionProp { id, property } => {
                let node = self
                    .nodes
                    .get_mut(id)
                    .ok_or_else(|| err(format!("remove-extension-prop: unknown node {id}")))?;
                if node.identity.kind().is_some() {
                    return Err(err("extension property targets standard node"));
                }
                node.extension_props.remove(property);
                if matches!(property.as_str(), "text" | "value") {
                    node.value_revision = node.value_revision.wrapping_add(1);
                }
                applied.dirty.insert(*id);
            }
            Op::InsertChild {
                parent,
                child,
                index,
            } => {
                self.attach(*parent, *child, *index, applied, orders)?;
            }
            Op::RemoveChild { parent, child } => {
                self.detach(*parent, *child, applied, orders)?;
            }
            Op::MoveChild {
                parent,
                child,
                index,
            } => {
                self.move_child(*parent, *child, *index, applied, orders)?;
            }
        }
        Ok(())
    }

    fn create_node(
        &mut self,
        id: i64,
        identity: NodeIdentity,
        applied: &mut Applied,
    ) -> Result<(), BackendError> {
        if self.nodes.contains_key(&id) {
            return Err(err(format!("create-node: duplicate node {id}")));
        }
        self.nodes.insert(
            id,
            Node {
                id,
                identity,
                props: BTreeMap::new(),
                extension_props: BTreeMap::new(),
                children: Vec::new(),
                parent: None,
                value_revision: 0,
            },
        );
        applied.dirty.insert(id);
        Ok(())
    }

    fn drop_node(
        &mut self,
        id: i64,
        applied: &mut Applied,
        orders: &mut BTreeMap<i64, Order>,
    ) -> Result<(), BackendError> {
        // Collect the whole subtree before mutating links.
        let mut stack = vec![id];
        let mut subtree = Vec::new();
        while let Some(current) = stack.pop() {
            let node = self
                .nodes
                .get(&current)
                .ok_or_else(|| err(format!("drop-node: unknown node {current}")))?;
            subtree.push(current);
            stack.extend(
                orders
                    .get(&current)
                    .map_or_else(|| node.children.clone(), Order::ids),
            );
        }
        if let Some(parent) = self.nodes.get(&id).and_then(|node| node.parent) {
            self.detach(parent, id, applied, orders)?;
        }
        for current in subtree {
            self.nodes.remove(&current);
            orders.remove(&current);
            applied.dirty.remove(&current);
            applied.dropped.push(current);
        }
        if self.root == Some(id) {
            self.root = None;
        }
        Ok(())
    }

    fn is_ancestor(&self, maybe_ancestor: i64, node: i64) -> bool {
        let mut current = Some(node);
        while let Some(id) = current {
            if id == maybe_ancestor {
                return true;
            }
            current = self.nodes.get(&id).and_then(|node| node.parent);
        }
        false
    }

    fn attach(
        &mut self,
        parent: i64,
        child: i64,
        index: i64,
        applied: &mut Applied,
        orders: &mut BTreeMap<i64, Order>,
    ) -> Result<(), BackendError> {
        let parent_node = self
            .nodes
            .get(&parent)
            .ok_or_else(|| err(format!("insert-child: unknown parent {parent}")))?;
        if !parent_node.identity.accepts_children() {
            return Err(err(format!(
                "insert-child: parent {parent} ({}) does not accept children",
                parent_node.identity.label()
            )));
        }
        if !self.nodes.contains_key(&child) {
            return Err(err(format!("insert-child: unknown child {child}")));
        }
        let child_node = self.node(child).expect("checked above");
        if let (Some(parent_kind), Some(child_kind)) =
            (parent_node.identity.kind(), child_node.identity.kind())
        {
            if !protocol_rules::child_supported(parent_kind, child_kind) {
                return Err(err("unsupported parent/child kind pair"));
            }
        } else if child_node.identity.kind() == Some(NodeKind::Root) {
            return Err(err("runtime root cannot have a parent"));
        }
        if self.is_ancestor(child, parent) {
            return Err(err(format!(
                "insert-child: {child} is an ancestor of {parent} (cycle)"
            )));
        }
        let length = orders
            .get(&parent)
            .map_or(parent_node.children.len(), Order::len);
        let same_parent = child_node.parent == Some(parent);
        if index < 0 || index as usize > length - usize::from(same_parent) {
            return Err(err("insert-child index is out of bounds"));
        }
        // A re-parent is expressed as insert on the new parent: detach first.
        if let Some(old_parent) = self.nodes.get(&child).and_then(|node| node.parent) {
            self.detach(old_parent, child, applied, orders)?;
        }
        let parent_node = self.nodes.get_mut(&parent).expect("checked above");
        orders
            .entry(parent)
            .or_insert_with(|| Order::new(&parent_node.children))
            .insert(index as usize, child);
        self.nodes.get_mut(&child).expect("checked above").parent = Some(parent);
        applied.dirty.insert(parent);
        applied.structural.insert(parent);
        Ok(())
    }

    fn detach(
        &mut self,
        parent: i64,
        child: i64,
        applied: &mut Applied,
        orders: &mut BTreeMap<i64, Order>,
    ) -> Result<(), BackendError> {
        let parent_node = self
            .nodes
            .get_mut(&parent)
            .ok_or_else(|| err(format!("remove-child: unknown parent {parent}")))?;
        let order = orders
            .entry(parent)
            .or_insert_with(|| Order::new(&parent_node.children));
        if !order.remove(child) {
            return Err(err(format!(
                "remove-child: node {child} is not a child of {parent}"
            )));
        }
        if let Some(child_node) = self.nodes.get_mut(&child) {
            child_node.parent = None;
        }
        applied.dirty.insert(parent);
        applied.structural.insert(parent);
        Ok(())
    }

    fn move_child(
        &mut self,
        parent: i64,
        child: i64,
        index: i64,
        applied: &mut Applied,
        orders: &mut BTreeMap<i64, Order>,
    ) -> Result<(), BackendError> {
        let parent_node = self
            .nodes
            .get_mut(&parent)
            .ok_or_else(|| err(format!("move-child: unknown parent {parent}")))?;
        let order = orders
            .entry(parent)
            .or_insert_with(|| Order::new(&parent_node.children));
        if order.index(child).is_none() {
            return Err(err("move-child targets a non-child"));
        }
        if index < 0 || index as usize >= order.len() {
            return Err(err("move-child index is out of bounds"));
        }
        order.move_to(child, index as usize);
        applied.dirty.insert(parent);
        applied.structural.insert(parent);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wire::decode_batch;

    fn apply_json(store: &mut Store, json: &str) -> Applied {
        let batch = decode_batch(json).expect("batch decodes");
        store.apply(&batch).expect("batch applies")
    }

    fn children_of(store: &Store, id: i64) -> Vec<i64> {
        store.node(id).expect("node exists").children.clone()
    }

    #[test]
    fn empty_dialog_is_rejected() {
        let mut store = Store::default();
        let batch = decode_batch(r#"{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"root"},
            {"op":"create-node","id":2,"kind":"dialog"},
            {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}"#).unwrap();
        assert!(store.apply(&batch).is_err());
    }

    #[test]
    fn property_patch_preserves_unrelated_payload_storage() {
        let mut store = Store::default();
        apply_json(
            &mut store,
            r#"{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"column"},
            {"op":"create-node","id":2,"kind":"text"},
            {"op":"set-prop","id":2,"property":"text","value":"Unchanged payload"}
        ]}"#,
        );
        let before = store
            .node(2)
            .unwrap()
            .string_prop(Property::TextValue)
            .unwrap()
            .as_ptr();
        apply_json(
            &mut store,
            r#"{"generation":2,"ops":[
            {"op":"set-prop","id":1,"property":"width","value":400}
        ]}"#,
        );
        let after = store
            .node(2)
            .unwrap()
            .string_prop(Property::TextValue)
            .unwrap()
            .as_ptr();
        assert_eq!(
            before, after,
            "a local patch must not reallocate unrelated payloads"
        );
    }

    #[test]
    fn rejected_batch_restores_reparented_and_dropped_nodes_and_root() {
        let mut store = Store::default();
        apply_json(
            &mut store,
            r#"{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"root"},
            {"op":"create-node","id":2,"kind":"column"},
            {"op":"create-node","id":3,"kind":"text"},
            {"op":"insert-child","parent":1,"child":2,"index":0},
            {"op":"insert-child","parent":2,"child":3,"index":0}
        ]}"#,
        );
        let before = format!("{:?}", store.nodes);
        let batch = decode_batch(
            r#"{"generation":2,"ops":[
            {"op":"insert-child","parent":1,"child":3,"index":0},
            {"op":"drop-node","id":1},
            {"op":"create-node","id":1,"kind":"root"},
            {"op":"create-node","id":4,"kind":"text"},
            {"op":"set-prop","id":99,"property":"text","value":"Reject"}
        ]}"#,
        )
        .unwrap();
        assert!(store.apply(&batch).is_err());
        assert_eq!(format!("{:?}", store.nodes), before);
        assert_eq!(store.root, Some(1));
        assert_eq!(store.generation, 1);
    }

    #[test]
    fn create_attach_and_prop_ops_build_the_tree() {
        let mut store = Store::default();
        let applied = apply_json(
            &mut store,
            r#"{"generation": 1, "ops": [
                {"op": "create-node", "id": 1, "kind": "root"},
                {"op": "create-node", "id": 2, "kind": "column"},
                {"op": "create-node", "id": 3, "kind": "text"},
                {"op": "insert-child", "parent": 1, "child": 2, "index": 0},
                {"op": "insert-child", "parent": 2, "child": 3, "index": 0},
                {"op": "set-prop", "id": 3, "property": "text",
                 "value": "hello"},
                {"op": "set-prop", "id": 2, "property": "gap", "value": 8},
                {"op": "set-prop", "id": 3,
                 "property": "style-class", "value": "text-sm"}
            ]}"#,
        );
        assert_eq!(applied.generation, 1);
        assert_eq!(store.root, Some(1));
        assert_eq!(children_of(&store, 1), vec![2]);
        assert_eq!(children_of(&store, 2), vec![3]);
        let text = store.node(3).expect("text node");
        assert_eq!(text.parent, Some(2));
        assert_eq!(text.string_prop(Property::TextValue), Some("hello"));
        assert_eq!(
            text.prop(Property::StyleClass),
            Some(&Value::Str("text-sm".into()))
        );
        assert_eq!(store.node(2).unwrap().float_prop(Property::Gap), Some(8.0));
        // Structural ops + every touched node are dirty.
        assert!(applied.dirty.contains(&1));
        assert!(applied.dirty.contains(&2));
        assert!(applied.dirty.contains(&3));
    }

    #[test]
    fn prop_updates_overwrite_and_remove() {
        let mut store = Store::default();
        apply_json(
            &mut store,
            r#"{"generation": 1, "ops": [
                {"op": "create-node", "id": 1, "kind": "root"},
                {"op": "create-node", "id": 2, "kind": "button"},
                {"op": "insert-child", "parent": 1, "child": 2, "index": 0},
                {"op": "set-prop", "id": 2, "property": "text",
                 "value": "before"},
                {"op": "create-extension", "id": 3, "identifier": "test-widget", "fingerprint": "test"},
                {"op": "set-extension-prop", "id": 3, "property": "k",
                 "value": 1}
            ]}"#,
        );
        apply_json(
            &mut store,
            r#"{"generation": 2, "ops": [
                {"op": "set-prop", "id": 2, "property": "text",
                 "value": "after"},
                {"op": "remove-prop", "id": 2, "property": "enabled"},
                {"op": "set-extension-prop", "id": 3, "property": "k",
                 "value": 2},
                {"op": "remove-extension-prop", "id": 3, "property": "k"}
            ]}"#,
        );
        let node = store.node(2).unwrap();
        assert_eq!(node.string_prop(Property::TextValue), Some("after"));
        assert!(node.prop(Property::Enabled).is_none());
        assert!(!store.node(3).unwrap().extension_props.contains_key("k"));
    }

    #[test]
    fn drop_node_removes_the_whole_subtree() {
        let mut store = Store::default();
        apply_json(
            &mut store,
            r#"{"generation": 1, "ops": [
                {"op": "create-node", "id": 1, "kind": "column"},
                {"op": "create-node", "id": 2, "kind": "column"},
                {"op": "create-node", "id": 3, "kind": "text"},
                {"op": "create-node", "id": 4, "kind": "text"},
                {"op": "insert-child", "parent": 1, "child": 2, "index": 0},
                {"op": "insert-child", "parent": 2, "child": 3, "index": 0},
                {"op": "insert-child", "parent": 3, "child": 4, "index": 0}
            ]}"#,
        );
        let applied = apply_json(
            &mut store,
            r#"{"generation": 2, "ops": [{"op": "drop-node", "id": 2}]}"#,
        );
        assert_eq!(children_of(&store, 1), Vec::<i64>::new());
        for id in [2, 3, 4] {
            assert!(store.node(id).is_none(), "node {id} must be gone");
            assert!(applied.dropped.contains(&id));
        }
        // The parent is dirty (child list changed); dropped nodes are not.
        assert!(applied.dirty.contains(&1));
        assert!(!applied.dirty.contains(&2));
    }

    #[test]
    fn drop_root_clears_the_root_slot() {
        let mut store = Store::default();
        apply_json(
            &mut store,
            r#"{"generation": 1, "ops": [
                {"op": "create-node", "id": 1, "kind": "root"},
                {"op": "create-node", "id": 2, "kind": "text"},
                {"op": "insert-child", "parent": 1, "child": 2, "index": 0}
            ]}"#,
        );
        apply_json(
            &mut store,
            r#"{"generation": 2, "ops": [{"op": "drop-node", "id": 1}]}"#,
        );
        assert_eq!(store.root, None);
    }

    #[test]
    fn insert_child_reparents_existing_nodes() {
        let mut store = Store::default();
        apply_json(
            &mut store,
            r#"{"generation": 1, "ops": [
                {"op": "create-node", "id": 1, "kind": "column"},
                {"op": "create-node", "id": 2, "kind": "column"},
                {"op": "create-node", "id": 3, "kind": "column"},
                {"op": "create-node", "id": 4, "kind": "text"},
                {"op": "insert-child", "parent": 1, "child": 2, "index": 0},
                {"op": "insert-child", "parent": 1, "child": 3, "index": 1},
                {"op": "insert-child", "parent": 2, "child": 4, "index": 0}
            ]}"#,
        );
        apply_json(
            &mut store,
            r#"{"generation": 2, "ops": [
                {"op": "insert-child", "parent": 3, "child": 4, "index": 0}
            ]}"#,
        );
        assert_eq!(children_of(&store, 2), Vec::<i64>::new());
        assert_eq!(children_of(&store, 3), vec![4]);
        assert_eq!(store.node(4).unwrap().parent, Some(3));
    }

    #[test]
    fn move_child_reorders_within_one_parent() {
        let mut store = Store::default();
        apply_json(
            &mut store,
            r#"{"generation": 1, "ops": [
                {"op": "create-node", "id": 1, "kind": "column"},
                {"op": "create-node", "id": 2, "kind": "text"},
                {"op": "create-node", "id": 3, "kind": "text"},
                {"op": "create-node", "id": 4, "kind": "text"},
                {"op": "insert-child", "parent": 1, "child": 2, "index": 0},
                {"op": "insert-child", "parent": 1, "child": 3, "index": 1},
                {"op": "insert-child", "parent": 1, "child": 4, "index": 2}
            ]}"#,
        );
        apply_json(
            &mut store,
            r#"{"generation": 2, "ops": [
                {"op": "move-child", "parent": 1, "child": 4, "index": 0}
            ]}"#,
        );
        assert_eq!(children_of(&store, 1), vec![4, 2, 3]);
    }

    #[test]
    fn insert_at_the_end_preserves_child_order() {
        let mut store = Store::default();
        apply_json(
            &mut store,
            r#"{"generation": 1, "ops": [
                {"op": "create-node", "id": 1, "kind": "column"},
                {"op": "create-node", "id": 2, "kind": "text"},
                {"op": "create-node", "id": 3, "kind": "text"},
                {"op": "insert-child", "parent": 1, "child": 2, "index": 0},
                {"op": "insert-child", "parent": 1, "child": 3, "index": 1}
            ]}"#,
        );
        assert_eq!(children_of(&store, 1), vec![2, 3]);
    }

    #[test]
    fn mid_batch_error_leaves_the_store_untouched() {
        let mut store = Store::default();
        apply_json(
            &mut store,
            r#"{"generation": 1, "ops": [
                {"op": "create-node", "id": 1, "kind": "root"},
                {"op": "create-node", "id": 2, "kind": "text"},
                {"op": "insert-child", "parent": 1, "child": 2, "index": 0}
            ]}"#,
        );
        let generation_before = store.generation;
        // Second op targets a node that does not exist — the whole batch
        // must roll back, including the valid ops before it.
        let batch = decode_batch(
            r#"{"generation": 2, "ops": [
                {"op": "create-node", "id": 3, "kind": "text"},
                {"op": "set-prop", "id": 99, "property": "text", "value": "x"}
            ]}"#,
        )
        .unwrap();
        assert!(store.apply(&batch).is_err());
        assert_eq!(store.nodes.keys().copied().collect::<Vec<_>>(), vec![1, 2]);
        assert_eq!(children_of(&store, 1), vec![2]);
        assert_eq!(store.generation, generation_before);
    }

    #[test]
    fn apply_rejects_invalid_ops() {
        let mut store = Store::default();
        let seed = |store: &mut Store| {
            apply_json(
                store,
                r#"{"generation": 1, "ops": [
                    {"op": "create-node", "id": 1, "kind": "root"},
                    {"op": "create-node", "id": 2, "kind": "spinner"},
                    {"op": "insert-child", "parent": 1, "child": 2, "index": 0}
                ]}"#,
            );
        };
        seed(&mut store);
        for json in [
            // duplicate create
            r#"{"generation":2,"ops":[{"op":"create-node","id":1,"kind":"text"}]}"#,
            // unknown node kind
            r#"{"generation":2,"ops":[{"op":"create-node","id":5,"kind":"nope"}]}"#,
            // unknown property
            r#"{"generation":2,"ops":[{"op":"set-prop","id":2,"property":"nope","value":1}]}"#,
            // set-prop on missing node
            r#"{"generation":2,"ops":[{"op":"set-prop","id":99,"property":"text","value":"x"}]}"#,
            // drop missing node
            r#"{"generation":2,"ops":[{"op":"drop-node","id":99}]}"#,
            // insert into non-container (spinner accepts no children)
            r#"{"generation":2,"ops":[
                {"op":"create-node","id":5,"kind":"text"},
                {"op":"insert-child","parent":2,"child":5,"index":0}]}"#,
            // insert into missing parent
            r#"{"generation":2,"ops":[
                {"op":"create-node","id":5,"kind":"text"},
                {"op":"insert-child","parent":99,"child":5,"index":0}]}"#,
            // insert missing child
            r#"{"generation":2,"ops":[{"op":"insert-child","parent":1,"child":99,"index":0}]}"#,
            // cycle: root under its own descendant
            r#"{"generation":2,"ops":[
                {"op":"create-node","id":5,"kind":"column"},
                {"op":"insert-child","parent":1,"child":5,"index":1},
                {"op":"insert-child","parent":5,"child":1,"index":0}]}"#,
            // remove-child on a node that is not a child
            r#"{"generation":2,"ops":[{"op":"remove-child","parent":1,"child":2},{"op":"remove-child","parent":1,"child":2}]}"#,
            // move-child on a node that is not a child
            r#"{"generation":2,"ops":[{"op":"move-child","parent":2,"child":1,"index":0}]}"#,
        ] {
            assert!(decode_batch(json).is_ok(), "decode: {json}");
            let batch = decode_batch(json).unwrap();
            assert!(store.apply(&batch).is_err(), "must reject: {json}");
        }
    }

    #[test]
    fn generation_tracks_the_last_applied_batch() {
        let mut store = Store::default();
        apply_json(&mut store, r#"{"generation": 11, "ops": []}"#);
        assert_eq!(store.generation, 11);
        apply_json(&mut store, r#"{"generation": 12, "ops": []}"#);
        assert_eq!(store.generation, 12);
        let skipped = decode_batch(r#"{"generation": 14, "ops": []}"#).unwrap();
        assert!(store.apply(&skipped).is_err());
        assert_eq!(store.generation, 12);
        store.reset();
        assert_eq!(store.generation, 0);
        apply_json(&mut store, r#"{"generation": 14, "ops": []}"#);
        assert_eq!(store.generation, 14);
    }
}

#[cfg(test)]
mod review_regressions {
    use super::Store;
    use crate::wire::decode_batch;

    #[test]
    fn invalid_schema_patches_rollback_and_allow_a_corrected_retry() {
        let cases = [
            r#"{"op":"set-prop","id":2,"property":"checked","value":true}"#,
            r#"{"op":"set-prop","id":2,"property":"text","value":42}"#,
            r#"{"op":"set-prop","id":1,"property":"width","value":-2}"#,
            r#"{"op":"set-prop","id":1,"property":"width","value":"wide"}"#,
            r#"{"op":"set-extension-prop","id":2,"property":"text","value":"wrong boundary"}"#,
            r#"{"op":"insert-child","parent":1,"child":2,"index":99}"#,
        ];
        for operation in cases {
            let mut store = Store::default();
            store
                .apply(
                    &decode_batch(
                        r#"{"generation":1,"ops":[
                {"op":"create-node","id":1,"kind":"column"},
                {"op":"create-node","id":2,"kind":"text"},
                {"op":"set-prop","id":2,"property":"text","value":"before"},
                {"op":"insert-child","parent":1,"child":2,"index":0}
            ]}"#,
                    )
                    .unwrap(),
                )
                .unwrap();
            let before = format!("{:?}", store.nodes);
            let patch = decode_batch(&format!(
                r#"{{"generation":2,"ops":[
                {{"op":"set-prop","id":2,"property":"text","value":"candidate"}},
                {operation}
            ]}}"#
            ))
            .unwrap();
            assert!(store.apply(&patch).is_err(), "must reject: {operation}");
            assert_eq!(format!("{:?}", store.nodes), before);
            store
                .apply(
                    &decode_batch(
                        r#"{"generation":2,"ops":[
                {"op":"set-prop","id":2,"property":"text","value":"corrected"}
            ]}"#,
                    )
                    .unwrap(),
                )
                .unwrap();
        }
    }

    #[test]
    fn invalid_context_menu_metadata_is_rejected() {
        for extra in [
            r#"{"op":"create-node","id":3,"kind":"context-menu"},{"op":"insert-child","parent":1,"child":3,"index":1}"#,
            r#"{"op":"create-node","id":3,"kind":"menu-item"},{"op":"set-prop","id":3,"property":"text","value":"Action"},{"op":"insert-child","parent":2,"child":3,"index":0}"#,
            r#"{"op":"create-node","id":3,"kind":"divider"},{"op":"set-prop","id":3,"property":"width","value":4},{"op":"insert-child","parent":2,"child":3,"index":0}"#,
        ] {
            let batch = decode_batch(&format!(
                r#"{{"generation":1,"ops":[
                {{"op":"create-node","id":1,"kind":"text"}},
                {{"op":"create-node","id":2,"kind":"context-menu"}},
                {{"op":"insert-child","parent":1,"child":2,"index":0}},
                {extra}
            ]}}"#
            ))
            .unwrap();
            let mut store = Store::default();
            assert!(store.apply(&batch).is_err(), "must reject: {extra}");
            assert!(store.nodes.is_empty());
        }
    }

    #[test]
    fn canonical_parent_child_constraints_are_enforced() {
        let cases = [
            r#"{"generation":1,"ops":[
                {"op":"create-node","id":1,"kind":"column"},
                {"op":"create-node","id":2,"kind":"list-section"},
                {"op":"insert-child","parent":1,"child":2,"index":0}
            ]}"#,
            r#"{"generation":1,"ops":[
                {"op":"create-node","id":1,"kind":"radio-group"},
                {"op":"create-node","id":2,"kind":"text"},
                {"op":"insert-child","parent":1,"child":2,"index":0}
            ]}"#,
            r#"{"generation":1,"ops":[
                {"op":"create-node","id":1,"kind":"root"},
                {"op":"create-node","id":2,"kind":"column"},
                {"op":"create-node","id":3,"kind":"column"},
                {"op":"insert-child","parent":1,"child":2,"index":0},
                {"op":"insert-child","parent":1,"child":3,"index":1}
            ]}"#,
        ];
        for json in cases {
            let mut store = Store::default();
            assert!(
                store.apply(&decode_batch(json).unwrap()).is_err(),
                "must reject: {json}"
            );
            assert!(store.nodes.is_empty());
        }
    }
}
