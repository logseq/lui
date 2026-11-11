//! Public TimeField editing, source updates, identity and submission order.
use super::*;
use crate::{render::Renderer, wire::Batch};
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use serde_json::{Value, json};
use std::sync::Mutex;

#[test]
fn time_input_preserves_canonical_text_precision_without_normalizing_invalid_drafts() {
    for (wire, precision) in [
        ("09:30", TimePrecision::Minute),
        ("09:30:00", TimePrecision::Second),
        ("23:59:59", TimePrecision::Second),
    ] {
        let (time, parsed) = value(wire).unwrap();
        assert_eq!(parsed, precision);
        assert_eq!(text(time, parsed), wire);
    }
    for wire in [
        "",
        "9:30",
        "09:3",
        " 09:30",
        "09:30 ",
        "24:00",
        "09:60",
        "09:30:60",
        "09:30:01.5",
        "9:30 AM",
    ] {
        assert!(value(wire).is_err(), "{wire}");
    }
    let mut node = crate::store::Node {
        kind: "input".into(),
        props: serde_json::from_value(
            json!({"input-type":"time","text":"09:30","pointer-enabled":true}),
        )
        .unwrap(),
        ..Default::default()
    };
    super::super::validate(&node).unwrap();
    for flag in ["read-only", "autofocus", "navigate-enabled"] {
        node.props.insert(flag.into(), json!(false));
        super::super::validate(&node).unwrap();
        node.props.insert(flag.into(), json!(true));
        assert!(super::super::validate(&node).unwrap_err().contains(flag));
        node.props.remove(flag);
    }
    node.props.insert("placeholder".into(), json!("Time"));
    assert!(
        super::super::validate(&node)
            .unwrap_err()
            .contains("placeholder")
    );
}

type Events = Arc<Mutex<Vec<Event>>>;
type Rejection = Arc<Mutex<Option<String>>>;
struct Fixture {
    events: Events,
    rejected: Rejection,
    replace: bool,
}
fn batch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}
fn input_ops(text: &str) -> Vec<Value> {
    vec![
        json!({"op":"create-node","id":2,"kind":"input"}),
        json!({"op":"set-prop","id":2,"property":"input-type","value":"time"}),
        json!({"op":"set-prop","id":2,"property":"text","value":text}),
        json!({"op":"set-prop","id":2,"property":"accessibility-label","value":"Time"}),
        json!({"op":"set-prop","id":2,"property":"width","value":200}),
        json!({"op":"set-prop","id":2,"property":"height","value":40}),
        json!({"op":"set-prop","id":2,"property":"pointer-enabled","value":true}),
        json!({"op":"set-prop","id":2,"property":"change-enabled","value":true}),
        json!({"op":"set-prop","id":2,"property":"submit-enabled","value":true}),
        json!({"op":"set-prop","id":2,"property":"submit-on-blur","value":true}),
        json!({"op":"insert-child","parent":1,"child":2,"index":0}),
    ]
}
#[component]
fn TimeProbe() -> impl IntoElement {
    let fixture = engine_context::<Fixture>().unwrap();
    let generation = Rc::new(Cell::new(1));
    let updating = generation.clone();
    let observed = fixture.events.clone();
    let replace = fixture.replace;
    let renderer = Renderer::new(move |event, renderer| {
        observed.lock().unwrap().push(event.clone());
        let ops = match event {
            Event::Text(id, text) => {
                json!([{"op":"set-prop","id":id,"property":"text","value":text}])
            }
            Event::Submit(2) if replace => {
                let mut ops = vec![json!({"op":"drop-node","id":2})];
                ops.extend(input_ops("18:45"));
                json!(ops)
            }
            _ => return,
        };
        let next = updating.get() + 1;
        renderer.apply(batch(next, ops)).unwrap();
        updating.set(next);
    });
    let mut ops = vec![json!({"op":"create-node","id":1,"kind":"column"})];
    ops.extend(input_ops("09:30"));
    ops.extend([
        json!({"op":"create-node","id":3,"kind":"text-field"}),
        json!({"op":"set-prop","id":3,"property":"text","value":"outside"}),
        json!({"op":"set-prop","id":3,"property":"width","value":200}),
        json!({"op":"set-prop","id":3,"property":"height","value":40}),
        json!({"op":"insert-child","parent":1,"child":3,"index":1}),
    ]);
    renderer.apply(batch(1, json!(ops))).unwrap();
    renderer.set_root(1).unwrap();
    for (key, ops) in [
        (
            "f2",
            json!([{"op":"set-prop","id":2,"property":"text","value":"18:45:12"}]),
        ),
        (
            "f3",
            json!([{"op":"set-prop","id":2,"property":"submit-on-blur","value":false}]),
        ),
        (
            "f4",
            json!([{"op":"set-prop","id":2,"property":"submit-on-blur","value":true}]),
        ),
        (
            "f5",
            json!([{"op":"set-prop","id":2,"property":"enabled","value":false}]),
        ),
        (
            "f6",
            json!([{"op":"set-prop","id":2,"property":"enabled","value":true}]),
        ),
    ] {
        let updating = generation.clone();
        let renderer = renderer.clone();
        on_key_with(
            key,
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| {
                let next = updating.get() + 1;
                renderer.apply(batch(next, ops.clone())).unwrap();
                updating.set(next);
            },
        );
    }
    let cycling = renderer.clone();
    let cycling_generation = generation.clone();
    on_key_with(
        "f10",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            let next = cycling_generation.get() + 1;
            cycling
                .apply(batch(
                    next,
                    json!([
                        {"op":"set-prop","id":2,"property":"text","value":"04:05"}
                    ]),
                ))
                .unwrap();
            cycling_generation.set(next);
        },
    );
    let cycling = renderer.clone();
    let cycling_generation = generation.clone();
    on_key_with(
        "shift+f2",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            let next = cycling_generation.get() + 1;
            cycling
                .apply(batch(
                    next,
                    json!([
                        {"op":"set-prop","id":2,"property":"text","value":"06:07:49"}
                    ]),
                ))
                .unwrap();
            cycling_generation.set(next);
        },
    );
    let rapid = renderer.clone();
    let rapid_generation = generation.clone();
    on_key_with(
        "shift+f3",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            // Separate accepted source transactions, before another native commit.
            for text in ["01:02", "03:04:57", "05:06", "07:08:49"] {
                let next = rapid_generation.get() + 1;
                rapid
                    .apply(batch(
                        next,
                        json!([
                            {"op":"set-prop","id":2,"property":"text","value":text}
                        ]),
                    ))
                    .unwrap();
                rapid_generation.set(next);
            }
        },
    );
    for (key, property, value) in [
        ("f7", "input-type", json!("text")),
        ("f8", "read-only", json!(true)),
        ("f9", "text", json!("")),
    ] {
        let rejecting = renderer.clone();
        let rejected = fixture.rejected.clone();
        let generation = generation.clone();
        on_key_with(
            key,
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| {
                let next = generation.get() + 1;
                let error = rejecting
                    .apply(batch(
                        next,
                        json!([
                            {"op":"set-prop","id":3,"property":"text","value":"must not publish"},
                            {"op":"set-prop","id":2,"property":property,"value":value}
                        ]),
                    ))
                    .unwrap_err();
                *rejected.lock().unwrap() = Some(error);
            },
        );
    }
    renderer.element()
}
fn start(replace: bool) -> (Headless, Events, Rejection) {
    let events = Arc::new(Mutex::new(Vec::new()));
    let rejected = Arc::new(Mutex::new(None));
    let app = Headless::start(EngineConfig {
        context: EngineContext::default().with(Fixture {
            events: events.clone(),
            rejected: rejected.clone(),
            replace,
        }),
        ..EngineConfig::new(Root::of::<TimeProbe>())
    })
    .unwrap();
    (app, events, rejected)
}
fn identities(app: &Headless) -> Vec<nsh_core::NodeId> {
    let nodes = app.screen().layout_nodes();
    let root = nodes
        .iter()
        .find(|node| node.test_id.as_deref() == Some("lui-2"))
        .unwrap()
        .id;
    let mut identities = vec![root];
    for node in nodes
        .iter()
        .filter(|node| node.parent == root && node.kind == nsh_core::ViewKind::Input)
    {
        identities.push(node.id);
    }
    assert_eq!(
        identities.len(),
        2,
        "one actual native input belongs to TimeField"
    );
    identities
}
#[test]
fn native_time_changes_then_enter_and_blur_submit_once_with_retained_field() {
    let (mut app, events, _) = start(false);
    app.wait_for("id:lui-2").unwrap();
    let before = identities(&app);
    app.type_text("id:lui-2", "").unwrap();
    app.press_key("up").unwrap();
    app.press_key("enter").unwrap();
    app.type_text("id:lui-3", "").unwrap();
    assert_eq!(
        *events.lock().unwrap(),
        [Event::Text(2, "10:30".into()), Event::Submit(2)]
    );
    app.type_text("id:lui-2", "").unwrap();
    app.press_key("up").unwrap();
    app.type_text("id:lui-3", "").unwrap();
    assert_eq!(
        *events.lock().unwrap(),
        [
            Event::Text(2, "10:30".into()),
            Event::Submit(2),
            Event::Text(2, "11:30".into()),
            Event::Submit(2)
        ]
    );
    assert_eq!(identities(&app), before);
}
#[test]
fn native_time_precision_programmatic_update_and_refused_mode_change_are_atomic() {
    let (mut app, events, rejected) = start(false);
    app.wait_for("id:lui-2").unwrap();
    let before = identities(&app);
    app.press_key("f2").unwrap();
    app.type_text("id:lui-2", "").unwrap();
    app.press_key("up").unwrap();
    assert_eq!(
        events.lock().unwrap().first(),
        Some(&Event::Text(2, "19:45:12".into()))
    );
    for (key, message) in [("f7", "input-type"), ("f8", "read-only"), ("f9", "24-hour")] {
        app.press_key(key).unwrap();
        assert!(rejected.lock().unwrap().as_ref().unwrap().contains(message));
        assert_eq!(
            app.screen().input_text("id:lui-3").unwrap(),
            Some("outside")
        );
    }
    assert_eq!(identities(&app), before);
}
#[test]
fn retired_time_blur_cannot_submit_a_replacement_incarnation() {
    let (mut app, events, _) = start(true);
    app.wait_for("id:lui-2").unwrap();
    let before = identities(&app);
    app.type_text("id:lui-2", "").unwrap();
    app.press_key("enter").unwrap();
    app.type_text("id:lui-3", "").unwrap();
    assert_eq!(*events.lock().unwrap(), [Event::Submit(2)]);
    assert_ne!(identities(&app), before);
}

#[test]
fn native_time_live_blur_policy_and_disabled_state_keep_the_same_native_field() {
    let (mut app, events, _) = start(false);
    app.wait_for("id:lui-2").unwrap();
    let before = identities(&app);
    app.press_key("f3").unwrap();
    app.type_text("id:lui-2", "").unwrap();
    app.press_key("up").unwrap();
    app.type_text("id:lui-3", "").unwrap();
    assert_eq!(*events.lock().unwrap(), [Event::Text(2, "10:30".into())]);
    app.type_text("id:lui-2", "").unwrap();
    app.press_key("f5").unwrap();
    app.press_key("up").unwrap();
    assert_eq!(events.lock().unwrap().len(), 1);
    app.press_key("f6").unwrap();
    app.press_key("f4").unwrap();
    app.type_text("id:lui-2", "").unwrap();
    app.press_key("up").unwrap();
    app.type_text("id:lui-3", "").unwrap();
    assert_eq!(
        *events.lock().unwrap(),
        [
            Event::Text(2, "10:30".into()),
            Event::Text(2, "11:30".into()),
            Event::Submit(2)
        ]
    );
    assert_eq!(identities(&app), before);
}

#[test]
fn native_precision_cycles_and_rapid_source_updates_preserve_seconds_focus_and_identity() {
    let (mut app, events, _) = start(false);
    app.wait_for("id:lui-2").unwrap();
    let before = identities(&app);
    app.type_text("id:lui-2", "").unwrap();
    for (key, source, changed) in [
        ("f2", "18:45:12", "19:45:12"),
        ("f10", "04:05", "05:05"),
        ("shift+f2", "06:07:49", "07:07:49"),
        ("shift+f3", "07:08:49", "08:08:49"),
    ] {
        events.lock().unwrap().clear();
        app.press_key(key).unwrap();
        assert_eq!(app.screen().input_text("id:lui-2").unwrap(), Some(source));
        assert!(
            events.lock().unwrap().is_empty(),
            "a source update emitted a user edit"
        );
        // Do not focus again: a native segment edit proves focus survived.
        app.press_key("up").unwrap();
        assert_eq!(*events.lock().unwrap(), [Event::Text(2, changed.into())]);
        assert_eq!(identities(&app), before);
    }
}
