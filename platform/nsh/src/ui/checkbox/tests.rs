//! Actual native parts and unchanged controlled Checkbox semantics.
use super::*;
use crate::{
    render::{Event, Renderer},
    wire::Batch,
};
use nsh_core::{Color, EventKind, EventPayload, MountBatch, MountItem, NodeId, ViewStyle};
use nsh_engine::{Engine, EngineConfig, EngineContext, MountSink, Root};
use nsh_testing::Headless;
use serde_json::{Value, json};
use std::{
    cell::Cell,
    collections::HashMap,
    rc::Rc,
    sync::{Condvar, Mutex},
    time::Duration,
};

#[derive(Default)]
struct Trace {
    ids: HashMap<String, NodeId>,
    labels: HashMap<String, NodeId>,
    parents: HashMap<NodeId, NodeId>,
    styles: HashMap<NodeId, ViewStyle>,
    errors: Vec<String>,
}
type SharedTrace = Arc<(Mutex<Trace>, Condvar)>;
struct Sink(SharedTrace);
impl MountSink for Sink {
    fn submit(&self, batch: MountBatch) {
        let mut trace = self.0.0.lock().unwrap();
        for item in batch.items {
            match item {
                MountItem::ViewProps { id, props } => {
                    if let Some(name) = props.test_id {
                        trace.ids.insert(name.to_string(), id);
                    }
                }
                MountItem::ViewStyle { id, style } => {
                    trace.styles.insert(id, *style);
                }
                MountItem::Text { id, text, .. } => {
                    trace.labels.insert(text.text.clone(), id);
                }
                MountItem::Insert { parent, child, .. } => {
                    trace.parents.insert(child, parent);
                    // The mount protocol omits an unchanged default ViewStyle.
                    trace.styles.entry(child).or_default();
                }
                MountItem::Delete { id } => {
                    trace.styles.remove(&id);
                    trace.parents.remove(&id);
                }
                _ => {}
            }
        }
        self.0.1.notify_all();
    }
    fn report_error(&self, message: &str) {
        self.0.0.lock().unwrap().errors.push(message.into());
        self.0.1.notify_all();
    }
}
fn indicator(trace: &Trace, root: &str) -> Option<NodeId> {
    let root = *trace.ids.get(root)?;
    trace.parents.iter().find_map(|(child, parent)| {
        (*parent == root
            && trace
                .styles
                .get(child)
                .is_some_and(|style| style.borders.widths.top == px(1.0)))
        .then_some(*child)
    })
}
fn wait(trace: &SharedTrace, ready: impl Fn(&Trace) -> bool) {
    let state = trace.0.lock().unwrap();
    let (state, timeout) = trace
        .1
        .wait_timeout_while(state, Duration::from_secs(5), |state| {
            state.errors.is_empty() && !ready(state)
        })
        .unwrap();
    assert!(state.errors.is_empty(), "{:?}", state.errors);
    assert!(
        !timeout.timed_out() || ready(&state),
        "native Checkbox part update did not arrive"
    );
}
#[component]
fn PartsProbe() -> impl IntoElement {
    let node=signal(Arc::new(Node {id:1,kind:"checkbox".into(),props:serde_json::from_value(json!({"text":"Owned label","indicator-border-color":"#ff0000","checked-indicator-border-color":"#00ff00","label-opacity":0.4})).unwrap(),..Default::default()}));
    let reference = signal(Arc::new(Node {
        id: 2,
        kind: "checkbox".into(),
        props: serde_json::from_value(json!({"text":"Reference label"})).unwrap(),
        ..Default::default()
    }));
    let theme = signal(Arc::new(ThemeView::new(tokens(), dark(), reduce_motion())));
    let make = move |node: Signal<Arc<Node>>| {
        element(
            nsh_base::CheckboxProps {
                checked: Prop::bind(move || node.get().boolean("checked", false)),
                ..Default::default()
            },
            theme,
            node,
        )
    };
    view()
        .child(make(node).test_id("parts-checkbox"))
        .child(make(reference).test_id("reference-checkbox"))
        .child(
            nsh_base::Button::element(Default::default())
                .test_id("check")
                .child(text("Check"))
                .on_event(move |event: &nsh_base::ButtonEvent| {
                    if *event != nsh_base::ButtonEvent::Press {
                        return;
                    }
                    node.update(|node| {
                        Arc::make_mut(node)
                            .props
                            .insert("checked".into(), json!(true));
                        Arc::make_mut(node)
                            .props
                            .insert("label-opacity".into(), json!(0.8));
                    })
                }),
        )
        .child(
            nsh_base::Button::element(Default::default())
                .test_id("recolor")
                .child(text("Recolor"))
                .on_event(move |event: &nsh_base::ButtonEvent| {
                    if *event != nsh_base::ButtonEvent::Press {
                        return;
                    }
                    node.update(|node| {
                        Arc::make_mut(node)
                            .props
                            .insert("checked-indicator-border-color".into(), json!("#0000ff"));
                    })
                }),
        )
        .child(
            nsh_base::Button::element(Default::default())
                .test_id("reset")
                .child(text("Reset"))
                .on_event(move |event: &nsh_base::ButtonEvent| {
                    if *event != nsh_base::ButtonEvent::Press {
                        return;
                    }
                    node.update(|node| {
                        let node = Arc::make_mut(node);
                        node.props.remove("indicator-border-color");
                        node.props.remove("checked-indicator-border-color");
                        node.props.remove("label-opacity");
                        node.props.insert("checked".into(), json!(false));
                    })
                }),
        )
}
#[test]
fn authored_paint_reaches_the_native_indicator_and_label_and_updates_without_remounting() {
    let trace = SharedTrace::default();
    let engine = Engine::start(
        EngineConfig {
            viewport: Size::new(px(500.0), px(400.0)),
            ..EngineConfig::new(Root::of::<PartsProbe>())
        },
        || nsh_core::ApproxTextEngine,
        Sink(trace.clone()),
    )
    .unwrap();
    wait(&trace, |t| {
        indicator(t, "parts-checkbox").is_some()
            && indicator(t, "reference-checkbox").is_some()
            && t.labels
                .get("Owned label")
                .is_some_and(|id| t.styles.get(id).is_some_and(|style| style.opacity == 0.4))
            && t.ids.contains_key("reset")
    });
    let (root, part, label, check, recolor, reset) = {
        let t = trace.0.lock().unwrap();
        let part = indicator(&t, "parts-checkbox").unwrap();
        assert_eq!(
            t.styles[&part].borders.colors,
            [Color::parse("#ff0000").unwrap(); 4]
        );
        (
            t.ids["parts-checkbox"],
            part,
            t.labels["Owned label"],
            t.ids["check"],
            t.ids["recolor"],
            t.ids["reset"],
        )
    };
    engine
        .control()
        .dispatch_event(check, EventKind::Press, EventPayload::None);
    wait(&trace, |t| {
        t.styles
            .get(&part)
            .is_some_and(|style| style.borders.colors == [Color::parse("#00ff00").unwrap(); 4])
            && t.styles
                .get(&label)
                .is_some_and(|style| style.opacity == 0.8)
    });
    engine
        .control()
        .dispatch_event(recolor, EventKind::Press, EventPayload::None);
    wait(&trace, |t| {
        t.styles
            .get(&part)
            .is_some_and(|style| style.borders.colors == [Color::parse("#0000ff").unwrap(); 4])
    });
    engine
        .control()
        .dispatch_event(reset, EventKind::Press, EventPayload::None);
    wait(&trace, |t| {
        indicator(t, "reference-checkbox")
            .and_then(|reference| t.styles.get(&part).zip(t.styles.get(&reference)))
            .is_some_and(|(part, reference)| part.borders.colors == reference.borders.colors)
            && t.styles
                .get(&label)
                .is_some_and(|style| style.opacity == 1.0)
    });
    let t = trace.0.lock().unwrap();
    assert_eq!(t.ids["parts-checkbox"], root);
    assert_eq!(indicator(&t, "parts-checkbox"), Some(part));
    assert_eq!(t.labels["Owned label"], label);
    assert_eq!(
        t.styles[&root].opacity, 1.0,
        "label opacity must not dim the root or indicator"
    );
    assert_eq!(t.styles[&part].opacity, 1.0);
}

struct Fixture {
    kind: &'static str,
    events: Arc<Mutex<Vec<Event>>>,
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
#[component]
fn ControlledProbe() -> impl IntoElement {
    let fixture = engine_context::<Fixture>().unwrap();
    let observed = fixture.events.clone();
    let renderer = Renderer::new(move |event, _| observed.lock().unwrap().push(event));
    let generation = Rc::new(Cell::new(0));
    apply(
        &renderer,
        &generation,
        json!([
            {"op":"create-node","id":1,"kind":"column"},
            {"op":"create-node","id":2,"kind":fixture.kind},
            {"op":"set-prop","id":2,"property":"text","value":"Choose rows"},
            {"op":"set-prop","id":2,"property":"accessibility-label","value":"Choose rows"},
            {"op":"set-prop","id":2,"property":"toggle-enabled","value":true},
            {"op":"set-prop","id":2,"property":"indicator-border-color","value":"#ff0000"},
            {"op":"set-prop","id":2,"property":"checked-indicator-border-color","value":"#00ff00"},
            {"op":"set-prop","id":2,"property":"label-opacity","value":0.4},
            {"op":"insert-child","parent":1,"child":2,"index":0},
            {"op":"create-node","id":3,"kind":"text-field"},
            {"op":"set-prop","id":3,"property":"text","value":"draft"},
            {"op":"insert-child","parent":1,"child":3,"index":1}
        ]),
    );
    renderer.set_root(1).unwrap();
    for (key, ops) in [
        (
            "f2",
            json!([{"op":"set-prop","id":2,"property":"checked","value":true}]),
        ),
        (
            "f3",
            json!([{"op":"set-prop","id":2,"property":"indeterminate","value":true}]),
        ),
        (
            "f4",
            json!([{"op":"set-prop","id":2,"property":"enabled","value":false}]),
        ),
        (
            "f5",
            json!([{"op":"move-child","parent":1,"child":3,"index":0},{"op":"set-prop","id":2,"property":"label-opacity","value":0.8},{"op":"set-prop","id":2,"property":"indicator-border-color","value":"#0000ff"}]),
        ),
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
    let invalid = renderer.clone();
    let error = fixture.rejection.clone();
    on_key_with(
        "f6",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            let next = generation.get() + 1;
            let rejected=invalid.apply(batch(next,json!([
            {"op":"set-prop","id":3,"property":"text","value":"must not publish"},
            {"op":"set-prop","id":2,"property":"indicator-border-color","value":"var(--missing-checkbox-border)"}
        ]))).unwrap_err();
            assert!(
                invalid
                    .apply(batch(
                        next,
                        json!([
                            {"op":"set-prop","id":3,"property":"text","value":"must not publish"},
                            {"op":"set-prop","id":2,"property":"toggle-detail-enabled","value":true}
                        ])
                    ))
                    .unwrap_err()
                    .contains("native modifier projection")
            );
            *error.lock().unwrap() = Some(rejected);
            apply(
                &invalid,
                &generation,
                json!([{"op":"set-prop","id":2,"property":"label-opacity","value":0.6}]),
            );
        },
    );
    renderer.element()
}
type Started = (Headless, Arc<Mutex<Vec<Event>>>, Arc<Mutex<Option<String>>>);
fn start(kind: &'static str) -> Started {
    let events = Arc::new(Mutex::new(Vec::new()));
    let rejection = Arc::new(Mutex::new(None));
    let mut config = EngineConfig {
        context: EngineContext::default().with(Fixture {
            kind,
            events: events.clone(),
            rejection: rejection.clone(),
        }),
        ..EngineConfig::new(Root::of::<ControlledProbe>())
    };
    // The test exercises desktop Tab traversal; GenericOS keeps Tab in fields.
    config.environment.os = nsh_core::platform::Os::MacOs;
    let mut app = Headless::start(config).unwrap();
    app.wait_for("role:checkbox[Choose rows]").unwrap();
    (app, events, rejection)
}
fn identity(app: &Headless, name: &str) -> NodeId {
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some(name))
        .unwrap()
        .id
}
#[test]
fn checkbox_and_toggle_keep_native_controlled_refusal_mixed_state_and_disabled_behavior() {
    for kind in ["checkbox", "toggle"] {
        let (mut app, events, _) = start(kind);
        let before = identity(&app, "lui-2");
        app.type_text("id:lui-3", "").unwrap();
        app.press_key("shift+tab").unwrap();
        app.press_key("space").unwrap();
        assert_eq!(
            *events.lock().unwrap(),
            [Event::Toggle(2, true)],
            "desktop keyboard Space must request one controlled change"
        );
        app.press("role:checkbox[Choose rows]").unwrap();
        assert_eq!(
            *events.lock().unwrap(),
            [Event::Toggle(2, true), Event::Toggle(2, true)]
        );
        app.press_key("f2").unwrap();
        app.press("role:checkbox[Choose rows]").unwrap();
        assert_eq!(
            events.lock().unwrap().last(),
            Some(&Event::Toggle(2, false))
        );
        app.press_key("f3").unwrap();
        app.press("role:checkbox[Choose rows]").unwrap();
        assert_eq!(events.lock().unwrap().last(), Some(&Event::Toggle(2, true)));
        let count = events.lock().unwrap().len();
        app.press_key("f4").unwrap();
        assert!(!app.screen().enabled("role:checkbox[Choose rows]").unwrap());
        app.press("role:checkbox[Choose rows]").unwrap();
        assert_eq!(events.lock().unwrap().len(), count);
        assert_eq!(identity(&app, "lui-2"), before);
    }
}
#[test]
fn part_color_validation_is_atomic_and_authored_part_changes_keep_the_editor_and_control() {
    let (mut app, _, rejection) = start("checkbox");
    let control = identity(&app, "lui-2");
    let editor = identity(&app, "lui-3");
    app.type_text("id:lui-3", " edited").unwrap();
    app.press_key("f5").unwrap();
    app.press_key("x").unwrap();
    assert_eq!(
        app.screen().input_text("id:lui-3").unwrap(),
        Some("draft editedx")
    );
    app.press_key("f6").unwrap();
    assert!(rejection.lock().unwrap().is_some());
    assert_eq!(
        app.screen().input_text("id:lui-3").unwrap(),
        Some("draft editedx")
    );
    assert_eq!(identity(&app, "lui-2"), control);
    assert_eq!(identity(&app, "lui-3"), editor);
}
