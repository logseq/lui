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
            assert!(result.unwrap_err().contains("uninstalled native event"));
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
