//! Structural contents regions participate in the real native parent's layout.
use super::*;
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use serde_json::json;
use std::sync::Mutex;

#[derive(Clone)]
struct Probe {
    column: bool,
    appeared: Arc<Mutex<Vec<u64>>>,
}
fn patch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}
fn publish(renderer: &Renderer, ops: Value) {
    let generation = renderer.0.borrow().store.generation + 1;
    renderer.apply(patch(generation, ops)).unwrap();
}
#[component]
fn ContentsScenario() -> impl IntoElement {
    let probe = engine_context::<Probe>().unwrap();
    let appeared = probe.appeared.clone();
    let renderer = Renderer::new(move |event, renderer| match event {
        Event::Text(id, text) => publish(
            &renderer,
            json!([{"op":"set-prop","id":id,"property":"text","value":text}]),
        ),
        Event::Appear(id) => appeared.lock().unwrap().push(id),
        _ => {}
    });
    renderer
        .apply(patch(
            1,
            json!([
                {"op":"create-node","id":1,"kind":if probe.column {"column"} else {"row"}},
                {"op":"set-prop","id":1,"property":"width","value":260},
                {"op":"set-prop","id":1,"property":"height","value":220},
                {"op":"set-prop","id":1,"property":"gap","value":10},
                {"op":"set-prop","id":1,"property":"cross","value":"start"},
                {"op":"create-node","id":2,"kind":"box"},
                {"op":"set-prop","id":2,"property":"display","value":"contents"},
                {"op":"set-prop","id":2,"property":"width","value":999},
                {"op":"set-prop","id":2,"property":"padding","value":100},
                {"op":"set-prop","id":2,"property":"gap","value":77},
                {"op":"set-prop","id":2,"property":"background","value":"#ff0000"},
                {"op":"set-prop","id":2,"property":"appear-enabled","value":true},
                {"op":"create-node","id":6,"kind":"row"},
                {"op":"set-prop","id":6,"property":"display","value":"contents"},
                {"op":"create-node","id":3,"kind":"text-field"},
                {"op":"set-prop","id":3,"property":"text","value":"seed"},
                {"op":"set-prop","id":3,"property":"change-enabled","value":true},
                {"op":"set-prop","id":3,"property":"width","value":80},
                {"op":"set-prop","id":3,"property":"height","value":32},
                {"op":"create-node","id":4,"kind":"button"},
                {"op":"set-prop","id":4,"property":"text","value":"B"},
                {"op":"set-prop","id":4,"property":"width","value":50},
                {"op":"set-prop","id":4,"property":"height","value":32},
                {"op":"create-node","id":5,"kind":"box"},
                {"op":"set-prop","id":5,"property":"width","value":20},
                {"op":"set-prop","id":5,"property":"height","value":32},
                {"op":"create-node","id":7,"kind":"column"},
                {"op":"set-prop","id":7,"property":"display","value":"contents"},
                {"op":"set-prop","id":7,"property":"appear-enabled","value":true},
                {"op":"insert-child","parent":6,"child":3,"index":0},
                {"op":"insert-child","parent":2,"child":6,"index":0},
                {"op":"insert-child","parent":2,"child":4,"index":1},
                {"op":"insert-child","parent":1,"child":2,"index":0},
                {"op":"insert-child","parent":1,"child":5,"index":1},
                {"op":"insert-child","parent":1,"child":7,"index":2}
            ]),
        ))
        .unwrap();
    renderer.set_root(1).unwrap();
    let reorder = renderer.clone();
    on_key_with(
        "f7",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            publish(
                &reorder,
                json!([
                    {"op":"move-child","parent":1,"child":2,"index":1},
                    {"op":"move-child","parent":2,"child":4,"index":0}
                ]),
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
            for (property, value) in [
                ("display", json!("flex")),
                ("press-enabled", json!(true)),
                ("font-size", json!("20px")),
                ("enabled", json!(false)),
            ] {
                let before = rejecting.0.borrow().store.nodes[&3].clone();
                let generation = rejecting.0.borrow().store.generation;
                assert!(rejecting.apply(patch(generation+1,json!([
                {"op":"set-prop","id":3,"property":"text","value":"must not publish"},
                {"op":"set-prop","id":2,"property":property,"value":value}
            ]))).is_err(),"{property}");
                assert_eq!(rejecting.0.borrow().store.generation, generation);
                assert!(Arc::ptr_eq(&before, &rejecting.0.borrow().store.nodes[&3]));
            }
        },
    );
    renderer.element()
}
fn geometry(app: &Headless, id: u64) -> nsh_testing::LayoutNode {
    let test_id = format!("lui-{id}");
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some(test_id.as_str()))
        .unwrap()
}
fn close(actual: f32, expected: f32) {
    assert!((actual - expected).abs() < 0.1, "{actual} != {expected}");
}
fn exercise(column: bool) {
    let appeared = Arc::new(Mutex::new(Vec::new()));
    let mut app = Headless::start(EngineConfig {
        context: EngineContext::default().with(Probe {
            column,
            appeared: appeared.clone(),
        }),
        ..EngineConfig::new(Root::of::<ContentsScenario>())
    })
    .unwrap();
    app.wait_for("id:lui-3").unwrap();
    let parent = geometry(&app, 1);
    let field = geometry(&app, 3);
    let button = geometry(&app, 4);
    let sibling = geometry(&app, 5);
    close(field.bounds.origin.x.0, parent.bounds.origin.x.0);
    close(field.bounds.origin.y.0, parent.bounds.origin.y.0);
    close(field.bounds.size.width.0, 80.0);
    close(field.bounds.size.height.0, 32.0);
    if column {
        close(button.bounds.origin.y.0 - field.bounds.origin.y.0, 42.0);
        close(sibling.bounds.origin.y.0 - button.bounds.origin.y.0, 42.0);
    } else {
        close(button.bounds.origin.x.0 - field.bounds.origin.x.0, 90.0);
        close(sibling.bounds.origin.x.0 - button.bounds.origin.x.0, 60.0);
    }
    assert!(
        !app.screen()
            .layout_nodes()
            .iter()
            .any(|node| matches!(node.test_id.as_deref(), Some("lui-2" | "lui-6" | "lui-7")))
    );
    app.type_text("id:lui-3", " draft").unwrap();
    let draft = app
        .screen()
        .input_text("id:lui-3")
        .unwrap()
        .unwrap()
        .to_owned();
    app.press_key("f7").unwrap();
    for (id, native) in [(3, field.id), (4, button.id), (5, sibling.id)] {
        assert_eq!(geometry(&app, id).id, native);
    }
    let moved = geometry(&app, 3);
    if column {
        close(moved.bounds.origin.y.0 - parent.bounds.origin.y.0, 84.0);
    } else {
        close(moved.bounds.origin.x.0 - parent.bounds.origin.x.0, 90.0);
    }
    app.press_key("x").unwrap();
    let expected = format!("{draft}x");
    assert_eq!(
        app.screen().input_text("id:lui-3").unwrap(),
        Some(expected.as_str())
    );
    app.press_key("f8").unwrap();
    assert_eq!(geometry(&app, 3).id, field.id);
    assert_eq!(
        app.screen().input_text("id:lui-3").unwrap(),
        Some(expected.as_str())
    );
    let mut appeared = appeared.lock().unwrap().clone();
    appeared.sort_unstable();
    assert_eq!(appeared, [2, 7]);
}
#[test]
fn contents_regions_flatten_into_row_geometry_and_reorder_retained_focused_editor() {
    exercise(false);
}
#[test]
fn contents_regions_flatten_into_column_geometry_and_reorder_retained_focused_editor() {
    exercise(true);
}
