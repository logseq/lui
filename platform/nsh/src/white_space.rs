//! Canonical whitespace policy over NSH's inherited native NoWrap text property.
//! Text normalization is presentation-only; editable values and extension payloads
//! remain owned by their existing controllers.
use crate::store::Node;
use nsh_core::prelude::*;
use std::sync::Arc;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum WhiteSpace {
    Normal,
    Nowrap,
    Pre,
    PreWrap,
}
impl WhiteSpace {
    fn parse(value: &str) -> Result<Self, String> {
        match value {
            "normal" => Ok(Self::Normal),
            "nowrap" => Ok(Self::Nowrap),
            "pre" => Ok(Self::Pre),
            "pre-wrap" => Ok(Self::PreWrap),
            _ => Err(format!(
                "NSH white-space={value:?} has no faithful native mapping"
            )),
        }
    }
    fn class(self) -> &'static str {
        match self {
            Self::Normal | Self::PreWrap => "whitespace-normal",
            Self::Nowrap | Self::Pre => "whitespace-nowrap",
        }
    }
    fn text(self, value: &str) -> String {
        match self {
            Self::Pre | Self::PreWrap => value.to_owned(),
            Self::Normal | Self::Nowrap => {
                let mut output = String::with_capacity(value.len());
                let mut space = false;
                for character in value.chars() {
                    let collapsible = matches!(character, ' ' | '\t' | '\n' | '\r' | '\x0c');
                    if !collapsible || !space {
                        output.push(if collapsible { ' ' } else { character });
                    }
                    space = collapsible;
                }
                output
            }
        }
    }
}
fn authored(node: &Node) -> Result<Option<WhiteSpace>, String> {
    node.props
        .get("white-space")
        .map(|value| WhiteSpace::parse(value.as_str().ok_or("NSH white-space requires a string")?))
        .transpose()
}
pub(crate) fn validate(node: &Node) -> Result<(), String> {
    authored(node).map(|_| ())
}
#[derive(Clone, Copy)]
struct Scope(Memo<Option<WhiteSpace>>);

/// The memo only notifies descendants when the effective policy changes; an
/// unrelated parent property edit does not re-normalize its children's strings.
pub(crate) fn enter(node: Signal<Arc<Node>>) {
    let parent = use_context::<Scope>();
    let policy = computed(move || {
        authored(&node.get())
            .expect("validated whitespace policy")
            .or_else(|| parent.and_then(|parent| parent.0.get()))
    });
    provide_context(Scope(policy));
}
pub(crate) fn bind<E: Element>(element: E, node: Signal<Arc<Node>>) -> E {
    let inherited = use_context::<Scope>();
    element.app_class(move || {
        let policy = authored(&node.get())
            .expect("validated whitespace policy")
            .or_else(|| inherited.and_then(|scope| scope.0.get()));
        policy.map(|policy| SharedString::from(policy.class()))
    })
}

pub(crate) fn property(node: Signal<Arc<Node>>, name: &str) -> SharedString {
    let inherited = use_context::<Scope>();
    let node = node.get();
    let policy = authored(&node)
        .expect("validated whitespace policy")
        .or_else(|| inherited.and_then(|scope| scope.0.get()));
    let text = node.string(name);
    match policy {
        Some(policy) => policy.text(text).into(),
        None => text.to_owned().into(),
    }
}
pub(crate) fn text(node: Signal<Arc<Node>>) -> SharedString {
    property(node, "text")
}
