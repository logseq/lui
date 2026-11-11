//! Public focus/ref/key lifetimes over real native Input hosts.
use super::*;
use crate::{render::Renderer, wire::Batch};
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use serde_json::{Value, json};
use std::sync::Mutex;

struct Fixture {
    kind: &'static str,
    first_navigation: Option<bool>,
    events: Arc<Mutex<Vec<Event>>>,
    fallback: Arc<Mutex<usize>>,
    rejection: Arc<Mutex<Option<String>>>,
}
fn batch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}
fn apply(renderer: &Renderer, generation: &Cell<u64>, ops: Value) {
    let next = generation.get() + 1;
    renderer.apply(batch(next, ops)).unwrap();
    generation.set(next);
}
fn first_ops(kind: &str, navigation: Option<bool>) -> Vec<Value> {
    let mut ops = vec![
        json!({"op":"create-node","id":2,"kind":kind}),
        json!({"op":"set-prop","id":2,"property":"text","value":"first"}),
        json!({"op":"set-prop","id":2,"property":"change-enabled","value":true}),
        json!({"op":"set-prop","id":2,"property":"submit-enabled","value":true}),
        json!({"op":"set-prop","id":2,"property":"submit-on-blur","value":true}),
        json!({"op":"insert-child","parent":1,"child":2,"index":0}),
    ];
    if let Some(value) = navigation {
        ops.push(json!({"op":"set-prop","id":2,"property":"navigate-enabled","value":value}));
    }
    ops
}
#[component]
fn NavigationProbe() -> impl IntoElement {
    let fixture = engine_context::<Fixture>().unwrap();
    let fallback = fixture.fallback.clone();
    // A real application shortcut wins only after this editor removes its own
    // keys. Returning early inside a permanently installed handler would fail.
    on_key_with(
        "up",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| *fallback.lock().unwrap() += 1,
    );
    let generation = Rc::new(Cell::new(0));
    let updating = generation.clone();
    let observed = fixture.events.clone();
    let renderer = Renderer::new(move |event, renderer| {
        observed.lock().unwrap().push(event.clone());
        if let Event::Text(id, text) = event {
            apply(
                &renderer,
                &updating,
                json!([{"op":"set-prop","id":id,"property":"text","value":text}]),
            );
        }
    });
    let mut ops = vec![json!({"op":"create-node","id":1,"kind":"column"})];
    ops.extend(first_ops(fixture.kind, fixture.first_navigation));
    ops.extend([
        json!({"op":"create-node","id":3,"kind":"text-field"}),
        json!({"op":"set-prop","id":3,"property":"text","value":"second"}),
        json!({"op":"set-prop","id":3,"property":"navigate-enabled","value":true}),
        json!({"op":"insert-child","parent":1,"child":3,"index":1}),
        json!({"op":"create-node","id":4,"kind":"text-field"}),
        json!({"op":"set-prop","id":4,"property":"text","value":"plain"}),
        json!({"op":"insert-child","parent":1,"child":4,"index":2}),
    ]);
    apply(&renderer, &generation, json!(ops));
    renderer.set_root(1).unwrap();
    for (key, ops) in [
        (
            "f2",
            json!([{"op":"set-prop","id":2,"property":"navigate-enabled","value":false}]),
        ),
        (
            "f3",
            json!([{"op":"set-prop","id":2,"property":"navigate-enabled","value":true}]),
        ),
        (
            "f4",
            json!([{"op":"set-prop","id":2,"property":"enabled","value":false}]),
        ),
        (
            "f5",
            json!([{"op":"set-prop","id":2,"property":"enabled","value":true}]),
        ),
        (
            "f6",
            json!([{"op":"move-child","parent":1,"child":3,"index":0}]),
        ),
        ("f7", json!([{"op":"drop-node","id":2}])),
    ] {
        let renderer = renderer.clone();
        let generation = generation.clone();
        on_key_with(
            key,
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| apply(&renderer, &generation, ops.clone()),
        );
    }
    let remounting = renderer.clone();
    let mounting = generation.clone();
    let kind = fixture.kind;
    on_key_with(
        "f8",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            let mut ops = vec![json!({"op":"drop-node","id":2})];
            ops.extend(first_ops(kind, Some(true)));
            apply(&remounting, &mounting, json!(ops));
        },
    );
    let rejecting = renderer.clone();
    let rejection = fixture.rejection.clone();
    on_key_with(
        "f10",
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
                        {"op":"set-prop","id":2,"property":"text","value":"must not publish"},
                        {"op":"set-prop","id":2,"property":"navigate-enabled","value":true}
                    ]),
                ))
                .unwrap_err();
            *rejection.lock().unwrap() = Some(error);
            apply(
                &rejecting,
                &generation,
                json!([{"op":"set-prop","id":2,"property":"navigate-enabled","value":false}]),
            );
        },
    );
    renderer.element()
}
struct Started {
    app: Headless,
    events: Arc<Mutex<Vec<Event>>>,
    fallback: Arc<Mutex<usize>>,
    rejection: Arc<Mutex<Option<String>>>,
}
fn start(kind: &'static str, first_navigation: Option<bool>) -> Started {
    let events = Arc::new(Mutex::new(Vec::new()));
    let fallback = Arc::new(Mutex::new(0));
    let rejection = Arc::new(Mutex::new(None));
    let mut config = EngineConfig {
        context: EngineContext::default().with(Fixture {
            kind,
            first_navigation,
            events: events.clone(),
            fallback: fallback.clone(),
            rejection: rejection.clone(),
        }),
        ..EngineConfig::new(Root::of::<NavigationProbe>())
    };
    config.environment.os = nsh_core::platform::Os::MacOs;
    let mut app = Headless::start(config).unwrap();
    app.wait_for("id:lui-2").unwrap();
    Started {
        app,
        events,
        fallback,
        rejection,
    }
}
fn navigation(events: &Mutex<Vec<Event>>) -> Vec<Event> {
    events
        .lock()
        .unwrap()
        .iter()
        .filter(|event| matches!(event, Event::NavigatePrevious(_) | Event::NavigateNext(_)))
        .cloned()
        .collect()
}
fn identity(app: &Headless, name: &str) -> nsh_core::NodeId {
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some(name))
        .unwrap()
        .id
}

#[test]
fn each_input_kind_projects_only_the_focused_editors_unmodified_arrows() {
    for kind in [
        "input",
        "text-field",
        "secure-field",
        "search-field",
        "textarea",
    ] {
        let mut t = start(kind, Some(true));
        let native = identity(&t.app, "lui-2");
        t.app.type_text("id:lui-2", "x").unwrap();
        t.app.press_key("up").unwrap();
        t.app.press_key("down").unwrap();
        assert_eq!(
            navigation(&t.events),
            [Event::NavigatePrevious(2), Event::NavigateNext(2)],
            "{kind}"
        );
        for key in ["shift+up", "alt+up", "ctrl+up", "meta+up"] {
            t.app.press_key(key).unwrap();
        }
        assert_eq!(
            navigation(&t.events).len(),
            2,
            "modified keys remain native"
        );
        assert_eq!(*t.fallback.lock().unwrap(), 0);
        t.app.type_text("id:lui-3", "").unwrap();
        t.app.press_key("up").unwrap();
        assert_eq!(
            navigation(&t.events).last(),
            Some(&Event::NavigatePrevious(3))
        );
        t.app.type_text("id:lui-4", "").unwrap();
        t.app.press_key("up").unwrap();
        assert_eq!(
            *t.fallback.lock().unwrap(),
            1,
            "plain Input must not be shadowed by another field's key binding"
        );
        assert_eq!(identity(&t.app, "lui-2"), native);
    }
}

#[test]
fn initially_false_and_live_disabled_flags_remove_the_actual_bindings() {
    let mut t = start("text-field", Some(false));
    let native = identity(&t.app, "lui-2");
    t.app.type_text("id:lui-2", "").unwrap();
    t.app.press_key("up").unwrap();
    assert!(navigation(&t.events).is_empty());
    assert_eq!(*t.fallback.lock().unwrap(), 1);
    t.app.press_key("f3").unwrap();
    t.app.press_key("up").unwrap();
    assert_eq!(navigation(&t.events), [Event::NavigatePrevious(2)]);
    t.app.press_key("f2").unwrap();
    t.app.press_key("up").unwrap();
    assert_eq!(*t.fallback.lock().unwrap(), 2);
    t.app.press_key("f3").unwrap();
    t.app.press_key("f4").unwrap();
    t.app.press_key("up").unwrap();
    assert_eq!(navigation(&t.events).len(), 1);
    assert_eq!(*t.fallback.lock().unwrap(), 3);
    t.app.press_key("f5").unwrap();
    t.app.type_text("id:lui-2", "").unwrap();
    t.app.press_key("down").unwrap();
    assert_eq!(navigation(&t.events).last(), Some(&Event::NavigateNext(2)));
    assert_eq!(identity(&t.app, "lui-2"), native);
}

#[test]
fn composition_removes_navigation_and_shares_the_single_blur_composition_hook() {
    let mut t = start("text-field", Some(true));
    let native = identity(&t.app, "lui-2");
    t.app.compose("id:lui-2", "zhong").unwrap();
    t.app.press_key("up").unwrap();
    assert!(navigation(&t.events).is_empty());
    assert_eq!(*t.fallback.lock().unwrap(), 1);
    t.app.type_text("id:lui-4", "").unwrap();
    assert!(
        !t.events.lock().unwrap().contains(&Event::Submit(2)),
        "marked text is not prematurely submitted"
    );
    t.app.compose("id:lui-2", "").unwrap();
    t.app.type_text("id:lui-2", "中").unwrap();
    t.app.press_key("down").unwrap();
    t.app.type_text("id:lui-4", "").unwrap();
    let events = t.events.lock().unwrap();
    let edit = events
        .iter()
        .rposition(|event| matches!(event,Event::Text(2,text) if text=="first中"))
        .unwrap();
    let submitted = events
        .iter()
        .rposition(|event| *event == Event::Submit(2))
        .unwrap();
    assert!(edit < submitted);
    drop(events);
    assert_eq!(navigation(&t.events), [Event::NavigateNext(2)]);
    assert_eq!(identity(&t.app, "lui-2"), native);
}

#[test]
fn focused_reorder_retains_the_editor_and_removal_releases_its_keys() {
    let mut t = start("input", Some(true));
    let first = identity(&t.app, "lui-2");
    let second = identity(&t.app, "lui-3");
    t.app.type_text("id:lui-2", "x").unwrap();
    t.app.press_key("f6").unwrap();
    t.app.press_key("down").unwrap();
    assert_eq!(navigation(&t.events), [Event::NavigateNext(2)]);
    t.app.press_key("z").unwrap();
    assert_eq!(
        t.app.screen().input_text("id:lui-2").unwrap(),
        Some("firstxz")
    );
    assert_eq!(identity(&t.app, "lui-2"), first);
    assert_eq!(identity(&t.app, "lui-3"), second);
    t.app.press_key("f7").unwrap();
    t.app.press_key("up").unwrap();
    assert_eq!(navigation(&t.events).len(), 1);
    assert_eq!(*t.fallback.lock().unwrap(), 1);
}

#[test]
fn absent_false_true_cannot_bypass_installed_capacity_and_remount_restores_navigation() {
    let mut t = start("input", None);
    let native = identity(&t.app, "lui-2");
    t.app.type_text("id:lui-2", "x").unwrap();
    t.app.press_key("f2").unwrap();
    t.app.press_key("f10").unwrap();
    assert!(
        t.rejection
            .lock()
            .unwrap()
            .as_ref()
            .unwrap()
            .contains("uninstalled native event capability")
    );
    assert_eq!(
        t.app.screen().input_text("id:lui-2").unwrap(),
        Some("firstx")
    );
    assert_eq!(identity(&t.app, "lui-2"), native);
    t.app.press_key("up").unwrap();
    assert!(navigation(&t.events).is_empty());
    t.app.press_key("f8").unwrap();
    t.app.wait_for("id:lui-2").unwrap();
    assert_ne!(identity(&t.app, "lui-2"), native);
    t.app.type_text("id:lui-2", "").unwrap();
    t.app.press_key("up").unwrap();
    assert_eq!(navigation(&t.events), [Event::NavigatePrevious(2)]);
}
