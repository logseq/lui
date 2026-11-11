//! Native Input policy and retention checks; headless is not an OS IME test.
use super::*;
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use serde_json::json;
use std::sync::Mutex;

struct InputProbe {
    kind: &'static str,
    events: Arc<Mutex<Vec<Event>>>,
}

fn patch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}

#[component]
fn InputPolicies() -> impl IntoElement {
    let probe = engine_context::<InputProbe>().unwrap();
    let observed = probe.events.clone();
    let renderer = Renderer::new(move |event, renderer| {
        observed.lock().unwrap().push(event.clone());
        if let Event::Text(id, text) = event {
            let revision = renderer.0.borrow().store.generation + 1;
            renderer
                .apply(patch(
                    revision,
                    json!([
                        {"op":"set-prop","id":id,"property":"text","value":text}
                    ]),
                ))
                .unwrap();
        }
    });
    let mut ops = json!([
        {"op":"create-node","id":1,"kind":"column"},
        {"op":"create-node","id":2,"kind":probe.kind},
        {"op":"set-prop","id":2,"property":"text","value":"draft"},
        {"op":"set-prop","id":2,"property":"change-enabled","value":true},
        {"op":"set-prop","id":2,"property":"submit-enabled","value":true},
        {"op":"insert-child","parent":1,"child":2,"index":0}
    ])
    .as_array()
    .unwrap()
    .clone();
    if probe.kind == "textarea" {
        ops.push(json!({"op":"set-prop","id":2,"property":"submit-on-enter","value":false}));
    }
    renderer.apply(patch(1, Value::Array(ops))).unwrap();
    renderer.set_root(1).unwrap();
    for (key, operations) in [
        (
            "f2",
            json!([{"op":"set-prop","id":2,"property":"submit-on-enter","value":true}]),
        ),
        (
            "f3",
            json!([{"op":"set-prop","id":2,"property":"submit-on-enter","value":false}]),
        ),
        (
            "f4",
            json!([{"op":"remove-prop","id":2,"property":"submit-on-enter"}]),
        ),
        (
            "f5",
            json!([{"op":"set-prop","id":2,"property":"submit-enabled","value":true}]),
        ),
        (
            "f6",
            json!([{"op":"set-prop","id":2,"property":"submit-enabled","value":false}]),
        ),
    ] {
        let renderer = renderer.clone();
        on_key_with(
            key,
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| {
                let revision = renderer.0.borrow().store.generation + 1;
                renderer.apply(patch(revision, operations.clone())).unwrap();
            },
        );
    }
    let reject = renderer.clone();
    on_key_with(
        "f7",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            let generation = reject.0.borrow().store.generation;
            let before = reject.0.borrow().nodes[&2].node.get_untracked();
            for (property, value) in [
                ("input-type", json!("color")),
                ("input-type", json!("time")),
            ] {
                assert!(reject.apply(patch(generation+1, json!([
                {"op":"set-prop","id":2,"property":"text","value":"must not publish"},
                {"op":"set-prop","id":2,"property":property,"value":value}
            ]))).is_err());
                assert_eq!(reject.0.borrow().store.generation, generation);
                assert!(Arc::ptr_eq(
                    &before,
                    &reject.0.borrow().nodes[&2].node.get_untracked()
                ));
            }
            reject
                .apply(patch(
                    generation + 1,
                    json!([
                        {"op":"set-prop","id":2,"property":"input-type","value":"text"},
                        {"op":"set-prop","id":2,"property":"navigate-enabled","value":false},
                        {"op":"set-prop","id":2,"property":"submit-on-blur","value":false}
                    ]),
                ))
                .unwrap();
        },
    );
    renderer.element()
}

fn start(kind: &'static str) -> (Headless, Arc<Mutex<Vec<Event>>>) {
    let events = Arc::new(Mutex::new(Vec::new()));
    let mut app = Headless::start(EngineConfig {
        context: EngineContext::default().with(InputProbe {
            kind,
            events: events.clone(),
        }),
        ..EngineConfig::new(Root::of::<InputPolicies>())
    })
    .unwrap();
    app.wait_for("id:lui-2").unwrap();
    (app, events)
}

fn identity(app: &Headless) -> nsh_core::NodeId {
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some("lui-2"))
        .unwrap()
        .id
}

fn submissions(events: &Mutex<Vec<Event>>) -> usize {
    events
        .lock()
        .unwrap()
        .iter()
        .filter(|event| **event == Event::Submit(2))
        .count()
}

#[test]
fn single_line_inputs_keep_native_submit_and_blur_defaults() {
    for kind in ["text-field", "secure-field", "input", "search-field"] {
        let (mut app, events) = start(kind);
        let before = identity(&app);
        app.type_text("id:lui-2", "x").unwrap();
        app.press_key("enter").unwrap();
        assert_eq!(submissions(&events), 1, "{kind}");
        {
            let observed = events.lock().unwrap();
            let edited = observed
                .iter()
                .position(|event| *event == Event::Text(2, "draftx".into()))
                .unwrap();
            let submitted = observed
                .iter()
                .position(|event| *event == Event::Submit(2))
                .unwrap();
            assert!(
                edited < submitted,
                "{kind}: the committed edit precedes submit"
            );
        }
        // A raw key after Enter must not refocus the field in the test driver.
        app.press_key("z").unwrap();
        assert_eq!(
            app.screen().input_text("id:lui-2").unwrap(),
            Some("draftx"),
            "{kind}"
        );
        assert_eq!(identity(&app), before, "{kind}");
    }
}

#[test]
fn textarea_live_enter_policy_keeps_the_editor_and_native_line_break_rules() {
    let (mut app, events) = start("textarea");
    let before = identity(&app);
    app.type_text("id:lui-2", "x").unwrap();
    app.press_key("enter").unwrap();
    assert_eq!(submissions(&events), 0);
    assert_eq!(
        app.screen().input_text("id:lui-2").unwrap(),
        Some("draftx\n")
    );
    app.press_key("f2").unwrap();
    app.press_key("enter").unwrap();
    assert_eq!(submissions(&events), 1);
    app.press_key("z").unwrap();
    app.press_key("shift+enter").unwrap();
    app.press_key("alt+enter").unwrap();
    assert_eq!(
        app.screen().input_text("id:lui-2").unwrap(),
        Some("draftx\nz\n\n")
    );
    assert_eq!(submissions(&events), 1);
    app.press_key("f3").unwrap();
    app.press_key("enter").unwrap();
    app.press_key("f4").unwrap();
    app.press_key("enter").unwrap();
    assert_eq!(submissions(&events), 1);
    assert_eq!(
        app.screen().input_text("id:lui-2").unwrap(),
        Some("draftx\nz\n\n\n\n")
    );
    assert_eq!(identity(&app), before);
}

#[test]
fn submit_flag_changes_are_checked_without_replacing_the_textarea() {
    let (mut app, events) = start("textarea");
    let before = identity(&app);
    app.type_text("id:lui-2", "x").unwrap();
    app.press_key("f2").unwrap();
    app.press_key("f6").unwrap();
    app.press_key("enter").unwrap();
    assert_eq!(submissions(&events), 0);
    app.press_key("f5").unwrap();
    app.press_key("enter").unwrap();
    assert_eq!(submissions(&events), 1);
    assert_eq!(app.screen().input_text("id:lui-2").unwrap(), Some("draftx"));
    assert_eq!(identity(&app), before);
}

#[test]
fn unsupported_input_policies_fail_before_any_text_or_identity_is_published() {
    let (mut app, _) = start("input");
    app.type_text("id:lui-2", " edited").unwrap();
    let before = identity(&app);
    app.press_key("f7").unwrap();
    assert_eq!(
        app.screen().input_text("id:lui-2").unwrap(),
        Some("draft edited")
    );
    assert_eq!(identity(&app), before);
}

#[test]
fn native_composition_survives_an_enter_policy_update_until_its_commit() {
    let (mut app, events) = start("textarea");
    let before = identity(&app);
    app.compose("id:lui-2", "zhong").unwrap();
    app.press_key("f2").unwrap();
    assert_eq!(submissions(&events), 0);
    assert_eq!(app.screen().input_text("id:lui-2").unwrap(), Some("draft"));
    app.type_text("id:lui-2", "中").unwrap();
    assert_eq!(
        app.screen().input_text("id:lui-2").unwrap(),
        Some("draft中")
    );
    assert_eq!(submissions(&events), 0);
    assert_eq!(identity(&app), before);
    // OS-specific composition key handling needs the native fixture; this
    // checks that changing policy neither replaces nor submits the editor.
}
