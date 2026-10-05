//! App-scoped extension registry (ADR 0002). Extensions are kebab-case
//! identifiers registered by the application layer; `create-extension` ops
//! carry identifier + fingerprint. This crate stores the specs so the
//! renderer can resolve props/events and pick specialized renderers; the
//! backend records the fingerprint at first use (the registry "freezes"
//! declaratively — OCaml already validates prop/event conformance).

use std::collections::HashMap;

/// How the extension presents: `component` renders standalone content;
/// `tweak` wraps its single child with platform-specific behaviour (ADR 0003).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExtensionFlavor {
    Component,
    Tweak,
}

#[derive(Debug, Clone)]
pub struct ExtensionSpec {
    pub identifier: String,
    pub flavor: ExtensionFlavor,
    /// Child extension/kind wire names the node admits. Empty = children
    /// declared unconstrained by the backend (OCaml-side already enforces).
    pub children: Vec<String>,
    /// Extension prop names (scalar payloads travel in `extension_props`).
    pub properties: Vec<String>,
    /// Extension event names — fired via `lui_ocaml_extension_event`.
    pub events: Vec<String>,
}

impl ExtensionSpec {
    pub fn component(identifier: impl Into<String>) -> Self {
        ExtensionSpec {
            identifier: identifier.into(),
            flavor: ExtensionFlavor::Component,
            children: Vec::new(),
            properties: Vec::new(),
            events: Vec::new(),
        }
    }

    pub fn tweak(identifier: impl Into<String>) -> Self {
        ExtensionSpec {
            flavor: ExtensionFlavor::Tweak,
            ..ExtensionSpec::component(identifier)
        }
    }
}

#[derive(Default)]
pub struct ExtensionRegistry {
    specs: HashMap<String, ExtensionSpec>,
}

impl ExtensionRegistry {
    pub fn register(&mut self, spec: ExtensionSpec) {
        self.specs.insert(spec.identifier.clone(), spec);
    }

    pub fn get(&self, identifier: &str) -> Option<&ExtensionSpec> {
        self.specs.get(identifier)
    }

    /// A `gpui-*` identifier is the conventional namespace for
    /// gpui-specific components (see platform/gpui/README.md).
    pub fn is_gpui_namespace(identifier: &str) -> bool {
        identifier.starts_with("gpui-")
    }
}
