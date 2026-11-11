//! Resolve 1em through the real native parent and preserve retained text/control roots.
use super::*;
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
use serde_json::json;

fn patch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}
#[component]
fn FontSizeScenario() -> impl IntoElement {
    let renderer = Renderer::new(|_, _| {});
    renderer
        .apply(patch(
            1,
            json!([
                {"op":"create-node","id":1,"kind":"column"},
                {"op":"set-prop","id":1,"property":"font-size","value":"24px"},
                {"op":"set-prop","id":1,"property":"gap","value":4},
                {"op":"set-prop","id":1,"property":"cross","value":"start"},
                {"op":"create-node","id":2,"kind":"box"},
                {"op":"set-prop","id":2,"property":"font-size","value":"20px"},
                {"op":"set-prop","id":2,"property":"line-height","value":"1.2"},
                {"op":"set-prop","id":2,"property":"cross","value":"start"},
                {"op":"create-node","id":3,"kind":"text"},
                {"op":"set-prop","id":3,"property":"text","value":"MMMM"},
                {"op":"set-prop","id":3,"property":"font-size","value":"1em"},
                {"op":"create-node","id":4,"kind":"text"},
                {"op":"set-prop","id":4,"property":"text","value":"MMMM"},
                {"op":"set-prop","id":4,"property":"font-size","value":"20px"},
                {"op":"create-node","id":5,"kind":"text"},
                {"op":"set-prop","id":5,"property":"text","value":"MMMM"},
                {"op":"set-prop","id":5,"property":"font-size","value":"1.25rem"},
                {"op":"create-node","id":6,"kind":"button"},
                {"op":"set-prop","id":6,"property":"text","value":"Command"},
                {"op":"set-prop","id":6,"property":"font-size","value":"1.0em"},
                {"op":"set-prop","id":6,"property":"width","value":180},
                {"op":"set-prop","id":6,"property":"height","value":48},
                {"op":"insert-child","parent":2,"child":3,"index":0},
                {"op":"insert-child","parent":2,"child":6,"index":1},
                {"op":"insert-child","parent":1,"child":2,"index":0},
                {"op":"insert-child","parent":1,"child":4,"index":1},
                {"op":"insert-child","parent":1,"child":5,"index":2}
            ]),
        ))
        .unwrap();
    renderer.set_root(1).unwrap();
    let changing = renderer.clone();
    on_key_with(
        "f7",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            changing
                .apply(patch(
                    2,
                    json!([
                        {"op":"set-prop","id":2,"property":"font-size","value":"32px"}
                    ]),
                ))
                .unwrap();
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
            let before = rejecting.node_snapshot(3).unwrap();
            assert!(
                rejecting
                    .apply(patch(
                        3,
                        json!([
                            {"op":"set-prop","id":3,"property":"text","value":"must not publish"},
                            {"op":"set-prop","id":3,"property":"font-size","value":"2em"}
                        ])
                    ))
                    .is_err()
            );
            assert!(Arc::ptr_eq(&before, &rejecting.node_snapshot(3).unwrap()));
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
fn size(app: &Headless, selector: &str) -> f32 {
    app.screen().span_style(selector).unwrap().font_size.0
}
#[test]
fn one_em_follows_nearest_parent_native_typography_and_live_geometry_without_remounting() {
    let mut app = Headless::start(EngineConfig::new(Root::of::<FontSizeScenario>())).unwrap();
    app.wait_for("id:lui-3").unwrap();
    let before = geometry(&app, 3);
    let control = geometry(&app, 6).id;
    assert_eq!(size(&app, "id:lui-3 >> text:MMMM"), 20.0);
    assert_eq!(size(&app, "id:lui-4 >> text:MMMM"), 20.0);
    assert_eq!(size(&app, "id:lui-5 >> text:MMMM"), 20.0);
    assert_eq!(size(&app, "id:lui-6 >> text:Command"), 20.0);
    app.press_key("f7").unwrap();
    assert_eq!(size(&app, "id:lui-3 >> text:MMMM"), 32.0);
    assert_eq!(size(&app, "id:lui-6 >> text:Command"), 32.0);
    assert_eq!(size(&app, "id:lui-4 >> text:MMMM"), 20.0);
    assert_eq!(size(&app, "id:lui-5 >> text:MMMM"), 20.0);
    let after = geometry(&app, 3);
    assert_eq!(after.id, before.id);
    assert_eq!(geometry(&app, 6).id, control);
    assert!(
        after.bounds.size.height.0 > before.bounds.size.height.0,
        "inherited text geometry did not grow: {:?} -> {:?}",
        before.bounds,
        after.bounds
    );
    app.press_key("f8").unwrap();
    assert_eq!(geometry(&app, 3).id, before.id);
    assert_eq!(size(&app, "id:lui-3 >> text:MMMM"), 32.0);
    assert!(!app.screen().shows("text:must not publish"));
}
