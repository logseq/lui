//! Paired native layout and semantic-controller probes for attached menus.
use super::*;
use nsh_core::{ViewKind, geometry::Bounds};
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use serde_json::json;
use std::sync::Mutex;

struct ContextProbe {
    attached: bool,
    profile: usize,
    events: Arc<Mutex<Vec<Event>>>,
    reference: Arc<Mutex<Option<nsh_core::NodeId>>>,
}

fn patch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}

fn publish(renderer: &Renderer, ops: Value) {
    let generation = renderer.0.borrow().store.generation + 1;
    renderer.apply(patch(generation, ops)).unwrap();
}

#[component]
fn ContextScenario() -> impl IntoElement {
    let probe = engine_context::<ContextProbe>().unwrap();
    let observed = probe.events.clone();
    let reference = probe.reference.clone();
    let renderer = Renderer::new(move |event, renderer| {
        if event == Event::Press(10) {
            *reference.lock().unwrap() = renderer.0.borrow().nodes[&10].reference.node();
        }
        observed.lock().unwrap().push(event.clone());
        if let Event::Text(id, value) = event {
            publish(
                &renderer,
                json!([
                    {"op":"set-prop","id":id,"property":"text","value":value}
                ]),
            );
        }
    });
    let mut ops = json!([
        {"op":"create-node","id":1,"kind":"column"},
        {"op":"set-prop","id":1,"property":"width","value":400},
        {"op":"set-prop","id":1,"property":"gap","value":8},
        {"op":"set-prop","id":1,"property":"padding","value":7},
        {"op":"create-node","id":2,"kind":"row"},
        {"op":"set-prop","id":2,"property":"width","value":360},
        {"op":"set-prop","id":2,"property":"height","value":96},
        {"op":"set-prop","id":2,"property":"gap","value":8},
        {"op":"set-prop","id":2,"property":"cross","value":if probe.profile==4 {"stretch"} else {"center"}},
        {"op":"create-node","id":10,"kind":if probe.profile==3 {"list-item"} else {"button"}},
        {"op":"set-prop","id":10,"property":"accessibility-label","value":"Context trigger"},
        {"op":"set-prop","id":10,"property":"press-enabled","value":true},
        {"op":"set-prop","id":10,"property":"margin-horizontal","value":3},
        {"op":"create-node","id":20,"kind":"box"},
        {"op":"set-prop","id":20,"property":"width","value":32},
        {"op":"set-prop","id":20,"property":"height","value":28},
        {"op":"create-node","id":30,"kind":"text-field"},
        {"op":"set-prop","id":30,"property":"text","value":"draft"},
        {"op":"set-prop","id":30,"property":"change-enabled","value":true},
        {"op":"create-node","id":40,"kind":"context-menu"},
        {"op":"create-node","id":41,"kind":"menu-item"},
        {"op":"set-prop","id":41,"property":"text","value":"Blocked"},
        {"op":"set-prop","id":41,"property":"enabled","value":false},
        {"op":"set-prop","id":41,"property":"press-enabled","value":true},
        {"op":"create-node","id":42,"kind":"menu-item"},
        {"op":"set-prop","id":42,"property":"text","value":"First"},
        {"op":"set-prop","id":42,"property":"press-enabled","value":true},
        {"op":"create-node","id":43,"kind":"divider"},
        {"op":"insert-child","parent":40,"child":41,"index":0},
        {"op":"insert-child","parent":40,"child":42,"index":1},
        {"op":"insert-child","parent":40,"child":43,"index":2},
        {"op":"insert-child","parent":2,"child":10,"index":0},
        {"op":"insert-child","parent":2,"child":20,"index":1},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":30,"index":1}
    ]).as_array().unwrap().clone();
    let properties = match probe.profile {
        0 => json!({"size":"icon","variant":"ghost","icon":"x","width":22,"height":24}),
        1 => json!({"text":"Switch graph","grow":1.0,"min-height":44,"text-alignment":"start"}),
        2 => {
            json!({"text":"Delete local graph","height":22,"padding-vertical":0,"variant":"ghost","foreground":"#123456","hover-foreground":"#654321"})
        }
        3 => json!({"grow":1.0,"min-height":44,"padding-horizontal":5,"padding-vertical":2}),
        5 => json!({"size":"icon","variant":"ghost","icon":"x"}),
        6 => json!({"size":"sm","text":"Small action"}),
        7 => json!({"size":"lg","text":"Large action"}),
        _ => json!({"text":"Stretched action","grow":1.0}),
    };
    ops.extend(
        properties
            .as_object()
            .unwrap()
            .iter()
            .map(|(property, value)| {
                json!({
                    "op":"set-prop","id":10,"property":property,"value":value
                })
            }),
    );
    if probe.profile == 3 {
        ops.extend(
            json!([
                {"op":"create-node","id":11,"kind":"column"},
                {"op":"set-prop","id":11,"property":"gap","value":4},
                {"op":"create-node","id":12,"kind":"text"},
                {"op":"set-prop","id":12,"property":"text","value":"Graph 中文"},
                {"op":"create-node","id":13,"kind":"text"},
                {"op":"set-prop","id":13,"property":"text","value":"Preparing"},
                {"op":"insert-child","parent":11,"child":12,"index":0},
                {"op":"insert-child","parent":11,"child":13,"index":1},
                {"op":"insert-child","parent":10,"child":11,"index":0}
            ])
            .as_array()
            .unwrap()
            .iter()
            .cloned(),
        );
    }
    if probe.attached {
        ops.push(json!({"op":"insert-child","parent":10,"child":40,"index":if probe.profile==3 {1} else {0}}));
    }
    renderer.apply(patch(1, Value::Array(ops))).unwrap();
    renderer.set_root(1).unwrap();
    let update = renderer.clone();
    on_key_with(
        "f5",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            publish(
                &update,
                json!([
                    {"op":"set-prop","id":42,"property":"text","value":"Renamed"},
                    {"op":"create-node","id":46,"kind":"menu-item"},
                    {"op":"set-prop","id":46,"property":"text","value":"Added"},
                    {"op":"set-prop","id":46,"property":"press-enabled","value":true},
                    {"op":"insert-child","parent":40,"child":46,"index":3}
                ]),
            );
        },
    );
    let reject = renderer.clone();
    let attached = probe.attached;
    on_key_with(
        "f7",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            let generation = reject.0.borrow().store.generation;
            let trigger = reject.0.borrow().nodes[&10].node.get_untracked();
            let editor = reject.0.borrow().nodes[&30].node.get_untracked();
            let mut ops =
                vec![json!({"op":"set-prop","id":30,"property":"text","value":"must not publish"})];
            if attached {
                ops.push(json!({"op":"remove-child","parent":10,"child":40}));
            } else {
                ops.push(json!({"op":"insert-child","parent":10,"child":40,"index":0}));
            }
            let error = reject
                .apply(patch(generation + 1, Value::Array(ops)))
                .unwrap_err();
            assert!(error.contains("context-menu attachment mode"));
            assert!(error.contains("node=10, kind=button"));
            assert!(error.contains(&format!("previous_attached={attached}")));
            assert!(error.contains(&format!("next_attached={}", !attached)));
            assert!(error.contains(&format!("previous_declared={attached}")));
            assert!(error.contains("native_ref_bound=true"));
            assert_eq!(reject.0.borrow().store.generation, generation);
            assert!(Arc::ptr_eq(
                &trigger,
                &reject.0.borrow().nodes[&10].node.get_untracked()
            ));
            assert!(Arc::ptr_eq(
                &editor,
                &reject.0.borrow().nodes[&30].node.get_untracked()
            ));
        },
    );
    renderer.element()
}

struct Started {
    app: Headless,
    events: Arc<Mutex<Vec<Event>>>,
    reference: Arc<Mutex<Option<nsh_core::NodeId>>>,
}
fn start(profile: usize, attached: bool) -> Started {
    let events = Arc::new(Mutex::new(Vec::new()));
    let reference = Arc::new(Mutex::new(None));
    let mut config = EngineConfig {
        context: EngineContext::default().with(ContextProbe {
            attached,
            profile,
            events: events.clone(),
            reference: reference.clone(),
        }),
        ..EngineConfig::new(Root::of::<ContextScenario>())
    };
    config.environment.os = nsh_core::platform::Os::Linux;
    config.environment.reduce_motion = true;
    let mut app = Headless::start(config).unwrap();
    app.wait_for("id:lui-10").unwrap();
    Started {
        app,
        events,
        reference,
    }
}
fn identity(app: &Headless, id: u64) -> nsh_core::NodeId {
    let id = format!("lui-{id}");
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some(id.as_str()))
        .unwrap()
        .id
}
fn bounds(app: &Headless, id: u64) -> Bounds<Points> {
    let id = identity(app, id);
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.id == id)
        .unwrap()
        .bounds
}
fn closed(app: &mut Headless) {
    app.wait_until(
        "context menu closed",
        std::time::Duration::from_secs(1),
        |screen| {
            screen.count("role:menuitem[First]") == Ok(0)
                && screen.count("role:menuitem[Renamed]") == Ok(0)
        },
    )
    .unwrap();
}

#[test]
fn attached_context_layout_matches_plain_size_grow_margins_intrinsics_and_stretch() {
    for profile in 0..8 {
        let mut plain = start(profile, false);
        let mut attached = start(profile, true);
        for id in [2, 10, 20, 30] {
            assert_eq!(
                bounds(&attached.app, id),
                bounds(&plain.app, id),
                "profile {profile}, node {id}"
            );
        }
        if profile == 2 {
            let original = plain
                .app
                .screen()
                .span_style("text:Delete local graph")
                .unwrap()
                .color;
            assert_eq!(
                attached
                    .app
                    .screen()
                    .span_style("text:Delete local graph")
                    .unwrap()
                    .color,
                original
            );
            plain.app.hover("id:lui-10").unwrap();
            attached.app.hover("id:lui-10").unwrap();
            let hovered = plain
                .app
                .screen()
                .span_style("text:Delete local graph")
                .unwrap()
                .color;
            assert_ne!(
                hovered, original,
                "the authored native hover foreground applies"
            );
            assert_eq!(
                attached
                    .app
                    .screen()
                    .span_style("text:Delete local graph")
                    .unwrap()
                    .color,
                hovered
            );
        }
        if profile == 3 {
            for id in [11, 12, 13] {
                assert_eq!(bounds(&attached.app, id), bounds(&plain.app, id));
            }
        }
        let trigger = identity(&attached.app, 10);
        let nodes = attached.app.screen().layout_nodes();
        let host = nodes.iter().find(|node| node.id == trigger).unwrap();
        let outer = nodes.iter().find(|node| node.id == host.parent).unwrap();
        assert_eq!(
            outer.bounds, host.bounds,
            "native trigger fills its layout participant"
        );
        attached.app.press("id:lui-10").unwrap();
        assert_eq!(
            *attached.reference.lock().unwrap(),
            Some(trigger),
            "the public slot preserves the canonical native ref"
        );
        if matches!(profile, 0 | 5) {
            let svg = nodes
                .iter()
                .find(|node| node.kind == ViewKind::Canvas)
                .unwrap();
            assert_eq!(
                svg.bounds.origin.x + svg.bounds.size.width / 2.0,
                host.bounds.origin.x + host.bounds.size.width / 2.0
            );
            assert_eq!(
                svg.bounds.origin.y + svg.bounds.size.height / 2.0,
                host.bounds.origin.y + host.bounds.size.height / 2.0
            );
        }
    }
}

#[test]
fn native_context_menu_owns_secondary_keyboard_disabled_items_and_repeated_actions() {
    let mut started = start(3, true);
    let trigger = identity(&started.app, 10);
    let editor = identity(&started.app, 30);
    started.app.type_text("id:lui-30", " retained").unwrap();
    started.app.press("id:lui-10").unwrap();
    started.app.right_click("id:lui-10").unwrap();
    started.app.wait_for("role:menuitem[First]").unwrap();
    assert!(started.app.press("role:menuitem[Blocked]").is_err());
    // Pointer opening keeps the trigger's focus. Hover uses the native
    // menu's pointer-focus path; keyboard opening below skips the disabled row.
    started.app.hover("role:menuitem[First]").unwrap();
    started.app.press_key("enter").unwrap();
    closed(&mut started.app);
    started.app.press_key("shift+f10").unwrap();
    started.app.wait_for("role:menuitem[First]").unwrap();
    started.app.press_key("enter").unwrap();
    closed(&mut started.app);
    let observed = started.events.lock().unwrap();
    assert_eq!(
        observed
            .iter()
            .filter(|event| **event == Event::Press(42))
            .count(),
        2
    );
    assert_eq!(
        observed
            .iter()
            .filter(|event| **event == Event::Press(10))
            .count(),
        1,
        "secondary/keyboard menu opening must not activate its button"
    );
    assert!(!observed.contains(&Event::Press(41)));
    drop(observed);
    assert_eq!(identity(&started.app, 10), trigger);
    assert_eq!(identity(&started.app, 30), editor);
    assert_eq!(
        started.app.screen().input_text("id:lui-30").unwrap(),
        Some("draft retained")
    );
}

#[test]
fn context_menu_item_updates_preserve_native_item_identity_and_the_surrounding_editor() {
    let mut started = start(3, true);
    let editor = identity(&started.app, 30);
    started.app.type_text("id:lui-30", " retained").unwrap();
    started.app.right_click("id:lui-10").unwrap();
    started.app.wait_for("role:menuitem[First]").unwrap();
    let first = identity(&started.app, 42);
    started.app.press_key("f5").unwrap();
    started.app.wait_for("role:menuitem[Renamed]").unwrap();
    started.app.wait_for("role:menuitem[Added]").unwrap();
    assert_eq!(identity(&started.app, 42), first);
    started.app.press("role:menuitem[Added]").unwrap();
    closed(&mut started.app);
    assert_eq!(
        started
            .events
            .lock()
            .unwrap()
            .iter()
            .filter(|event| **event == Event::Press(46))
            .count(),
        1
    );
    assert_eq!(identity(&started.app, 30), editor);
    assert_eq!(
        started.app.screen().input_text("id:lui-30").unwrap(),
        Some("draft retained")
    );
}

#[test]
fn context_attachment_changes_roll_back_before_replacing_a_live_trigger_or_editor() {
    for attached in [false, true] {
        let mut started = start(1, attached);
        let trigger = identity(&started.app, 10);
        let editor = identity(&started.app, 30);
        started.app.type_text("id:lui-30", " retained").unwrap();
        started.app.press_key("f7").unwrap();
        assert_eq!(identity(&started.app, 10), trigger);
        assert_eq!(identity(&started.app, 30), editor);
        assert_eq!(
            started.app.screen().input_text("id:lui-30").unwrap(),
            Some("draft retained")
        );
        if attached {
            started.app.press("id:lui-10").unwrap();
            started.app.wait_for("role:menuitem[First]").unwrap();
            started.app.press_key("escape").unwrap();
            closed(&mut started.app);
            assert!(started.events.lock().unwrap().contains(&Event::Dismiss(40)));
        } else {
            started.app.right_click("id:lui-10").unwrap();
            assert_eq!(
                started.app.screen().count("role:menuitem[First]").unwrap(),
                0
            );
        }
    }
}

#[test]
fn button_context_attachment_is_a_native_primary_menu_with_keyboard_reopening() {
    let mut started = start(1, true);
    let trigger = identity(&started.app, 10);
    started.app.press("id:lui-10").unwrap();
    started.app.wait_for("role:menuitem[First]").unwrap();
    started.app.press_key("down").unwrap();
    started.app.press_key("enter").unwrap();
    closed(&mut started.app);
    started.app.press_key("down").unwrap();
    started.app.wait_for("role:menuitem[First]").unwrap();
    started.app.press_key("enter").unwrap();
    closed(&mut started.app);
    assert_eq!(identity(&started.app, 10), trigger);
    assert_eq!(*started.reference.lock().unwrap(), Some(trigger));
    assert_eq!(
        started
            .events
            .lock()
            .unwrap()
            .iter()
            .filter(|event| **event == Event::Press(42))
            .count(),
        2
    );
}
