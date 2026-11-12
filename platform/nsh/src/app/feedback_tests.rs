//! Accepted native virtual-list work must finish while new input is fenced.
use super::*;
use crate::wire::Batch;
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use serde_json::{Value, json};
use std::sync::{Arc, Mutex};

#[derive(Default)]
struct Probe {
    windows: Vec<(usize, usize)>,
    completions: Vec<(u64, String)>,
    visible: usize,
}
#[derive(Clone)]
struct Context(Arc<Mutex<Probe>>);

fn batch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}

fn record(event: GuardedEvent, renderer: &Renderer, probe: &Arc<Mutex<Probe>>) {
    if !event.current(renderer) {
        return;
    }
    let mut probe = probe.lock().unwrap();
    match event.event {
        ViewEvent::VirtualWindow { first, last, .. } => probe.windows.push((first, last)),
        ViewEvent::ScrollCompleted { token, outcome, .. } => {
            probe.completions.push((token, outcome))
        }
        ViewEvent::VisibleRange { .. } => probe.visible += 1,
        _ => {}
    }
}

#[component]
fn AcceptedVirtualFeedback() -> impl IntoElement {
    let probe = engine_context::<Context>().unwrap().0.clone();
    let responses = signal(0_u64);
    let allowed = signal(true);
    let admission = ApplicationMutations::new(move || {
        if allowed.get_untracked() {
            Ok(())
        } else {
            Err("preparing".into())
        }
    });
    let (sender, mut receiver) = mpsc::channel(64);
    let pump_sender = sender.clone();
    let windows = Windows::default();
    let enqueue_windows = windows.clone();
    let renderer = Renderer::new(move |event, renderer| {
        enqueue_renderer_event(event, renderer, Some(&admission), &enqueue_windows, &sender);
    });
    let mut ops = vec![
        json!({"op":"create-node","id":1,"kind":"virtual-list"}),
        json!({"op":"set-prop","id":1,"property":"height","value":320}),
        json!({"op":"set-prop","id":1,"property":"width","value":400}),
        json!({"op":"set-prop","id":1,"property":"virtual-total-count","value":100}),
        json!({"op":"set-prop","id":1,"property":"virtual-generation","value":1}),
        json!({"op":"set-prop","id":1,"property":"virtual-indices","value":serde_json::to_string(&(0..100).collect::<Vec<_>>()).unwrap()}),
        json!({"op":"set-prop","id":1,"property":"track-visible-range","value":true}),
    ];
    for index in 0..100 {
        let id = index + 100;
        ops.extend([
            json!({"op":"create-node","id":id,"kind":"text"}),
            json!({"op":"set-prop","id":id,"property":"text","value":format!("Row {index}")}),
            json!({"op":"set-prop","id":id,"property":"height","value":32}),
            json!({"op":"set-prop","id":id,"property":"accessibility-identifier","value":format!("row-{index}")}),
            json!({"op":"insert-child","parent":1,"child":id,"index":index}),
        ]);
    }
    renderer.apply(batch(1, json!(ops))).unwrap();
    renderer.set_root(1).unwrap();
    let querying = renderer.clone();
    spawn(async move {
        while let Some(request) = receiver.recv().await {
            match request {
                Request::Event(event) => record(event, &querying, &probe),
                Request::WindowWake => windows.waking.set(false),
                _ => panic!("fixture received an unrelated application request"),
            }
            if let Some(event) = windows.pop() {
                record(event, &querying, &probe);
            }
            windows.wake(&pump_sender);
            // Headless waits observe native commits. Recording only in the
            // mutex can otherwise finish just after the final layout batch,
            // leaving the successful observation with no batch to wake it.
            responses.update(|count| *count += 1);
        }
    });
    let scrolling = renderer.clone();
    on_key_with(
        "f2",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            // Accept the command, then fence input before its native layout and
            // deduplicated window/completion feedback run. Headless does not
            // synthesize a platform animation-end event.
            scrolling
                .apply(batch(
                    2,
                    json!([
                        {"op":"set-prop","id":1,"property":"scroll-target","value":"row-99"},
                        {"op":"set-prop","id":1,"property":"scroll-token","value":1},
                        {"op":"set-prop","id":1,"property":"scroll-animated","value":false},
                        {"op":"set-prop","id":1,"property":"virtual-scroll-index","value":99}
                    ]),
                ))
                .unwrap();
            allowed.set(false);
        },
    );
    on_key_with(
        "f3",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| allowed.set(true),
    );
    view()
        .w(px(400.))
        .h(px(320.))
        .child(renderer.element())
        .child(text(move || format!("Feedback responses: {}", responses.get())).absolute())
}

#[component]
fn SaturatedVirtualFeedback() -> impl IntoElement {
    let renderer = Renderer::new(|_, _| {});
    let mut ops = vec![
        json!({"op":"create-node","id":1,"kind":"virtual-list"}),
        json!({"op":"set-prop","id":1,"property":"virtual-generation","value":1}),
        json!({"op":"set-prop","id":1,"property":"virtual-total-count","value":10_000}),
        json!({"op":"set-prop","id":1,"property":"virtual-indices","value":"[]"}),
    ];
    for node in 100..163 {
        ops.extend([
            json!({"op":"create-node","id":node,"kind":"button"}),
            json!({"op":"set-prop","id":node,"property":"text","value":format!("Action {node}")}),
            json!({"op":"set-prop","id":node,"property":"press-enabled","value":true}),
        ]);
    }
    renderer.apply(batch(1, json!(ops))).unwrap();
    let incarnation = renderer.current_incarnation(1).unwrap();
    let (sender, mut receiver) = mpsc::channel(64);
    let windows = Windows::default();
    for node in 100..163 {
        enqueue_renderer_event(
            ViewEvent::Press(node),
            renderer.clone(),
            None,
            &windows,
            &sender,
        );
    }
    enqueue_renderer_event(
        ViewEvent::ScrollCompleted {
            node: 1,
            incarnation,
            token: 77,
            outcome: "succeeded".into(),
        },
        renderer.clone(),
        None,
        &windows,
        &sender,
    );
    assert_eq!(receiver.len(), 64);
    for first in 0..4096 {
        enqueue_renderer_event(
            ViewEvent::VirtualWindow {
                node: 1,
                incarnation,
                generation: 1,
                first,
                last: first + 10,
                pins: vec![],
            },
            renderer.clone(),
            None,
            &windows,
            &sender,
        );
        enqueue_renderer_event(
            ViewEvent::VisibleRange {
                node: 1,
                incarnation,
                first: first as i64,
                last: (first + 9) as i64,
            },
            renderer.clone(),
            None,
            &windows,
            &sender,
        );
    }
    assert!(renderer.failure().is_none());
    assert_eq!(receiver.len(), 64);
    assert_eq!(windows.pending.borrow().len(), 2);
    assert_eq!(windows.order.borrow().len(), 2);
    assert!(!windows.waking.get(), "a full queue defers its wakeup");
    for expected in 100..163 {
        match receiver.try_recv().unwrap() {
            Request::Event(GuardedEvent {
                event: ViewEvent::Press(node),
                ..
            }) => assert_eq!(node, expected),
            _ => panic!("list feedback displaced an ordered input"),
        }
    }
    match receiver.try_recv().unwrap() {
        Request::Event(GuardedEvent {
            event: ViewEvent::ScrollCompleted { token: 77, .. },
            ..
        }) => {}
        _ => panic!("list feedback displaced a scroll-token completion"),
    }
    for kind in [FeedbackKind::Window, FeedbackKind::VisibleRange] {
        windows.wake(&sender);
        assert!(matches!(receiver.try_recv().unwrap(), Request::WindowWake));
        windows.waking.set(false);
        let event = windows.pop().unwrap();
        assert!(event.current(&renderer));
        match (kind, event.event) {
            (
                FeedbackKind::Window,
                ViewEvent::VirtualWindow {
                    first: 4095,
                    last: 4105,
                    ..
                },
            )
            | (
                FeedbackKind::VisibleRange,
                ViewEvent::VisibleRange {
                    first: 4095,
                    last: 4104,
                    ..
                },
            ) => {}
            _ => panic!("list feedback lost its independent latest state"),
        }
    }
    windows.wake(&sender);
    assert!(receiver.try_recv().is_err());

    // A delayed range and window belong to their original source revision.
    for event in [
        ViewEvent::VirtualWindow {
            node: 1,
            incarnation,
            generation: 1,
            first: 0,
            last: 10,
            pins: vec![],
        },
        ViewEvent::VisibleRange {
            node: 1,
            incarnation,
            first: 0,
            last: 9,
        },
    ] {
        enqueue_renderer_event(event, renderer.clone(), None, &windows, &sender);
    }
    renderer
        .apply(batch(
            2,
            json!([
                {"op":"set-prop","id":1,"property":"virtual-generation","value":2}
            ]),
        ))
        .unwrap();
    while let Some(event) = windows.pop() {
        assert!(
            !event.current(&renderer),
            "retired source feedback must be rejected"
        );
    }
    let retired = GuardedEvent::capture(
        ViewEvent::VisibleRange {
            node: 1,
            incarnation,
            first: 0,
            last: 9,
        },
        &renderer,
    )
    .unwrap();
    renderer
        .apply(batch(
            3,
            json!([
                {"op":"drop-node","id":1},
                {"op":"create-node","id":1,"kind":"virtual-list"},
                {"op":"set-prop","id":1,"property":"virtual-generation","value":2},
                {"op":"set-prop","id":1,"property":"virtual-total-count","value":0},
                {"op":"set-prop","id":1,"property":"virtual-indices","value":"[]"}
            ]),
        ))
        .unwrap();
    assert!(
        !retired.current(&renderer),
        "reused wire ids cannot inherit feedback"
    );
    text("saturated list feedback checked").test_id("saturated-feedback-checked")
}

#[test]
fn list_feedback_coalesces_without_overflowing_input_or_reusing_retired_sources() {
    let mut app =
        Headless::start(EngineConfig::new(Root::of::<SaturatedVirtualFeedback>())).unwrap();
    app.wait_for("id:saturated-feedback-checked").unwrap();
}

#[test]
fn accepted_native_virtual_window_and_scroll_completion_survive_closed_admission_once() {
    let probe = Arc::new(Mutex::new(Probe::default()));
    let mut config = EngineConfig::new(Root::of::<AcceptedVirtualFeedback>());
    config.context = EngineContext::default().with(Context(probe.clone()));
    config.environment.os = nsh_core::platform::Os::MacOs;
    config.environment.idiom = nsh_core::platform::Idiom::Desktop;
    let mut app = Headless::start(config).unwrap();
    app.wait_until(
        "initial native virtual window",
        Duration::from_secs(3),
        |_| !probe.lock().unwrap().windows.is_empty(),
    )
    .unwrap_or_else(|error| {
        let probe = probe.lock().unwrap();
        panic!(
            "{error}; recorded windows={:?}, visible={}, completions={:?}",
            probe.windows, probe.visible, probe.completions
        );
    });
    {
        let mut probe = probe.lock().unwrap();
        probe.windows.clear();
        probe.visible = 0;
    }
    app.press_key("f2").unwrap();
    app.wait_until(
        "accepted scroll finishes while admission is closed",
        Duration::from_secs(5),
        |_| {
            let probe = probe.lock().unwrap();
            probe.windows.iter().any(|(_, last)| *last == 100)
                && probe.completions == [(1, "succeeded".into())]
        },
    )
    .unwrap();
    assert!(probe.lock().unwrap().visible > 0);
    app.press_key("f3").unwrap();
    app.wait(Duration::from_millis(50)).unwrap();
    assert_eq!(probe.lock().unwrap().completions, [(1, "succeeded".into())]);
}
