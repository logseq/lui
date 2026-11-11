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
