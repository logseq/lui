//! Frozen contracts exported from the OCaml application, independent of NSH views.
use crate::{contract, store::Node};
use serde::Deserialize;
use serde_json::{Map, Value};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Profile {
    pub os: String,
    pub host: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ScalarKind {
    String,
    Bool,
    Int,
    Float,
}

impl ScalarKind {
    pub fn accepts(self, value: &Value) -> bool {
        match self {
            Self::String => value.is_string(),
            Self::Bool => value.is_boolean(),
            Self::Int => value
                .as_i64()
                .is_some_and(|n| (-(1_i64 << 62)..(1_i64 << 62)).contains(&n)),
            Self::Float => value
                .as_number()
                .is_some_and(|n| n.is_f64() && n.as_f64().is_some_and(f64::is_finite)),
        }
    }
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Property {
    pub name: String,
    pub kind: ScalarKind,
    pub required: bool,
    #[serde(default, deserialize_with = "present_default")]
    pub default: Option<Value>,
}

fn present_default<'de, D: serde::Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<Value>, D::Error> {
    Value::deserialize(deserializer).map(Some)
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EventField {
    pub name: String,
    pub kind: ScalarKind,
    pub required: bool,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EventSchema {
    pub name: String,
    pub fields: Vec<EventField>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ExtensionKind {
    Component,
    Tweak,
}

/// The fingerprint is the exact OCaml literal, not a Rust float-formatting port.
#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Schema {
    pub identifier: String,
    pub fingerprint: String,
    pub kind: ExtensionKind,
    pub profiles: Vec<Profile>,
    pub standard_children: bool,
    pub extension_children: Vec<String>,
    pub properties: Vec<Property>,
    pub events: Vec<EventSchema>,
}

impl Schema {
    pub fn from_json(json: &str) -> Result<Self, String> {
        let schema: Self = serde_json::from_str(json).map_err(|e| e.to_string())?;
        schema.validate()?;
        Ok(schema)
    }

    pub(crate) fn validate(&self) -> Result<(), String> {
        if !valid_name(&self.identifier) || contract::kinds().contains_key(&self.identifier) {
            return Err("extension identifier is invalid or shadows a standard kind".into());
        }
        let prefix = match self.kind {
            ExtensionKind::Component => "lui-extension-v1",
            ExtensionKind::Tweak => "lui-tweak-v1",
        };
        let header = format!("{prefix}|{}:{}|", self.identifier.len(), self.identifier);
        if !self.fingerprint.starts_with(&header) {
            return Err("extension fingerprint has a different identifier or namespace".into());
        }
        unique(self.properties.iter().map(|p| p.name.as_str()))?;
        unique(self.events.iter().map(|e| e.name.as_str()))?;
        unique(self.extension_children.iter().map(String::as_str))?;
        for property in &self.properties {
            if property
                .default
                .as_ref()
                .is_some_and(|v| !property.kind.accepts(v))
            {
                return Err(format!("invalid extension default {}", property.name));
            }
        }
        for event in &self.events {
            unique(event.fields.iter().map(|f| f.name.as_str()))?;
        }
        if self.profiles.iter().any(|p| {
            !matches!(
                p.os.as_str(),
                "generic" | "web" | "macos" | "ios" | "android" | "linux" | "windows"
            ) || !matches!(
                p.host.as_str(),
                "generic" | "web" | "swiftui" | "kotlin" | "nsh"
            )
        }) {
            return Err("invalid extension profiles".into());
        }
        if self.kind == ExtensionKind::Tweak
            && (!self.standard_children
                || !self.extension_children.is_empty()
                || !self.events.is_empty())
        {
            return Err("a tweak accepts exactly one content child and declares no events or extension child list".into());
        }
        Ok(())
    }

    pub(crate) fn property(&self, name: &str) -> Result<&Property, String> {
        self.properties
            .iter()
            .find(|p| p.name == name)
            .ok_or_else(|| format!("undeclared extension property {name}"))
    }

    pub(crate) fn validate_property(&self, name: &str, value: &Value) -> Result<(), String> {
        if self.property(name)?.kind.accepts(value) {
            Ok(())
        } else {
            Err(format!("invalid extension property {name}"))
        }
    }

    pub(crate) fn validate_node(&self, node: &Node) -> Result<(), String> {
        let extension = node
            .extension
            .as_ref()
            .ok_or("missing extension identity")?;
        for (name, value) in &extension.properties {
            self.validate_property(name, value)?;
        }
        for property in &self.properties {
            if property.required
                && property.default.is_none()
                && !extension.properties.contains_key(&property.name)
            {
                return Err(format!(
                    "required extension property {} is missing",
                    property.name
                ));
            }
        }
        if self.kind == ExtensionKind::Tweak && node.children.len() != 1 {
            return Err("platform tweak requires exactly one child".into());
        }
        Ok(())
    }

    pub(crate) fn validate_event(
        &self,
        name: &str,
        values: &Map<String, Value>,
    ) -> Result<(), String> {
        let event = self
            .events
            .iter()
            .find(|e| e.name == name)
            .ok_or_else(|| format!("undeclared extension event {name}"))?;
        for field in &event.fields {
            if field.required && !values.contains_key(&field.name) {
                return Err(format!(
                    "required extension event field {} is missing",
                    field.name
                ));
            }
        }
        for (name, value) in values {
            if !event
                .fields
                .iter()
                .any(|f| f.name == *name && f.kind.accepts(value))
            {
                return Err(format!("invalid extension event field {name}"));
            }
        }
        Ok(())
    }
}

fn unique<'a>(names: impl Iterator<Item = &'a str>) -> Result<(), String> {
    let mut seen = BTreeSet::new();
    for name in names {
        if !valid_name(name) || !seen.insert(name) {
            return Err("duplicate or invalid extension field name".into());
        }
    }
    Ok(())
}

fn valid_name(name: &str) -> bool {
    let slug = |c: u8| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_';
    let bytes = name.as_bytes();
    !bytes.is_empty()
        && slug(bytes[0])
        && slug(bytes[bytes.len() - 1])
        && bytes
            .iter()
            .enumerate()
            .all(|(i, c)| slug(*c) || (*c == b'-' && bytes.get(i + 1).is_some_and(|c| slug(*c))))
}

pub(crate) type NodeValidator = Arc<dyn Fn(&Node) -> Result<(), String> + Send + Sync>;
pub(crate) struct Contract {
    pub schema: Schema,
    pub validate: Option<NodeValidator>,
}
pub(crate) struct Contracts {
    pub profile: Profile,
    pub entries: BTreeMap<String, Contract>,
}
impl std::fmt::Debug for Contracts {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_map()
            .entries(self.entries.iter().map(|(id, c)| (id, &c.schema)))
            .finish()
    }
}
impl Contracts {
    pub(crate) fn get(&self, identifier: &str) -> Result<&Contract, String> {
        self.entries
            .get(identifier)
            .ok_or_else(|| format!("unregistered NSH extension {identifier}"))
    }
    pub(crate) fn create(&self, identifier: &str, fingerprint: &str) -> Result<&Schema, String> {
        let schema = &self.get(identifier)?.schema;
        if !fingerprint.is_empty() && schema.fingerprint != fingerprint {
            return Err(format!("extension fingerprint mismatch for {identifier}"));
        }
        if !schema.profiles.contains(&self.profile) {
            return Err(format!(
                "extension {identifier} is unsupported by this backend profile"
            ));
        }
        Ok(schema)
    }
}
