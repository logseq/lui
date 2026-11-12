//! Public NSH responder feasibility probes. These exercise Headless touch
//! controllers, not a hardware mouse, and do not wire LUI PointerCapture.
use nsh_core::{
    MouseButton, MouseEvent, NodeId, PointerType, ScrollEvent, TouchEvent, TouchPhase,
    element::{ClaimRequest, ResponderEvent, TouchClaim},
    prelude::*,
};
use nsh_engine::{Clock, EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use std::{
    sync::{Arc, Mutex},
    time::SystemTime,
};

#[derive(Clone, Copy)]
enum Claim {
    Start,
    Moved,
}
#[derive(Clone, Copy)]
struct Options {
    claim: Claim,
    keep: bool,
    block_scroll: bool,
    outer_takes: bool,
    scroll: bool,
}
impl Default for Options {
    fn default() -> Self {
        Self {
            claim: Claim::Start,
            keep: true,
            block_scroll: true,
            outer_takes: false,
            scroll: false,
        }
    }
}
#[derive(Clone, Debug)]
struct Seen {
    owner: &'static str,
    phase: &'static str,
    page: Point<Points>,
    target: Option<NodeId>,
    pointer: Option<PointerType>,
    held: Option<MouseButton>,
}
type Trace = Arc<Mutex<Vec<Seen>>>;
struct Probe {
    options: Options,
    trace: Trace,
}

fn responder(trace: Trace, owner: &'static str, phase: &'static str) -> impl Fn(&ResponderEvent) {
    move |event| {
        trace.lock().unwrap().push(Seen {
            owner,
            phase,
            page: event.page,
            target: None,
            pointer: None,
            held: None,
        })
    }
}
fn touch(trace: Trace, owner: &'static str) -> impl Fn(&TouchEvent) {
    move |event| {
        let phase = match event.phase {
            TouchPhase::Start => "touch-start",
            TouchPhase::Move => "touch-move",
            TouchPhase::End => "touch-end",
            TouchPhase::Cancel => "touch-cancel",
        };
        for point in event.points.iter().filter(|point| point.changed) {
            trace.lock().unwrap().push(Seen {
                owner,
                phase,
                page: point.page,
                target: Some(point.target),
                pointer: Some(point.pointer_type),
                held: None,
            });
        }
    }
}
fn mouse(trace: Trace, owner: &'static str) -> impl Fn(&MouseEvent) {
    move |event| {
        trace.lock().unwrap().push(Seen {
            owner,
            phase: "mouse-move",
            page: event.page_position,
            target: None,
            pointer: Some(PointerType::Mouse),
            held: event.pressed_button,
        })
    }
}

#[component]
fn ResponderCaptureProbe() -> impl IntoElement {
    let probe = engine_context::<Probe>().unwrap();
    let options = probe.options;
    let trace = probe.trace.clone();
    let claim = match options.claim {
        Claim::Start => TouchClaim::on_start(),
        Claim::Moved => TouchClaim::on_move().ask(|request: &ClaimRequest| {
            if request.event.gesture.delta.x.abs() > px(12.0) {
                request.claim();
            }
        }),
    }
    .block_native(options.block_scroll);
    let pressed = trace.clone();
    let row_a = view()
        .test_id("capture-a")
        .w(px(120.0))
        .h(px(80.0))
        .claim_touches(claim)
        .keep_touches(options.keep)
        .on_touch(touch(trace.clone(), "a"))
        .on_mouse_move(mouse(trace.clone(), "a"))
        .on_responder_grant(responder(trace.clone(), "a", "grant"))
        .on_responder_move(responder(trace.clone(), "a", "move"))
        .on_responder_release(responder(trace.clone(), "a", "release"))
        .on_responder_terminate(responder(trace.clone(), "a", "terminate"))
        .child(
            view()
                .test_id("capture-child")
                .w(px(80.0))
                .h(px(24.0))
                .on_press(move |event: &PressEvent| {
                    pressed.lock().unwrap().push(Seen {
                        owner: "child",
                        phase: "press",
                        page: event.page_position,
                        target: None,
                        pointer: None,
                        held: None,
                    })
                })
                .child(text("Child action")),
        );
    let row_b = view()
        .test_id("capture-b")
        .w(px(120.0))
        .h(px(80.0))
        .on_touch(touch(trace.clone(), "b"))
        .on_mouse_move(mouse(trace.clone(), "b"))
        .on_responder_grant(responder(trace.clone(), "b", "grant"))
        .child(text("Row B"));
    let rows = view().flex_row().gap(px(40.0)).child(row_a).child(row_b);
    let mut outer = view()
        .test_id("capture-outer")
        .w(px(360.0))
        .h(px(240.0))
        .on_responder_grant(responder(trace.clone(), "outer", "grant"))
        .on_responder_release(responder(trace.clone(), "outer", "release"));
    if options.outer_takes {
        outer = outer.claim_touches(TouchClaim::on_move().capture().ask(
            |request: &ClaimRequest| {
                if request.event.gesture.delta.x.abs() > px(60.0) {
                    request.claim();
                }
            },
        ));
    }
    if options.scroll {
        let scroll_trace = trace.clone();
        outer = outer.child(
            scroll()
                .test_id("capture-scroll")
                .w(px(360.0))
                .h(px(160.0))
                .on_scroll(move |event: &ScrollEvent| {
                    scroll_trace.lock().unwrap().push(Seen {
                        owner: "scroll",
                        phase: "scroll",
                        page: point(px(0.0), event.offset.y),
                        target: None,
                        pointer: None,
                        held: None,
                    })
                })
                .child(view().child(rows).child(view().h(px(640.0)))),
        );
    } else {
        outer = outer.child(rows);
    }
    outer
}

fn start(options: Options) -> (Headless, Trace) {
    let trace = Trace::default();
    let mut config = EngineConfig {
        context: EngineContext::default().with(Probe {
            options,
            trace: trace.clone(),
        }),
        clock: Clock::manual(SystemTime::UNIX_EPOCH),
        ..EngineConfig::new(Root::of::<ResponderCaptureProbe>())
    };
    config.environment.os = nsh_core::platform::Os::MacOs;
    config.environment.reduce_motion = true;
    let mut app = Headless::start(config).unwrap();
    app.wait_for("Row B").unwrap();
    trace.lock().unwrap().clear();
    (app, trace)
}
fn count(trace: &[Seen], owner: &str, phase: &str) -> usize {
    trace
        .iter()
        .filter(|event| event.owner == owner && event.phase == phase)
        .count()
}

#[test]
fn public_touch_responder_retains_the_origin_outside_its_row() {
    let (mut app, trace) = start(Options::default());
    let row_b = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some("capture-b"))
        .unwrap()
        .bounds;
    app.drag_and_hold("id:capture-a", point(px(160.0), px(0.0)))
        .unwrap();
    let before_hover = trace.lock().unwrap().clone();
    let moved = before_hover
        .iter()
        .rev()
        .find(|event| event.owner == "a" && event.phase == "move")
        .unwrap();
    assert!(
        row_b.contains(&moved.page),
        "the held point must be over Row B: {before_hover:?}"
    );
    assert_eq!(count(&before_hover, "a", "grant"), 1);
    assert_eq!(count(&before_hover, "b", "grant"), 0);
    assert_eq!(
        count(&before_hover, "a", "mouse-move"),
        0,
        "touch movement is not also MouseMove"
    );
    let origin = before_hover
        .iter()
        .find(|event| event.owner == "a" && event.phase == "touch-start")
        .unwrap()
        .target;
    assert!(
        before_hover
            .iter()
            .filter(|event| event.owner == "a" && event.phase.starts_with("touch-"))
            .all(|event| event.target == origin && event.pointer == Some(PointerType::Touch))
    );
    app.hover("id:capture-b").unwrap();
    let hovered = trace.lock().unwrap().clone();
    assert_eq!(
        count(&hovered, "a", "move"),
        count(&before_hover, "a", "move")
    );
    assert_eq!(count(&hovered, "b", "mouse-move"), 1);
    assert!(
        hovered
            .iter()
            .filter(|event| event.phase == "mouse-move")
            .all(|event| event.held.is_none())
    );
    app.drop_held().unwrap();
    let released = trace.lock().unwrap().clone();
    assert_eq!(count(&released, "a", "release"), 1);
    assert_eq!(count(&released, "a", "terminate"), 0);
    assert_eq!(count(&released, "b", "grant"), 0);
    eprintln!(
        "PROOF touch capture keeps Row A as origin over Row B; separate hover has no held button"
    );
}

#[test]
fn move_claim_preserves_a_child_tap_and_cancels_a_drag_click() {
    let (mut app, trace) = start(Options {
        claim: Claim::Moved,
        ..Default::default()
    });
    app.press("id:capture-child").unwrap();
    let tapped = trace.lock().unwrap().clone();
    assert_eq!(count(&tapped, "child", "press"), 1);
    assert_eq!(count(&tapped, "a", "grant"), 0);
    trace.lock().unwrap().clear();
    app.drag("id:capture-child", point(px(160.0), px(0.0)))
        .unwrap();
    let dragged = trace.lock().unwrap().clone();
    assert_eq!(count(&dragged, "a", "grant"), 1);
    assert_eq!(count(&dragged, "a", "release"), 1);
    assert_eq!(count(&dragged, "child", "press"), 0);
}

#[test]
fn keep_touches_controls_ancestor_takeover_and_termination() {
    for keep in [true, false] {
        let (mut app, trace) = start(Options {
            keep,
            outer_takes: true,
            ..Default::default()
        });
        app.drag("id:capture-a", point(px(160.0), px(0.0))).unwrap();
        let observed = trace.lock().unwrap().clone();
        assert_eq!(count(&observed, "a", "grant"), 1);
        assert_eq!(
            count(&observed, "a", "terminate"),
            usize::from(!keep),
            "{observed:?}"
        );
        assert_eq!(
            count(&observed, "outer", "grant"),
            usize::from(!keep),
            "{observed:?}"
        );
        assert_eq!(
            count(&observed, "a", "release"),
            usize::from(keep),
            "{observed:?}"
        );
    }
}

#[test]
fn native_scroll_negotiates_with_the_public_responder_block_policy() {
    for block_scroll in [true, false] {
        let (mut app, trace) = start(Options {
            block_scroll,
            scroll: true,
            ..Default::default()
        });
        app.drag("id:capture-a", point(px(0.0), px(-120.0)))
            .unwrap();
        let observed = trace.lock().unwrap().clone();
        let scrolled = observed
            .iter()
            .any(|event| event.owner == "scroll" && event.page.y.0 > 0.0);
        assert_eq!(scrolled, !block_scroll, "{observed:?}");
        assert_eq!(count(&observed, "a", "grant"), 1);
        assert_eq!(
            count(&observed, "a", "terminate"),
            usize::from(!block_scroll),
            "{observed:?}"
        );
        assert_eq!(
            count(&observed, "a", "release"),
            usize::from(block_scroll),
            "{observed:?}"
        );
        assert_eq!(
            count(&observed, "a", "touch-cancel"),
            usize::from(!block_scroll),
            "{observed:?}"
        );
    }
}
