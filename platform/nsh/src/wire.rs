//! Lossless decoding of the existing LUI patch wire format.
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(default)]
#[non_exhaustive]
pub struct Batch {
    pub generation: u64,
    pub ops: Vec<Operation>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(tag = "op", rename_all = "kebab-case")]
pub enum Operation {
    CreateNode {
        id: u64,
        kind: String,
    },
    CreateExtension {
        id: u64,
        identifier: String,
        fingerprint: String,
    },
    DropNode {
        id: u64,
    },
    DetachSubtree {
        id: u64,
    },
    SetProp {
        id: u64,
        property: String,
        value: Value,
    },
    RemoveProp {
        id: u64,
        property: String,
    },
    SetExtensionProp {
        id: u64,
        property: String,
        value: Value,
    },
    RemoveExtensionProp {
        id: u64,
        property: String,
    },
    InsertChild {
        parent: u64,
        child: u64,
        index: usize,
    },
    RemoveChild {
        parent: u64,
        child: u64,
    },
    MoveChild {
        parent: u64,
        child: u64,
        index: usize,
    },
}

impl Batch {
    pub fn decode(json: &str) -> Result<Self, String> {
        serde_json::from_str(json).map_err(|error| error.to_string())
    }
}
