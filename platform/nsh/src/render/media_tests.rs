//! Native video host contracts; decoding and pixels require a real platform.
use super::*;
use nsh_core::{EventKind, EventPayload, MountBatch, MountItem, NativeProps, VideoProps, ViewKind};
use nsh_engine::{Engine, EngineConfig, MountSink, Root};
use nsh_testing::Headless;
use serde_json::json;
use std::sync::{Condvar, Mutex};

fn patch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}

fn publish(renderer: &Renderer, ops: Value) {
    let generation = renderer.0.borrow().store.generation + 1;
    renderer.apply(patch(generation, ops)).unwrap();
}

#[component]
fn MediaScenario() -> impl IntoElement {
    let renderer = Renderer::new(|event, renderer| {
        if let Event::Text(id, text) = event {
            publish(
                &renderer,
                json!([
                    {"op":"set-prop","id":id,"property":"text","value":text}
                ]),
            );
        }
    });
    publish(
        &renderer,
        json!([
            {"op":"create-node","id":1,"kind":"column"},
            {"op":"create-node","id":2,"kind":"media-surface"},
            {"op":"set-prop","id":2,"property":"url","value":"file:///tmp/clip-one.mp4"},
            {"op":"set-prop","id":2,"property":"accessibility-label","value":"Native clip"},
            {"op":"set-prop","id":2,"property":"width","value":320},
            {"op":"set-prop","id":2,"property":"height","value":180},
            {"op":"create-node","id":3,"kind":"text-field"},
            {"op":"set-prop","id":3,"property":"text","value":"draft"},
            {"op":"set-prop","id":3,"property":"change-enabled","value":true},
            {"op":"insert-child","parent":1,"child":2,"index":0},
            {"op":"insert-child","parent":1,"child":3,"index":1}
        ]),
    );
    renderer.set_root(1).unwrap();
    let changing = renderer.clone();
    let rejecting = renderer.clone();
    view().flex_col().child(renderer.element())
        .child(nsh_base::button().child(text("Change URL")).on_press(move || {
            publish(&changing, json!([
                {"op":"set-prop","id":2,"property":"url","value":"https://example.test/clip-two.mp4"},
                {"op":"set-prop","id":2,"property":"accessibility-label","value":"Updated native clip"}
            ]));
        }))
        .child(nsh_base::button().child(text("Reject media source")).on_press(move || {
            let generation = rejecting.0.borrow().store.generation;
            let media = rejecting.0.borrow().nodes[&2].node.get_untracked();
            let editor = rejecting.0.borrow().nodes[&3].node.get_untracked();
            for source in [
                json!([
                    {"op":"remove-prop","id":2,"property":"url"},
                    {"op":"set-prop","id":2,"property":"surface","value":0}
                ]),
                json!([{"op":"set-prop","id":2,"property":"url","value":""}]),
                json!([{"op":"set-prop","id":2,"property":"url","value":"   "}]),
                json!([{"op":"remove-prop","id":2,"property":"url"}]),
            ] {
                let mut ops = vec![json!({"op":"set-prop","id":3,"property":"text","value":"must not publish"})];
                ops.extend(source.as_array().unwrap().iter().cloned());
                assert!(rejecting.apply(patch(generation+1, Value::Array(ops))).is_err());
                assert_eq!(rejecting.0.borrow().store.generation, generation);
                assert!(Arc::ptr_eq(&media, &rejecting.0.borrow().nodes[&2].node.get_untracked()));
                assert!(Arc::ptr_eq(&editor, &rejecting.0.borrow().nodes[&3].node.get_untracked()));
            }
        }))
}

fn start() -> Headless {
    let mut app = Headless::start(EngineConfig::new(Root::of::<MediaScenario>())).unwrap();
    app.wait_for("id:lui-2").unwrap();
    app
}

fn native_id(app: &Headless, id: &str) -> nsh_core::NodeId {
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some(id))
        .unwrap()
        .id
}

#[test]
fn media_url_changes_keep_the_real_video_host_and_controlled_editor() {
    let mut app = start();
    let video = native_id(&app, "lui-2");
    let editor = native_id(&app, "lui-3");
    let nodes = app.screen().layout_nodes();
    let host = nodes.iter().find(|node| node.id == video).unwrap();
    assert_eq!(host.kind, ViewKind::Video);
    assert_eq!(host.bounds.size, nsh_core::Size::new(px(320.0), px(180.0)));
    app.type_text("id:lui-3", " retained").unwrap();
    app.press("text:Change URL").unwrap();
    app.wait_for("label:Updated native clip").unwrap();
    assert_eq!(native_id(&app, "lui-2"), video);
    assert_eq!(native_id(&app, "lui-3"), editor);
    assert_eq!(
        app.screen().input_text("id:lui-3").unwrap(),
        Some("draft retained")
    );
}

#[test]
fn foreign_surface_ids_and_empty_urls_fail_atomically() {
    let mut app = start();
    let video = native_id(&app, "lui-2");
    app.type_text("id:lui-3", " retained").unwrap();
    app.press("text:Reject media source").unwrap();
    assert_eq!(native_id(&app, "lui-2"), video);
    assert_eq!(
        app.screen().input_text("id:lui-3").unwrap(),
        Some("draft retained")
    );
    app.press("text:Change URL").unwrap();
    app.wait_for("label:Updated native clip").unwrap();
}

#[test]
fn a_native_player_error_is_nonfatal_and_keeps_other_controls_working() {
    let mut app = start();
    let video = native_id(&app, "lui-2");
    app.engine().control().dispatch_event(
        video,
        EventKind::Error,
        EventPayload::Error {
            message: "fixture decoder failed".into(),
        },
    );
    app.wait_for("text:Native video: fixture decoder failed")
        .unwrap();
    app.type_text("id:lui-3", " still editable").unwrap();
    assert_eq!(
        app.screen().input_text("id:lui-3").unwrap(),
        Some("draft still editable")
    );
    assert_eq!(native_id(&app, "lui-2"), video);
}

#[derive(Default)]
struct VideoTrace {
    created: Vec<nsh_core::NodeId>,
    properties: Vec<(nsh_core::NodeId, VideoProps)>,
    trigger: Option<nsh_core::NodeId>,
    errors: Vec<String>,
}
type NativeTrace = Arc<(Mutex<VideoTrace>, Condvar)>;

struct VideoSink(NativeTrace);
impl MountSink for VideoSink {
    fn submit(&self, batch: MountBatch) {
        let mut trace = self.0.0.lock().unwrap();
        for item in batch.items {
            match item {
                MountItem::Create {
                    id,
                    kind: ViewKind::Video,
                } => trace.created.push(id),
                MountItem::NativeProps {
                    id,
                    props: NativeProps::Video(props),
                } => trace.properties.push((id, *props)),
                MountItem::Events { id, events } if events.contains(EventKind::Press) => {
                    trace.trigger = Some(id)
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

#[component]
fn VideoProperties() -> impl IntoElement {
    let node = signal(Arc::new(Node {
        kind: "media-surface".into(),
        props: serde_json::from_value(json!({"url":"file:///tmp/first.mp4"})).unwrap(),
        ..Default::default()
    }));
    view()
        .child(
            crate::media::element(node, Rc::new(|_| {}))
                .w(px(320.0))
                .h(px(180.0)),
        )
        .child(
            nsh_base::button()
                .child(text("Change source"))
                .on_press(move || {
                    node.update(|node| {
                        Arc::make_mut(node)
                            .props
                            .insert("url".into(), json!("file:///tmp/second.mp4"));
                    });
                }),
        )
}

fn wait_trace(trace: &NativeTrace, ready: impl Fn(&VideoTrace) -> bool) {
    let (state, changed) = &**trace;
    let trace = state.lock().unwrap();
    let (trace, timeout) = changed
        .wait_timeout_while(trace, std::time::Duration::from_secs(5), |trace| {
            trace.errors.is_empty() && !ready(trace)
        })
        .unwrap();
    assert!(trace.errors.is_empty(), "{:?}", trace.errors);
    assert!(
        !timeout.timed_out() || ready(&trace),
        "native video properties did not arrive"
    );
}

#[test]
fn public_native_video_properties_enable_controls_and_reuse_nsh_playback_defaults() {
    let trace = NativeTrace::default();
    let engine = Engine::start(
        EngineConfig {
            viewport: nsh_core::Size::new(px(400.0), px(300.0)),
            content_culling: false,
            ..EngineConfig::new(Root::of::<VideoProperties>())
        },
        || nsh_core::ApproxTextEngine,
        VideoSink(trace.clone()),
    )
    .unwrap();
    wait_trace(&trace, |trace| {
        trace
            .properties
            .iter()
            .any(|(_, props)| props.source.as_deref() == Some("file:///tmp/first.mp4"))
            && trace.trigger.is_some()
    });
    let trigger = {
        let trace = trace.0.lock().unwrap();
        let (_, props) = trace
            .properties
            .iter()
            .find(|(_, props)| props.source.as_deref() == Some("file:///tmp/first.mp4"))
            .unwrap();
        let expected = VideoProps {
            source: props.source.clone(),
            controls: true,
            ..Default::default()
        };
        assert_eq!(*props, expected);
        trace.trigger.unwrap()
    };
    engine
        .control()
        .dispatch_event(trigger, EventKind::Press, EventPayload::None);
    wait_trace(&trace, |trace| {
        trace
            .properties
            .last()
            .is_some_and(|(_, props)| props.source.as_deref() == Some("file:///tmp/second.mp4"))
    });
    let trace = trace.0.lock().unwrap();
    assert_eq!(trace.created.len(), 1);
    assert!(
        trace
            .properties
            .iter()
            .filter(|(_, props)| props.source.is_some())
            .all(|(id, props)| *id == trace.created[0] && props.controls)
    );
}
