//! Compiled canonical OCaml validators and their scalar/string operations.
use crate::store::Node;
use serde_json::{Map, Value};
use std::sync::LazyLock;

#[path = "contract_generated.rs"]
mod generated;

pub use generated::DisplayValue;

/// Generated metadata contains no validator AST or oracle fixtures.
pub static CONTRACT: LazyLock<Value> = LazyLock::new(|| {
    serde_json::from_str(include_str!("../contract.json")).expect("generated native contract")
});

pub fn kinds() -> &'static Map<String, Value> {
    CONTRACT["kinds"].as_object().expect("kind map")
}

/// Standard parents admitted by the canonical extension validator.
pub fn extension_parent_supported(kind: &str) -> Result<bool, String> {
    let parents = CONTRACT["extensionRules"]["standardParents"]
        .as_array()
        .ok_or("canonical extension rules are missing; regenerate the native contract")?;
    Ok(parents.iter().any(|parent| parent == kind))
}

pub fn property_supported(kind: &str, property: &str) -> bool {
    kinds().get(kind).is_some_and(|definition| {
        definition["properties"]
            .as_array()
            .is_some_and(|properties| properties.iter().any(|name| name == property))
    })
}

pub fn child_supported(parent: &str, child: &str) -> bool {
    kinds().get(parent).is_some_and(|definition| {
        definition["children"]
            .as_array()
            .is_some_and(|children| children.iter().any(|kind| kind == child))
    })
}

pub fn event_supported(kind: &str, event: &str) -> bool {
    kinds().get(kind).is_some_and(|definition| {
        definition["events"]
            .as_array()
            .is_some_and(|events| events.iter().any(|name| name == event))
    })
}

pub fn validate_value(kind: &str, property: &str, value: &Value) -> Result<(), String> {
    if !property_supported(kind, property) {
        return Err(format!("{kind} does not support {property}"));
    }
    if scalar(property, value)
        .is_some_and(|value| generated::property_value_supported_for_kind(kind, property, value))
    {
        Ok(())
    } else {
        Err(format!("invalid {property} value for {kind}"))
    }
}

pub fn validate_node(node: &Node) -> Result<(), String> {
    if !kinds().contains_key(&node.kind) {
        return Err(format!("unknown kind {}", node.kind));
    }
    for (property, value) in &node.props {
        validate_value(&node.kind, property, value)?;
    }
    if !generated::node_properties_supported(&node.kind, &node.props) {
        return Err(format!("invalid final properties for {}", node.kind));
    }
    if node.kind == "box"
        && node.string("display") == "contents"
        && node.boolean("focus-within-enabled", false)
    {
        return Err("box display=contents cannot observe focus within".into());
    }
    sparse_virtual(node).map(|_| ())
}

/// Canonical sparse metadata, shared by final validation and native adapters.
pub(crate) struct SparseVirtual {
    pub count: u64,
    pub generation: u64,
    pub indices: Vec<usize>,
    pub scroll_index: Option<i64>,
}

pub(crate) fn sparse_virtual(node: &Node) -> Result<Option<SparseVirtual>, String> {
    if node.kind != "virtual-list" {
        return Ok(None);
    }
    let fields = [
        "virtual-total-count",
        "virtual-generation",
        "virtual-indices",
        "virtual-scroll-index",
    ];
    if !fields
        .iter()
        .any(|property| node.props.contains_key(*property))
    {
        return Ok(None);
    }
    let invalid = || format!("inconsistent virtual source on node {}", node.id);
    if !fields[..3]
        .iter()
        .all(|property| node.props.contains_key(*property))
    {
        return Err(invalid());
    }
    let count = node.props["virtual-total-count"]
        .as_i64()
        .filter(|count| (0..=OCAML_INT_MAX).contains(count))
        .ok_or_else(invalid)?;
    let generation = node.props["virtual-generation"]
        .as_i64()
        .filter(|generation| (1..=OCAML_INT_MAX).contains(generation))
        .ok_or_else(invalid)?;
    let indices = virtual_indices_of_string(node.string("virtual-indices")).ok_or_else(invalid)?;
    if indices.len() != node.children.len() || indices.iter().any(|index| *index >= count) {
        return Err(invalid());
    }
    let scroll_index = match node.props.get("virtual-scroll-index") {
        None => None,
        Some(value) => Some(
            value
                .as_i64()
                .filter(|target| *target >= -1 && *target < count)
                .ok_or_else(invalid)?,
        ),
    };
    Ok(Some(SparseVirtual {
        count: count as u64,
        generation: generation as u64,
        indices: indices
            .into_iter()
            .map(usize::try_from)
            .collect::<Result<_, _>>()
            .map_err(|_| invalid())?,
        scroll_index,
    }))
}

const OCAML_INT_MIN: i64 = -(1_i64 << 62);
const OCAML_INT_MAX: i64 = (1_i64 << 62) - 1;

#[derive(Clone, Copy, Debug, PartialEq)]
enum Scalar<'a> {
    String(&'a str),
    Int(i64),
    Float(f64),
    Bool(bool),
}

/// Integer syntax on a float-only property follows the existing wire decoder.
/// Integer properties keep their exact signed OCaml representation.
fn scalar<'a>(property: &str, value: &'a Value) -> Option<Scalar<'a>> {
    match value {
        Value::String(value) => Some(Scalar::String(value)),
        Value::Bool(value) => Some(Scalar::Bool(*value)),
        Value::Number(value) => {
            let types = CONTRACT["scalarTypes"][property].as_array()?;
            let floating = types.iter().any(|kind| kind == "float");
            let integer = types.iter().any(|kind| kind == "int");
            if value.is_f64() || (floating && !integer) {
                value.as_f64().map(Scalar::Float)
            } else {
                value
                    .as_i64()
                    .filter(|number| (OCAML_INT_MIN..=OCAML_INT_MAX).contains(number))
                    .map(Scalar::Int)
            }
        }
        Value::Null | Value::Array(_) | Value::Object(_) => None,
    }
}

fn lookup<'a>(property: &str, properties: &'a Map<String, Value>) -> Option<Scalar<'a>> {
    properties
        .get(property)
        .and_then(|value| scalar(property, value))
}

fn contains_property(property: &str, properties: &Map<String, Value>) -> bool {
    properties.contains_key(property)
}

fn true_property(properties: &Map<String, Value>, property: &str) -> bool {
    properties.get(property) == Some(&Value::Bool(true))
}

fn int_property(properties: &Map<String, Value>, property: &str, fallback: i64) -> i64 {
    match lookup(property, properties) {
        Some(Scalar::Int(value)) => value,
        _ => fallback,
    }
}

fn float_property(properties: &Map<String, Value>, property: &str, fallback: f64) -> f64 {
    match lookup(property, properties) {
        Some(Scalar::Float(value)) => value,
        _ => fallback,
    }
}

fn string_property_or<'a>(
    properties: &'a Map<String, Value>,
    property: &str,
    fallback: &'a str,
) -> &'a str {
    properties
        .get(property)
        .and_then(Value::as_str)
        .unwrap_or(fallback)
}

fn string_property_nonempty(properties: &Map<String, Value>, property: &str) -> bool {
    !string_property_or(properties, property, "").is_empty()
}

fn treeitem_properties(properties: &Map<String, Value>) -> bool {
    string_property_or(properties, "role", "") == "treeitem"
}

fn tree_row_kind(kind: &str) -> bool {
    kinds()
        .get(kind)
        .and_then(|kind| kind["treeRow"].as_bool())
        .unwrap_or(false)
}

fn surface_size_supported(properties: &Map<String, Value>) -> bool {
    ["width", "height"].iter().all(|axis| {
        let minimum = int_property(properties, &format!("min-{axis}"), 0);
        let fixed = int_property(properties, axis, minimum);
        fixed >= minimum
            && match lookup(&format!("max-{axis}"), properties) {
                None => true,
                Some(Scalar::Int(maximum)) => minimum <= maximum && fixed <= maximum,
                Some(_) => false,
            }
    })
}

fn viewport_size_supported(properties: &Map<String, Value>) -> bool {
    ["width", "height"].iter().all(|axis| {
        match (
            lookup(&format!("min-{axis}-viewport"), properties),
            lookup(&format!("max-{axis}-viewport"), properties),
        ) {
            (Some(Scalar::Float(minimum)), Some(Scalar::Float(maximum))) => minimum <= maximum,
            (Some(_), Some(_)) => false,
            _ => true,
        }
    })
}

fn ocaml_trim(value: &str) -> &str {
    value.trim_matches([' ', '\t', '\n', '\r', '\x0c'])
}

fn contains(value: &str, values: &[&str]) -> bool {
    values.contains(&value)
}

fn element_tag_supported(kind: &str, tag: &str) -> bool {
    kinds().get(kind).is_some_and(|kind| {
        kind["tags"]
            .as_array()
            .is_some_and(|tags| tags.iter().any(|value| value == tag))
    })
}

fn element_tag_known(tag: &str) -> bool {
    kinds().keys().any(|kind| element_tag_supported(kind, tag))
}

fn icon_name_supported(value: &str) -> bool {
    if CONTRACT["icons"]
        .as_array()
        .is_some_and(|icons| icons.iter().any(|icon| icon == value))
    {
        return true;
    }
    value.strip_prefix("app:").is_some_and(|slug| {
        !slug.is_empty()
            && slug.split('-').all(|part| {
                !part.is_empty()
                    && part
                        .bytes()
                        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
            })
    })
}

pub(crate) fn virtual_indices_of_string(value: &str) -> Option<Vec<i64>> {
    let body = value.strip_prefix('[')?.strip_suffix(']')?;
    if body.is_empty() {
        return Some(Vec::new());
    }
    let mut previous = -1;
    body.split(',')
        .map(|part| {
            let index = part.parse::<i64>().ok()?;
            if index <= previous || index > OCAML_INT_MAX || index.to_string() != part {
                return None;
            }
            previous = index;
            Some(index)
        })
        .collect()
}

/// The grammars use only finiteness and sign, avoiding precision loss when
/// classifying hexadecimal literals at overflow and subnormal boundaries.
fn finite_number_nonnegative(value: &str) -> Option<bool> {
    let without_separators = value.replace('_', "");
    let value = without_separators.trim_start_matches([' ', '\t', '\r', '\n', '\x0b', '\x0c']);
    let leading_space = value.len() != without_separators.len();
    let (negative, magnitude) = if let Some(value) = value.strip_prefix('-') {
        (true, value)
    } else {
        (false, value.strip_prefix('+').unwrap_or(value))
    };
    let Some(hex) = magnitude
        .strip_prefix("0x")
        .or_else(|| magnitude.strip_prefix("0X"))
    else {
        let number = value.parse::<f64>().ok()?;
        return number.is_finite().then_some(number >= 0.0);
    };
    let mut exponent_parts = hex.split(['p', 'P']);
    let mantissa = exponent_parts.next()?;
    let exponent = match exponent_parts.next() {
        None => 0_i64,
        Some(exponent) => {
            let exponent = if leading_space {
                exponent
            } else {
                exponent.trim_start_matches([' ', '\t', '\r', '\n', '\x0b', '\x0c'])
            };
            let unsigned = exponent.strip_prefix(['+', '-']).unwrap_or(exponent);
            if unsigned.is_empty() || !unsigned.bytes().all(|digit| digit.is_ascii_digit()) {
                return None;
            }
            exponent
                .parse::<i64>()
                .unwrap_or(if exponent.starts_with('-') {
                    i64::MIN
                } else {
                    i64::MAX
                })
        }
    };
    if exponent_parts.next().is_some() {
        return None;
    }
    let mut point = None;
    let mut digits = Vec::with_capacity(mantissa.len());
    for c in mantissa.bytes() {
        if c == b'.' && point.is_none() {
            point = Some(digits.len());
        } else {
            digits.push((c as char).to_digit(16)? as u8);
        }
    }
    if !leading_space && exponent <= i32::MIN as i64 {
        return Some(true);
    }
    if !leading_space && exponent >= i32::MAX as i64 {
        return digits.iter().all(|digit| *digit == 0).then_some(true);
    }
    if digits.is_empty() {
        return None;
    }
    let Some(first) = digits.iter().position(|digit| *digit != 0) else {
        return Some(true);
    };
    let leading = digits[first].ilog2() as i64;
    let binary_exponent = exponent
        .saturating_add(
            4_i64.saturating_mul(point.unwrap_or(digits.len()) as i64 - first as i64 - 1),
        )
        .saturating_add(leading);
    if binary_exponent > 1023 {
        return None;
    }
    let significant_bits = || {
        digits
            .iter()
            .flat_map(|digit| (0..4).rev().map(move |bit| digit & (1 << bit) != 0))
            .skip(first * 4 + (3 - leading as usize))
    };
    if binary_exponent == 1023 {
        let mut bits = significant_bits();
        if (0..54).all(|_| bits.next() == Some(true)) {
            return None;
        }
    }
    let mut fraction = significant_bits().skip(1);
    let rounded_above_one = fraction.by_ref().take(52).any(|bit| bit)
        || (fraction.next() == Some(true) && fraction.any(|bit| bit));
    // OCaml's own hex parser rounds its mantissa before scaling. Leading
    // whitespace selects strtod instead, which rounds the complete number.
    let zero = binary_exponent < -1075
        || (binary_exponent == -1075
            && if leading_space {
                !significant_bits().skip(1).any(|bit| bit)
            } else {
                !rounded_above_one
            });
    Some(!negative || zero)
}

fn anchor_rect_of_string(value: &str) -> Option<()> {
    let fields: Vec<_> = value.split(' ').collect();
    if fields.len() != 4 {
        return None;
    }
    for (index, field) in fields.iter().enumerate() {
        let nonnegative = finite_number_nonnegative(field)?;
        if index >= 2 && !nonnegative {
            return None;
        }
    }
    Some(())
}

fn data_attrs_value_ok(value: &str) -> bool {
    value.is_empty()
        || value.split('\x1e').all(|record| {
            let mut fields = record.split('\x1f');
            let name = fields.next().unwrap_or("");
            fields.next().is_some()
                && fields.next().is_none()
                && (matches!(name, "role" | "tabindex" | "draggable" | "style")
                    || name
                        .strip_prefix("data-")
                        .is_some_and(|suffix| !suffix.is_empty())
                    || name
                        .strip_prefix("aria-")
                        .is_some_and(|suffix| !suffix.is_empty()))
        })
}

fn text_decoration_supported(value: &str) -> bool {
    let tokens: Vec<_> = value
        .split(' ')
        .filter(|token| !ocaml_trim(token).is_empty())
        .collect();
    tokens == ["none"]
        || (!tokens.is_empty()
            && tokens
                .iter()
                .all(|token| matches!(*token, "underline" | "line-through" | "overline")))
}

fn css_identifier(value: &str) -> bool {
    let bytes = value.as_bytes();
    let alpha = |c: u8| c.is_ascii_alphabetic() || c == b'_';
    let Some(first) = bytes.first().copied() else {
        return false;
    };
    (alpha(first) || (first == b'-' && bytes.get(1).is_some_and(|c| alpha(*c) || *c == b'-')))
        && bytes[1..]
            .iter()
            .all(|c| alpha(*c) || c.is_ascii_digit() || *c == b'-')
}

fn css_time(value: &str) -> bool {
    value
        .strip_suffix("ms")
        .or_else(|| value.strip_suffix('s'))
        .is_some_and(|number| !number.is_empty() && finite_number_nonnegative(number) == Some(true))
}

fn css_tokens(segment: &str) -> Vec<&str> {
    let mut start = None;
    let mut depth = 0_u32;
    let mut tokens = Vec::new();
    for (index, c) in segment.bytes().enumerate() {
        if matches!(c, b' ' | b'\t' | b'\n' | b'\r') && depth == 0 {
            if let Some(start) = start.take() {
                tokens.push(&segment[start..index]);
            }
        } else {
            start.get_or_insert(index);
            if c == b'(' {
                depth += 1;
            } else if c == b')' {
                depth = depth.saturating_sub(1);
            }
        }
    }
    if let Some(start) = start {
        tokens.push(&segment[start..]);
    }
    tokens
}

fn transition_supported(value: &str) -> bool {
    if ocaml_trim(value).is_empty() {
        return false;
    }
    let mut segments = Vec::new();
    let mut start = 0;
    let mut depth = 0_u32;
    for (index, c) in value.bytes().enumerate() {
        match c {
            b'(' => depth += 1,
            b')' => depth = depth.saturating_sub(1),
            b',' if depth == 0 => {
                segments.push(&value[start..index]);
                start = index + 1;
            }
            _ => {}
        }
    }
    segments.push(&value[start..]);
    segments.into_iter().all(|segment| {
        let tokens = css_tokens(segment);
        if tokens.len() < 2 || !css_identifier(tokens[0]) {
            return false;
        }
        let mut times = 0;
        for token in &tokens[1..] {
            if css_time(token) {
                times += 1;
                continue;
            }
            if let Some(open) = token.find('(') {
                if open == 0
                    || token.len() <= open + 2
                    || !token.ends_with(')')
                    || !css_identifier(&token[..open])
                {
                    return false;
                }
            } else if !css_identifier(token) {
                return false;
            }
        }
        (1..=2).contains(&times)
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    static ORACLE: LazyLock<Value> = LazyLock::new(|| {
        serde_json::from_str(include_str!("../tests/fixtures/contract_oracle.json"))
            .expect("canonical OCaml oracle fixture")
    });

    fn raw_scalar(value: &Value) -> Scalar<'_> {
        match value["type"].as_str().unwrap() {
            "string" => Scalar::String(value["value"].as_str().unwrap()),
            "bool" => Scalar::Bool(value["value"].as_bool().unwrap()),
            "int" => Scalar::Int(value["value"].as_i64().unwrap()),
            "float" => Scalar::Float(value["value"].as_f64().unwrap()),
            ty => panic!("unsupported oracle type {ty}"),
        }
    }

    fn verdict(bits: &Value, index: usize) -> bool {
        let digit = bits.as_str().unwrap().as_bytes()[index / 4];
        (digit as char).to_digit(16).unwrap() & (1 << (index % 4)) != 0
    }

    #[test]
    fn compiled_scalar_predicates_match_the_canonical_ocaml_oracle() {
        let values = ORACLE["values"].as_array().unwrap();
        for (property, bits) in ORACLE["properties"].as_object().unwrap() {
            for (index, value) in values.iter().enumerate() {
                assert_eq!(
                    generated::property_value_supported(property, raw_scalar(value)),
                    verdict(bits, index),
                    "property {property}, value {value}"
                );
            }
        }
        for (kind, properties) in ORACLE["kindValues"].as_object().unwrap() {
            for (property, bits) in properties.as_object().unwrap() {
                for (index, value) in values.iter().enumerate() {
                    assert_eq!(
                        generated::property_value_supported_for_kind(
                            kind,
                            property,
                            raw_scalar(value)
                        ),
                        verdict(bits, index),
                        "kind {kind}, property {property}, value {value}"
                    );
                }
            }
        }
    }

    #[test]
    fn compiled_final_node_predicates_match_the_canonical_ocaml_oracle() {
        let values = ORACLE["values"].as_array().unwrap();
        for (kind, cases) in ORACLE["nodes"].as_object().unwrap() {
            let baseline: Map<String, Value> = cases["baseline"]
                .as_object()
                .unwrap()
                .iter()
                .map(|(name, value)| (name.clone(), value["value"].clone()))
                .collect();
            assert!(
                generated::node_properties_supported(kind, &baseline),
                "baseline {kind}"
            );
            for (property, bits) in cases["properties"].as_object().unwrap() {
                for (index, value) in values.iter().enumerate() {
                    let mut properties = baseline.clone();
                    properties.insert(property.clone(), value["value"].clone());
                    let actual = generated::property_value_supported_for_kind(
                        kind,
                        property,
                        raw_scalar(value),
                    ) && generated::node_properties_supported(kind, &properties);
                    assert_eq!(
                        actual,
                        verdict(bits, index),
                        "kind {kind}, property {property}, value {value}"
                    );
                }
            }
        }
    }

    #[test]
    fn integer_bounds_and_size_invariants_remain_exact_above_two_to_the_53() {
        let mut node = Node {
            kind: "column".into(),
            ..Default::default()
        };
        node.props
            .insert("min-width".into(), json!(9_007_199_254_740_993_i64));
        node.props
            .insert("width".into(), json!(9_007_199_254_740_992_i64));
        assert!(validate_node(&node).is_err());
        node.props
            .insert("width".into(), json!(9_007_199_254_740_993_i64));
        assert!(validate_node(&node).is_ok());
        assert!(validate_value("column", "width", &json!(OCAML_INT_MAX)).is_ok());
        assert!(validate_value("column", "width", &json!(OCAML_INT_MAX + 1)).is_err());
        assert!(validate_value("column", "margin", &json!(OCAML_INT_MIN)).is_ok());
        assert!(validate_value("column", "margin", &json!(OCAML_INT_MIN - 1)).is_err());
    }

    #[test]
    fn wire_float_normalization_preserves_domain_checks_and_rejects_non_scalars() {
        assert!(validate_value("column", "opacity", &json!(1)).is_ok());
        assert!(validate_value("column", "opacity", &json!(2)).is_err());
        assert!(validate_value("column", "gap", &json!(1.0)).is_err());
        assert!(validate_value("column", "gap", &json!(-1)).is_err());
        for invalid in [Value::Null, json!([]), json!({})] {
            assert!(validate_value("text", "text", &invalid).is_err());
        }
        for value in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
            assert!(!generated::property_value_supported(
                "opacity",
                Scalar::Float(value)
            ));
            assert!(!generated::property_value_supported(
                "grow",
                Scalar::Float(value)
            ));
        }
    }

    #[test]
    fn sparse_metadata_matches_committed_children_and_integer_grammar() {
        let mut node = Node {
            kind: "virtual-list".into(),
            props: json!({"virtual-total-count": 100_000, "virtual-generation": 7,
                          "virtual-indices": "[2,99999]", "virtual-scroll-index": -1})
            .as_object()
            .unwrap()
            .clone(),
            children: vec![5, 6].into(),
            ..Default::default()
        };
        assert!(validate_node(&node).is_ok());
        node.children = vec![5].into();
        assert!(validate_node(&node).is_err());
        node.children = vec![5, 6].into();
        node.props
            .insert("virtual-indices".into(), json!("[2,100000]"));
        assert!(validate_node(&node).is_err());
        node.props
            .insert("virtual-indices".into(), json!("[2,99999]"));
        node.props
            .insert("virtual-scroll-index".into(), json!(100_000));
        assert!(validate_node(&node).is_err());
        node.props.remove("virtual-generation");
        assert!(validate_node(&node).is_err());
        for malformed in [
            "[0, 1]",
            "[0,0]",
            "[01]",
            "[-0]",
            "[+1]",
            "[-1]",
            "[4611686018427387904]",
        ] {
            assert!(
                virtual_indices_of_string(malformed).is_none(),
                "{malformed}"
            );
        }
        assert_eq!(
            virtual_indices_of_string("[9007199254740993,9007199254740994]"),
            Some(vec![9_007_199_254_740_993, 9_007_199_254_740_994])
        );
    }

    #[test]
    fn hexadecimal_classification_covers_rounding_overflow_and_signed_underflow() {
        for value in [
            "0x1.fffffffffffffp1023",
            "0x1.fffffffffffff7p1023",
            "0x0p99999999999999999999999",
            "0x1p-1075",
            "-0x1p-1075",
            "-0x1.0000000000000001p-1075",
            "-0x1p-99999999999999999999999",
        ] {
            assert_eq!(finite_number_nonnegative(value), Some(true), "{value}");
        }
        assert_eq!(
            finite_number_nonnegative("-0x1.0000000000001p-1075"),
            Some(false)
        );
        for value in [
            "0x1.fffffffffffff8p1023",
            "0x1p1024",
            "0x1p99999999999999999999999",
            "0x1p",
            "0x.",
            "0x1  ",
            "0x1p+-1",
        ] {
            assert_eq!(finite_number_nonnegative(value), None, "{value}");
        }
    }
}
