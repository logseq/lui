//! Application-scoped, frozen native extension registrations.
//! Only trusted Rust code installs factories; wire data cannot name native classes.
mod host;
pub(crate) mod schema;

use crate::store::{Node, Store};
pub use host::{ExtensionChildren, ExtensionContext, ExtensionEmitter, TweakTarget};
use nsh_core::prelude::*;
use schema::{Contract, Contracts, NodeValidator};
pub use schema::{EventField, EventSchema, ExtensionKind, Profile, Property, ScalarKind, Schema};
use std::{collections::BTreeMap, rc::Rc, sync::Arc};

type Factory = Rc<dyn Fn(ExtensionContext) -> AnyElement>;
type Modifier = Rc<dyn Fn(ExtensionContext, TweakTarget) -> AnyElement>;
#[derive(Clone)]
pub(crate) enum Implementation {
    Component(Factory),
    Tweak(Modifier),
}

/// Immutable registrations supplied with `provide_context` above `Desktop`.
/// Metadata is shared with pure preflight; executable factories stay on the engine thread.
#[derive(Clone)]
pub struct Extensions {
    pub(crate) contracts: Arc<Contracts>,
    implementations: Rc<BTreeMap<String, Implementation>>,
}
impl Extensions {
    pub fn builder() -> ExtensionBuilder {
        ExtensionBuilder::default()
    }
    pub(crate) fn store(&self) -> Store {
        Store::with_extensions(self.contracts.clone())
    }
    pub(crate) fn implementation(&self, identifier: &str) -> &Implementation {
        self.implementations
            .get(identifier)
            .expect("preflight admitted a registered extension")
    }
}

/// Build once before mounting the application. Freezing validates all child references.
#[derive(Default)]
pub struct ExtensionBuilder {
    contracts: BTreeMap<String, Contract>,
    implementations: BTreeMap<String, Implementation>,
}
impl ExtensionBuilder {
    pub fn register(
        mut self,
        schema: Schema,
        factory: impl Fn(ExtensionContext) -> AnyElement + 'static,
    ) -> Result<Self, String> {
        if schema.kind != ExtensionKind::Component {
            return Err("component registration requires a component schema".into());
        }
        self.insert(schema, Implementation::Component(Rc::new(factory)))?;
        Ok(self)
    }
    pub fn register_tweak(
        mut self,
        schema: Schema,
        modifier: impl Fn(ExtensionContext, TweakTarget) -> AnyElement + 'static,
    ) -> Result<Self, String> {
        if schema.kind != ExtensionKind::Tweak {
            return Err("tweak registration requires a tweak schema".into());
        }
        self.insert(schema, Implementation::Tweak(Rc::new(modifier)))?;
        Ok(self)
    }
    fn insert(&mut self, schema: Schema, implementation: Implementation) -> Result<(), String> {
        schema.validate()?;
        if self.contracts.contains_key(&schema.identifier) {
            return Err("extension identifier is already registered".into());
        }
        self.implementations
            .insert(schema.identifier.clone(), implementation);
        self.contracts.insert(
            schema.identifier.clone(),
            Contract {
                schema,
                validate: None,
            },
        );
        Ok(())
    }
    /// Pure capability checks run on final transaction nodes before any native factory.
    pub fn validate(
        mut self,
        identifier: &str,
        validate: impl Fn(&Node) -> Result<(), String> + Send + Sync + 'static,
    ) -> Result<Self, String> {
        let entry = self
            .contracts
            .get_mut(identifier)
            .ok_or("validator requires an existing registration")?;
        entry.validate = Some(Arc::new(validate) as NodeValidator);
        Ok(self)
    }
    pub fn freeze(self, profile: Profile) -> Result<Extensions, String> {
        for contract in self.contracts.values() {
            for identifier in &contract.schema.extension_children {
                if !self.contracts.contains_key(identifier) {
                    return Err(format!("unknown extension child schema {identifier}"));
                }
            }
        }
        Ok(Extensions {
            contracts: Arc::new(Contracts {
                profile,
                entries: self.contracts,
            }),
            implementations: Rc::new(self.implementations),
        })
    }
}

pub(crate) use host::mount;

#[cfg(test)]
mod tests;
