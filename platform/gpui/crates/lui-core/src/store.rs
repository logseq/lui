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
        // Stage the mutation so a mid-batch error leaves the tree intact.
        let mut staged = Store {
            nodes: self.nodes.clone(),
            root: self.root,
            generation: self.generation,
        };
        for op in &batch.ops {
            staged.apply_op(op, &mut applied)?;
        }
        staged.generation = batch.generation;
        *self = staged;
        Ok(applied)
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
            Op::DropNode { id } => self.drop_node(*id, applied)?,
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
        Ok(())
    }
}
