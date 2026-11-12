//! Parent viewport requests use the actual enclosing native scroll controller.
use super::*;
use nsh_core::{
    EventKind, EventPayload, MountBatch, MountItem,
    platform::{Idiom, Os},
};
use nsh_engine::{
    Engine, EngineConfig, EngineContext, EngineControl, Environment, MountSink, Root,
};
use nsh_testing::Headless;
use serde_json::json;
use std::{
    sync::{Mutex, OnceLock},
    time::{Duration, Instant},
};

#[derive(Default)]
struct Probe {
    ids: BTreeMap<String, u32>,
    offsets: BTreeMap<u32, (Point<Points>, u32)>,
    outcomes: Vec<(u64, String)>,
    errors: Vec<String>,
}
struct Context {
    probe: Arc<Mutex<Probe>>,
    owner: &'static str,
    nearest: bool,
}
fn patch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}
#[component]
fn Fixture() -> impl IntoElement {
    let context = engine_context::<Context>().unwrap();
    let probe = context.probe.clone();
    let nearest = context.nearest;
    let next_token = Rc::new(Cell::new(0_u64));
    let renderer = Renderer::new(move |event, renderer| match event {
        Event::Press(9) => {
            let token = next_token.get() + 1;
            next_token.set(token);
            renderer.apply(patch(token + 1, json!([
                {"op":"set-prop","id":5,"property":"scroll-token","value":token},
                {"op":"set-prop","id":5,"property":"scroll-target","value":if nearest {"row-0"} else {"row-29"}},
                {"op":"set-prop","id":5,"property":"virtual-scroll-index","value":if nearest {0} else {29}},
                {"op":"set-prop","id":5,"property":"scroll-anchor","value":if nearest {"nearest"} else {"top"}},
                {"op":"set-prop","id":5,"property":"scroll-animated","value":!nearest}
            ]))).unwrap();
        }
        Event::ScrollCompleted { token, outcome, .. } => {
            probe.lock().unwrap().outcomes.push((token, outcome));
        }
        _ => {}
    });
    let mut ops = json!([
        {"op":"create-node","id":1,"kind":"column"},
        {"op":"set-prop","id":1,"property":"width","value":400},
        {"op":"create-node","id":9,"kind":"button"},
        {"op":"set-prop","id":9,"property":"text","value":"Request row"},
        {"op":"set-prop","id":9,"property":"press-enabled","value":true},
        {"op":"insert-child","parent":1,"child":9,"index":0},
        {"op":"create-node","id":2,"kind":"scroll"},
        {"op":"set-prop","id":2,"property":"width","value":400},
        {"op":"set-prop","id":2,"property":"height","value":128},
        {"op":"insert-child","parent":1,"child":2,"index":1},
        {"op":"create-node","id":7,"kind":context.owner},
        {"op":"set-prop","id":7,"property":"width","value":400},
        {"op":"set-prop","id":7,"property":"height","value":96},
        {"op":"insert-child","parent":2,"child":7,"index":0},
        {"op":"create-node","id":3,"kind":"column"},
        {"op":"insert-child","parent":7,"child":3,"index":0},
        {"op":"create-node","id":4,"kind":"text"},
        {"op":"set-prop","id":4,"property":"text","value":"Header before the list"},
        {"op":"set-prop","id":4,"property":"height","value":80},
        {"op":"insert-child","parent":3,"child":4,"index":0},
        {"op":"create-node","id":5,"kind":"virtual-list"},
        {"op":"set-prop","id":5,"property":"virtual-viewport","value":"parent"},
        {"op":"set-prop","id":5,"property":"virtual-total-count","value":30},
        {"op":"set-prop","id":5,"property":"virtual-generation","value":1},
        {"op":"set-prop","id":5,"property":"virtual-indices","value":serde_json::to_string(&(0..30).collect::<Vec<_>>()).unwrap()},
        {"op":"set-prop","id":5,"property":"item-extent","value":32.0},
        {"op":"set-prop","id":5,"property":"track-visible-range","value":true},
        {"op":"insert-child","parent":3,"child":5,"index":1}
    ])
    .as_array()
    .unwrap()
    .clone();
    for index in 0..30_u64 {
        let id = index + 100;
        ops.extend([
            json!({"op":"create-node","id":id,"kind":"text-field"}),
            json!({"op":"set-prop","id":id,"property":"text","value":format!("Row {index}")}),
            json!({"op":"set-prop","id":id,"property":"height","value":32}),
            json!({"op":"insert-child","parent":5,"child":id,"index":index}),
        ]);
    }
    renderer.apply(patch(1, Value::Array(ops))).unwrap();
    renderer.set_root(1).unwrap();
    renderer.element()
}
fn bounds(screen: &nsh_testing::Screen, id: &str) -> Bounds<Points> {
    screen
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some(id))
        .unwrap()
        .bounds
}

#[component]
fn AtomicParentOwnerValidation() -> impl IntoElement {
    let renderer = Renderer::new(|_, _| {});
    renderer
        .apply(patch(
            1,
            json!([
                {"op":"create-node","id":1,"kind":"column"},
                {"op":"create-node","id":2,"kind":"scroll"},
                {"op":"set-prop","id":2,"property":"height","value":80},
                {"op":"create-node","id":3,"kind":"virtual-list"},
                {"op":"set-prop","id":3,"property":"virtual-viewport","value":"parent"},
                {"op":"insert-child","parent":1,"child":2,"index":0},
                {"op":"insert-child","parent":2,"child":3,"index":0}
            ]),
        ))
        .unwrap();
    renderer.set_root(1).unwrap();
    let retained = renderer.0.borrow().store.nodes[&3].clone();
    let invalid_move = patch(
        2,
        json!([
            {"op":"remove-child","parent":2,"child":3},
            {"op":"insert-child","parent":1,"child":3,"index":1}
        ]),
    );
    assert!(
        renderer
            .apply(invalid_move)
            .unwrap_err()
            .contains("vertical Scroll owner")
    );
    assert_eq!(renderer.0.borrow().store.generation, 1);
    assert!(Arc::ptr_eq(&retained, &renderer.0.borrow().store.nodes[&3]));
    let across_surface = patch(
        2,
        json!([
            {"op":"create-node","id":4,"kind":"dialog"},
            {"op":"insert-child","parent":2,"child":4,"index":1},
            {"op":"remove-child","parent":2,"child":3},
            {"op":"insert-child","parent":4,"child":3,"index":0}
        ]),
    );
    assert!(
        renderer
            .apply(across_surface)
            .unwrap_err()
            .contains("native surface")
    );
    assert_eq!(renderer.0.borrow().store.generation, 1);
    assert!(!renderer.0.borrow().store.nodes.contains_key(&4));
    let unrendered_owner = patch(
        2,
        json!([
            {"op":"create-node","id":9,"kind":"scroll"},
            {"op":"insert-child","parent":9,"child":1,"index":0},
            {"op":"remove-child","parent":2,"child":3},
            {"op":"insert-child","parent":1,"child":3,"index":1}
        ]),
    );
    assert!(
        renderer
            .apply(unrendered_owner)
            .unwrap_err()
            .contains("vertical Scroll owner")
    );
    assert_eq!(renderer.0.borrow().store.generation, 1);
    assert!(!renderer.0.borrow().store.nodes.contains_key(&9));
    renderer
        .apply(patch(
            2,
            json!([
                {"op":"create-node","id":4,"kind":"dialog"},
                {"op":"create-node","id":5,"kind":"virtual-list"},
                {"op":"set-prop","id":5,"property":"virtual-viewport","value":"parent"},
                {"op":"insert-child","parent":4,"child":5,"index":0}
            ]),
        ))
        .unwrap();
    assert!(
        renderer
            .apply(patch(
                3,
                json!([
                    {"op":"insert-child","parent":2,"child":4,"index":1}
                ])
            ))
            .unwrap_err()
            .contains("native surface")
    );
    assert_eq!(renderer.0.borrow().store.generation, 2);
    renderer
        .apply(patch(
            3,
            json!([
                {"op":"create-node","id":6,"kind":"scroll"},
                {"op":"remove-child","parent":4,"child":5},
                {"op":"insert-child","parent":4,"child":6,"index":0},
                {"op":"insert-child","parent":6,"child":5,"index":0},
                {"op":"insert-child","parent":2,"child":4,"index":1}
            ]),
        ))
        .unwrap();
    let invalid_root = Renderer::new(|_, _| {});
    invalid_root
        .apply(patch(
            1,
            json!([
                {"op":"create-node","id":1,"kind":"virtual-list"},
                {"op":"set-prop","id":1,"property":"virtual-viewport","value":"parent"}
            ]),
        ))
        .unwrap();
    assert!(
        invalid_root
            .set_root(1)
            .unwrap_err()
            .contains("vertical Scroll owner")
    );
    assert_eq!(invalid_root.root_id(), None);
    view()
        .child(renderer.element())
        .child(text("Parent ownership rejected atomically"))
}

#[test]
fn parent_owner_shape_rejects_before_publication_or_root_selection() {
    let mut app =
        Headless::start(EngineConfig::new(Root::of::<AtomicParentOwnerValidation>())).unwrap();
    app.wait_for("text:Parent ownership rejected atomically")
        .unwrap();
}

#[test]
fn parent_nearest_reveals_a_partially_clipped_row_against_the_actual_scroll_viewport()
-> Result<(), String> {
    for owner in ["scroll", "list", "virtual-list"] {
        let probe = Arc::new(Mutex::new(Probe::default()));
        let mut app = Headless::start(EngineConfig {
            viewport: Size::new(px(400.0), px(200.0)),
            environment: Environment {
                os: Os::Linux,
                idiom: Idiom::Desktop,
                ..Default::default()
            },
            context: EngineContext::default().with(Context {
                probe: probe.clone(),
                owner,
                nearest: true,
            }),
            content_culling: false,
            ..EngineConfig::new(Root::of::<Fixture>())
        })
        .map_err(|error| error.to_string())?;
        app.wait_for("id:lui-100")?;
        let viewport = bounds(app.screen(), "lui-7");
        let before = bounds(app.screen(), "lui-100");
        assert!(
            before.origin.y >= viewport.origin.y && before.bottom() > viewport.bottom(),
            "fixture row is partly clipped by the actual {owner}: {before:?} {viewport:?}"
        );
        let id = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|node| node.test_id.as_deref() == Some("lui-100"))
            .unwrap()
            .id;
        app.press("id:lui-9")?;
        app.wait_until(
            "nearest reveals the clipped row",
            Duration::from_secs(3),
            |app| {
                let row = bounds(app, "lui-100");
                row.origin.y >= viewport.origin.y
                    && row.bottom() <= viewport.bottom()
                    && probe.lock().unwrap().outcomes == [(1, "succeeded".into())]
            },
        )?;
        assert_eq!(
            app.screen()
                .layout_nodes()
                .into_iter()
                .find(|node| node.test_id.as_deref() == Some("lui-100"))
                .unwrap()
                .id,
            id
        );
        assert_eq!(app.screen().input_text("id:lui-100")?, Some("Row 0"));
    }
    Ok(())
}

struct Platform {
    probe: Arc<Mutex<Probe>>,
    control: Arc<OnceLock<EngineControl>>,
}
impl MountSink for Platform {
    fn submit(&self, batch: MountBatch) {
        let mut reports = Vec::new();
        {
            let mut probe = self.probe.lock().unwrap();
            for item in batch.items {
                match item {
                    MountItem::ViewProps { id, props } => {
                        if let Some(name) = &props.test_id {
                            probe.ids.insert(name.to_string(), id);
                        }
                    }
                    MountItem::Command {
                        id,
                        command: nsh_core::Command::ScrollTo { x, y, .. },
                    } => {
                        let state = probe.offsets.entry(id).or_default();
                        state.0 = point(x, y);
                        state.1 += 1;
                        reports.push((id, state.0, state.1));
                    }
                    MountItem::ScrollBy { id, dx, dy } => {
                        let state = probe.offsets.entry(id).or_default();
                        state.0 = point(state.0.x + dx, state.0.y + dy);
                        state.1 += 1;
                        reports.push((id, state.0, state.1));
                    }
                    _ => {}
                }
            }
        }
        for (id, offset, applied) in reports {
            self.control.get().unwrap().scroll(id, offset, applied);
        }
    }
    fn report_error(&self, message: &str) {
        self.probe.lock().unwrap().errors.push(message.into());
    }
    fn request_frame(&self) {
        self.control.get().unwrap().frame();
    }
}
fn wait(probe: &Arc<Mutex<Probe>>, done: impl Fn(&Probe) -> bool) {
    let deadline = Instant::now() + Duration::from_secs(3);
    loop {
        {
            let probe = probe.lock().unwrap();
            assert!(probe.errors.is_empty(), "{:?}", probe.errors);
            if done(&probe) {
                return;
            }
        }
        assert!(
            Instant::now() < deadline,
            "Parent native event fixture did not settle"
        );
        std::thread::sleep(Duration::from_millis(2));
    }
}
fn flush(control: &EngineControl) {
    let (send, receive) = std::sync::mpsc::channel();
    control.flush(move |idle| {
        send.send(idle).unwrap();
    });
    assert!(
        receive.recv_timeout(Duration::from_secs(3)).unwrap(),
        "native event fixture is idle"
    );
}
#[test]
fn parent_tokens_finish_and_cancel_only_from_the_nearest_native_scroll_controller() {
    for owner in ["scroll", "list", "virtual-list"] {
        let probe = Arc::new(Mutex::new(Probe::default()));
        let control = Arc::new(OnceLock::new());
        let setup = control.clone();
        let engine = Engine::start_with(
            EngineConfig {
                viewport: Size::new(px(400.0), px(200.0)),
                environment: Environment {
                    os: Os::Linux,
                    idiom: Idiom::Desktop,
                    ..Default::default()
                },
                context: EngineContext::default().with(Context {
                    probe: probe.clone(),
                    owner,
                    nearest: false,
                }),
                content_culling: false,
                ..EngineConfig::new(Root::of::<Fixture>())
            },
            || nsh_core::ApproxTextEngine,
            Platform {
                probe: probe.clone(),
                control,
            },
            move |control| {
                assert!(setup.set(control.clone()).is_ok());
            },
        )
        .unwrap();
        wait(&probe, |probe| {
            probe.ids.contains_key("lui-9") && probe.ids.contains_key("lui-7")
        });
        let native = engine.control();
        let ids = probe.lock().unwrap().ids.clone();
        native.dispatch_event(ids["lui-9"], EventKind::Press, EventPayload::None);
        wait(&probe, |probe| {
            probe.ids.contains_key("lui-129")
                && probe
                    .offsets
                    .get(&ids["lui-7"])
                    .is_some_and(|(_, applied)| *applied > 0)
        });
        flush(&native);
        assert!(
            probe.lock().unwrap().outcomes.is_empty(),
            "materialization is not animation completion"
        );
        native.dispatch_event(
            ids["lui-2"],
            EventKind::ScrollEnd,
            EventPayload::Scroll(Point::default()),
        );
        flush(&native);
        assert!(
            probe.lock().unwrap().outcomes.is_empty(),
            "a farther Scroll must not complete the token"
        );
        let offset = probe.lock().unwrap().offsets[&ids["lui-7"]].0;
        native.dispatch_event(
            ids["lui-7"],
            EventKind::ScrollEnd,
            EventPayload::Scroll(offset),
        );
        flush(&native);
        assert_eq!(probe.lock().unwrap().outcomes, [(1, "succeeded".into())]);
        native.dispatch_event(
            ids["lui-7"],
            EventKind::ScrollEnd,
            EventPayload::Scroll(offset),
        );
        flush(&native);
        assert_eq!(
            probe.lock().unwrap().outcomes.len(),
            1,
            "end feedback is delivered once"
        );
        native.dispatch_event(ids["lui-9"], EventKind::Press, EventPayload::None);
        flush(&native);
        native.dispatch_event(
            ids["lui-7"],
            EventKind::ScrollDragStart,
            EventPayload::Scroll(offset),
        );
        flush(&native);
        assert_eq!(
            probe.lock().unwrap().outcomes,
            [(1, "succeeded".into()), (2, "cancelled".into())]
        );
        native.dispatch_event(
            ids["lui-7"],
            EventKind::ScrollEnd,
            EventPayload::Scroll(offset),
        );
        flush(&native);
        assert_eq!(
            probe.lock().unwrap().outcomes.len(),
            2,
            "late completion cannot repeat a cancelled token"
        );
    }
}
