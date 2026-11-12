//! Public headless input probes for canonical host event bindings.
use super::*;
use crate::{render::Renderer, wire::Batch};
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use serde_json::json;
use std::{cell::Cell, sync::Mutex};

struct Probe {
    column: bool,
    events: Arc<Mutex<Vec<Event>>>,
    rejected: Arc<Mutex<bool>>,
}
fn patch(generation: u64, operations: serde_json::Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":operations}).to_string()).unwrap()
}

#[component]
fn HostEvents() -> impl IntoElement {
    let probe = engine_context::<Probe>().unwrap();
    let observed = probe.events.clone();
    let renderer = Renderer::new(move |event, _| observed.lock().unwrap().push(event));
    renderer
        .apply(patch(
            1,
            json!([
                {"op":"create-node","id":1,"kind":"column"},
                {"op":"create-node","id":10,"kind":if probe.column { "column" } else { "box" }},
                {"op":"set-prop","id":10,"property":"width","value":220},
                {"op":"set-prop","id":10,"property":"height","value":60},
                {"op":"set-prop","id":10,"property":"press-enabled","value":!probe.column},
                {"op":"set-prop","id":10,"property":"pointer-enabled","value":true},
                {"op":"set-prop","id":10,"property":"appear-enabled","value":true},
                {"op":"set-prop","id":10,"property":"focus-within-enabled","value":true},
                {"op":"create-node","id":20,"kind":"text"},
                {"op":"set-prop","id":20,"property":"text","value":"Tap target"},
                {"op":"insert-child","parent":10,"child":20,"index":0},
                {"op":"insert-child","parent":1,"child":10,"index":0},
                {"op":"create-node","id":30,"kind":"text-field"},
                {"op":"set-prop","id":30,"property":"text","value":"Input"},
                {"op":"set-prop","id":30,"property":"accessibility-label","value":"Guarded input"},
                {"op":"insert-child","parent":10,"child":30,"index":1},
                {"op":"create-node","id":31,"kind":"checkbox"},
                {"op":"set-prop","id":31,"property":"text","value":"Guarded checkbox"},
                {"op":"set-prop","id":31,"property":"checked","value":false},
                {"op":"set-prop","id":31,"property":"indeterminate","value":true},
                {"op":"insert-child","parent":1,"child":31,"index":1},
                {"op":"create-node","id":40,"kind":"checkbox"},
                {"op":"set-prop","id":40,"property":"text","value":"Disabled seen"},
                {"op":"set-prop","id":40,"property":"checked","value":false},
                {"op":"set-prop","id":40,"property":"enabled","value":false},
                {"op":"set-prop","id":40,"property":"appear-enabled","value":true},
                {"op":"insert-child","parent":1,"child":40,"index":2}
            ]),
        ))
        .unwrap();
    renderer.set_root(1).unwrap();
    let generation = Rc::new(Cell::new(1_u64));
    for (key, active) in [("f6", false), ("f5", true)] {
        let renderer = renderer.clone();
        let generation = generation.clone();
        on_key_with(
            key,
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| {
                let next = generation.get() + 1;
                renderer.apply(patch(next,json!([
                {"op":"set-prop","id":10,"property":"press-enabled","value":active},
                {"op":"set-prop","id":10,"property":"pointer-enabled","value":active},
                {"op":"set-prop","id":10,"property":"focus-within-enabled","value":active},
                {"op":"set-prop","id":30,"property":"change-enabled","value":active},
                {"op":"set-prop","id":30,"property":"submit-enabled","value":active},
                {"op":"set-prop","id":31,"property":"toggle-enabled","value":active}
            ]))).unwrap();
                generation.set(next);
            },
        );
    }
    let resolving_mixed = renderer.clone();
    let mixed_generation = generation.clone();
    on_key_with(
        "f8",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            let next = mixed_generation.get() + 1;
            resolving_mixed
                .apply(patch(
                    next,
                    json!([
                        {"op":"set-prop","id":31,"property":"checked","value":true},
                        {"op":"set-prop","id":31,"property":"indeterminate","value":false}
                    ]),
                ))
                .unwrap();
            mixed_generation.set(next);
        },
    );
    let rejected = renderer.clone();
    on_key_with(
        "f4",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            let next = generation.get() + 1;
            let result = rejected.apply(patch(
                next,
                json!([
                    {"op":"set-prop","id":30,"property":"text","value":"must not publish"},
                    {"op":"set-prop","id":20,"property":"press-enabled","value":true}
                ]),
            ));
            let error = result.unwrap_err();
            assert!(error.contains("uninstalled native event"));
            assert!(error.contains("node=20, kind=text"));
            assert!(error.contains("missing=[\"press-enabled\"]"));
            rejected
                .apply(patch(
                    next,
                    json!([
                        {"op":"set-prop","id":20,"property":"text","value":"Leaf after rejection"}
                    ]),
                ))
                .unwrap();
            generation.set(next);
            *probe.rejected.lock().unwrap() = true;
        },
    );
    renderer.element()
}

type ProbeApp = (Headless, Arc<Mutex<Vec<Event>>>, Arc<Mutex<bool>>);
fn start() -> ProbeApp {
    start_kind(false)
}
fn start_kind(column: bool) -> ProbeApp {
    let events = Arc::new(Mutex::new(Vec::new()));
    let rejected = Arc::new(Mutex::new(false));
    let mut config = EngineConfig {
        context: EngineContext::default().with(Probe {
            column,
            events: events.clone(),
            rejected: rejected.clone(),
        }),
        ..EngineConfig::new(Root::of::<HostEvents>())
    };
    config.environment.os = nsh_core::platform::Os::MacOs;
    config.environment.reduce_motion = true;
    let mut app = Headless::start(config).unwrap();
    app.wait_for("Tap target").unwrap();
    (app, events, rejected)
}
fn node_id(app: &Headless, id: &str) -> nsh_core::NodeId {
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some(id))
        .unwrap()
        .id
}

#[test]
fn native_host_press_preserves_modifiers_pointer_payload_and_appear_without_text_stealing() {
    let (mut app, events, _) = start();
    let before = node_id(&app, "lui-10");
    assert!(events.lock().unwrap().contains(&Event::Appear(10)));
    assert!(
        events.lock().unwrap().contains(&Event::Appear(40)),
        "disabled controls still appear"
    );
    events.lock().unwrap().clear();
    app.hold_keys("ctrl+shift+meta+alt", true).unwrap();
    app.hover("id:lui-10").unwrap();
    app.press("Tap target").unwrap();
    app.hold_keys("ctrl+shift+meta+alt", false).unwrap();
    let observed = events.lock().unwrap().clone();
    assert_eq!(
        observed
            .iter()
            .filter(|event| matches!(event, Event::NativePress(10, 23)))
            .count(),
        1
    );
    assert!(
        !observed
            .iter()
            .any(|event| matches!(event, Event::Press(20) | Event::NativePress(20, _)))
    );
    for kind in [PointerKind::Down, PointerKind::Up, PointerKind::PressDetail] {
        assert!(observed.iter().any(|event|matches!(event, Event::Pointer {node:10,kind:current,detail} if *current==kind && detail.modifiers==23 && detail.x.is_finite() && detail.y.is_finite() && detail.button==0 && detail.target_class.is_empty())), "missing {kind:?}: {observed:?}");
    }
    assert!(observed.contains(&Event::PointerEnter(10)));
    assert!(
        observed.iter().any(|event| matches!(event,
        Event::Pointer { node:10,kind:PointerKind::Move,detail } if detail.button == -1)),
        "native hover must not report a held primary button: {observed:?}"
    );
    assert_eq!(node_id(&app, "lui-10"), before);
}

#[test]
fn mouse_move_preserves_the_public_native_held_button_state() {
    for (pressed, expected) in [
        (None, -1),
        (Some(MouseButton::Left), 0),
        (Some(MouseButton::Middle), 1),
        (Some(MouseButton::Right), 2),
        (Some(MouseButton::Back), 3),
        (Some(MouseButton::Forward), 4),
    ] {
        let event = nsh_core::MouseEvent::new(
            point(px(3.0), px(5.0)),
            point(px(31.0), px(47.0)),
            Modifiers {
                ctrl: true,
                shift: true,
                cmd: true,
                ..Default::default()
            },
            pressed,
        );
        let value = move_detail(&event);
        assert_eq!(value.button, expected);
        assert_eq!((value.x, value.y), (31.0, 47.0));
        assert_eq!(
            value.modifiers,
            if pressed == Some(MouseButton::Right) {
                15
            } else {
                7
            }
        );
        assert!(value.target_class.is_empty());
    }
    assert_eq!(
        detail(point(px(1.0), px(2.0)), Modifiers::default(), None).button,
        0
    );
}

#[test]
fn live_flags_guard_input_checkbox_and_host_callbacks_without_remounting() {
    let (mut app, events, _) = start();
    let before = node_id(&app, "lui-10");
    events.lock().unwrap().clear();
    app.type_text("id:lui-30", "x").unwrap();
    app.submit("id:lui-30").unwrap();
    app.press("Guarded checkbox").unwrap();
    assert!(!events.lock().unwrap().iter().any(|event| matches!(
        event,
        Event::Text(30, _) | Event::Submit(30) | Event::Toggle(31, _)
    )));
    app.press_key("f6").unwrap();
    events.lock().unwrap().clear();
    app.press("Tap target").unwrap();
    assert!(events.lock().unwrap().is_empty());
    app.press_key("f5").unwrap();
    app.type_text("id:lui-30", "y").unwrap();
    app.submit("id:lui-30").unwrap();
    app.press("Guarded checkbox").unwrap();
    app.press("Tap target").unwrap();
    let observed = events.lock().unwrap().clone();
    assert!(
        observed
            .iter()
            .any(|event| matches!(event, Event::Text(30, _)))
    );
    assert!(observed.contains(&Event::Submit(30)));
    assert!(
        observed
            .iter()
            .any(|event| matches!(event, Event::Toggle(31, _)))
    );
    assert!(observed.contains(&Event::Press(10)));
    assert!(
        !observed
            .iter()
            .any(|event| matches!(event, Event::Appear(_)))
    );
    assert_eq!(node_id(&app, "lui-10"), before);
}

#[test]
fn native_checkbox_mixed_state_is_controlled_until_the_model_resolves_it() {
    let (mut app, events, _) = start();
    let before = node_id(&app, "lui-31");
    let checked = |app: &Headless| {
        app.screen()
            .accessibility_state("id:lui-31")
            .unwrap()
            .checked
    };
    assert_eq!(checked(&app), Some(nsh_core::Checked::Mixed));
    app.press_key("f5").unwrap();
    events.lock().unwrap().clear();
    app.press("Guarded checkbox").unwrap();
    assert!(events.lock().unwrap().contains(&Event::Toggle(31, true)));
    assert_eq!(checked(&app), Some(nsh_core::Checked::Mixed));
    app.press_key("f8").unwrap();
    assert_eq!(checked(&app), Some(nsh_core::Checked::True));
    assert_eq!(node_id(&app, "lui-31"), before);
}

#[test]
fn adding_an_uninstalled_host_listener_rolls_back_other_edits_and_retains_native_identity() {
    let (mut app, _, rejected) = start();
    let leaf = node_id(&app, "lui-20");
    let editor = node_id(&app, "lui-30");
    app.press_key("f4").unwrap();
    assert!(*rejected.lock().unwrap());
    app.wait_for("Leaf after rejection").unwrap();
    assert_eq!(node_id(&app, "lui-20"), leaf);
    assert_eq!(node_id(&app, "lui-30"), editor);
    assert_eq!(app.screen().input_text("id:lui-30").unwrap(), Some("Input"));
}

#[test]
fn a_container_observes_one_focus_entry_and_exit_from_its_real_input() {
    let (mut app, events, _) = start();
    events.lock().unwrap().clear();
    app.type_text("id:lui-30", "").unwrap();
    app.press_key("tab").unwrap();
    let focus: Vec<_> = events
        .lock()
        .unwrap()
        .iter()
        .filter(|event| matches!(event, Event::Focus(_) | Event::Blur(_)))
        .cloned()
        .collect();
    assert_eq!(focus, [Event::Focus(10), Event::Blur(10)]);
}

#[test]
fn keyboard_context_menu_uses_root_coordinates_without_a_fake_secondary_button() {
    let (mut app, events) = pointer_picker(nsh_core::platform::Os::Linux);
    app.press_key("tab").unwrap();
    events.lock().unwrap().clear();
    app.press_key("shift+f10").unwrap();
    let observed = events.lock().unwrap();
    assert!(
        observed.iter().any(|event| matches!(event,
            Event::Pointer {node:10, kind:PointerKind::ContextMenu, detail}
            if detail.modifiers==2 && detail.button==0 && detail.target_class.is_empty()
            && detail.x.is_finite() && detail.y.is_finite()
        )),
        "{observed:?}"
    );
}

struct PointerPicker(Arc<Mutex<Vec<Event>>>);
#[component]
fn PointerOnlyPicker() -> impl IntoElement {
    let probe = engine_context::<PointerPicker>().unwrap();
    let renderer = Renderer::new(move |event, _| probe.0.lock().unwrap().push(event));
    renderer
        .apply(patch(
            1,
            json!([
                {"op":"create-node","id":1,"kind":"column"},
                {"op":"create-node","id":10,"kind":"select"},
                {"op":"set-prop","id":10,"property":"text","value":"Pointer picker"},
                {"op":"set-prop","id":10,"property":"pointer-enabled","value":true},
                {"op":"insert-child","parent":1,"child":10,"index":0}
            ]),
        ))
        .unwrap();
    renderer.set_root(1).unwrap();
    renderer.element()
}
fn pointer_picker(os: nsh_core::platform::Os) -> (Headless, Arc<Mutex<Vec<Event>>>) {
    let events = Arc::new(Mutex::new(Vec::new()));
    let mut config = EngineConfig {
        context: EngineContext::default().with(PointerPicker(events.clone())),
        ..EngineConfig::new(Root::of::<PointerOnlyPicker>())
    };
    config.environment.os = os;
    config.environment.reduce_motion = true;
    let mut app = Headless::start(config).unwrap();
    app.wait_for("Pointer picker").unwrap();
    (app, events)
}
#[test]
fn pointer_only_controlled_picker_delivers_detail_once_without_semantic_activation() {
    let (mut app, events) = pointer_picker(nsh_core::platform::Os::MacOs);
    app.hold_keys("meta", true).unwrap();
    app.press("Pointer picker").unwrap();
    app.hold_keys("meta", false).unwrap();
    let observed = events.lock().unwrap();
    assert_eq!(observed.iter().filter(|event|matches!(event,Event::Pointer {node:10,kind:PointerKind::PressDetail,detail} if detail.modifiers==4)).count(),1,"{observed:?}");
    assert!(
        !observed
            .iter()
            .any(|event| matches!(event, Event::Press(10) | Event::NativePress(10, _))),
        "{observed:?}"
    );
}

struct ObserverProbe(Arc<Mutex<Vec<&'static str>>>);
#[component]
fn ObserverBoundary() -> impl IntoElement {
    let probe = engine_context::<ObserverProbe>().unwrap();
    let parent = probe.0.clone();
    view()
        .on_press(move || parent.lock().unwrap().push("observer"))
        .child(
            nsh_base::button()
                .on_press(move || probe.0.lock().unwrap().push("button"))
                .child(text("Child command")),
        )
}
#[test]
fn an_observer_parent_cannot_capture_a_typed_buttons_native_press_payload() {
    let events = Arc::new(Mutex::new(Vec::new()));
    let mut config = EngineConfig {
        context: EngineContext::default().with(ObserverProbe(events.clone())),
        ..EngineConfig::new(Root::of::<ObserverBoundary>())
    };
    config.environment.os = nsh_core::platform::Os::MacOs;
    let mut app = Headless::start(config).unwrap();
    app.wait_for("Child command").unwrap();
    app.press("Child command").unwrap();
    assert_eq!(*events.lock().unwrap(), ["button"]);
}

#[test]
fn column_detail_only_capability_does_not_emit_an_unsupported_ordinary_press() {
    let (mut app, events, _) = start_kind(true);
    events.lock().unwrap().clear();
    app.press("Tap target").unwrap();
    let events = events.lock().unwrap();
    assert!(events.iter().any(|event| matches!(
        event,
        Event::Pointer {
            node: 10,
            kind: PointerKind::PressDetail,
            ..
        }
    )));
    assert!(
        !events
            .iter()
            .any(|event| matches!(event, Event::Press(10) | Event::NativePress(10, _)))
    );
}

#[test]
fn pointer_alt_bit_does_not_replace_secondary_or_other_modifier_bits() {
    let all = Modifiers {
        ctrl: true,
        shift: true,
        cmd: true,
        alt: true,
    };
    assert_eq!(modifiers(all, true), 31);
    assert_eq!(modifiers(all, false), 23);
    assert_eq!(
        modifiers(
            Modifiers {
                alt: true,
                ..Default::default()
            },
            false
        ),
        16
    );
    assert_eq!(modifiers(Modifiers::default(), true), 8);
}

// These are public engine-boundary input samples, not physical mouse-driver
// proof. Headless::press models a Touch and does not send MouseUp.
struct ReleaseProbe(Arc<Mutex<Vec<Event>>>);
#[component]
fn ReleaseEvents() -> impl IntoElement {
    let observed = engine_context::<ReleaseProbe>().unwrap().0.clone();
    let renderer = Renderer::new(move |event, _| observed.lock().unwrap().push(event));
    renderer
        .apply(patch(
            1,
            json!([
                {"op":"create-node","id":1,"kind":"row"},
                {"op":"create-node","id":10,"kind":"box"},
                {"op":"set-prop","id":10,"property":"width","value":100},
                {"op":"set-prop","id":10,"property":"height","value":80},
                {"op":"set-prop","id":10,"property":"press-enabled","value":true},
                {"op":"set-prop","id":10,"property":"pointer-enabled","value":true},
                {"op":"create-node","id":11,"kind":"text"},
                {"op":"set-prop","id":11,"property":"text","value":"Release source"},
                {"op":"insert-child","parent":10,"child":11,"index":0},
                {"op":"create-node","id":20,"kind":"box"},
                {"op":"set-prop","id":20,"property":"width","value":100},
                {"op":"set-prop","id":20,"property":"height","value":80},
                {"op":"set-prop","id":20,"property":"press-enabled","value":true},
                {"op":"set-prop","id":20,"property":"pointer-enabled","value":true},
                {"op":"create-node","id":21,"kind":"text"},
                {"op":"set-prop","id":21,"property":"text","value":"Release destination"},
                {"op":"insert-child","parent":20,"child":21,"index":0},
                {"op":"insert-child","parent":1,"child":10,"index":0},
                {"op":"insert-child","parent":1,"child":20,"index":1}
            ]),
        ))
        .unwrap();
    renderer.set_root(1).unwrap();
    let retiring = renderer.clone();
    on_key("f9", move |_| {
        retiring
            .apply(patch(
                2,
                json!([
                    {"op":"drop-node","id":10},
                    {"op":"create-node","id":10,"kind":"box"},
                    {"op":"set-prop","id":10,"property":"width","value":100},
                    {"op":"set-prop","id":10,"property":"height","value":80},
                    {"op":"set-prop","id":10,"property":"press-enabled","value":true},
                    {"op":"set-prop","id":10,"property":"pointer-enabled","value":true},
                    {"op":"create-node","id":12,"kind":"text"},
                    {"op":"set-prop","id":12,"property":"text","value":"Replacement source"},
                    {"op":"insert-child","parent":10,"child":12,"index":0},
                    {"op":"insert-child","parent":1,"child":10,"index":0}
                ]),
            ))
            .unwrap();
    });
    renderer.element()
}
fn release_app() -> (Headless, Arc<Mutex<Vec<Event>>>) {
    let events = Arc::new(Mutex::new(Vec::new()));
    let config = EngineConfig {
        context: EngineContext::default().with(ReleaseProbe(events.clone())),
        ..EngineConfig::new(Root::of::<ReleaseEvents>())
    };
    let mut app = Headless::start(config).unwrap();
    app.wait_for("Release source").unwrap();
    (app, events)
}
fn send_release_input(
    app: &mut Headless,
    node: nsh_core::NodeId,
    kind: nsh_core::EventKind,
    payload: nsh_core::EventPayload,
) {
    app.engine().control().dispatch_event(node, kind, payload);
    assert!(app.settle());
}
fn released(events: &Arc<Mutex<Vec<Event>>>) -> Vec<(u64, PointerDetail)> {
    events
        .lock()
        .unwrap()
        .iter()
        .filter_map(|event| {
            if let Event::Pointer {
                node,
                kind: PointerKind::Up,
                detail,
            } = event
            {
                Some((*node, detail.clone()))
            } else {
                None
            }
        })
        .collect()
}

#[test]
fn uncaptured_mouse_up_uses_the_release_owner_and_fresh_metadata_not_deactivation() {
    use nsh_core::{EventKind, EventPayload, MouseEvent};
    let (mut app, events) = release_app();
    let source = node_id(&app, "lui-10");
    let destination = node_id(&app, "lui-20");
    let down = PressEvent {
        page_position: point(px(10.0), px(12.0)),
        modifiers: Modifiers {
            ctrl: true,
            ..Default::default()
        },
        clicks: 1,
        ..Default::default()
    };
    send_release_input(
        &mut app,
        source,
        EventKind::PressDown,
        EventPayload::Press(down),
    );
    send_release_input(
        &mut app,
        source,
        EventKind::PressUp,
        EventPayload::Press(down),
    );
    assert!(
        released(&events).is_empty(),
        "press deactivation is not release"
    );
    send_release_input(
        &mut app,
        destination,
        EventKind::MouseUp,
        EventPayload::Mouse(MouseEvent::released(
            point(px(3.0), px(5.0)),
            point(px(103.0), px(5.0)),
            Modifiers {
                shift: true,
                alt: true,
                ..Default::default()
            },
            MouseButton::Left,
        )),
    );
    let up = released(&events);
    assert_eq!(up.len(), 1);
    assert_eq!(up[0].0, 20);
    assert_eq!(
        (up[0].1.x, up[0].1.y, up[0].1.modifiers, up[0].1.button),
        (103.0, 5.0, 18, 0)
    );
    assert!(
        !events
            .lock()
            .unwrap()
            .iter()
            .any(|event| matches!(event, Event::Press(_) | Event::NativePress(_, _)))
    );
}

#[test]
fn mouse_up_preserves_middle_secondary_and_other_released_buttons_once() {
    use nsh_core::{EventKind, EventPayload, MouseEvent};
    let (mut app, events) = release_app();
    let destination = node_id(&app, "lui-20");
    send_release_input(
        &mut app,
        destination,
        EventKind::MouseUp,
        EventPayload::Mouse(MouseEvent::new(
            point(px(7.0), px(9.0)),
            point(px(107.0), px(9.0)),
            Modifiers::default(),
            None,
        )),
    );
    assert!(
        released(&events).is_empty(),
        "a missing changed button is not a primary release"
    );
    for (button, expected_button, expected_modifiers) in [
        (MouseButton::Middle, 1, 23),
        (MouseButton::Right, 2, 31),
        (MouseButton::Back, 3, 23),
        (MouseButton::Forward, 4, 23),
    ] {
        events.lock().unwrap().clear();
        send_release_input(
            &mut app,
            destination,
            EventKind::MouseUp,
            EventPayload::Mouse(MouseEvent::released(
                point(px(7.0), px(9.0)),
                point(px(107.0), px(9.0)),
                Modifiers {
                    ctrl: true,
                    shift: true,
                    cmd: true,
                    alt: true,
                },
                button,
            )),
        );
        let up = released(&events);
        assert_eq!(up.len(), 1);
        assert_eq!(up[0].0, 20);
        assert_eq!(
            (up[0].1.x, up[0].1.y, up[0].1.modifiers, up[0].1.button),
            (107.0, 9.0, expected_modifiers, expected_button)
        );
    }
}

fn release_touch(
    app: &mut Headless,
    source: nsh_core::NodeId,
    id: u32,
    phase: TouchPhase,
    pointer_type: nsh_core::PointerType,
) {
    use nsh_core::{EventKind, EventPayload, TouchEvent, TouchPoint};
    send_release_input(
        app,
        nsh_core::ROOT_ID,
        EventKind::Touch,
        EventPayload::Touch(Box::new(TouchEvent {
            phase,
            timestamp: 10.0,
            points: vec![TouchPoint {
                id,
                target: source,
                path: if phase == TouchPhase::Start {
                    vec![source]
                } else {
                    vec![]
                },
                page: point(px(31.0), px(47.0)),
                location: point(px(31.0), px(47.0)),
                changed: true,
                pointer_type,
            }],
            activated: None,
        })),
    );
}

#[test]
fn touch_up_requires_its_owned_end_and_never_cancel_deactivation_or_keyboard() {
    use nsh_core::{EventKind, EventPayload, PointerType};
    let (mut app, events) = release_app();
    let source = node_id(&app, "lui-10");
    let down = PressEvent {
        clicks: 1,
        modifiers: Modifiers {
            ctrl: true,
            shift: true,
            cmd: true,
            alt: true,
        },
        ..Default::default()
    };
    release_touch(&mut app, source, 7, TouchPhase::Start, PointerType::Touch);
    send_release_input(
        &mut app,
        source,
        EventKind::PressDown,
        EventPayload::Press(down),
    );
    send_release_input(
        &mut app,
        source,
        EventKind::PressUp,
        EventPayload::Press(down),
    );
    assert!(released(&events).is_empty());
    release_touch(&mut app, source, 8, TouchPhase::End, PointerType::Touch);
    assert!(
        released(&events).is_empty(),
        "a different finger cannot finish the owner"
    );
    release_touch(&mut app, source, 7, TouchPhase::End, PointerType::Touch);
    let up = released(&events);
    assert_eq!(up.len(), 1);
    assert_eq!(
        (up[0].0, up[0].1.x, up[0].1.y, up[0].1.modifiers),
        (10, 31.0, 47.0, 23)
    );
    release_touch(&mut app, source, 7, TouchPhase::End, PointerType::Touch);
    assert_eq!(released(&events).len(), 1, "duplicate End is ignored");
    events.lock().unwrap().clear();
    release_touch(&mut app, source, 9, TouchPhase::Start, PointerType::Touch);
    send_release_input(
        &mut app,
        source,
        EventKind::PressDown,
        EventPayload::Press(down),
    );
    release_touch(&mut app, source, 9, TouchPhase::Cancel, PointerType::Touch);
    release_touch(&mut app, source, 9, TouchPhase::End, PointerType::Touch);
    assert!(
        released(&events).is_empty(),
        "cancel clears the pending touch release"
    );
    send_release_input(&mut app, source, EventKind::PressDown, EventPayload::None);
    send_release_input(&mut app, source, EventKind::PressUp, EventPayload::None);
    assert!(
        released(&events).is_empty(),
        "keyboard-only press phases are not pointer release"
    );
    release_touch(&mut app, source, 10, TouchPhase::Start, PointerType::Mouse);
    send_release_input(
        &mut app,
        source,
        EventKind::PressDown,
        EventPayload::Press(down),
    );
    release_touch(&mut app, source, 10, TouchPhase::End, PointerType::Mouse);
    assert!(
        released(&events).is_empty(),
        "mouse Touch End cannot duplicate MouseUp"
    );
}

fn held_mouse_sample(app: &mut Headless, source: nsh_core::NodeId) {
    use nsh_core::{EventKind, EventPayload, MouseEvent};
    send_release_input(
        app,
        source,
        EventKind::MouseMove,
        EventPayload::Mouse(MouseEvent::new(
            point(px(11.0), px(13.0)),
            point(px(41.0), px(53.0)),
            Modifiers {
                shift: true,
                alt: true,
                ..Default::default()
            },
            Some(MouseButton::Left),
        )),
    );
}
fn cancelled(events: &Arc<Mutex<Vec<Event>>>) -> Vec<(u64, PointerDetail)> {
    events
        .lock()
        .unwrap()
        .iter()
        .filter_map(|event| {
            if let Event::Pointer {
                node,
                kind: PointerKind::Cancel,
                detail,
            } = event
            {
                Some((*node, detail.clone()))
            } else {
                None
            }
        })
        .collect()
}

#[test]
fn mouse_end_without_current_hit_up_cancels_once_with_authentic_detail() {
    use nsh_core::{EventKind, EventPayload, PointerType};
    let (mut app, events) = release_app();
    let source = node_id(&app, "lui-10");
    release_touch(&mut app, source, 40, TouchPhase::Start, PointerType::Mouse);
    held_mouse_sample(&mut app, source);
    // A press deactivated on leaving its retained origin is not a release.
    send_release_input(&mut app, source, EventKind::PressUp, EventPayload::None);
    assert!(cancelled(&events).is_empty());
    release_touch(&mut app, source, 40, TouchPhase::End, PointerType::Mouse);
    let cancel = cancelled(&events);
    assert_eq!(cancel.len(), 1);
    assert_eq!(
        (
            cancel[0].0,
            cancel[0].1.x,
            cancel[0].1.y,
            cancel[0].1.modifiers,
            cancel[0].1.button
        ),
        (10, 41.0, 53.0, 18, 0)
    );
    assert!(
        released(&events).is_empty(),
        "outside End must not fabricate successful Up"
    );
    release_touch(&mut app, source, 40, TouchPhase::End, PointerType::Mouse);
    assert_eq!(cancelled(&events).len(), 1);
    events.lock().unwrap().clear();
    release_touch(&mut app, source, 41, TouchPhase::Start, PointerType::Mouse);
    release_touch(&mut app, source, 41, TouchPhase::End, PointerType::Mouse);
    assert!(
        cancelled(&events).is_empty(),
        "missing authentic metadata must not become a zero-filled sample"
    );
    release_touch(&mut app, source, 42, TouchPhase::Start, PointerType::Mouse);
    held_mouse_sample(&mut app, source);
    release_touch(&mut app, source, 42, TouchPhase::Cancel, PointerType::Mouse);
    release_touch(&mut app, source, 42, TouchPhase::End, PointerType::Mouse);
    assert_eq!(
        cancelled(&events).len(),
        1,
        "a native Cancel consumes the pending End"
    );
}

#[test]
fn accepted_destination_up_prevents_late_origin_cancel_and_preserves_completion() {
    use nsh_core::{EventKind, EventPayload, MouseEvent, PointerType};
    let (mut app, events) = release_app();
    let source = node_id(&app, "lui-10");
    let destination = node_id(&app, "lui-20");
    release_touch(&mut app, source, 50, TouchPhase::Start, PointerType::Mouse);
    held_mouse_sample(&mut app, source);
    send_release_input(
        &mut app,
        destination,
        EventKind::MouseUp,
        EventPayload::Mouse(MouseEvent::released(
            point(px(7.0), px(9.0)),
            point(px(107.0), px(9.0)),
            Modifiers::default(),
            MouseButton::Left,
        )),
    );
    release_touch(&mut app, source, 50, TouchPhase::End, PointerType::Mouse);
    assert_eq!(released(&events).len(), 1);
    assert_eq!(released(&events)[0].0, 20);
    assert!(
        cancelled(&events).is_empty(),
        "a post-commit Cancel would erase application click suppression"
    );
    events.lock().unwrap().clear();
    release_touch(&mut app, source, 51, TouchPhase::Start, PointerType::Mouse);
    held_mouse_sample(&mut app, source);
    send_release_input(
        &mut app,
        destination,
        EventKind::MouseUp,
        EventPayload::Mouse(MouseEvent::released(
            point(px(7.0), px(9.0)),
            point(px(107.0), px(9.0)),
            Modifiers::default(),
            MouseButton::Right,
        )),
    );
    release_touch(&mut app, source, 51, TouchPhase::End, PointerType::Mouse);
    assert_eq!(
        cancelled(&events).len(),
        1,
        "secondary Up cannot complete the primary sequence"
    );
}

#[test]
fn outside_mouse_end_cannot_cancel_a_reused_wire_identity() {
    use nsh_core::PointerType;
    let (mut app, events) = release_app();
    let source = node_id(&app, "lui-10");
    release_touch(&mut app, source, 60, TouchPhase::Start, PointerType::Mouse);
    held_mouse_sample(&mut app, source);
    app.press_key("f9").unwrap();
    app.wait_for("Replacement source").unwrap();
    assert_ne!(node_id(&app, "lui-10"), source);
    events.lock().unwrap().clear();
    release_touch(&mut app, source, 60, TouchPhase::End, PointerType::Mouse);
    assert!(cancelled(&events).is_empty());
    assert!(released(&events).is_empty());
}
