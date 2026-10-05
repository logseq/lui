//! Decoding of the `patch_batch` wire format (see `src/lui_wire.ml`).

use serde_json::{Map, Value as Json};

/// A wire property value. OCaml encodes `StringValue|BoolValue|IntValue|
/// FloatValue` as the matching JSON primitive.
#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Str(String),
    Bool(bool),
    Int(i64),
    Float(f64),
}

impl Value {
    pub fn from_json(json: &Json) -> Option<Value> {
        match json {
            Json::String(text) => Some(Value::Str(text.clone())),
            Json::Bool(flag) => Some(Value::Bool(*flag)),
            Json::Number(number) => {
                if let Some(int) = number.as_i64() {
                    Some(Value::Int(int))
                } else {
                    number.as_f64().map(Value::Float)
                }
            }
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::Str(text) => Some(text),
            _ => None,
        }
    }

    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Value::Bool(flag) => Some(*flag),
            _ => None,
        }
    }

    pub fn as_int(&self) -> Option<i64> {
        match self {
            Value::Int(int) => Some(*int),
            _ => None,
        }
    }

    /// Ints are accepted where a float is expected (OCaml emits `1` for
    /// `IntValue`; callers of numeric props should not care which arrived).
    pub fn as_float(&self) -> Option<f64> {
        match self {
            Value::Int(int) => Some(*int as f64),
            Value::Float(float) => Some(*float),
            _ => None,
        }
    }
}

/// One wire op, normalized to owned fields (kind/property names stay strings;
/// the store resolves them against the generated schema tables).
#[derive(Debug, Clone)]
pub enum Op {
    CreateNode {
        id: i64,
        kind: String,
    },
    CreateExtension {
        id: i64,
        identifier: String,
        fingerprint: String,
    },
    DropNode {
        id: i64,
    },
    SetProp {
        id: i64,
        property: String,
        value: Value,
    },
    RemoveProp {
        id: i64,
        property: String,
    },
    SetExtensionProp {
        id: i64,
        property: String,
        value: Value,
    },
    RemoveExtensionProp {
        id: i64,
        property: String,
    },
    InsertChild {
        parent: i64,
        child: i64,
        index: i64,
    },
    RemoveChild {
        parent: i64,
        child: i64,
    },
    MoveChild {
        parent: i64,
        child: i64,
        index: i64,
    },
}

#[derive(Debug, Clone)]
pub struct Batch {
    pub generation: i64,
    pub ops: Vec<Op>,
}

#[derive(Debug)]
pub struct DecodeError(pub String);

impl std::fmt::Display for DecodeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for DecodeError {}

fn int_field(object: &Map<String, Json>, name: &str, op: &str) -> Result<i64, DecodeError> {
    object
        .get(name)
        .and_then(Json::as_i64)
        .ok_or_else(|| DecodeError(format!("{op}: missing int field '{name}'")))
}

fn string_field<'a>(
    object: &'a Map<String, Json>,
    name: &str,
    op: &str,
) -> Result<&'a str, DecodeError> {
    object
        .get(name)
        .and_then(Json::as_str)
        .ok_or_else(|| DecodeError(format!("{op}: missing string field '{name}'")))
}

fn value_field(object: &Map<String, Json>, name: &str, op: &str) -> Result<Value, DecodeError> {
    object
        .get(name)
        .and_then(Value::from_json)
        .ok_or_else(|| DecodeError(format!("{op}: missing value field '{name}'")))
}

fn decode_op(json: &Json) -> Result<Op, DecodeError> {
    let object = json
        .as_object()
        .ok_or_else(|| DecodeError("op is not an object".into()))?;
    let op_name = string_field(object, "op", "op")?;
    match op_name {
        "create-node" => Ok(Op::CreateNode {
            id: int_field(object, "id", op_name)?,
            kind: string_field(object, "kind", op_name)?.to_string(),
        }),
        "create-extension" => Ok(Op::CreateExtension {
            id: int_field(object, "id", op_name)?,
            identifier: string_field(object, "identifier", op_name)?.to_string(),
            fingerprint: string_field(object, "fingerprint", op_name)?.to_string(),
        }),
        "drop-node" => Ok(Op::DropNode {
            id: int_field(object, "id", op_name)?,
        }),
        "set-prop" => Ok(Op::SetProp {
            id: int_field(object, "id", op_name)?,
            property: string_field(object, "property", op_name)?.to_string(),
            value: value_field(object, "value", op_name)?,
        }),
        "remove-prop" => Ok(Op::RemoveProp {
            id: int_field(object, "id", op_name)?,
            property: string_field(object, "property", op_name)?.to_string(),
        }),
        "set-extension-prop" => Ok(Op::SetExtensionProp {
            id: int_field(object, "id", op_name)?,
            property: string_field(object, "property", op_name)?.to_string(),
            value: value_field(object, "value", op_name)?,
        }),
        "remove-extension-prop" => Ok(Op::RemoveExtensionProp {
            id: int_field(object, "id", op_name)?,
            property: string_field(object, "property", op_name)?.to_string(),
        }),
        "insert-child" => Ok(Op::InsertChild {
            parent: int_field(object, "parent", op_name)?,
            child: int_field(object, "child", op_name)?,
            index: int_field(object, "index", op_name)?,
        }),
        "remove-child" => Ok(Op::RemoveChild {
            parent: int_field(object, "parent", op_name)?,
            child: int_field(object, "child", op_name)?,
        }),
        "move-child" => Ok(Op::MoveChild {
            parent: int_field(object, "parent", op_name)?,
            child: int_field(object, "child", op_name)?,
            index: int_field(object, "index", op_name)?,
        }),
        other => Err(DecodeError(format!("unknown op '{other}'"))),
    }
}

pub fn decode_batch(json: &str) -> Result<Batch, DecodeError> {
    let parsed: Json =
        serde_json::from_str(json).map_err(|error| DecodeError(error.to_string()))?;
    let object = parsed
        .as_object()
        .ok_or_else(|| DecodeError("patch batch is not an object".into()))?;
    let generation = int_field(object, "generation", "batch")?;
    let ops = object
        .get("ops")
        .and_then(Json::as_array)
        .ok_or_else(|| DecodeError("batch: missing 'ops' array".into()))?
        .iter()
        .map(decode_op)
        .collect::<Result<Vec<Op>, DecodeError>>()?;
    Ok(Batch { generation, ops })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_every_op_variant() {
        let json = r#"{
            "generation": 7,
            "ops": [
                {"op": "create-node", "id": 1, "kind": "root"},
                {"op": "create-extension", "id": 2, "identifier": "logseq-div",
                 "fingerprint": "fp1"},
                {"op": "set-prop", "id": 1, "property": "text", "value": "hi"},
                {"op": "remove-prop", "id": 1, "property": "text"},
                {"op": "set-extension-prop", "id": 2, "property": "style-class",
                 "value": "p-4"},
                {"op": "remove-extension-prop", "id": 2,
                 "property": "style-class"},
                {"op": "insert-child", "parent": 1, "child": 2, "index": 0},
                {"op": "move-child", "parent": 1, "child": 2, "index": 0},
                {"op": "remove-child", "parent": 1, "child": 2},
                {"op": "drop-node", "id": 2}
            ]
        }"#;
        let batch = decode_batch(json).expect("batch decodes");
        assert_eq!(batch.generation, 7);
        assert_eq!(batch.ops.len(), 10);
        match &batch.ops[0] {
            Op::CreateNode { id, kind } => {
                assert_eq!(*id, 1);
                assert_eq!(kind, "root");
            }
            other => panic!("expected create-node, got {other:?}"),
        }
        match &batch.ops[1] {
            Op::CreateExtension {
                id,
                identifier,
                fingerprint,
            } => {
                assert_eq!(*id, 2);
                assert_eq!(identifier, "logseq-div");
                assert_eq!(fingerprint, "fp1");
            }
            other => panic!("expected create-extension, got {other:?}"),
        }
        match &batch.ops[2] {
            Op::SetProp {
                id,
                property,
                value,
            } => {
                assert_eq!(*id, 1);
                assert_eq!(property, "text");
                assert_eq!(*value, Value::Str("hi".into()));
            }
            other => panic!("expected set-prop, got {other:?}"),
        }
        match &batch.ops[6] {
            Op::InsertChild {
                parent,
                child,
                index,
            } => {
                assert_eq!((*parent, *child, *index), (1, 2, 0));
            }
            other => panic!("expected insert-child, got {other:?}"),
        }
        match &batch.ops[7] {
            Op::MoveChild {
                parent,
                child,
                index,
            } => {
                assert_eq!((*parent, *child, *index), (1, 2, 0));
            }
            other => panic!("expected move-child, got {other:?}"),
        }
        match &batch.ops[8] {
            Op::RemoveChild { parent, child } => {
                assert_eq!((*parent, *child), (1, 2));
            }
            other => panic!("expected remove-child, got {other:?}"),
        }
        match &batch.ops[9] {
            Op::DropNode { id } => assert_eq!(*id, 2),
            other => panic!("expected drop-node, got {other:?}"),
        }
    }

    #[test]
    fn decodes_all_value_kinds() {
        assert_eq!(
            Value::from_json(&serde_json::json!("text")),
            Some(Value::Str("text".into()))
        );
        assert_eq!(
            Value::from_json(&serde_json::json!(true)),
            Some(Value::Bool(true))
        );
        assert_eq!(
            Value::from_json(&serde_json::json!(42)),
            Some(Value::Int(42))
        );
        assert_eq!(
            Value::from_json(&serde_json::json!(1.5)),
            Some(Value::Float(1.5))
        );
        assert_eq!(Value::from_json(&serde_json::json!(null)), None);
        assert_eq!(Value::from_json(&serde_json::json!([1])), None);
    }

    #[test]
    fn value_accessors_are_type_tolerant() {
        // Ints read as floats (OCaml emits IntValue where a float prop is
        // expected); the reverse is not true.
        assert_eq!(Value::Int(3).as_float(), Some(3.0));
        assert_eq!(Value::Float(2.5).as_int(), None);
        assert_eq!(Value::Bool(true).as_str(), None);
    }

    #[test]
    fn rejects_unknown_op_and_missing_fields() {
        for json in [
            r#"{"generation":1,"ops":[{"op":"frobnicate","id":1}]}"#,
            r#"{"generation":1,"ops":[{"op":"create-node"}]}"#,
            r#"{"generation":1,"ops":[{"op":"set-prop","id":1,"property":"text"}]}"#,
            r#"{"generation":1}"#,
            r#"{"ops":[]}"#,
            r#"[1,2,3]"#,
            "not json",
        ] {
            assert!(decode_batch(json).is_err(), "should reject: {json}");
        }
    }
}
