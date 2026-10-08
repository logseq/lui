//! The retained node tree: applies wire ops, tracks which nodes changed so the
//! renderer can redraw exactly the dirty entities — never the whole tree.

use std::collections::{BTreeMap, BTreeSet};
use std::fmt;

use crate::wire::{Batch, Op, Value};
use crate::wire_schema::{NodeKind, Property};

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
            NodeIdentity::Standard(kind) => kind.is_container(),
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

    /// Apply one decoded batch. On error the batch is rejected wholesale:
    /// partial state must not leak into a tree the renderer trusts.
    pub fn apply(&mut self, batch: &Batch) -> Result<Applied, BackendError> {
        let mut applied = Applied {
            generation: batch.generation,
            ..Applied::default()
        };
        // Keep only the first before-image of each touched node. Property
        // patches stay local while a rejected batch restores every link.
        let root = self.root;
        let mut undo = BTreeMap::new();
        for op in &batch.ops {
            self.record_before(op, &mut undo);
            if let Err(error) = self.apply_op(op, &mut applied) {
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
        }
        self.generation = batch.generation;
        Ok(applied)
    }

    fn record_before(&self, op: &Op, undo: &mut BTreeMap<i64, Option<Node>>) {
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
                        stack.extend(node.children.iter().copied());
                    }
                }
            }
        }
        for id in ids {
            undo.entry(id).or_insert_with(|| self.node(id).cloned());
        }
    }

    fn apply_op(&mut self, op: &Op, applied: &mut Applied) -> Result<(), BackendError> {
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
                self.drop_node(*id, applied)?
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
                node.props.insert(property, value.clone());
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
                node.props.remove(&property);
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
                node.extension_props.insert(property.clone(), value.clone());
                applied.dirty.insert(*id);
            }
            Op::RemoveExtensionProp { id, property } => {
                let node = self
                    .nodes
                    .get_mut(id)
                    .ok_or_else(|| err(format!("remove-extension-prop: unknown node {id}")))?;
                node.extension_props.remove(property);
                applied.dirty.insert(*id);
            }
            Op::InsertChild {
                parent,
                child,
                index,
            } => {
                self.attach(*parent, *child, *index, applied)?;
            }
            Op::RemoveChild { parent, child } => {
                self.detach(*parent, *child, applied)?;
            }
            Op::MoveChild {
                parent,
                child,
                index,
            } => {
                self.move_child(*parent, *child, *index, applied)?;
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
            },
        );
        applied.dirty.insert(id);
        Ok(())
    }

    fn drop_node(&mut self, id: i64, applied: &mut Applied) -> Result<(), BackendError> {
        // Collect the whole subtree before mutating links.
        let mut stack = vec![id];
        let mut subtree = Vec::new();
        while let Some(current) = stack.pop() {
            let node = self
                .nodes
                .get(&current)
                .ok_or_else(|| err(format!("drop-node: unknown node {current}")))?;
            subtree.push(current);
            stack.extend(node.children.iter().copied());
        }
        if let Some(parent) = self.nodes.get(&id).and_then(|node| node.parent) {
            if let Some(parent_node) = self.nodes.get_mut(&parent) {
                parent_node.children.retain(|child| *child != id);
            }
            applied.dirty.insert(parent);
            applied.structural.insert(parent);
        }
        for current in subtree {
            self.nodes.remove(&current);
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
        if self.is_ancestor(child, parent) {
            return Err(err(format!(
                "insert-child: {child} is an ancestor of {parent} (cycle)"
            )));
        }
        // A re-parent is expressed as insert on the new parent: detach first.
        if let Some(old_parent) = self.nodes.get(&child).and_then(|node| node.parent) {
            self.detach(old_parent, child, applied)?;
        }
        let parent_node = self.nodes.get_mut(&parent).expect("checked above");
        let index = (index.max(0) as usize).min(parent_node.children.len());
        parent_node.children.insert(index, child);
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
    ) -> Result<(), BackendError> {
        let parent_node = self
            .nodes
            .get_mut(&parent)
            .ok_or_else(|| err(format!("remove-child: unknown parent {parent}")))?;
        if !parent_node.children.contains(&child) {
            return Err(err(format!(
                "remove-child: node {child} is not a child of {parent}"
            )));
        }
        parent_node.children.retain(|entry| *entry != child);
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
    ) -> Result<(), BackendError> {
        let parent_node = self
            .nodes
            .get_mut(&parent)
            .ok_or_else(|| err(format!("move-child: unknown parent {parent}")))?;
        let position = parent_node
            .children
            .iter()
            .position(|entry| *entry == child)
            .ok_or_else(|| {
                err(format!(
                    "move-child: node {child} is not a child of {parent}"
                ))
            })?;
        parent_node.children.remove(position);
        let index = (index.max(0) as usize).min(parent_node.children.len());
        parent_node.children.insert(index, child);
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
    fn property_patch_preserves_unrelated_payload_storage() {
        let mut store = Store::default();
        apply_json(
            &mut store,
            r#"{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"root"},
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
                {"op": "set-extension-prop", "id": 3,
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
        assert_eq!(text.extension_props.get("style-class"), Some(&Value::Str("text-sm".into())));
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
                {"op": "set-extension-prop", "id": 2, "property": "k",
                 "value": 1}
            ]}"#,
        );
        apply_json(
            &mut store,
            r#"{"generation": 2, "ops": [
                {"op": "set-prop", "id": 2, "property": "text",
                 "value": "after"},
                {"op": "remove-prop", "id": 2, "property": "enabled"},
                {"op": "set-extension-prop", "id": 2, "property": "k",
                 "value": 2},
                {"op": "remove-extension-prop", "id": 2, "property": "k"}
            ]}"#,
        );
        let node = store.node(2).unwrap();
        assert_eq!(node.string_prop(Property::TextValue), Some("after"));
        assert!(node.prop(Property::Enabled).is_none());
        assert!(node.extension_props.get("k").is_none());
    }

    #[test]
    fn drop_node_removes_the_whole_subtree() {
        let mut store = Store::default();
        apply_json(
            &mut store,
            r#"{"generation": 1, "ops": [
                {"op": "create-node", "id": 1, "kind": "root"},
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
                {"op": "create-node", "id": 1, "kind": "root"}
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
                {"op": "create-node", "id": 1, "kind": "root"},
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
                {"op": "create-node", "id": 1, "kind": "root"},
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
    fn insert_index_is_clamped_to_the_child_list() {
        let mut store = Store::default();
        apply_json(
            &mut store,
            r#"{"generation": 1, "ops": [
                {"op": "create-node", "id": 1, "kind": "root"},
                {"op": "create-node", "id": 2, "kind": "text"},
                {"op": "create-node", "id": 3, "kind": "text"},
                {"op": "insert-child", "parent": 1, "child": 2, "index": 0},
                {"op": "insert-child", "parent": 1, "child": 3, "index": 99}
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
        assert_eq!(
            store.nodes.keys().copied().collect::<Vec<_>>(),
            vec![1, 2]
        );
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
                    {"op": "create-node", "id": 2, "kind": "slider"},
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
            // insert into non-container (slider accepts no children)
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
    }
}

