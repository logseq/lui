use super::*;
use crate::{
    render::{Event, Renderer},
    wire::Batch,
};
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use serde_json::{Value, json};
use std::{cell::Cell, sync::Mutex};

#[derive(Clone)]
struct Fixture {
    duration: Option<u64>,
    editor: bool,
    initial: bool,
    events: Arc<Mutex<Vec<Event>>>,
}
fn patch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}
fn notification(duration: Option<u64>, editor: bool, value: &str) -> Vec<Value> {
    let mut ops = vec![
        json!({"op":"create-node","id":3,"kind":"toast"}),
        json!({"op":"set-prop","id":3,"property":"accessibility-label","value":"Saved notification"}),
        json!({"op":"set-prop","id":3,"property":"pointer-enabled","value":true}),
        json!({"op":"create-node","id":4,"kind":"text"}),
        json!({"op":"set-prop","id":4,"property":"text","value":value}),
        json!({"op":"insert-child","parent":3,"child":4,"index":0}),
    ];
    if let Some(duration) = duration {
        ops.push(json!({"op":"set-prop","id":3,"property":"duration","value":duration}));
    }
    if editor {
        ops.extend([
            json!({"op":"create-node","id":5,"kind":"text-field"}),
            json!({"op":"set-prop","id":5,"property":"text","value":"seed"}),
            json!({"op":"set-prop","id":5,"property":"change-enabled","value":true}),
            json!({"op":"set-prop","id":5,"property":"accessibility-label","value":"Notification draft"}),
            json!({"op":"set-prop","id":5,"property":"width","value":120}),
            json!({"op":"insert-child","parent":3,"child":5,"index":1}),
            json!({"op":"create-node","id":6,"kind":"button"}),
            json!({"op":"set-prop","id":6,"property":"text","value":"Undo"}),
            json!({"op":"set-prop","id":6,"property":"press-enabled","value":true}),
            json!({"op":"insert-child","parent":3,"child":6,"index":2}),
        ]);
    }
    ops.push(json!({"op":"insert-child","parent":2,"child":3,"index":1}));
    ops
}
#[component]
fn ToastProbe() -> impl IntoElement {
    let fixture = engine_context::<Fixture>().unwrap();
    let generation = Rc::new(Cell::new(1_u64));
    let next = generation.clone();
    let events = fixture.events.clone();
    let editor = fixture.editor;
    let renderer = Renderer::new(move |event, renderer| {
        events.lock().unwrap().push(event.clone());
        let ops = match event {
            Event::Text(5, text) => {
                vec![json!({"op":"set-prop","id":5,"property":"text","value":text})]
            }
            Event::Press(10) => vec![
                json!({"op":"set-prop","id":4,"property":"text","value":"Updated notification"}),
                json!({"op":"set-prop","id":3,"property":"duration","value":0}),
            ],
            Event::Press(11) => vec![json!({"op":"detach-subtree","id":3})],
            Event::Press(12) => {
                let mut ops = vec![json!({"op":"detach-subtree","id":3})];
                ops.extend(notification(Some(0), editor, "Reopened notification"));
                ops
            }
            Event::Press(13) => vec![
                json!({"op":"create-node","id":20,"kind":"toast"}),
                json!({"op":"set-prop","id":20,"property":"duration","value":0}),
                json!({"op":"set-prop","id":20,"property":"accessibility-label","value":"Second notification"}),
                json!({"op":"create-node","id":21,"kind":"text"}),
                json!({"op":"set-prop","id":21,"property":"text","value":"Second notification"}),
                json!({"op":"insert-child","parent":20,"child":21,"index":0}),
                json!({"op":"insert-child","parent":2,"child":20,"index":0}),
            ],
            _ => vec![],
        };
        if !ops.is_empty() {
            let generation = next.get() + 1;
            renderer.apply(patch(generation, json!(ops))).unwrap();
            next.set(generation);
        }
    });
    let mut ops = vec![
        json!({"op":"create-node","id":1,"kind":"root"}),
        json!({"op":"create-node","id":2,"kind":"column"}),
        json!({"op":"set-prop","id":2,"property":"gap","value":10}),
        json!({"op":"set-prop","id":2,"property":"width","value":280}),
        json!({"op":"insert-child","parent":1,"child":2,"index":0}),
    ];
    for (index, id, text) in [
        (0, 7, "Before"),
        (1, 8, "After"),
        (2, 10, "Update"),
        (3, 11, "Detach"),
        (4, 12, "Reopen"),
        (5, 13, "Add second"),
    ] {
        let kind = if id >= 10 { "button" } else { "text" };
        ops.extend([
            json!({"op":"create-node","id":id,"kind":kind}),
            json!({"op":"set-prop","id":id,"property":"text","value":text}),
            json!({"op":"insert-child","parent":2,"child":id,"index":index}),
        ]);
        if id >= 10 {
            ops.push(json!({"op":"set-prop","id":id,"property":"press-enabled","value":true}));
        }
    }
    if fixture.initial {
        ops.extend(notification(
            fixture.duration,
            fixture.editor,
            "Original notification",
        ));
    }
    renderer.apply(patch(1, json!(ops))).unwrap();
    renderer.element()
}
fn fixture_app(duration: Option<u64>, editor: bool, initial: bool) -> (Headless, Fixture) {
    let fixture = Fixture {
        duration,
        editor,
        initial,
        events: Arc::new(Mutex::new(Vec::new())),
    };
    let mut config = EngineConfig {
        viewport: Size::new(px(800.0), px(500.0)),
        clock: nsh_core::time::Clock::manual(std::time::SystemTime::UNIX_EPOCH),
        context: EngineContext::default().with(fixture.clone()),
        ..EngineConfig::new(Root::of::<ToastProbe>())
    };
    config.environment.os = nsh_core::platform::Os::MacOs;
    (Headless::start(config).unwrap(), fixture)
}
fn dismissals(fixture: &Fixture) -> usize {
    fixture
        .events
        .lock()
        .unwrap()
        .iter()
        .filter(|event| matches!(event, Event::Dismiss(3)))
        .count()
}
fn native_id(app: &Headless, test_id: &str) -> nsh_core::NodeId {
    app.screen()
        .layout_nodes()
        .iter()
        .find(|node| node.test_id.as_deref() == Some(test_id))
        .unwrap()
        .id
}

#[test]
fn toast_is_non_flow_metadata_and_retains_arbitrary_native_children_on_update() {
    let (mut app, fixture) = fixture_app(Some(0), true, true);
    app.wait_for("Original notification").unwrap();
    let before = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some("lui-7"))
        .unwrap()
        .bounds;
    let after = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some("lui-8"))
        .unwrap()
        .bounds;
    assert_eq!(
        after.origin.y,
        before.origin.y + before.size.height + px(10.0)
    );
    let editor = native_id(&app, "lui-5");
    let action = native_id(&app, "lui-6");
    app.type_text("id:lui-5", " draft").unwrap();
    let draft = app
        .screen()
        .input_text("id:lui-5")
        .unwrap()
        .unwrap()
        .to_owned();
    app.press("id:lui-10").unwrap();
    app.wait_for("Updated notification").unwrap();
    assert_eq!(native_id(&app, "lui-5"), editor);
    assert_eq!(native_id(&app, "lui-6"), action);
    assert_eq!(
        app.screen().input_text("id:lui-5").unwrap(),
        Some(draft.as_str())
    );
    app.press("id:lui-6").unwrap();
    assert_eq!(
        fixture
            .events
            .lock()
            .unwrap()
            .iter()
            .filter(|event| matches!(event, Event::Press(6)))
            .count(),
        1
    );
    assert_eq!(dismissals(&fixture), 0);
}

#[test]
fn native_timeout_does_not_restart_and_closed_source_incarnation_never_reopens() {
    let (mut app, fixture) = fixture_app(Some(1000), false, true);
    app.wait_for("Original notification").unwrap();
    app.run_for(Duration::from_millis(800)).unwrap();
    app.press("id:lui-10").unwrap();
    app.wait_for("Updated notification").unwrap();
    app.run_for(Duration::from_millis(850)).unwrap();
    assert_eq!(dismissals(&fixture), 1);
    assert_eq!(app.screen().count("id:lui-3").unwrap(), 0);
    // The canonical node still exists. Its property update is cleanup-neutral.
    app.press("id:lui-10").unwrap();
    app.run_for(Duration::from_secs(2)).unwrap();
    assert_eq!(app.screen().count("id:lui-3").unwrap(), 0);
    assert_eq!(dismissals(&fixture), 1);
}

#[test]
fn desktop_default_and_zero_persistence_use_native_lifecycle_without_idle_polling() {
    let (mut default, fixture) = fixture_app(None, false, true);
    default.run_for(Duration::from_millis(4300)).unwrap();
    assert_eq!(
        dismissals(&fixture),
        0,
        "four seconds of native Present time plus enter/exit motion"
    );
    default.run_for(Duration::from_millis(400)).unwrap();
    assert_eq!(dismissals(&fixture), 1);
    default.run_for(Duration::from_secs(1)).unwrap();
    assert!(
        default.clock().next_alarm().is_none(),
        "an empty stack has no lifecycle wake"
    );
    let (mut persistent, fixture) = fixture_app(Some(0), false, true);
    persistent.run_for(Duration::from_secs(30)).unwrap();
    assert_eq!(dismissals(&fixture), 0);
    assert_eq!(persistent.screen().count("id:lui-3").unwrap(), 1);
    assert!(
        persistent.clock().next_alarm().is_none(),
        "an idle persistent toast has no lifecycle wake"
    );
}

#[test]
fn native_hover_and_keyboard_focus_pause_timeout_then_resume_remaining_time() {
    let (mut app, fixture) = fixture_app(Some(1000), true, true);
    app.wait_for("Original notification").unwrap();
    app.hover("id:lui-3").unwrap();
    app.run_for(Duration::from_secs(4)).unwrap();
    assert_eq!(dismissals(&fixture), 0);
    app.type_text("id:lui-5", " focused").unwrap();
    app.hover("id:lui-7").unwrap();
    app.run_for(Duration::from_secs(4)).unwrap();
    assert_eq!(
        dismissals(&fixture),
        0,
        "focus keeps the stack paused after pointer departure"
    );
    // The first Tab reaches Undo inside this Toast; the second leaves it.
    app.press_key("tab").unwrap();
    app.press_key("tab").unwrap();
    app.run_for(Duration::from_millis(1300)).unwrap();
    assert_eq!(dismissals(&fixture), 1);
}

#[test]
fn native_swipe_closes_once_and_source_detach_cancels_late_callbacks_before_reopen() {
    let (mut app, fixture) = fixture_app(Some(0), false, true);
    app.wait_for("Original notification").unwrap();
    app.drag("id:lui-3", Point::new(px(120.0), px(0.0)))
        .unwrap();
    app.run_for(Duration::from_millis(300)).unwrap();
    assert_eq!(dismissals(&fixture), 1);
    assert_eq!(app.screen().count("id:lui-3").unwrap(), 0);
    let (mut app, fixture) = fixture_app(Some(1000), false, true);
    app.run_for(Duration::from_millis(600)).unwrap();
    app.press("id:lui-11").unwrap();
    app.press("id:lui-12").unwrap();
    app.wait_for("Reopened notification").unwrap();
    app.run_for(Duration::from_secs(3)).unwrap();
    assert_eq!(
        dismissals(&fixture),
        0,
        "the old incarnation cannot dismiss its replacement"
    );
    assert_eq!(app.screen().count("id:lui-3").unwrap(), 1);
}

#[test]
fn native_stack_keeps_existing_identity_and_escape_closes_only_the_newest() {
    let (mut app, fixture) = fixture_app(Some(0), false, true);
    app.wait_for("Original notification").unwrap();
    let first = native_id(&app, "lui-4");
    app.press("id:lui-13").unwrap();
    app.wait_for("id:lui-20").unwrap();
    app.run_for(Duration::from_millis(500)).unwrap();
    assert_eq!(app.screen().count("role:alert").unwrap(), 2);
    assert_eq!(native_id(&app, "lui-4"), first);
    app.press_key("escape").unwrap();
    app.run_for(Duration::from_millis(300)).unwrap();
    assert_eq!(app.screen().count("id:lui-20").unwrap(), 0);
    assert_eq!(app.screen().count("id:lui-3").unwrap(), 1);
    assert_eq!(native_id(&app, "lui-4"), first);
    assert_eq!(dismissals(&fixture), 0);
    assert_eq!(
        fixture
            .events
            .lock()
            .unwrap()
            .iter()
            .filter(|event| matches!(event, Event::Dismiss(20)))
            .count(),
        1
    );
}
