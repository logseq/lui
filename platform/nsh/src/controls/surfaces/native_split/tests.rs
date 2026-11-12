use super::*;
use crate::{render::Renderer, wire::Batch};
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use serde_json::{Value, json};
use std::{
    cell::Cell,
    rc::Rc,
    sync::{
        Mutex,
        atomic::{AtomicBool, Ordering},
    },
};

#[derive(Clone)]
struct Fixture {
    pixels: Option<f64>,
    motion: bool,
    echo: bool,
    proposals: Arc<Mutex<Vec<f64>>>,
    reorder: Arc<AtomicBool>,
}
fn patch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}
#[component]
fn Panels() -> impl IntoElement {
    let fixture = engine_context::<Fixture>().unwrap();
    let generation = Rc::new(Cell::new(1));
    let next = generation.clone();
    let events = fixture.proposals.clone();
    let reorder = fixture.reorder.clone();
    let echo = fixture.echo;
    let renderer = Renderer::new(move |event, renderer| {
        let ops = match event {
            Event::Value(2, pixels) => {
                events.lock().unwrap().push(pixels);
                if echo {
                    vec![
                        json!({"op":"set-prop","id":2,"property":"first-pane-width","value":pixels}),
                    ]
                } else {
                    vec![]
                }
            }
            Event::Text(id @ (3 | 4), text) => {
                let mut ops = vec![json!({"op":"set-prop","id":id,"property":"text","value":text})];
                if reorder.swap(false, Ordering::SeqCst) {
                    ops.push(json!({"op":"move-child","parent":2,"child":4,"index":0}));
                }
                ops
            }
            _ => vec![],
        };
        if !ops.is_empty() {
            let generation = next.get() + 1;
            renderer.apply(patch(generation, json!(ops))).unwrap();
            next.set(generation);
        }
    });
    let mut ops = vec![
        json!({"op":"create-node","id":1,"kind":"column"}),
        json!({"op":"set-prop","id":1,"property":"width","value":600}),
        json!({"op":"create-node","id":2,"kind":"split"}),
        json!({"op":"set-prop","id":2,"property":"width","value":600}),
        json!({"op":"set-prop","id":2,"property":"height","value":120}),
        json!({"op":"set-prop","id":2,"property":"accessibility-label","value":"Workspace"}),
        json!({"op":"set-prop","id":2,"property":"change-enabled","value":true}),
        json!({"op":"insert-child","parent":1,"child":2,"index":0}),
    ];
    if fixture.motion {
        ops.extend([
            json!({"op":"set-prop","id":2,"property":"resize-duration","value":300}),
            json!({"op":"set-prop","id":2,"property":"resize-easing","value":"standard"}),
        ]);
    }
    if let Some(pixels) = fixture.pixels {
        ops.push(json!({"op":"set-prop","id":2,"property":"first-pane-width","value":pixels}));
    }
    for (index, id, text) in [(0, 3, "First"), (1, 4, "Second")] {
        ops.extend([
            json!({"op":"create-node","id":id,"kind":"text-field"}),
            json!({"op":"set-prop","id":id,"property":"text","value":text}),
            json!({"op":"set-prop","id":id,"property":"change-enabled","value":true}),
            json!({"op":"set-prop","id":id,"property":"min-width","value":100}),
            json!({"op":"insert-child","parent":2,"child":id,"index":index}),
        ]);
    }
    renderer.apply(patch(1, json!(ops))).unwrap();
    renderer.set_root(1).unwrap();
    for key in ["f1", "f2", "f3", "f4", "f5", "f6"] {
        let renderer = renderer.clone();
        let generation = generation.clone();
        on_key(key, move |_| {
            let ops = match key {
                "f1" => {
                    json!([{"op":"set-prop","id":2,"property":"first-pane-width","value":180.0}])
                }
                "f2" => json!([{"op":"set-prop","id":2,"property":"change-enabled","value":false}]),
                "f3" => json!([{"op":"set-prop","id":3,"property":"max-width","value":200}]),
                "f5" => json!([
                    {"op":"set-prop","id":3,"property":"min-width","value":0},
                    {"op":"set-prop","id":2,"property":"first-pane-width","value":0.0}
                ]),
                "f6" => json!([
                    {"op":"set-prop","id":3,"property":"min-width","value":100},
                    {"op":"set-prop","id":2,"property":"first-pane-width","value":240.0}
                ]),
                "f4" => {
                    assert!(renderer.apply(patch(generation.get() + 1, json!([
                        {"op":"set-prop","id":3,"property":"text","value":"must not publish"},
                        {"op":"set-prop","id":2,"property":"value","value":0.25}
                    ]))).is_err());
                    return;
                }
                _ => unreachable!(),
            };
            let next = generation.get() + 1;
            renderer.apply(patch(next, ops)).unwrap();
            generation.set(next);
        });
    }
    renderer.element()
}
fn app(pixels: Option<f64>, echo: bool, rtl: bool) -> (Headless, Fixture) {
    app_with_motion(pixels, echo, rtl, false)
}
fn app_with_motion(
    pixels: Option<f64>,
    echo: bool,
    rtl: bool,
    motion: bool,
) -> (Headless, Fixture) {
    let fixture = Fixture {
        pixels,
        motion,
        echo,
        proposals: Arc::new(Mutex::new(Vec::new())),
        reorder: Arc::new(AtomicBool::new(false)),
    };
    let mut config = EngineConfig {
        viewport: Size::new(px(800.0), px(400.0)),
        context: EngineContext::default().with(fixture.clone()),
        ..EngineConfig::new(Root::of::<Panels>())
    };
    config.environment.os = nsh_core::platform::Os::MacOs;
    config.environment.rtl = rtl;
    let mut app = Headless::start(config).unwrap();
    app.wait_for("id:lui-3").unwrap();
    (app, fixture)
}
fn layout(app: &Headless, id: &str) -> nsh_testing::LayoutNode {
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some(id))
        .unwrap()
}
const HANDLE: &str = "role:adjustable[Workspace divider]";

#[test]
fn native_equal_panels_keep_user_sizes_without_model_echo_and_report_pixels_once() {
    let (mut app, fixture) = app(None, false, false);
    let first = layout(&app, "lui-3").id;
    let second = layout(&app, "lui-4").id;
    assert_eq!(
        layout(&app, "lui-2-split-pane-3").bounds.size.width,
        px(300.0)
    );
    assert_eq!(app.screen().count(HANDLE).unwrap(), 1);
    app.drag(HANDLE, Point::new(px(100.0), px(0.0))).unwrap();
    assert_eq!(
        layout(&app, "lui-2-split-pane-3").bounds.size.width,
        px(400.0)
    );
    assert_eq!(
        layout(&app, "lui-2-split-pane-4").bounds.size.width,
        px(200.0)
    );
    assert_eq!(*fixture.proposals.lock().unwrap(), [400.0]);
    assert_eq!(layout(&app, "lui-3").id, first);
    assert_eq!(layout(&app, "lui-4").id, second);
}

#[test]
fn native_pixel_source_update_and_keyed_reorder_retain_both_editors_and_focus() {
    let (mut app, fixture) = app(Some(240.0), true, false);
    let first = layout(&app, "lui-3").id;
    let second = layout(&app, "lui-4").id;
    assert_eq!(
        layout(&app, "lui-2-split-pane-3").bounds.size.width,
        px(240.0)
    );
    app.press_key("f1").unwrap();
    assert_eq!(
        layout(&app, "lui-2-split-pane-3").bounds.size.width,
        px(180.0)
    );
    assert!(fixture.proposals.lock().unwrap().is_empty());
    app.type_text("id:lui-3", " draft").unwrap();
    fixture.reorder.store(true, Ordering::SeqCst);
    app.type_text("id:lui-3", "~").unwrap();
    let edited = app
        .screen()
        .input_text("id:lui-3")
        .unwrap()
        .unwrap()
        .to_owned();
    app.press_key("x").unwrap();
    let continued = app.screen().input_text("id:lui-3").unwrap().unwrap();
    assert_eq!(continued.replace('x', ""), edited);
    assert_eq!(continued.len(), edited.len() + 1);
    assert_eq!(layout(&app, "lui-3").id, first);
    assert_eq!(layout(&app, "lui-4").id, second);
    assert_eq!(
        layout(&app, "lui-2-split-pane-4").bounds.size.width,
        px(180.0)
    );
    assert_eq!(
        layout(&app, "lui-2-split-pane-3").bounds.size.width,
        px(420.0)
    );
}

#[test]
fn native_constraints_and_notification_disable_do_not_add_a_second_resize_policy() {
    let (mut app, fixture) = app(None, false, false);
    app.press_key("f3").unwrap();
    app.drag(HANDLE, Point::new(px(500.0), px(0.0))).unwrap();
    assert_eq!(
        layout(&app, "lui-2-split-pane-3").bounds.size.width,
        px(200.0)
    );
    let count = fixture.proposals.lock().unwrap().len();
    app.press_key("f2").unwrap();
    app.drag(HANDLE, Point::new(px(-50.0), px(0.0))).unwrap();
    assert_eq!(
        layout(&app, "lui-2-split-pane-3").bounds.size.width,
        px(150.0)
    );
    assert_eq!(fixture.proposals.lock().unwrap().len(), count);
    let text = app
        .screen()
        .input_text("id:lui-3")
        .unwrap()
        .unwrap()
        .to_owned();
    app.press_key("f4").unwrap();
    assert_eq!(
        app.screen().input_text("id:lui-3").unwrap(),
        Some(text.as_str())
    );
}

#[test]
fn native_rtl_report_selects_the_first_logical_panel_and_legacy_options_reject() {
    let (mut app, fixture) = app(Some(240.0), true, true);
    assert!(
        layout(&app, "lui-2-split-pane-3").bounds.origin.x
            > layout(&app, "lui-2-split-pane-4").bounds.origin.x
    );
    app.drag(HANDLE, Point::new(px(-60.0), px(0.0))).unwrap();
    let actual = layout(&app, "lui-2-split-pane-3").bounds.size.width.0 as f64;
    assert_eq!(
        fixture.proposals.lock().unwrap().last().copied(),
        Some(actual)
    );
    let mut node = Node {
        kind: "split".into(),
        children: Arc::new(vec![3, 4]),
        ..Default::default()
    };
    for (property, value) in [
        ("value", json!(0.5)),
        ("pointer-enabled", json!(true)),
        ("first-pane-width", json!(f64::MAX)),
        ("resize-handle-width", json!(9)),
        ("resize-handle-offset", json!(1.0)),
        ("resize-easing", json!("emphasized")),
        ("resize-easing", json!("spring")),
        ("resize-origin", json!(0.5)),
    ] {
        node.props.insert(property.into(), value);
        assert!(validate(&node).unwrap_err().contains("NSH split"));
        node.props.clear();
    }
}

#[test]
fn native_sidebar_width_motion_retains_editors_and_respects_reduced_motion() {
    for echo in [false, true] {
        let (mut app, fixture) = app_with_motion(Some(240.0), echo, false, true);
        let first = layout(&app, "lui-3").id;
        let second = layout(&app, "lui-4").id;
        let transitions = Arc::new(Mutex::new(Vec::new()));
        let observed = transitions.clone();
        app.observe(move |_, batch| {
            for item in &batch.items {
                if let nsh_core::MountItem::LayoutAnimation(animation) = item {
                    if let Some(update) = animation.update {
                        observed.lock().unwrap().push(update);
                    }
                }
            }
        });
        app.type_text("id:lui-4", "retained").unwrap();
        assert!(transitions.lock().unwrap().is_empty());
        app.press_key("f5").unwrap();
        assert_eq!(
            layout(&app, "lui-2-split-pane-3").bounds.size.width,
            px(0.0)
        );
        assert!(layout(&app, "lui-2-split-pane-3").clips);
        assert!(transitions.lock().unwrap().iter().all(|motion| {
            motion.duration_ms == 300.0 && motion.curve == LayoutCurve::EaseInEaseOut
        }));
        assert!(!transitions.lock().unwrap().is_empty());
        app.press_key("f6").unwrap();
        assert_eq!(layout(&app, "lui-3").id, first);
        assert_eq!(layout(&app, "lui-4").id, second);
        let before = app
            .screen()
            .input_text("id:lui-4")
            .unwrap()
            .unwrap()
            .to_owned();
        app.press_key("x").unwrap();
        let after = app.screen().input_text("id:lui-4").unwrap().unwrap();
        assert_eq!(after.len(), before.len() + 1);
        assert_eq!(after.replace('x', ""), before);
        transitions.lock().unwrap().clear();
        app.drag(HANDLE, Point::new(px(30.0), px(0.0))).unwrap();
        assert_eq!(fixture.proposals.lock().unwrap().len(), 1);
        assert!(transitions.lock().unwrap().is_empty());
        // A later application toggle must still animate, with or without an echo.
        app.press_key("f5").unwrap();
        app.press_key("f6").unwrap();
        assert!(!transitions.lock().unwrap().is_empty());
        transitions.lock().unwrap().clear();
        app.set_environment("reduce motion", |environment| {
            environment.reduce_motion = true
        })
        .unwrap();
        app.press_key("f5").unwrap();
        assert_eq!(
            layout(&app, "lui-2-split-pane-3").bounds.size.width,
            px(0.0)
        );
        assert!(layout(&app, "lui-2-split-pane-3").clips);
        app.press_key("f6").unwrap();
        assert_eq!(
            layout(&app, "lui-2-split-pane-3").bounds.size.width,
            px(240.0)
        );
        assert!(transitions.lock().unwrap().is_empty());
        assert_eq!(layout(&app, "lui-3").id, first);
        assert_eq!(layout(&app, "lui-4").id, second);
    }
}
