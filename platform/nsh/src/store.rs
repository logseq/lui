//! Transactional retained node storage, independent of native windows.
use crate::{
    contract,
    wire::{Batch, Operation},
};
use serde_json::{Map, Value};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};

#[derive(Debug, Clone, Default, PartialEq)]
#[non_exhaustive]
pub struct Node {
    pub id: u64,
    pub incarnation: u64,
    pub kind: String,
    pub props: Map<String, Value>,
    pub children: Arc<Vec<u64>>,
    pub parent: Option<u64>,
}
impl Node {
    pub fn string(&self, property: &str) -> &str {
        self.props
            .get(property)
            .and_then(Value::as_str)
            .unwrap_or("")
    }
    pub fn boolean(&self, property: &str, fallback: bool) -> bool {
        self.props
            .get(property)
            .and_then(Value::as_bool)
            .unwrap_or(fallback)
    }
    pub fn number(&self, property: &str, fallback: f64) -> f64 {
        self.props
            .get(property)
            .and_then(Value::as_f64)
            .unwrap_or(fallback)
    }
}
#[derive(Debug, Default)]
#[non_exhaustive]
pub struct Store {
    pub nodes: BTreeMap<u64, Arc<Node>>,
    pub generation: u64,
    next_incarnation: u64,
    root: Option<u64>,
}
#[derive(Debug, Default)]
#[non_exhaustive]
pub struct Changes {
    pub updated: BTreeSet<u64>,
    pub removed: BTreeSet<u64>,
}
impl Store {
    pub fn root(&self) -> Option<u64> {
        self.root
    }
    /// Selects the application root returned by the native ABI. A LUI view may
    /// start with any component kind; detached extension trees are not roots.
    pub fn set_root(&mut self, id: u64) -> Result<(), String> {
        let node = self
            .nodes
            .get(&id)
            .ok_or("application root is not mounted")?;
        if node.parent.is_some() {
            return Err("application root has a parent".into());
        }
        self.root = Some(id);
        Ok(())
    }
    pub fn apply(&mut self, batch: Batch) -> Result<Changes, String> {
        self.apply_validated(batch, |_| Ok(()))
    }
    /// Checks host-specific final-node constraints before committing anything.
    pub(crate) fn apply_validated(
        &mut self,
        batch: Batch,
        validate: impl Fn(&Node) -> Result<(), String>,
    ) -> Result<Changes, String> {
        self.apply_inspected(batch, validate, |_| Ok(()))
    }
    /// The inspector sees final relationships without exposing mutable state.
    pub(crate) fn apply_inspected(
        &mut self,
        batch: Batch,
        validate: impl Fn(&Node) -> Result<(), String>,
        inspect: impl Fn(&Transaction<'_>) -> Result<(), String>,
    ) -> Result<Changes, String> {
        if batch.generation > ((1_u64 << 62) - 1) {
            return Err("patch generation is outside the OCaml integer range".into());
        }
        if self.generation.checked_add(1) != Some(batch.generation) {
            return Err("nonsequential patch generation; request an authoritative snapshot".into());
        }
        let next_incarnation = self.next_incarnation;
        let root = self.root;
        let mut transaction = Transaction {
            store: self,
            touched: BTreeMap::new(),
            removed: BTreeSet::new(),
            created: BTreeSet::new(),
            next_incarnation,
            root,
        };
        for op in batch.ops {
            transaction.operation(op)?;
        }
        transaction.validate(&validate)?;
        inspect(&transaction)?;
        let mut changes = Changes::default();
        for id in &transaction.removed {
            transaction.store.nodes.remove(id);
            changes.removed.insert(*id);
        }
        for (id, node) in transaction.touched {
            if !transaction.removed.contains(&id) {
                changes.updated.insert(id);
                transaction.store.nodes.insert(id, Arc::new(node));
            }
        }
        transaction.store.generation = batch.generation;
        transaction.store.next_incarnation = transaction.next_incarnation;
        transaction.store.root = transaction
            .root
            .filter(|id| !transaction.removed.contains(id));
        Ok(changes)
    }
    /// Validates a complete replacement before adopting its generation baseline.
    pub fn apply_snapshot(&mut self, snapshot: Batch) -> Result<Changes, String> {
        self.apply_snapshot_validated(snapshot, |_| Ok(()))
    }
    pub(crate) fn apply_snapshot_validated(
        &mut self,
        snapshot: Batch,
        validate: impl Fn(&Node) -> Result<(), String>,
    ) -> Result<Changes, String> {
        self.apply_snapshot_inspected(snapshot, validate, |_| Ok(()))
    }
    pub(crate) fn apply_snapshot_inspected(
        &mut self,
        snapshot: Batch,
        validate: impl Fn(&Node) -> Result<(), String>,
        inspect: impl Fn(&Transaction<'_>) -> Result<(), String>,
    ) -> Result<Changes, String> {
        if snapshot.generation < self.generation {
            return Err("snapshot generation is older than the committed state".into());
        }
        let generation = snapshot
            .generation
            .checked_sub(1)
            .ok_or("invalid snapshot generation")?;
        let mut next = Self {
            generation,
            next_incarnation: self.next_incarnation,
            ..Self::default()
        };
        let mut changes = next.apply_inspected(snapshot, validate, inspect)?;
        changes.removed = self
            .nodes
            .keys()
            .filter(|id| !next.nodes.contains_key(id))
            .copied()
            .collect();
        *self = next;
        Ok(changes)
    }
}
pub(crate) struct Transaction<'a> {
    store: &'a mut Store,
    touched: BTreeMap<u64, Node>,
    removed: BTreeSet<u64>,
    created: BTreeSet<u64>,
    next_incarnation: u64,
    root: Option<u64>,
}
impl Transaction<'_> {
    pub(crate) fn previous(&self, id: u64) -> Option<&Node> {
        self.store.nodes.get(&id).map(Arc::as_ref)
    }
    pub(crate) fn updated(&self) -> impl Iterator<Item = &Node> {
        self.touched
            .iter()
            .filter(|(id, _)| !self.removed.contains(id))
            .map(|(_, node)| node)
    }
    pub(crate) fn get(&self, id: u64) -> Result<&Node, String> {
        if self.removed.contains(&id) {
            return Err(format!("node {id} was dropped"));
        }
        self.touched
            .get(&id)
            .or_else(|| self.store.nodes.get(&id).map(Arc::as_ref))
            .ok_or_else(|| format!("unknown node {id}"))
    }
    fn edit(&mut self, id: u64) -> Result<&mut Node, String> {
        if !self.touched.contains_key(&id) {
            let node = self.get(id)?.clone();
            self.touched.insert(id, node);
        }
        self.touched
            .get_mut(&id)
            .ok_or_else(|| format!("unknown node {id}"))
    }
    fn operation(&mut self, op: Operation) -> Result<(), String> {
        match op {
            Operation::CreateNode { id, kind } => {
                if id == 0
                    || id > ((1_u64 << 62) - 1)
                    || self.get(id).is_ok()
                    || self.created.contains(&id)
                {
                    return Err(format!("duplicate or invalid node {id}"));
                }
                if !contract::kinds().contains_key(&kind) {
                    return Err(format!("unknown node kind {kind}"));
                }
                self.next_incarnation = self
                    .next_incarnation
                    .checked_add(1)
                    .ok_or("node incarnation overflow")?;
                if kind == "root" {
                    if self.root.is_some_and(|id| self.get(id).is_ok()) {
                        return Err("multiple root nodes".into());
                    }
                    self.root = Some(id);
                }
                self.removed.remove(&id);
                self.created.insert(id);
                self.touched.insert(
                    id,
                    Node {
                        id,
                        incarnation: self.next_incarnation,
                        kind,
                        props: Map::new(),
                        children: Arc::default(),
                        parent: None,
                    },
                );
            }
            Operation::CreateExtension { identifier, .. } => {
                return Err(format!("unregistered NSH extension {identifier}"));
            }
            Operation::DropNode { id } => {
                let node = self.get(id)?.clone();
                if let Some(parent) = node.parent {
                    Arc::make_mut(&mut self.edit(parent)?.children).retain(|child| *child != id);
                }
                for child in node.children.iter().copied() {
                    self.edit(child)?.parent = None;
                }
                self.touched.remove(&id);
                self.removed.insert(id);
            }
            Operation::DetachSubtree { id } => {
                // Unknown/retired roots are an idempotent detach, like LUI's other hosts.
                if let Ok(node) = self.get(id) {
                    let mut pending = vec![id];
                    if let Some(parent) = node.parent {
                        Arc::make_mut(&mut self.edit(parent)?.children)
                            .retain(|child| *child != id);
                    }
                    while let Some(current) = pending.pop() {
                        pending.extend(self.get(current)?.children.iter().copied());
                        self.touched.remove(&current);
                        self.removed.insert(current);
                    }
                }
            }
            Operation::SetProp {
                id,
                property,
                value,
            } => {
                contract::validate_value(&self.get(id)?.kind, &property, &value)?;
                self.edit(id)?.props.insert(property, value);
            }
            Operation::RemoveProp { id, property } => {
                let kind = &self.get(id)?.kind;
                if !contract::property_supported(kind, &property) {
                    return Err(format!("{kind} does not support {property}"));
                }
                self.edit(id)?.props.remove(&property);
            }
            Operation::SetExtensionProp { .. } | Operation::RemoveExtensionProp { .. } => {
                return Err("extension properties require a registered NSH extension".into());
            }
            Operation::InsertChild {
                parent,
                child,
                index,
            } => {
                if self.get(child)?.parent.is_some() {
                    return Err(format!("node {child} already has a parent"));
                }
                self.attach(parent, child, index)?;
            }
            Operation::RemoveChild { parent, child } => {
                if self.get(child)?.parent != Some(parent) {
                    return Err("remove-child parent mismatch".into());
                }
                Arc::make_mut(&mut self.edit(parent)?.children).retain(|id| *id != child);
                self.edit(child)?.parent = None;
            }
            Operation::MoveChild {
                parent,
                child,
                index,
            } => {
                if self.get(child)?.parent != Some(parent) {
                    return Err("move-child parent mismatch".into());
                }
                Arc::make_mut(&mut self.edit(parent)?.children).retain(|id| *id != child);
                self.attach(parent, child, index)?;
            }
        }
        Ok(())
    }
    fn attach(&mut self, parent: u64, child: u64, index: usize) -> Result<(), String> {
        if index > self.get(parent)?.children.len() {
            return Err("child index out of bounds".into());
        }
        let mut ancestor = Some(parent);
        while let Some(id) = ancestor {
            if id == child {
                return Err("cyclic child relationship".into());
            }
            ancestor = self.get(id)?.parent;
        }
        let parent_kind = &self.get(parent)?.kind;
        if !contract::child_supported(parent_kind, &self.get(child)?.kind) {
            return Err(format!("invalid child of {parent_kind}"));
        }
        Arc::make_mut(&mut self.edit(parent)?.children).insert(index, child);
        self.edit(child)?.parent = Some(parent);
        Ok(())
    }
    fn validate(&self, extra: &impl Fn(&Node) -> Result<(), String>) -> Result<(), String> {
        for (id, node) in &self.touched {
            if !self.removed.contains(id) {
                contract::validate_node(node)?;
                extra(node)?;
            }
        }
        Ok(())
    }
}
