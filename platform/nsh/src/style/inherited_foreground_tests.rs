//! Public native colors and state variants; no adapter-side ancestor color cache.
use super::*;
use crate::{render::Renderer, wire::Batch};
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
use serde_json::json;
use std::{cell::Cell, rc::Rc};

fn theme(dark: bool) -> ThemeView {
    ThemeView::new(
        Arc::new(nsh_base::Theme::default().tokens().clone()),
        dark,
        true,
    )
}
fn node(props: Value) -> Node {
    Node {
        kind: "button".into(),
        props: props.as_object().unwrap().clone(),
        ..Default::default()
    }
}
#[test]
fn inherited_foreground_is_typed_and_only_authored_channels_add_classes() {
    let t = theme(false);
    assert_eq!(t.foreground("inherit").unwrap(), Foreground::Inherit);
    assert_eq!(t.foreground("currentColor").unwrap(), Foreground::Inherit);
    assert!(
        t.color("inherit").is_err(),
        "nonforeground color properties still need actual colors"
    );
    let base = node(json!({"foreground":"inherit","hover-foreground":"#00ff00"}));
    assert_eq!(
        foreground_classes(&base, &t).unwrap().as_deref(),
        Some("text-inherit")
    );
    let hovered = node(json!({"foreground":"#0000ff","hover-foreground":"inherit"}));
    assert_eq!(
        foreground_classes(&hovered, &t).unwrap().as_deref(),
        Some("hover:text-inherit")
    );
    assert!(foreground_classes(&node(json!({})), &t).unwrap().is_none());
}
#[test]
fn aliases_and_mixed_appearance_tokens_follow_the_scoped_theme() {
    let props = json!({"theme":r##"{"--ink":"inherit","alias":"--ink","--mixed":{"light":"inherit","dark":"#123456"}}"##});
    let scope = Node {
        kind: "box".into(),
        props: props.as_object().unwrap().clone(),
        ..Default::default()
    };
    let light = theme(false).overlay(&scope).unwrap();
    let dark = theme(true).overlay(&scope).unwrap();
    assert_eq!(light.foreground("alias").unwrap(), Foreground::Inherit);
    assert_eq!(
        light.foreground("var(--missing, inherit)").unwrap(),
        Foreground::Inherit
    );
    assert_eq!(
        light.foreground("var(--mixed)").unwrap(),
        Foreground::Inherit
    );
    assert_eq!(
        dark.foreground("var(--mixed)").unwrap(),
        Foreground::Color(Color::parse("#123456").unwrap().into())
    );
}
fn batch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}
#[component]
fn NativeInheritance() -> impl IntoElement {
    let renderer = Renderer::new(|_, _| {});
    renderer
        .apply(batch(
            1,
            json!([
                {"op":"create-node","id":1,"kind":"column"},
                {"op":"set-prop","id":1,"property":"width","value":400},
                {"op":"set-prop","id":1,"property":"height","value":400},
                {"op":"set-prop","id":1,"property":"foreground","value":"#ff0000"},
                {"op":"create-node","id":2,"kind":"text"},
                {"op":"set-prop","id":2,"property":"text","value":"Plain  inherited"},
                {"op":"set-prop","id":2,"property":"foreground","value":"inherit"},
                {"op":"set-prop","id":2,"property":"white-space","value":"normal"},
                {"op":"insert-child","parent":1,"child":2,"index":0},
                {"op":"create-node","id":3,"kind":"button"},
                {"op":"set-prop","id":3,"property":"text","value":"Inherited label"},
                {"op":"set-prop","id":3,"property":"foreground","value":"inherit"},
                {"op":"set-prop","id":3,"property":"hover-foreground","value":"#00ff00"},
                {"op":"insert-child","parent":1,"child":3,"index":1},
                {"op":"create-node","id":4,"kind":"button"},
                {"op":"set-prop","id":4,"property":"text","value":"Inherited hover"},
                {"op":"set-prop","id":4,"property":"foreground","value":"#0000ff"},
                {"op":"set-prop","id":4,"property":"hover-foreground","value":"inherit"},
                {"op":"insert-child","parent":1,"child":4,"index":2},
            ]),
        ))
        .unwrap();
    renderer.set_root(1).unwrap();
    let revision = Rc::new(Cell::new(1));
    let recolor = renderer.clone();
    let recolor_revision = revision.clone();
    on_key_with(
        "f2",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            let next = recolor_revision.get() + 1;
            recolor
                .apply(batch(
                    next,
                    json!([
                        {"op":"set-prop","id":1,"property":"foreground","value":"#00ffff"}
                    ]),
                ))
                .unwrap();
            recolor_revision.set(next);
        },
    );
    let own = renderer.clone();
    on_key_with(
        "f3",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            let next = revision.get() + 1;
            own.apply(batch(
                next,
                json!([
                    {"op":"set-prop","id":3,"property":"foreground","value":"#112233"}
                ]),
            ))
            .unwrap();
            revision.set(next);
        },
    );
    renderer.element()
}
fn start() -> Headless {
    let mut config = EngineConfig::new(Root::of::<NativeInheritance>());
    config.environment.reduce_motion = true;
    config.environment.os = nsh_core::platform::Os::MacOs;
    let mut app = Headless::start(config).unwrap();
    app.wait_for("text:Inherited label").unwrap();
    app
}
fn native_text(app: &Headless, label: &str) -> (nsh_core::NodeId, Color) {
    app.screen()
        .layout_nodes()
        .into_iter()
        .find_map(|node| {
            let text = node.text?;
            (text.text.text == label).then(|| (node.id, text.text.uniform_color().unwrap()))
        })
        .unwrap_or_else(|| panic!("native text absent: {label}"))
}
#[test]
fn native_button_default_is_cleared_and_concrete_hover_still_wins() {
    let mut app = start();
    let red = Color::parse("#ff0000").unwrap();
    let green = Color::parse("#00ff00").unwrap();
    let before = native_text(&app, "Inherited label");
    assert_eq!(before.1, red);
    assert_eq!(
        native_text(&app, "Plain inherited").1,
        red,
        "whitespace and inheritance must share one app_class binding"
    );
    app.hover("id:lui-3").unwrap();
    assert_eq!(native_text(&app, "Inherited label").1, green);
    app.hover("id:lui-1").unwrap();
    assert_eq!(native_text(&app, "Inherited label"), before);
    app.press_key("f3").unwrap();
    assert_eq!(native_text(&app, "Inherited label").0, before.0);
    assert_eq!(
        native_text(&app, "Inherited label").1,
        Color::parse("#112233").unwrap()
    );
}
#[test]
fn native_hover_inherits_live_ancestor_changes_without_remounting() {
    let mut app = start();
    let before = native_text(&app, "Inherited hover");
    assert_eq!(before.1, Color::parse("#0000ff").unwrap());
    app.hover("id:lui-4").unwrap();
    assert_eq!(
        native_text(&app, "Inherited hover").1,
        Color::parse("#ff0000").unwrap()
    );
    app.press_key("f2").unwrap();
    let next = native_text(&app, "Inherited hover");
    assert_eq!(next.0, before.0);
    assert_eq!(next.1, Color::parse("#00ffff").unwrap());
    assert_eq!(native_text(&app, "Inherited label").1, next.1);
    app.hover("id:lui-1").unwrap();
    assert_eq!(native_text(&app, "Inherited hover"), before);
}
