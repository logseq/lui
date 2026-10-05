//! Headless end-to-end scenarios for the LUI GPUI backend.
//!
//! Each scenario is a JSON document of the shape
//!
//! ```json
//! {
//!   "name": "click flows a dom-event back to OCaml",
//!   "steps": [
//!     {"apply": {"generation": 1, "ops": [ ... ]}},
//!     {"click": 3},
//!     {"expect-events": [{"kind": "extension-event", "node": 3, ...}]},
//!     {"dom-op": {"op": "measure-node", "body": {"ref": {"node-id": 3}},
//!                  "expect": {"node-rect": {"rect": {"width": {"$gt": 0}}}}}}
//!   ]
//! }
//! ```
//!
//! Steps run against a real `LuiRootView` mounted in a `TestAppContext`
//! window — `apply` feeds patch batches through `apply_stream_json`,
//! `click`/`input`/`keys` use GPUI's simulated input dispatch, and
//! `expect-events` compares the calls the OCaml bridge would have
//! received (recorded by the `lui_ocaml_*` stubs in `support/`).
//!
//! Value matching is subset-shaped: an expected object must have every
//! listed member match recursively; `"*"` accepts anything, `"~x"` accepts
//! a string containing `x`, and `{"$gt"|"$lt"|"$ge"|"$le": n}` compares a
//! number.

mod support;

use std::sync::Mutex;

use gpui_kit::gpui::{MouseButton, TestAppContext, VisualTestContext};
use gpui_kit::Focusable;
use lui_gpui::backend::apply_stream_json;
use lui_gpui::domops::handle_dom_op;
use lui_gpui::{LuiRootView, LuiShared, Shared};
use serde_json::Value;
use support::RecordedEvent;

/// The `lui_ocaml_*` recorder is process-global — serialize scenario runs so
/// parallel `#[gpui_kit::test]`s cannot drain or interleave each other's
/// event streams.
static SCENARIO_LOCK: Mutex<()> = Mutex::new(());

fn run_scenario(cx: &mut TestAppContext, source: &str) {
    let _lock = SCENARIO_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let scenario: Value = serde_json::from_str(source).expect("scenario JSON must parse");
    let name = scenario
        .get("name")
        .and_then(Value::as_str)
        .unwrap_or("<unnamed>")
        .to_string();

    // Isolate this scenario's event stream; the recording stubs are
    // process-global.
    let _ = support::take_events();

    cx.update(gpui_kit::init);
    let shared = LuiShared::new();
    let build = shared.clone();
    let (_view, cx) =
        cx.add_window_view(move |_, _| LuiRootView::new(build));
    cx.update(|window, _| window.refresh());
    cx.run_until_parked();

    let steps = scenario
        .get("steps")
        .and_then(Value::as_array)
        .unwrap_or_else(|| panic!("scenario '{name}': missing steps"));
    for (ix, step) in steps.iter().enumerate() {
        run_step(cx, &shared, step, &name, ix);
        // Scroll-into-view and friends defer to the next prepaint — force a
        // frame so deferred state lands before the assertion steps.
        cx.update(|window, _| window.refresh());
        cx.run_until_parked();
    }
}

fn run_step(
    cx: &mut VisualTestContext,
    shared: &Shared,
    step: &Value,
    scenario: &str,
    ix: usize,
) {
    let where_ = || format!("scenario '{scenario}' step {ix}: {step}");
    if let Some(batch) = step.get("apply") {
        let json = batch.to_string();
        cx.update(|_, app| apply_stream_json(shared, &json, app));
        cx.update(|window, _| window.refresh());
        let errors = shared.borrow().last_errors.clone();
        assert!(errors.is_empty(), "{} — apply errors: {errors:?}", where_());
    } else if let Some(target) = step.get("click") {
        let center = node_center(shared, target, &where_);
        cx.simulate_click(center, Default::default());
    } else if let Some(target) = step.get("right-click") {
        let center = node_center(shared, target, &where_);
        cx.simulate_mouse_down(center, MouseButton::Right, Default::default());
        cx.simulate_mouse_up(center, MouseButton::Right, Default::default());
    } else if let Some(target) = step.get("hover") {
        let center = node_center(shared, target, &where_);
        cx.simulate_mouse_move(center, None::<MouseButton>, Default::default());
    } else if let Some(text) = step.get("input") {
        cx.simulate_input(text.as_str().unwrap_or_default());
    } else if let Some(keys) = step.get("keys") {
        cx.simulate_keystrokes(keys.as_str().unwrap_or_default());
    } else if let Some(op) = step.get("dom-op") {
        let name = op["op"].as_str().expect("dom-op needs 'op'");
        let body = op
            .get("body")
            .map(Value::to_string)
            .unwrap_or_else(|| "{}".to_string());
        // Dom-ops take `&mut App`, not a window — call them at App scope like
        // the host does, not inside a window update (the window is then on
        // the update stack and `handle_dom_op`'s own `window.update` fails).
        let replies = cx.cx.update(|app| handle_dom_op(shared, name, &body, app));
        if let Some(expect) = op.get("expect") {
            let expect = expect.as_object().expect("dom-op expect must be an object");
            for (reply_name, subset) in expect {
                let matched = replies.iter().any(|(event, value)| {
                    event == reply_name && matches_subset(subset, value)
                });
                assert!(
                    matched,
                    "{} — dom-op '{name}' never replied '{reply_name}' matching {subset}; got {replies:?}",
                    where_()
                );
            }
        }
    } else if let Some(expect) = step.get("expect-events") {
        let recorded = support::take_events();
        let expected = expect.as_array().expect("expect-events must be an array");
        assert_eq!(
            recorded.len(),
            expected.len(),
            "{} — expected {expected:?}, recorded {recorded:?}",
            where_()
        );
        for (recorded, spec) in recorded.iter().zip(expected) {
            assert!(
                event_matches(recorded, spec),
                "{} — expected {spec}, recorded {recorded:?}",
                where_()
            );
        }
    } else if let Some(spec) = step.get("expect-bounds") {
        let id = node_id(spec.get("node").expect("expect-bounds needs 'node'"));
        let bounds = shared.borrow().node_bounds.get(&id).copied();
        if spec.get("absent").and_then(Value::as_bool) == Some(true) {
            assert!(bounds.is_none(), "{} — node {id} still has bounds", where_());
        } else {
            let bounds =
                bounds.unwrap_or_else(|| panic!("{} — node {id} has no recorded bounds", where_()));
            if let Some(rect) = spec.get("rect") {
                let actual = serde_json::json!({
                    "left": f32::from(bounds.origin.x),
                    "top": f32::from(bounds.origin.y),
                    "right": f32::from(bounds.origin.x + bounds.size.width),
                    "bottom": f32::from(bounds.origin.y + bounds.size.height),
                    "width": f32::from(bounds.size.width),
                    "height": f32::from(bounds.size.height),
                });
                assert!(
                    matches_subset(rect, &actual),
                    "{} — bounds of node {id}: {actual} does not satisfy {rect}",
                    where_()
                );
            }
        }
    } else if let Some(spec) = step.get("expect-focused") {
        let id = node_id(spec);
        let focused = cx.update(|window, app| node_focused(shared, id, window, app));
        assert!(focused, "{} — node {id} is not focused", where_());
    } else if let Some(spec) = step.get("expect-scroll") {
        let id = node_id(spec.get("node").expect("expect-scroll needs 'node'"));
        let offset = cx.update(|_, app| scroll_offset(shared, id, app));
        let actual = serde_json::json!({
            "x": f32::from(offset.x),
            "y": f32::from(offset.y),
        });
        for (axis, want) in spec
            .as_object()
            .expect("expect-scroll must be an object")
            .iter()
            .filter(|(key, _)| *key != "node")
        {
            assert!(
                matches_subset(want, &actual[axis]),
                "{} — scroll of node {id}: {actual} axis '{axis}' does not satisfy {want}",
                where_()
            );
        }
    } else {
        panic!("{} — unknown step shape", where_());
    }
}

fn node_id(target: &Value) -> i64 {
    if let Some(id) = target.as_i64() {
        return id;
    }
    let name = target.as_str().expect("node ref must be int or 'lui-N'");
    name.strip_prefix("lui-")
        .and_then(|rest| rest.parse::<i64>().ok())
        .unwrap_or_else(|| panic!("bad node ref {target}"))
}

fn node_center(
    shared: &Shared,
    target: &Value,
    where_: &dyn Fn() -> String,
) -> gpui_kit::gpui::Point<gpui_kit::gpui::Pixels> {
    let id = node_id(target);
    shared
        .borrow()
        .node_bounds
        .get(&id)
        .copied()
        .map(|bounds| bounds.center())
        .unwrap_or_else(|| {
            panic!(
                "{} — node {id} has no recorded bounds (not rendered?)",
                where_()
            )
        })
}

fn node_focused(
    shared: &Shared,
    id: i64,
    window: &gpui_kit::gpui::Window,
    app: &mut gpui_kit::gpui::App,
) -> bool {
    let Some(view) = shared.borrow().views.get(&id).cloned() else {
        return false;
    };
    view.read_with(app, |view, cx| {
        view.states
            .input
            .as_ref()
            .map(|input| input.read(cx).focus_handle(cx).is_focused(window))
            .or_else(|| {
                view.states
                    .textarea
                    .as_ref()
                    .map(|textarea| textarea.read(cx).focus_handle(cx).is_focused(window))
            })
            .unwrap_or(false)
    })
}

fn scroll_offset(
    shared: &Shared,
    id: i64,
    app: &mut gpui_kit::gpui::App,
) -> gpui_kit::gpui::Point<gpui_kit::gpui::Pixels> {
    let view = shared
        .borrow()
        .views
        .get(&id)
        .cloned()
        .unwrap_or_else(|| panic!("node {id} has no view"));
    view.read_with(app, |view, _| view.states.scroll.offset())
}

/// A recorded `lui_ocaml_*` call satisfies a JSON spec when every listed
/// field matches (subset semantics on `json`/`payload` for extension events).
fn event_matches(recorded: &RecordedEvent, spec: &Value) -> bool {
    let Some(kind) = spec.get("kind").and_then(Value::as_str) else {
        return false;
    };
    let node_is = |spec: &Value, node: i64| {
        spec.get("node")
            .and_then(Value::as_i64)
            .map(|want| want == node)
            .unwrap_or(true)
    };
    match (recorded, kind) {
        (RecordedEvent::Press(node), "press") => node_is(spec, *node),
        (RecordedEvent::TextChanged { node, text }, "text-changed") => {
            node_is(spec, *node)
                && spec
                    .get("text")
                    .and_then(Value::as_str)
                    .map(|want| text == want)
                    .unwrap_or(true)
        }
        (RecordedEvent::Submit(node), "submit") => node_is(spec, *node),
        (RecordedEvent::Dismiss(node), "dismiss") => node_is(spec, *node),
        (RecordedEvent::Picked { node, payload }, "picked") => {
            node_is(spec, *node)
                && spec
                    .get("payload")
                    .map(|want| string_or_json_subset(want, payload))
                    .unwrap_or(true)
        }
        (RecordedEvent::ToggleChanged { node, checked }, "toggle-changed") => {
            node_is(spec, *node)
                && spec
                    .get("checked")
                    .and_then(Value::as_bool)
                    .map(|want| want == *checked)
                    .unwrap_or(true)
        }
        (RecordedEvent::RadioChanged(node), "radio-changed") => node_is(spec, *node),
        (RecordedEvent::SliderChanged { node, fraction }, "slider-changed") => {
            node_is(spec, *node)
                && spec
                    .get("fraction")
                    .and_then(Value::as_f64)
                    .map(|want| (want - fraction).abs() < 1e-3)
                    .unwrap_or(true)
        }
        (
            RecordedEvent::ExtensionEvent {
                node,
                identifier,
                name,
                json,
            },
            "extension-event",
        ) => {
            node_is(spec, *node)
                && spec
                    .get("identifier")
                    .and_then(Value::as_str)
                    .map(|want| identifier == want)
                    .unwrap_or(true)
                && spec
                    .get("name")
                    .and_then(Value::as_str)
                    .map(|want| name == want)
                    .unwrap_or(true)
                && spec
                    .get("json")
                    .map(|want| string_or_json_subset(want, json))
                    .unwrap_or(true)
        }
        _ => false,
    }
}

/// `actual` is a JSON string produced by the bridge; `expected` is matched
/// as a subset of the parsed value.
fn string_or_json_subset(expected: &Value, actual: &str) -> bool {
    match serde_json::from_str::<Value>(actual) {
        Ok(parsed) => matches_subset(expected, &parsed),
        Err(_) => matches_subset(expected, &Value::String(actual.to_string())),
    }
}

/// Subset match: every member of an expected object must match the actual
/// member recursively; `"*"` accepts anything, `"~x"` accepts a string
/// containing `x`, `{"$gt"|"$lt"|"$ge"|"$le": n}` compares a number.
fn matches_subset(expected: &Value, actual: &Value) -> bool {
    // A single "$op"-keyed object is a numeric comparator leaf, whatever
    // the actual value's shape.
    if let Value::Object(want) = expected {
        if want.len() == 1 {
            if let Some((comparator, bound)) = want.iter().next() {
                if comparator.starts_with('$') {
                    let number = actual.as_f64().unwrap_or(f64::NAN);
                    let bound = bound.as_f64().unwrap_or(f64::NAN);
                    return match comparator.as_str() {
                        "$gt" => number > bound,
                        "$lt" => number < bound,
                        "$ge" => number >= bound,
                        "$le" => number <= bound,
                        _ => false,
                    };
                }
            }
        }
    }
    match (expected, actual) {
        (Value::Object(want), Value::Object(have)) => {
            want.iter().all(|(key, want)| {
                have.get(key)
                    .map(|have| {
                        // Bridge payloads travel as JSON strings: "payload" in
                        // a dom-event is itself a JSON document.
                        if let (Value::Object(_) | Value::Array(_), Value::String(text)) =
                            (want, have)
                        {
                            if let Ok(parsed) = serde_json::from_str::<Value>(text) {
                                return matches_subset(want, &parsed);
                            }
                        }
                        matches_subset(want, have)
                    })
                    .unwrap_or(false)
            })
        }
        (Value::Array(want), Value::Array(have)) => {
            want.len() == have.len()
                && want
                    .iter()
                    .zip(have)
                    .all(|(want, have)| matches_subset(want, have))
        }
        (Value::String(want), Value::String(have)) => {
            if let Some(sub) = want.strip_prefix('~') {
                have.contains(sub)
            } else {
                want == "*" || want == have
            }
        }
        (Value::Number(want), Value::Number(have)) => {
            want.as_f64() == have.as_f64()
        }
        (Value::Bool(want), Value::Bool(have)) => want == have,
        (Value::Null, Value::Null) => true,
        _ => false,
    }
}

// -- Scenarios ---------------------------------------------------------------

#[gpui_kit::test]
fn click_dom_event(cx: &mut TestAppContext) {
    run_scenario(cx, include_str!("scenarios/click_dom_event.json"));
}

#[gpui_kit::test]
fn contextmenu_dom_event(cx: &mut TestAppContext) {
    run_scenario(cx, include_str!("scenarios/contextmenu_dom_event.json"));
}

#[gpui_kit::test]
fn input_text_and_submit(cx: &mut TestAppContext) {
    run_scenario(cx, include_str!("scenarios/input_text_and_submit.json"));
}

#[gpui_kit::test]
fn press_and_toggle(cx: &mut TestAppContext) {
    run_scenario(cx, include_str!("scenarios/press_and_toggle.json"));
}

#[gpui_kit::test]
fn scroll_focus_and_dom_ops(cx: &mut TestAppContext) {
    run_scenario(
        cx,
        include_str!("scenarios/scroll_focus_and_dom_ops.json"),
    );
}

#[gpui_kit::test]
fn update_and_remove_subtree(cx: &mut TestAppContext) {
    run_scenario(cx, include_str!("scenarios/update_and_remove_subtree.json"));
}
