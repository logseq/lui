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
    PreWrap,
}
impl WhiteSpace {
    fn parse(value: &str) -> Result<Self, String> {
        match value {
            "normal" => Ok(Self::Normal),
            "nowrap" => Ok(Self::Nowrap),
            "pre-wrap" => Ok(Self::PreWrap),
            _ => Err(format!(
                "NSH white-space={value:?} has no faithful native mapping"
            )),
        }
    }
    fn class(self) -> &'static str {
        match self {
            Self::Normal | Self::PreWrap => "whitespace-normal",
            Self::Nowrap => "whitespace-nowrap",
        }
    }
    fn text(self, value: &str) -> String {
        match self {
            Self::PreWrap => value.to_owned(),
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
pub(crate) fn bind<E: Element>(
    element: E,
    node: Signal<Arc<Node>>,
    theme: Option<crate::ui::Theme>,
) -> E {
    let inherited = use_context::<Scope>();
    element.app_class(move || {
        let node = node.get();
        let policy = authored(&node)
            .expect("validated whitespace policy")
            .or_else(|| inherited.and_then(|scope| scope.0.get()));
        let foreground = theme.and_then(|theme| {
            crate::style::foreground_classes(&node, &theme.get())
                .expect("atomically validated foreground inheritance")
        });
        // app_class is a single native binding: combine policy and color
        // utilities here so either live update cannot overwrite the other.
        match (policy, foreground) {
            (Some(policy), Some(foreground)) => {
                Some(format!("{} {}", policy.class(), foreground).into())
            }
            (Some(policy), None) => Some(policy.class().into()),
            (None, foreground) => foreground,
        }
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        render::{Event, Renderer},
        wire::Batch,
    };
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;
    use serde_json::{Value, json};
    use std::{cell::Cell, rc::Rc};

    #[test]
    fn explicit_whitespace_modes_collapse_only_css_spaces_and_preserve_preformatted_source() {
        let value = " a\t\r\n  b\u{00a0}\u{2003} c ";
        for policy in [WhiteSpace::Normal, WhiteSpace::Nowrap] {
            assert_eq!(policy.text(value), " a b\u{00a0}\u{2003} c ");
        }
        assert_eq!(WhiteSpace::PreWrap.text(value), value);
        for value in ["pre", "pre-line", "break-spaces", "inherit", "unknown"] {
            assert!(WhiteSpace::parse(value).is_err(), "{value}");
        }
    }
    fn patch(generation: u64, ops: Value) -> Batch {
        Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
    }
    fn publish(renderer: &Renderer, revision: &Cell<u64>, ops: Value) {
        let generation = revision.get() + 1;
        renderer.apply(patch(generation, ops)).unwrap();
        revision.set(generation);
    }
    #[component]
    fn WhitespaceScenario() -> impl IntoElement {
        let revision = Rc::new(Cell::new(1));
        let text_revision = revision.clone();
        let renderer = Renderer::new(move |event, renderer| {
            if let Event::Text(id, text) = event {
                publish(
                    &renderer,
                    &text_revision,
                    json!([{"op":"set-prop","id":id,"property":"text","value":text}]),
                );
            }
        });
        let mut ops = vec![
            json!({"op":"create-node","id":1,"kind":"alert"}),
            json!({"op":"set-prop","id":1,"property":"width","value":240}),
            json!({"op":"create-node","id":20,"kind":"column"}),
            json!({"op":"set-prop","id":20,"property":"cross","value":"start"}),
            json!({"op":"insert-child","parent":1,"child":20,"index":0}),
            json!({"op":"set-prop","id":1,"property":"font-size","value":"16px"}),
            json!({"op":"set-prop","id":1,"property":"line-height","value":"20px"}),
            json!({"op":"set-prop","id":1,"property":"white-space","value":"nowrap"}),
            json!({"op":"set-prop","id":20,"property":"gap","value":4}),
        ];
        for (id, policy) in [
            (2, None),
            (3, Some("normal")),
            (4, Some("pre-wrap")),
            (5, Some("pre-wrap")),
        ] {
            ops.extend([
                json!({"op":"create-node","id":id,"kind":"text"}),
                json!({"op":"set-prop","id":id,"property":"text","value":if id==5 {"one\nnext"} else {"Alpha  beta gamma\nnext"}}),
                json!({"op":"set-prop","id":id,"property":"width","value":100}),
                json!({"op":"insert-child","parent":20,"child":id,"index":id-2}),
            ]);
            if let Some(policy) = policy {
                ops.push(json!({"op":"set-prop","id":id,"property":"white-space","value":policy}));
            }
        }
        ops.extend([
            json!({"op":"create-node","id":6,"kind":"heading"}),
            json!({"op":"set-prop","id":6,"property":"text","value":"Head  \n label"}),
            json!({"op":"set-prop","id":6,"property":"white-space","value":"normal"}),
            json!({"op":"create-node","id":7,"kind":"button"}),
            json!({"op":"set-prop","id":7,"property":"text","value":"Save  \n draft"}),
            json!({"op":"set-prop","id":7,"property":"white-space","value":"normal"}),
            json!({"op":"set-prop","id":7,"property":"width","value":180}),
            json!({"op":"create-node","id":8,"kind":"textarea"}),
            json!({"op":"set-prop","id":8,"property":"text","value":"edit  me\nnext"}),
            json!({"op":"set-prop","id":8,"property":"change-enabled","value":true}),
            json!({"op":"set-prop","id":8,"property":"height","value":60}),
            json!({"op":"set-prop","id":8,"property":"width","value":180}),
            json!({"op":"insert-child","parent":20,"child":6,"index":4}),
            json!({"op":"insert-child","parent":20,"child":7,"index":5}),
            json!({"op":"insert-child","parent":20,"child":8,"index":6}),
        ]);
        renderer.apply(patch(1, Value::Array(ops))).unwrap();
        renderer.set_root(1).unwrap();
        let changing = renderer.clone();
        let change_revision = revision.clone();
        on_key_with(
            "f7",
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| {
                publish(
                    &changing,
                    &change_revision,
                    json!([{"op":"set-prop","id":1,"property":"white-space","value":"pre-wrap"}]),
                );
            },
        );
        let rejecting = renderer.clone();
        on_key_with(
            "f8",
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| {
                let generation = revision.get();
                let before = rejecting.node_snapshot(2).unwrap();
                assert!(rejecting.apply(patch(generation+1,json!([
                {"op":"set-prop","id":2,"property":"text","value":"must not publish"},
                {"op":"set-prop","id":2,"property":"white-space","value":"break-spaces"}
            ]))).is_err());
                assert!(Arc::ptr_eq(&before, &rejecting.node_snapshot(2).unwrap()));
            },
        );
        renderer.element()
    }
    fn geometry(app: &Headless, id: u64) -> nsh_testing::LayoutNode {
        let name = format!("lui-{id}");
        app.screen()
            .layout_nodes()
            .into_iter()
            .find(|node| node.test_id.as_deref() == Some(name.as_str()))
            .unwrap()
    }
    #[test]
    fn native_wrapping_inheritance_preserves_preformatted_labels_and_retained_editing() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<WhitespaceScenario>())).unwrap();
        app.wait_for("id:lui-2").unwrap();
        let nowrap = geometry(&app, 2);
        let normal = geometry(&app, 3);
        let prewrap = geometry(&app, 4);
        let pre = geometry(&app, 5);
        assert!(
            (nowrap.bounds.size.height.0 - 20.0).abs() < 0.1,
            "{:?}",
            nowrap.bounds
        );
        assert!(normal.bounds.size.height.0 > nowrap.bounds.size.height.0);
        assert!(
            (pre.bounds.size.height.0 - 40.0).abs() < 0.1,
            "{:?}",
            pre.bounds
        );
        assert!(prewrap.bounds.size.height.0 > pre.bounds.size.height.0);
        assert!(app.screen().texts().contains(&"Alpha beta gamma next"));
        assert!(app.screen().texts().contains(&"Alpha  beta gamma\nnext"));
        app.wait_for("text:Head label").unwrap();
        app.wait_for("text:Save draft").unwrap();
        assert_eq!(
            app.screen().input_text("id:lui-8").unwrap(),
            Some("edit  me\nnext")
        );
        let editor = geometry(&app, 8).id;
        app.type_text("id:lui-8", "  retained").unwrap();
        let draft = app
            .screen()
            .input_text("id:lui-8")
            .unwrap()
            .unwrap()
            .to_owned();
        app.press_key("f7").unwrap();
        assert_eq!(geometry(&app, 2).id, nowrap.id);
        assert_eq!(geometry(&app, 3).id, normal.id);
        assert_eq!(geometry(&app, 8).id, editor);
        assert!(geometry(&app, 2).bounds.size.height.0 > nowrap.bounds.size.height.0);
        assert!((geometry(&app, 3).bounds.size.height.0 - normal.bounds.size.height.0).abs() < 0.1);
        assert_eq!(
            app.screen().input_text("id:lui-8").unwrap(),
            Some(draft.as_str())
        );
        app.press_key("x").unwrap();
        let expected = format!("{draft}x");
        assert_eq!(
            app.screen().input_text("id:lui-8").unwrap(),
            Some(expected.as_str())
        );
        app.press_key("f8").unwrap();
        assert_eq!(geometry(&app, 2).id, nowrap.id);
        assert!(!app.screen().texts().contains(&"must not publish"));
        app.press_key("y").unwrap();
        assert_eq!(
            app.screen().input_text("id:lui-8").unwrap(),
            Some(format!("{expected}y").as_str())
        );
    }
}
