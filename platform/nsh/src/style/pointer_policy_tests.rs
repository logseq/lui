use super::*;
use crate::{
    render::{Event, Renderer},
    wire::Batch,
};
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use serde_json::json;
use std::sync::Mutex;

#[derive(Clone)]
struct Presses(Arc<Mutex<Vec<u64>>>);

#[component]
fn CoverScenario() -> impl IntoElement {
    let presses = engine_context::<Presses>().unwrap();
    let renderer = Renderer::new(move |event, _| {
        if let Event::Press(id) = event {
            presses.0.lock().unwrap().push(id);
        }
    });
    renderer
        .apply(
            Batch::decode(
                &json!({"generation":1,"ops":[
                    {"op":"create-node","id":1,"kind":"stack"},
                    {"op":"set-prop","id":1,"property":"width","value":400},
                    {"op":"set-prop","id":1,"property":"height","value":240},
                    {"op":"create-node","id":2,"kind":"column"},
                    {"op":"create-node","id":3,"kind":"button"},
                    {"op":"set-prop","id":3,"property":"text","value":"Underlying"},
                    {"op":"set-prop","id":3,"property":"press-enabled","value":true},
                    {"op":"set-prop","id":3,"property":"width","value":240},
                    {"op":"set-prop","id":3,"property":"height","value":40},
                    {"op":"insert-child","parent":2,"child":3,"index":0},
                    {"op":"insert-child","parent":1,"child":2,"index":0},
                    {"op":"create-node","id":4,"kind":"overlay"},
                    {"op":"set-prop","id":4,"property":"pointer-enabled","value":false},
                    {"op":"set-prop","id":4,"property":"width","value":400},
                    {"op":"set-prop","id":4,"property":"height","value":240},
                    {"op":"insert-child","parent":1,"child":4,"index":1},
                    {"op":"create-node","id":5,"kind":"column"},
                    {"op":"insert-child","parent":4,"child":5,"index":0},
                    {"op":"create-node","id":7,"kind":"button"},
                    {"op":"set-prop","id":7,"property":"text","value":"Suppressed caption"},
                    {"op":"set-prop","id":7,"property":"press-enabled","value":true},
                    {"op":"set-prop","id":7,"property":"width","value":240},
                    {"op":"set-prop","id":7,"property":"height","value":40},
                    {"op":"insert-child","parent":5,"child":7,"index":0},
                    {"op":"create-node","id":6,"kind":"button"},
                    {"op":"set-prop","id":6,"property":"text","value":"Opted in"},
                    {"op":"set-prop","id":6,"property":"pointer-enabled","value":true},
                    {"op":"set-prop","id":6,"property":"press-enabled","value":true},
                    {"op":"insert-child","parent":5,"child":6,"index":1}
                ]})
                .to_string(),
            )
            .unwrap(),
        )
        .unwrap();
    renderer.set_root(1).unwrap();
    renderer.element()
}

#[test]
fn cover_policy_routes_real_presses_through_passive_descendants_and_restores_explicit_children() {
    let presses = Arc::new(Mutex::new(Vec::new()));
    let mut config = EngineConfig::new(Root::of::<CoverScenario>());
    config.context = EngineContext::default().with(Presses(presses.clone()));
    let mut app = Headless::start(config).unwrap();
    app.wait_for("Underlying").unwrap();
    app.press("Underlying").unwrap();
    app.press("Opted in").unwrap();
    app.press("Underlying").unwrap();
    assert_eq!(*presses.lock().unwrap(), [3, 6, 3]);
}

#[test]
fn pointer_policy_preserves_explicit_overrides_and_presented_surface_defaults() {
    use nsh_core::PointerEvents;
    let mut node = Node::default();
    for kind in ["box", "button", "overlay"] {
        node.kind = kind.into();
        assert_eq!(pointer_policy(&node), None);
        node.props.insert("pointer-enabled".into(), json!(false));
        assert_eq!(pointer_policy(&node), Some(PointerEvents::None));
        node.props.insert("pointer-enabled".into(), json!(true));
        assert_eq!(pointer_policy(&node), Some(PointerEvents::Auto));
        node.props.clear();
    }
    for kind in [
        "dialog",
        "sheet",
        "popover",
        "dropdown-menu",
        "context-menu",
        "toast",
        "drawer",
    ] {
        node.kind = kind.into();
        assert_eq!(pointer_policy(&node), Some(PointerEvents::Auto));
        node.props.insert(
            "data-attrs".into(),
            json!("title\u{1f}layer\u{1e}data-overlay-layer\u{1f}true"),
        );
        assert_eq!(pointer_policy(&node), None);
        node.props.clear();
    }
    node.kind = "drawer".into();
    node.props.insert("selected".into(), json!(false));
    assert_eq!(pointer_policy(&node), None);
}

#[derive(Clone)]
struct SpacerProbe {
    opt_in: bool,
    events: Arc<Mutex<Vec<Event>>>,
}

#[component]
fn StackedSpacers() -> impl IntoElement {
    let probe = engine_context::<SpacerProbe>().unwrap();
    let events = probe.events.clone();
    let renderer = Renderer::new(move |event, _| events.lock().unwrap().push(event));
    let mut operations = vec![
        json!({"op":"create-node","id":1,"kind":"stack"}),
        json!({"op":"set-prop","id":1,"property":"width","value":400}),
        json!({"op":"set-prop","id":1,"property":"height","value":240}),
        json!({"op":"create-node","id":2,"kind":"column"}),
        json!({"op":"insert-child","parent":1,"child":2,"index":0}),
        json!({"op":"create-node","id":3,"kind":"button"}),
        json!({"op":"set-prop","id":3,"property":"text","value":"Toggle sidebar"}),
        json!({"op":"set-prop","id":3,"property":"press-enabled","value":true}),
        json!({"op":"set-prop","id":3,"property":"width","value":240}),
        json!({"op":"set-prop","id":3,"property":"height","value":40}),
        json!({"op":"insert-child","parent":2,"child":3,"index":0}),
        json!({"op":"create-node","id":41,"kind":"spacer"}),
        json!({"op":"insert-child","parent":1,"child":41,"index":1}),
        json!({"op":"create-node","id":42,"kind":"spacer"}),
        json!({"op":"insert-child","parent":1,"child":42,"index":2}),
    ];
    if probe.opt_in {
        operations.push(json!({"op":"set-prop","id":42,"property":"pointer-enabled","value":true}));
    }
    renderer
        .apply(Batch::decode(&json!({"generation":1,"ops":operations}).to_string()).unwrap())
        .unwrap();
    renderer.set_root(1).unwrap();
    let changing = renderer.clone();
    on_key_with(
        "f6",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            changing
                .apply(
                    Batch::decode(
                        &json!({"generation":2,"ops":[
                            {"op":"set-prop","id":42,"property":"pointer-enabled","value":false}
                        ]})
                        .to_string(),
                    )
                    .unwrap(),
                )
                .unwrap();
        },
    );
    renderer.element()
}

fn spacer_app(opt_in: bool) -> (Headless, Arc<Mutex<Vec<Event>>>) {
    let events = Arc::new(Mutex::new(Vec::new()));
    let mut config = EngineConfig::new(Root::of::<StackedSpacers>());
    config.context = EngineContext::default().with(SpacerProbe {
        opt_in,
        events: events.clone(),
    });
    let mut app = Headless::start(config).unwrap();
    app.wait_for("Toggle sidebar").unwrap();
    (app, events)
}

#[test]
fn default_empty_stacked_spacers_do_not_intercept_native_button_presses() {
    let (mut app, events) = spacer_app(false);
    let before = app.screen().layout_nodes();
    let button = before
        .iter()
        .find(|node| node.test_id.as_deref() == Some("lui-3"))
        .unwrap();
    for id in ["lui-41", "lui-42"] {
        let spacer = before
            .iter()
            .find(|node| node.test_id.as_deref() == Some(id))
            .unwrap();
        assert!(spacer.bounds.size.width >= button.bounds.size.width);
        assert!(spacer.bounds.size.height >= button.bounds.size.height);
    }
    app.press("Toggle sidebar").unwrap();
    app.press("Toggle sidebar").unwrap();
    assert_eq!(
        events
            .lock()
            .unwrap()
            .iter()
            .filter(|event| matches!(event, Event::Press(3)))
            .count(),
        2
    );
}

#[test]
fn explicit_spacer_pointer_opt_in_receives_hover_and_can_disable_without_remounting() {
    let (mut app, events) = spacer_app(true);
    let before = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some("lui-42"))
        .unwrap();
    app.hover("id:lui-42").unwrap();
    assert!(events.lock().unwrap().contains(&Event::PointerEnter(42)));
    let error = app.press("Toggle sidebar").unwrap_err();
    assert!(error.contains("lui-42"), "{error}");
    app.press_key("f6").unwrap();
    app.press("Toggle sidebar").unwrap();
    assert!(events.lock().unwrap().contains(&Event::Press(3)));
    let after = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some("lui-42"))
        .unwrap();
    assert_eq!(before.id, after.id);
    assert_eq!(before.bounds, after.bounds);
}

#[test]
fn spacer_pointer_policy_defaults_to_transparency_and_respects_explicit_values() {
    use nsh_core::PointerEvents;
    let mut node = Node {
        kind: "spacer".into(),
        ..Default::default()
    };
    assert_eq!(pointer_policy(&node), Some(PointerEvents::None));
    node.props.insert("pointer-enabled".into(), json!(true));
    assert_eq!(pointer_policy(&node), Some(PointerEvents::Auto));
    node.props.insert("pointer-enabled".into(), json!(false));
    assert_eq!(pointer_policy(&node), Some(PointerEvents::None));
}
