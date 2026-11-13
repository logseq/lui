//! Real Overlay Escape dispatch, not a synthesized Input KeyPress callback.
use super::*;
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use serde_json::json;
use std::sync::Mutex;

struct Fixture {
    seen: Arc<Mutex<Vec<Event>>>,
}
fn patch(renderer: &Renderer, ops: Value) {
    let generation = renderer.0.borrow().store.generation + 1;
    renderer
        .apply(Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap())
        .unwrap();
}
fn input(id: u64, dismiss: bool) -> Vec<Value> {
    vec![
        json!({"op":"create-node","id":id,"kind":"search-field"}),
        json!({"op":"set-prop","id":id,"property":"text","value":"query"}),
        json!({"op":"set-prop","id":id,"property":"autofocus","value":true}),
        json!({"op":"set-prop","id":id,"property":"change-enabled","value":true}),
        json!({"op":"set-prop","id":id,"property":"submit-enabled","value":true}),
        json!({"op":"set-prop","id":id,"property":"submit-on-blur","value":true}),
        json!({"op":"set-prop","id":id,"property":"dismiss-enabled","value":dismiss}),
        json!({"op":"insert-child","parent":20,"child":id,"index":0}),
    ]
}
#[component]
fn PopupInput() -> impl IntoElement {
    let fixture = engine_context::<Fixture>().unwrap();
    let seen = fixture.seen.clone();
    let current = Rc::new(Cell::new(21_u64));
    let editing = current.clone();
    let renderer = Renderer::new(move |event, renderer| {
        seen.lock().unwrap().push(event.clone());
        match event {
            Event::Text(id, value) => patch(
                &renderer,
                json!([
                    {"op":"set-prop","id":id,"property":"text","value":value}
                ]),
            ),
            Event::Dismiss(id) if id == editing.get() => {
                let empty = renderer.0.borrow().store.nodes[&id]
                    .string("text")
                    .is_empty();
                if empty {
                    patch(&renderer, json!([{"op":"detach-subtree","id":20}]));
                } else {
                    let next = id + 1;
                    editing.set(next);
                    let mut ops = vec![json!({"op":"detach-subtree","id":id})];
                    ops.extend(input(next, true));
                    ops.push(json!({"op":"set-prop","id":next,"property":"text","value":""}));
                    patch(&renderer, Value::Array(ops));
                }
            }
            Event::Dismiss(id @ (20 | 40)) => {
                patch(&renderer, json!([{"op":"detach-subtree","id":id}]))
            }
            _ => {}
        }
    });
    let mut ops = vec![
        json!({"op":"create-node","id":1,"kind":"column"}),
        json!({"op":"set-prop","id":1,"property":"width","value":600}),
        json!({"op":"set-prop","id":1,"property":"height","value":500}),
        json!({"op":"create-node","id":10,"kind":"button"}),
        json!({"op":"set-prop","id":10,"property":"text","value":"Outside"}),
        json!({"op":"set-prop","id":10,"property":"press-enabled","value":true}),
        json!({"op":"insert-child","parent":1,"child":10,"index":0}),
        json!({"op":"create-node","id":20,"kind":"popover"}),
        json!({"op":"set-prop","id":20,"property":"x","value":100}),
        json!({"op":"set-prop","id":20,"property":"y","value":100}),
        json!({"op":"insert-child","parent":1,"child":20,"index":1}),
        json!({"op":"create-node","id":50,"kind":"text"}),
        json!({"op":"set-prop","id":50,"property":"text","value":"status:ready"}),
        json!({"op":"insert-child","parent":1,"child":50,"index":2}),
    ];
    ops.extend(input(21, false));
    patch(&renderer, Value::Array(ops));
    renderer.set_root(1).unwrap();
    for (key, mode) in [("f2", 2), ("f3", 3), ("f4", 4), ("f5", 5), ("f6", 6)] {
        let renderer = renderer.clone();
        let current = current.clone();
        on_key_with(
            key,
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| {
                let id = current.get();
                if mode == 6 {
                    let old = renderer.0.borrow().nodes[&id].input_cancel.clone().unwrap();
                    let mut ops = vec![json!({"op":"detach-subtree","id":id})];
                    current.set(30);
                    ops.extend(input(30, true));
                    patch(&renderer, Value::Array(ops));
                    assert!(
                        !old.cancel(),
                        "retired input cannot claim popup cancellation"
                    );
                    return;
                }
                let mut ops = match mode {
                    2 | 3 => {
                        json!([{"op":"set-prop","id":id,"property":"dismiss-enabled","value":mode==2}])
                    }
                    4 => json!([{"op":"set-prop","id":id,"property":"enabled","value":false}]),
                    _ => json!([
                        {"op":"create-node","id":40,"kind":"popover"},
                        {"op":"set-prop","id":40,"property":"x","value":250},
                        {"op":"set-prop","id":40,"property":"y","value":200},
                        {"op":"create-node","id":41,"kind":"text"},
                        {"op":"set-prop","id":41,"property":"text","value":"Nested popup"},
                        {"op":"insert-child","parent":40,"child":41,"index":0},
                        {"op":"insert-child","parent":20,"child":40,"index":1}
                    ]),
                };
                ops.as_array_mut().unwrap().push(json!({"op":"set-prop","id":50,"property":"text","value":format!("status:{mode}")}));
                patch(&renderer, ops);
            },
        );
    }
    renderer.element()
}
fn start() -> (Headless, Arc<Mutex<Vec<Event>>>) {
    let seen = Arc::new(Mutex::new(Vec::new()));
    let mut config = EngineConfig {
        context: EngineContext::default().with(Fixture { seen: seen.clone() }),
        ..EngineConfig::new(Root::of::<PopupInput>())
    };
    config.environment.os = nsh_core::platform::Os::MacOs;
    config.environment.reduce_motion = true;
    let mut app = Headless::start(config).unwrap();
    app.wait_for("id:lui-21").unwrap();
    // Public native controller input establishes actual Core focus before Escape.
    app.type_text("id:lui-21", "").unwrap();
    (app, seen)
}
fn gone(app: &mut Headless, selector: &str) {
    app.wait_until(
        "popup retired",
        std::time::Duration::from_secs(2),
        |screen| screen.count(selector) == Ok(0),
    )
    .unwrap();
}
#[test]
fn overlay_escape_delegates_live_opt_in_clears_query_and_restores_typing() {
    let (mut app, seen) = start();
    app.press_key("f2").unwrap();
    app.wait_for("text:status:2").unwrap();
    app.press_key("escape").unwrap();
    app.wait_for("id:lui-22").unwrap();
    assert_eq!(app.screen().input_text("id:lui-22").unwrap(), Some(""));
    // Headless does not implement native auto_focus. Establish replacement
    // focus through its public input controller; AppKit autofocus is qualified
    // separately by the application's unchanged native keyboard scenario.
    app.type_text("id:lui-22", "").unwrap();
    app.press_key("b").unwrap();
    app.wait_until(
        "fresh input receives keyboard text",
        std::time::Duration::from_secs(2),
        |screen| screen.input_text("id:lui-22") == Ok(Some("b")),
    )
    .unwrap();
    app.press_key("escape").unwrap();
    app.wait_for("id:lui-23").unwrap();
    app.type_text("id:lui-23", "").unwrap();
    app.press_key("escape").unwrap();
    gone(&mut app, "id:lui-23");
    let seen = seen.lock().unwrap();
    let dismissals: Vec<_> = seen
        .iter()
        .filter_map(|event| match event {
            Event::Dismiss(id) => Some(*id),
            _ => None,
        })
        .collect();
    assert_eq!(dismissals, [21, 22, 23]);
    assert!(
        !seen.iter().any(|event| matches!(event, Event::Submit(_))),
        "cancel must suppress reentrant blur submission"
    );
}
#[test]
fn outside_press_dismisses_even_with_a_nonempty_opted_in_query() {
    let (mut app, seen) = start();
    app.press_key("f2").unwrap();
    app.press("Outside").unwrap();
    gone(&mut app, "id:lui-21");
    assert!(seen.lock().unwrap().contains(&Event::Dismiss(20)));
    assert!(!seen.lock().unwrap().contains(&Event::Dismiss(21)));
}
#[test]
fn disabled_or_removed_handler_falls_back_to_popup_dismissal() {
    for key in ["f3", "f4"] {
        let (mut app, seen) = start();
        app.press_key("f2").unwrap();
        app.press_key(key).unwrap();
        app.press_key("escape").unwrap();
        gone(&mut app, "id:lui-21");
        assert!(seen.lock().unwrap().contains(&Event::Dismiss(20)), "{key}");
        assert!(!seen.lock().unwrap().contains(&Event::Dismiss(21)), "{key}");
    }
}
#[test]
fn absent_live_handler_and_retired_input_never_receive_a_late_cancel() {
    let (mut app, seen) = start();
    app.press_key("escape").unwrap();
    gone(&mut app, "id:lui-21");
    assert!(seen.lock().unwrap().contains(&Event::Dismiss(20)));
    let (mut app, seen) = start();
    app.press_key("f2").unwrap();
    app.press_key("f6").unwrap();
    app.wait_for("id:lui-30").unwrap();
    app.type_text("id:lui-30", "").unwrap();
    assert!(!seen.lock().unwrap().contains(&Event::Dismiss(21)));
    app.press_key("escape").unwrap();
    app.wait_for("id:lui-31").unwrap();
    assert!(seen.lock().unwrap().contains(&Event::Dismiss(30)));
}
#[test]
fn nested_top_popup_keeps_escape_before_the_outer_focused_input() {
    let (mut app, seen) = start();
    app.press_key("f2").unwrap();
    app.press_key("f5").unwrap();
    app.wait_for("Nested popup").unwrap();
    app.press_key("escape").unwrap();
    gone(&mut app, "Nested popup");
    assert_eq!(app.screen().count("id:lui-21").unwrap(), 1);
    assert!(seen.lock().unwrap().contains(&Event::Dismiss(40)));
    assert!(!seen.lock().unwrap().contains(&Event::Dismiss(21)));
}
