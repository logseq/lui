//! Real rejected patches keep their first diagnostic visible above a full root.
use super::*;
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
use serde_json::json;

fn patch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}
#[component]
fn FailureScenario() -> impl IntoElement {
    let renderer = Renderer::new(|_, _| {});
    renderer.apply(patch(1, json!([
        {"op":"create-node","id":1,"kind":"column"},
        {"op":"set-prop","id":1,"property":"width","value":640},
        {"op":"set-prop","id":1,"property":"height","value":480},
        {"op":"set-prop","id":1,"property":"accessibility-identifier","value":"mounted-app"},
        {"op":"create-node","id":2,"kind":"text"},
        {"op":"set-prop","id":2,"property":"text","value":"Retained application content"},
        {"op":"insert-child","parent":1,"child":2,"index":0}
    ]))).unwrap();
    renderer.set_root(1).unwrap();
    let failing = renderer.clone();
    on_key_with(
        "f7",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            let before = failing.node_snapshot(1).unwrap();
            let first = failing.apply(patch(2, json!([
            {"op":"set-prop","id":1,"property":"foreground","value":"var(--missing-diagnostic-color)"}
        ]))).unwrap_err();
            assert!(first.contains("--missing-diagnostic-color"));
            failing.fail(first.clone());
            let subsequent = failing
                .apply(patch(
                    3,
                    json!([
                        {"op":"set-prop","id":2,"property":"text","value":"Must not publish"}
                    ]),
                ))
                .unwrap_err();
            assert!(subsequent.contains("nonsequential patch generation"));
            failing.fail(subsequent);
            failing.fail("resync failed: authoritative snapshot also rejected".into());
            // A repeated original failure must not replace either useful message.
            failing.fail(first);
            assert!(Arc::ptr_eq(&before, &failing.node_snapshot(1).unwrap()));
        },
    );
    renderer.element()
}
#[test]
fn original_rejection_and_recovery_failure_stay_visible_above_full_height_content() {
    let mut config = EngineConfig::new(Root::of::<FailureScenario>());
    config.viewport = Size::new(px(640.0), px(480.0));
    let mut app = Headless::start(config).unwrap();
    app.wait_for("id:mounted-app").unwrap();
    let original = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some("mounted-app"))
        .unwrap();
    app.press_key("f7").unwrap();
    app.wait_for("id:lui-backend-error").unwrap();
    let screen = app.screen();
    let message = screen
        .texts()
        .into_iter()
        .find(|value| value.contains("--missing-diagnostic-color"))
        .unwrap();
    assert!(message.contains("resync failed: authoritative snapshot also rejected"));
    assert!(!message.contains("Must not publish"));
    let nodes = screen.layout_nodes();
    let diagnostic = nodes
        .iter()
        .find(|node| node.test_id.as_deref() == Some("lui-backend-error"))
        .unwrap();
    assert!(diagnostic.bounds.origin.y.0 >= 0.0);
    assert!(diagnostic.bounds.origin.y.0 + diagnostic.bounds.size.height.0 <= 480.0);
    assert!(diagnostic.bounds.size.width.0 > 0.0);
    let retained = nodes
        .iter()
        .find(|node| node.test_id.as_deref() == Some("mounted-app"))
        .unwrap();
    assert_eq!(retained.id, original.id);
    assert_eq!(retained.bounds, original.bounds);
}
