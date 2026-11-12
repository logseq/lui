//! Policy/event-order tests; Headless does not synthesize input Escape.
//! Actual AppKit keyboard delivery is qualified by the application scalar test.
use super::*;
use crate::{events::Capabilities, store::Store, wire::Batch};
use serde_json::json;
use std::cell::RefCell;

fn node(kind: &str) -> Node {
    Node {
        id: 2,
        kind: kind.into(),
        props: serde_json::from_value(json!({"dismiss-enabled":true,"submit-on-blur":true}))
            .unwrap(),
        ..Default::default()
    }
}

#[test]
fn cancellation_arms_blur_suppression_before_dispatch_and_once_per_draft() {
    for kind in [
        "input",
        "text-field",
        "secure-field",
        "search-field",
        "textarea",
    ] {
        let node = node(kind);
        let state = Cell::new(BlurState::default());
        let events = RefCell::new(Vec::new());
        request_dismiss(&node, &state, &|event| {
            assert!(
                !submits_on_blur(&node, state.get()),
                "{kind}: a reentrant blur must not save"
            );
            events.borrow_mut().push(event);
        });
        request_dismiss(&node, &state, &|event| events.borrow_mut().push(event));
        assert_eq!(*events.borrow(), [Event::Dismiss(2)], "{kind}");
        let before = state.replace(BlurState::default());
        assert!(
            !submits_on_blur(&node, before),
            "{kind}: the following native blur is suppressed"
        );
        // A fresh focus interval has the ordinary save policy again.
        assert!(submits_on_blur(&node, state.get()), "{kind}");
    }
}

#[test]
fn removed_disabled_and_composing_dismissal_leave_the_policy_unclaimed() {
    for mode in ["removed", "false", "disabled", "composing"] {
        let mut node = node("text-field");
        let state = Cell::new(BlurState {
            composing: mode == "composing",
            ..Default::default()
        });
        match mode {
            "removed" => {
                node.props.remove("dismiss-enabled");
            }
            "false" => {
                node.props.insert("dismiss-enabled".into(), json!(false));
            }
            "disabled" => {
                node.props.insert("enabled".into(), json!(false));
            }
            _ => {}
        }
        request_dismiss(&node, &state, &|_| {
            panic!("{mode}: dismissal must not escape")
        });
        assert!(!state.get().suppress_native_blur, "{mode}");
    }
    let mut ordinary = node("input");
    ordinary.props.remove("dismiss-enabled");
    let state = Cell::new(BlurState::default());
    request_dismiss(&ordinary, &state, &|_| panic!("unhandled cancellation"));
    assert!(
        submits_on_blur(&ordinary, state.get()),
        "ordinary number/editor blur keeps saving"
    );
}

#[test]
fn cancellation_capability_retains_mount_capacity_without_reviving_removed_handlers() {
    let mut node = node("input");
    node.props.insert("dismiss-enabled".into(), json!(false));
    let installed = Capabilities::authored(&node);
    node.props.insert("dismiss-enabled".into(), json!(true));
    assert!(installed.contains(Capabilities::required(&node)));
    node.props.remove("dismiss-enabled");
    let absent = Capabilities::authored(&node);
    assert!(absent.contains(Capabilities::required(&node)));
    node.props.insert("dismiss-enabled".into(), json!(true));
    assert!(
        !absent.contains(Capabilities::required(&node)),
        "late observer requires a keyed remount"
    );
    assert!(
        installed.contains(Capabilities::required(&node)),
        "removing an installed flag retains capacity"
    );
}

#[test]
fn dismissal_wire_kind_and_scalar_validation_are_atomic() {
    for (kind, value) in [("button", json!(true)), ("input", json!("true"))] {
        let mut store = Store::default();
        let wire = json!({"generation":1,"ops":[
            {"op":"create-node","id":2,"kind":kind},
            {"op":"set-prop","id":2,"property":"dismiss-enabled","value":value}
        ]});
        let result = Batch::decode(&wire.to_string()).and_then(|batch| store.apply(batch));
        assert!(
            result.is_err(),
            "{kind}: invalid cancellation capability must fail"
        );
        assert!(
            store.nodes.is_empty(),
            "rejected input batch must not partially publish"
        );
        assert_eq!(store.generation, 0);
    }
}

struct RetainedFixture {
    events: Arc<std::sync::Mutex<Vec<Event>>>,
}

#[component]
fn RetainedCancellation() -> impl IntoElement {
    let fixture = engine_context::<RetainedFixture>().unwrap();
    let events = fixture.events.clone();
    let generation = Rc::new(Cell::new(1));
    let advancing = generation.clone();
    let canceled = Cell::new(0);
    let renderer = crate::render::Renderer::new(move |event, renderer| {
        events.lock().unwrap().push(event.clone());
        let update = match event {
            Event::Text(id, value) => Some((id, value)),
            Event::Dismiss(2) => {
                let count = canceled.get() + 1;
                canceled.set(count);
                Some((4, format!("cancel-count:{count}")))
            }
            _ => None,
        };
        if let Some((id, value)) = update {
            let next = advancing.get() + 1;
            renderer
                .apply(
                    Batch::decode(
                        &json!({"generation":next,"ops":[
                            {"op":"set-prop","id":id,"property":"text","value":value}
                        ]})
                        .to_string(),
                    )
                    .unwrap(),
                )
                .unwrap();
            advancing.set(next);
        }
    });
    renderer
        .apply(
            Batch::decode(
                &json!({"generation":1,"ops":[
                    {"op":"create-node","id":1,"kind":"column"},
                    {"op":"create-node","id":2,"kind":"text-field"},
                    {"op":"set-prop","id":2,"property":"text","value":"draft"},
                    {"op":"set-prop","id":2,"property":"change-enabled","value":true},
                    {"op":"set-prop","id":2,"property":"submit-enabled","value":true},
                    {"op":"set-prop","id":2,"property":"submit-on-blur","value":true},
                    {"op":"set-prop","id":2,"property":"dismiss-enabled","value":true},
                    {"op":"insert-child","parent":1,"child":2,"index":0},
                    {"op":"create-node","id":3,"kind":"text-field"},
                    {"op":"set-prop","id":3,"property":"text","value":"outside"},
                    {"op":"insert-child","parent":1,"child":3,"index":1},
                    {"op":"create-node","id":4,"kind":"text"},
                    {"op":"set-prop","id":4,"property":"text","value":"cancel-count:0"},
                    {"op":"insert-child","parent":1,"child":4,"index":2}
                ]})
                .to_string(),
            )
            .unwrap(),
        )
        .unwrap();
    renderer.set_root(1).unwrap();
    let patched = renderer.clone();
    on_key_with(
        "f2",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            let next = generation.get() + 1;
            patched
                .apply(
                    Batch::decode(
                        &json!({"generation":next,"ops":[
                            {"op":"set-prop","id":2,"property":"text","value":"authoritative"}
                        ]})
                        .to_string(),
                    )
                    .unwrap(),
                )
                .unwrap();
            generation.set(next);
        },
    );
    renderer.element()
}

fn retained() -> (nsh_testing::Headless, Arc<std::sync::Mutex<Vec<Event>>>) {
    use nsh_engine::{EngineConfig, EngineContext, Root};
    let events = Arc::new(std::sync::Mutex::new(Vec::new()));
    let mut app = nsh_testing::Headless::start(EngineConfig {
        context: EngineContext::default().with(RetainedFixture {
            events: events.clone(),
        }),
        ..EngineConfig::new(Root::of::<RetainedCancellation>())
    })
    .unwrap();
    app.wait_for("id:lui-2").unwrap();
    (app, events)
}

fn native_id(app: &nsh_testing::Headless) -> nsh_core::NodeId {
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some("lui-2"))
        .unwrap()
        .id
}

// Headless's keyboard driver does not report input Escape. Exercise the actual
// native KeyPress listener with the public engine boundary, without claiming an
// OS keyboard or focus transition. User edits and blur below use normal steps.
fn cancel_boundary(app: &mut nsh_testing::Headless, events: &Arc<std::sync::Mutex<Vec<Event>>>) {
    let count = events
        .lock()
        .unwrap()
        .iter()
        .filter(|event| **event == Event::Dismiss(2))
        .count();
    app.engine().control().dispatch_event(
        native_id(app),
        nsh_core::EventKind::KeyPress,
        nsh_core::EventPayload::Map(vec![("key", nsh_core::PayloadValue::Str("Escape".into()))]),
    );
    // Dismiss intentionally retains the input, so the policy itself emits no
    // native mutation. A separate visible acknowledgement gives wait_for its
    // normal platform-publication barrier without changing input focus/value.
    let delivered = app.wait_for(&format!("text:cancel-count:{}", count + 1));
    assert!(
        delivered.is_ok(),
        "{delivered:?}; actual events={:?}",
        *events.lock().unwrap()
    );
}

#[test]
fn retained_native_edit_after_cancel_rearms_ordinary_blur_without_replacing_input() {
    let (mut app, events) = retained();
    app.type_text("id:lui-2", "x").unwrap();
    let id = native_id(&app);
    cancel_boundary(&mut app, &events);
    app.type_text("id:lui-2", "y").unwrap();
    app.type_text("id:lui-3", "").unwrap();
    assert_eq!(
        *events.lock().unwrap(),
        [
            Event::Text(2, "draftx".into()),
            Event::Dismiss(2),
            Event::Text(2, "draftxy".into()),
            Event::Submit(2)
        ]
    );
    assert_eq!(native_id(&app), id);
}

#[test]
fn retained_native_edit_allows_a_second_cancel_and_late_submit_does_not_save() {
    let (mut app, events) = retained();
    app.type_text("id:lui-2", "x").unwrap();
    cancel_boundary(&mut app, &events);
    app.type_text("id:lui-2", "y").unwrap();
    cancel_boundary(&mut app, &events);
    app.submit("id:lui-2").unwrap();
    assert_eq!(
        *events.lock().unwrap(),
        [
            Event::Text(2, "draftx".into()),
            Event::Dismiss(2),
            Event::Text(2, "draftxy".into()),
            Event::Dismiss(2)
        ]
    );
}

#[test]
fn authoritative_controlled_patch_does_not_rearm_a_canceled_native_draft() {
    let (mut app, events) = retained();
    app.type_text("id:lui-2", "x").unwrap();
    let id = native_id(&app);
    cancel_boundary(&mut app, &events);
    app.press_key("f2").unwrap();
    assert_eq!(
        app.screen().input_text("id:lui-2").unwrap(),
        Some("authoritative")
    );
    app.type_text("id:lui-3", "").unwrap();
    assert_eq!(
        *events.lock().unwrap(),
        [Event::Text(2, "draftx".into()), Event::Dismiss(2)]
    );
    assert_eq!(native_id(&app), id);
    app.type_text("id:lui-2", "z").unwrap();
    app.type_text("id:lui-3", "").unwrap();
    assert!(
        events
            .lock()
            .unwrap()
            .ends_with(&[Event::Text(2, "authoritativez".into()), Event::Submit(2)])
    );
}

#[test]
fn prior_enter_blur_deduplication_does_not_swallow_a_distinct_cancel() {
    let node = node("input");
    let state = Cell::new(BlurState {
        suppress_native_blur: true,
        ..Default::default()
    });
    let events = RefCell::new(Vec::new());
    request_dismiss(&node, &state, &|event| events.borrow_mut().push(event));
    assert_eq!(*events.borrow(), [Event::Dismiss(2)]);
    assert!(state.get().dismissed);
}

#[test]
fn cancellation_remains_closed_after_blur_until_the_input_gets_fresh_focus() {
    let (mut app, events) = retained();
    app.type_text("id:lui-2", "x").unwrap();
    let id = native_id(&app);
    cancel_boundary(&mut app, &events);
    app.type_text("id:lui-3", "").unwrap();
    // A delayed native Submit is not a new input step: submit(selector) would
    // explicitly focus the field first and begin a legitimate fresh interval.
    app.engine().control().dispatch_event(
        id,
        nsh_core::EventKind::SubmitEditing,
        nsh_core::EventPayload::Text {
            text: "draftx".into(),
            count: 1,
        },
    );
    // The following ordered application key applies a visible controlled patch,
    // giving the earlier boundary event a deterministic processing barrier.
    app.press_key("f2").unwrap();
    assert_eq!(
        app.screen().input_text("id:lui-2").unwrap(),
        Some("authoritative")
    );
    assert_eq!(
        *events.lock().unwrap(),
        [Event::Text(2, "draftx".into()), Event::Dismiss(2)]
    );
    app.type_text("id:lui-2", "").unwrap();
    app.type_text("id:lui-3", "").unwrap();
    assert!(
        events.lock().unwrap().ends_with(&[Event::Submit(2)]),
        "fresh focus restores ordinary blur submission"
    );
    assert_eq!(native_id(&app), id);
}
