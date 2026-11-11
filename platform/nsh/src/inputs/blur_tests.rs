//! Actual native Input event order and opted-in observer lifetime checks.
use super::*;
use crate::{render::Renderer, wire::Batch};
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use serde_json::{Value, json};
use std::sync::Mutex;

struct Fixture {
    kind: &'static str,
    authored: Option<bool>,
    replace_on_submit: bool,
    events: Arc<Mutex<Vec<Event>>>,
    rejection: Arc<Mutex<Option<String>>>,
}

fn batch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}
fn apply(renderer: &Renderer, generation: &Cell<u64>, ops: Value) {
    let next = generation.get() + 1;
    renderer.apply(batch(next, ops)).unwrap();
    generation.set(next);
}
fn input_ops(kind: &str, authored: Option<bool>, value: &str) -> Vec<Value> {
    let mut ops = vec![
        json!({"op":"create-node","id":2,"kind":kind}),
        json!({"op":"set-prop","id":2,"property":"text","value":value}),
        json!({"op":"set-prop","id":2,"property":"change-enabled","value":true}),
        json!({"op":"set-prop","id":2,"property":"submit-enabled","value":true}),
        json!({"op":"insert-child","parent":1,"child":2,"index":0}),
    ];
    if let Some(value) = authored {
        ops.push(json!({"op":"set-prop","id":2,"property":"submit-on-blur","value":value}));
    }
    ops
}

#[component]
fn BlurProbe() -> impl IntoElement {
    let fixture = engine_context::<Fixture>().unwrap();
    let kind = fixture.kind;
    let generation = Rc::new(Cell::new(0));
    let publishing = generation.clone();
    let observed = fixture.events.clone();
    let replace_on_submit = fixture.replace_on_submit;
    let renderer = Renderer::new(move |event, renderer| {
        observed.lock().unwrap().push(event.clone());
        if let Event::Text(id, text) = event {
            apply(
                &renderer,
                &publishing,
                json!([
                    {"op":"set-prop","id":id,"property":"text","value":text}
                ]),
            );
        } else if replace_on_submit && event == Event::Submit(2) {
            let mut ops = vec![json!({"op":"drop-node","id":2})];
            ops.extend(input_ops(kind, Some(true), "replacement"));
            apply(&renderer, &publishing, json!(ops));
        }
    });
    let mut ops = vec![json!({"op":"create-node","id":1,"kind":"column"})];
    ops.extend(input_ops(kind, fixture.authored, "draft"));
    ops.extend([
        json!({"op":"create-node","id":3,"kind":"text-field"}),
        json!({"op":"set-prop","id":3,"property":"text","value":"outside"}),
        json!({"op":"insert-child","parent":1,"child":3,"index":1}),
    ]);
    apply(&renderer, &generation, json!(ops));
    renderer.set_root(1).unwrap();
    for (key, property, value) in [
        ("f2", "submit-on-blur", false),
        ("f3", "submit-on-blur", true),
        ("f4", "enabled", false),
        ("f5", "enabled", true),
        ("f6", "submit-enabled", false),
        ("f7", "submit-enabled", true),
        ("f8", "submit-on-enter", true),
        ("f9", "submit-on-blur", false),
    ] {
        let renderer = renderer.clone();
        let generation = generation.clone();
        on_key_with(
            key,
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| {
                apply(
                    &renderer,
                    &generation,
                    json!([
                        {"op":"set-prop","id":2,"property":property,"value":value}
                    ]),
                );
            },
        );
    }
    let rejecting = renderer.clone();
    let revision = generation.clone();
    let rejected = fixture.rejection.clone();
    on_key_with(
        "f10",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            let next = revision.get() + 1;
            let error = rejecting
                .apply(batch(
                    next,
                    json!([
                        {"op":"set-prop","id":2,"property":"text","value":"must not publish"},
                        {"op":"set-prop","id":2,"property":"submit-on-blur","value":true}
                    ]),
                ))
                .unwrap_err();
            *rejected.lock().unwrap() = Some(error);
            // A subsequent valid transaction reuses the rejected generation.
            apply(
                &rejecting,
                &revision,
                json!([
                    {"op":"set-prop","id":2,"property":"submit-on-blur","value":false}
                ]),
            );
        },
    );
    let remounting = renderer.clone();
    on_key_with(
        "f11",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            let mut ops = vec![json!({"op":"drop-node","id":2})];
            ops.extend(input_ops(kind, Some(true), "remounted"));
            apply(&remounting, &generation, json!(ops));
        },
    );
    renderer.element()
}

type Started = (Headless, Arc<Mutex<Vec<Event>>>, Arc<Mutex<Option<String>>>);
fn start(kind: &'static str, authored: Option<bool>, replace_on_submit: bool) -> Started {
    let events = Arc::new(Mutex::new(Vec::new()));
    let rejection = Arc::new(Mutex::new(None));
    let mut app = Headless::start(EngineConfig {
        context: EngineContext::default().with(Fixture {
            kind,
            authored,
            replace_on_submit,
            events: events.clone(),
            rejection: rejection.clone(),
        }),
        ..EngineConfig::new(Root::of::<BlurProbe>())
    })
    .unwrap();
    app.wait_for("id:lui-2").unwrap();
    (app, events, rejection)
}
fn identity(app: &Headless, name: &str) -> nsh_core::NodeId {
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some(name))
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
fn opted_in_single_line_enter_reports_one_submit_before_its_native_blur() {
    for kind in ["input", "text-field", "secure-field", "search-field"] {
        let (mut app, events, _) = start(kind, Some(true), false);
        let native = identity(&app, "lui-2");
        app.type_text("id:lui-2", "x").unwrap();
        app.press_key("enter").unwrap();
        assert_eq!(
            *events.lock().unwrap(),
            [Event::Text(2, "draftx".into()), Event::Submit(2)],
            "{kind}"
        );
        app.press_key("z").unwrap();
        assert_eq!(
            app.screen().input_text("id:lui-2").unwrap(),
            Some("draftx"),
            "{kind}: native Enter still blurs"
        );
        assert_eq!(identity(&app, "lui-2"), native);
        app.type_text("id:lui-2", "y").unwrap();
        app.type_text("id:lui-3", "").unwrap();
        assert_eq!(
            submissions(&events),
            2,
            "{kind}: a new focus interval may submit again"
        );
    }
}

#[test]
fn ordinary_blur_submits_the_committed_draft_once_and_keeps_both_inputs() {
    let (mut app, events, _) = start("text-field", Some(true), false);
    let native = identity(&app, "lui-2");
    let outside = identity(&app, "lui-3");
    app.type_text("id:lui-2", " committed").unwrap();
    app.type_text("id:lui-3", "").unwrap();
    assert_eq!(
        *events.lock().unwrap(),
        [Event::Text(2, "draft committed".into()), Event::Submit(2)]
    );
    app.type_text("id:lui-3", "").unwrap();
    assert_eq!(submissions(&events), 1);
    assert_eq!(identity(&app, "lui-2"), native);
    assert_eq!(identity(&app, "lui-3"), outside);
    assert_eq!(
        app.screen().input_text("id:lui-2").unwrap(),
        Some("draft committed")
    );
}

#[test]
fn textarea_enter_and_later_blur_are_distinct_requests_without_changing_native_focus() {
    let (mut app, events, _) = start("textarea", Some(true), false);
    let native = identity(&app, "lui-2");
    app.press_key("f8").unwrap();
    app.type_text("id:lui-2", "x").unwrap();
    app.press_key("enter").unwrap();
    assert_eq!(submissions(&events), 1);
    app.press_key("z").unwrap();
    assert_eq!(
        app.screen().input_text("id:lui-2").unwrap(),
        Some("draftxz")
    );
    app.type_text("id:lui-3", "").unwrap();
    assert_eq!(
        *events.lock().unwrap(),
        [
            Event::Text(2, "draftx".into()),
            Event::Submit(2),
            Event::Text(2, "draftxz".into()),
            Event::Submit(2)
        ]
    );
    assert_eq!(identity(&app, "lui-2"), native);
}

#[test]
fn initially_false_policy_uses_live_blur_enabled_and_submit_flags_without_remounting() {
    let (mut app, events, _) = start("input", Some(false), false);
    let native = identity(&app, "lui-2");
    app.type_text("id:lui-2", "x").unwrap();
    app.press_key("f3").unwrap();
    app.type_text("id:lui-3", "").unwrap();
    assert_eq!(submissions(&events), 1);
    app.type_text("id:lui-2", "y").unwrap();
    app.press_key("f2").unwrap();
    app.type_text("id:lui-3", "").unwrap();
    assert_eq!(submissions(&events), 1);
    app.type_text("id:lui-2", "z").unwrap();
    app.press_key("f3").unwrap();
    app.press_key("f6").unwrap();
    app.type_text("id:lui-3", "").unwrap();
    assert_eq!(submissions(&events), 1);
    app.press_key("f7").unwrap();
    app.type_text("id:lui-2", "k").unwrap();
    app.press_key("f4").unwrap();
    app.type_text("id:lui-3", "").unwrap();
    assert_eq!(submissions(&events), 1);
    app.press_key("f5").unwrap();
    app.type_text("id:lui-2", "m").unwrap();
    app.type_text("id:lui-3", "").unwrap();
    assert_eq!(submissions(&events), 2);
    assert_eq!(identity(&app, "lui-2"), native);
}

#[test]
fn absent_then_false_cannot_bypass_installation_and_rejection_preserves_draft_and_generation() {
    let (mut app, events, rejection) = start("input", None, false);
    let native = identity(&app, "lui-2");
    let outside = identity(&app, "lui-3");
    app.type_text("id:lui-2", "x").unwrap();
    app.press_key("f9").unwrap();
    app.press_key("f10").unwrap();
    assert!(
        rejection
            .lock()
            .unwrap()
            .as_ref()
            .unwrap()
            .contains("uninstalled native event capability")
    );
    assert_eq!(app.screen().input_text("id:lui-2").unwrap(), Some("draftx"));
    assert_eq!(identity(&app, "lui-2"), native);
    app.type_text("id:lui-3", "").unwrap();
    assert_eq!(submissions(&events), 0);
    app.press_key("f11").unwrap();
    app.wait_for("id:lui-2").unwrap();
    assert_ne!(identity(&app, "lui-2"), native);
    assert_eq!(identity(&app, "lui-3"), outside);
    app.type_text("id:lui-2", "y").unwrap();
    app.type_text("id:lui-3", "").unwrap();
    assert_eq!(submissions(&events), 1);
}

#[test]
fn composition_is_not_submitted_early_and_its_committed_text_precedes_blur_submit() {
    let (mut app, events, _) = start("text-field", Some(true), false);
    let native = identity(&app, "lui-2");
    app.compose("id:lui-2", "zhong").unwrap();
    app.type_text("id:lui-3", "").unwrap();
    assert!(events.lock().unwrap().is_empty());
    app.type_text("id:lui-2", "中").unwrap();
    app.type_text("id:lui-3", "").unwrap();
    assert_eq!(
        *events.lock().unwrap(),
        [Event::Text(2, "draft中".into()), Event::Submit(2)]
    );
    assert_eq!(identity(&app, "lui-2"), native);
}

#[test]
fn submit_handler_replacement_cannot_deliver_the_retired_inputs_following_blur() {
    let (mut app, events, _) = start("input", Some(true), true);
    let before = identity(&app, "lui-2");
    app.type_text("id:lui-2", "x").unwrap();
    app.press_key("enter").unwrap();
    assert_eq!(
        *events.lock().unwrap(),
        [Event::Text(2, "draftx".into()), Event::Submit(2)]
    );
    assert_ne!(identity(&app, "lui-2"), before);
    assert_eq!(
        app.screen().input_text("id:lui-2").unwrap(),
        Some("replacement")
    );
}
