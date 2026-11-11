//! Transactional retained node storage, independent of native windows.
use crate::{
    contract,
    extensions::schema::{Contracts, ExtensionKind},
    wire::{Batch, Operation},
};
use serde_json::{Map, Value};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};

#[derive(Debug, Clone, PartialEq)]
pub struct ExtensionNode {
    pub identifier: String,
    pub fingerprint: String,
    pub properties: Map<String, Value>,
}

#[derive(Debug, Clone, Default, PartialEq)]
#[non_exhaustive]
pub struct Node {
    pub id: u64,
    pub incarnation: u64,
    pub kind: String,
    pub props: Map<String, Value>,
    pub extension: Option<ExtensionNode>,
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
    extensions: Option<Arc<Contracts>>,
}
#[derive(Debug, Default)]
#[non_exhaustive]
pub struct Changes {
    pub updated: BTreeSet<u64>,
    pub removed: BTreeSet<u64>,
}
impl Store {
    pub(crate) fn with_extensions(contracts: Arc<Contracts>) -> Self {
        Self {
            extensions: Some(contracts),
            ..Self::default()
        }
    }
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
            extensions: self.extensions.clone(),
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
                if !contract::kinds().contains_key(&kind) {
                    return Err(format!("unknown node kind {kind}"));
                }
                if kind == "root" {
                    if self.root.is_some_and(|id| self.get(id).is_ok()) {
                        return Err("multiple root nodes".into());
                    }
                    self.root = Some(id);
                }
                self.create(id, kind, None)?;
            }
            Operation::CreateExtension {
                id,
                identifier,
                fingerprint,
            } => {
                let schema = self.contracts()?.create(&identifier, &fingerprint)?;
                let identity = ExtensionNode {
                    identifier: identifier.clone(),
                    fingerprint: schema.fingerprint.clone(),
                    properties: Map::new(),
                };
                self.create(id, identifier, Some(identity))?;
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
                if self.get(id)?.extension.is_some() {
                    return Err("standard properties cannot target an extension".into());
                }
                contract::validate_value(&self.get(id)?.kind, &property, &value)?;
                self.edit(id)?.props.insert(property, value);
            }
            Operation::RemoveProp { id, property } => {
                if self.get(id)?.extension.is_some() {
                    return Err("standard properties cannot target an extension".into());
                }
                let kind = &self.get(id)?.kind;
                if !contract::property_supported(kind, &property) {
                    return Err(format!("{kind} does not support {property}"));
                }
                self.edit(id)?.props.remove(&property);
            }
            Operation::SetExtensionProp {
                id,
                property,
                value,
            } => {
                let extension = self
                    .get(id)?
                    .extension
                    .as_ref()
                    .ok_or("extension property targets a standard node")?;
                self.contracts()?
                    .get(&extension.identifier)?
                    .schema
                    .validate_property(&property, &value)?;
                self.edit(id)?
                    .extension
                    .as_mut()
                    .expect("validated extension")
                    .properties
                    .insert(property, value);
            }
            Operation::RemoveExtensionProp { id, property } => {
                let extension = self
                    .get(id)?
                    .extension
                    .as_ref()
                    .ok_or("extension property targets a standard node")?;
                self.contracts()?
                    .get(&extension.identifier)?
                    .schema
                    .property(&property)?;
                self.edit(id)?
                    .extension
                    .as_mut()
                    .expect("validated extension")
                    .properties
                    .remove(&property);
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
        if self.get(parent)?.extension.is_none()
            && self.get(child)?.extension.is_none()
            && !contract::child_supported(parent_kind, &self.get(child)?.kind)
        {
            return Err(format!("invalid child of {parent_kind}"));
        }
        Arc::make_mut(&mut self.edit(parent)?.children).insert(index, child);
        self.edit(child)?.parent = Some(parent);
        Ok(())
    }
    fn validate(&self, extra: &impl Fn(&Node) -> Result<(), String>) -> Result<(), String> {
        for (id, node) in &self.touched {
            if !self.removed.contains(id) {
                if let Some(extension) = &node.extension {
                    let contract = self.contracts()?.get(&extension.identifier)?;
                    contract.schema.validate_node(node)?;
                    if contract.schema.kind == ExtensionKind::Tweak
                        && node
                            .children
                            .first()
                            .is_some_and(|id| self.get(*id).is_ok_and(|child| child.kind == "root"))
                    {
                        return Err("Root cannot be a tweak child".into());
                    }
                    if contract.schema.kind == ExtensionKind::Tweak
                        && self.previous(node.id).is_some_and(|old| {
                            old.incarnation == node.incarnation
                                && (old.children != node.children
                                    || node.children.iter().any(|id| {
                                        self.previous(*id).map(|child| child.incarnation)
                                            != self.get(*id).ok().map(|child| child.incarnation)
                                    }))
                        })
                    {
                        return Err(
                            "changing a mounted NSH tweak target requires a new keyed tweak node"
                                .into(),
                        );
                    }
                    if let Some(validate) = &contract.validate {
                        validate(node)?;
                    }
                } else {
                    contract::validate_node(node)?;
                }
                extra(node)?;
            }
        }
        self.validate_extension_edges()?;
        Ok(())
    }

    fn contracts(&self) -> Result<&Contracts, String> {
        self.store
            .extensions
            .as_deref()
            .ok_or_else(|| "no NSH extension registry is configured".into())
    }

    fn create(
        &mut self,
        id: u64,
        kind: String,
        extension: Option<ExtensionNode>,
    ) -> Result<(), String> {
        if id == 0 || id > ((1_u64 << 62) - 1) || self.get(id).is_ok() || self.created.contains(&id)
        {
            return Err(format!("duplicate or invalid node {id}"));
        }
        self.next_incarnation = self
            .next_incarnation
            .checked_add(1)
            .ok_or("node incarnation overflow")?;
        self.removed.remove(&id);
        self.created.insert(id);
        self.touched.insert(
            id,
            Node {
                id,
                incarnation: self.next_incarnation,
                kind,
                extension,
                ..Node::default()
            },
        );
        Ok(())
    }

    fn is_tweak(&self, node: &Node) -> Result<bool, String> {
        node.extension.as_ref().map_or(Ok(false), |extension| {
            Ok(self.contracts()?.get(&extension.identifier)?.schema.kind == ExtensionKind::Tweak)
        })
    }

    fn validate_extension_edges(&self) -> Result<(), String> {
        if self.store.extensions.is_none() {
            return Ok(());
        }
        let mut parents = BTreeSet::new();
        for node in self.updated() {
            if self
                .previous(node.id)
                .is_none_or(|previous| !Arc::ptr_eq(&previous.children, &node.children))
            {
                parents.insert(node.id);
                let mut current = node;
                while self.is_tweak(current)? {
                    let Some(parent) = current.parent else { break };
                    if !parents.insert(parent) {
                        break;
                    }
                    current = self.get(parent)?;
                }
            }
        }
        // Memoized only for this transaction; nested tweaks share unwrapping work.
        let mut effective = BTreeMap::new();
        for id in parents {
            let parent = self.get(id)?;
            if self.is_tweak(parent)? {
                continue;
            }
            for child in parent.children.iter() {
                let mut path = Vec::new();
                let mut id = *child;
                loop {
                    if let Some(cached) = effective.get(&id) {
                        id = *cached;
                        break;
                    }
                    let node = self.get(id)?;
                    if !self.is_tweak(node)? {
                        break;
                    }
                    path.push(id);
                    id = *node
                        .children
                        .first()
                        .ok_or("platform tweak requires exactly one child")?;
                }
                for tweak in path {
                    effective.insert(tweak, id);
                }
                let child = self.get(id)?;
                let supported = match (&parent.extension, &child.extension) {
                    (None, None) => contract::child_supported(&parent.kind, &child.kind),
                    (None, Some(_)) => contract::extension_parent_supported(&parent.kind)?,
                    (Some(extension), None) => {
                        child.kind != "root"
                            && self
                                .contracts()?
                                .get(&extension.identifier)?
                                .schema
                                .standard_children
                    }
                    (Some(extension), Some(child)) => self
                        .contracts()?
                        .get(&extension.identifier)?
                        .schema
                        .extension_children
                        .contains(&child.identifier),
                };
                if !supported {
                    return Err(format!("invalid extension child of {}", parent.kind));
                }
            }
        }
        Ok(())
    }
}
