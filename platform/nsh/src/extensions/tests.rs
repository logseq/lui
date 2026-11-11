use super::*;
use crate::{
    render::{Event, Renderer},
    wire::Batch,
};
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use serde_json::{Value, json};
use std::{
    cell::{Cell, RefCell},
    sync::{
        Mutex,
        atomic::{AtomicUsize, Ordering},
    },
};

fn oracle() -> Value {
    serde_json::from_str::<Value>(include_str!("../../tests/fixtures/contract_oracle.json"))
        .unwrap()["extensions"]
        .clone()
}
fn schema(tweak: bool) -> Schema {
    serde_json::from_value(oracle()[if tweak { "tweak" } else { "schema" }].clone())
        .expect("regenerate canonical OCaml extension oracle")
}
fn profile() -> Profile {
    Profile {
        os: "macos".into(),
        host: "nsh".into(),
    }
}
fn batch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}
fn registry() -> Extensions {
    Extensions::builder()
        .register(schema(false), |_| text("oracle").into_element())
        .unwrap()
        .register_tweak(schema(true), |_, target| target.into_element())
        .unwrap()
        .freeze(profile())
        .unwrap()
}
#[test]
fn canonical_ocaml_scalar_defaults_properties_events_and_wire_agree() {
    let schema = schema(false);
    for case in oracle()["properties"].as_array().unwrap() {
        let mut node = Node::default();
        node.extension = Some(crate::store::ExtensionNode {
            identifier: schema.identifier.clone(),
            fingerprint: schema.fingerprint.clone(),
            properties: case["values"].as_object().unwrap().clone(),
        });
        assert_eq!(
            schema.validate_node(&node).is_ok(),
            case["accepted"].as_bool().unwrap(),
            "{case}"
        );
    }
    for case in oracle()["events"].as_array().unwrap() {
        assert_eq!(
            schema
                .validate_event("changed", case["values"].as_object().unwrap())
                .is_ok(),
            case["accepted"].as_bool().unwrap(),
            "{case}"
        );
    }
    let mut store = registry().store();
    store
        .apply(Batch::decode(&oracle()["wire"].to_string()).unwrap())
        .unwrap();
    assert_eq!(
        store.nodes[&2].extension.as_ref().unwrap().properties["count"],
        json!(7)
    );
    assert_eq!(
        store.nodes[&2].extension.as_ref().unwrap().fingerprint,
        store.nodes[&3].extension.as_ref().unwrap().fingerprint
    );
}
#[test]
fn admission_is_atomic_and_empty_fingerprint_is_not_a_seen_cache() {
    let mut store = registry().store();
    store
        .apply(batch(
            1,
            json!([
        {"op":"create-node","id":1,"kind":"column"},
        {"op":"create-extension","id":2,"identifier":"app-oracle","fingerprint":""},
        {"op":"set-extension-prop","id":2,"property":"count","value":1},
        {"op":"insert-child","parent":1,"child":2,"index":0}]),
        ))
        .unwrap();
    let old = store.nodes.clone();
    let invalid = [
        json!([{"op":"create-extension","id":3,"identifier":"missing","fingerprint":""}]),
        json!([{"op":"create-extension","id":3,"identifier":"app-oracle","fingerprint":"wrong"}]),
        json!([{"op":"remove-extension-prop","id":2,"property":"count"}]),
        json!([{"op":"set-extension-prop","id":2,"property":"count","value":1.0}]),
        json!([{"op":"set-extension-prop","id":2,"property":"count","value":4611686018427387904_u64}]),
        json!([{"op":"set-prop","id":2,"property":"width","value":100.0}]),
        json!([{"op":"set-extension-prop","id":1,"property":"count","value":1}]),
        json!([{"op":"create-extension","id":3,"identifier":"app-oracle","fingerprint":""}]),
        json!([{"op":"create-extension","id":3,"identifier":"app-oracle-tint","fingerprint":""},{"op":"set-extension-prop","id":3,"property":"width","value":10.0}]),
    ];
    for ops in invalid {
        assert!(store.apply(batch(2, ops)).is_err());
        assert_eq!(store.generation, 1);
        for (id, node) in &old {
            assert!(Arc::ptr_eq(node, &store.nodes[id]));
        }
    }
    store
        .apply_snapshot(batch(
            1,
            json!([
        {"op":"create-extension","id":4,"identifier":"app-oracle","fingerprint":""},
        {"op":"set-extension-prop","id":4,"property":"count","value":2}]),
        ))
        .unwrap();
    assert_eq!(store.nodes[&4].incarnation, 3);
}
#[test]
fn profile_child_names_and_transparent_tweak_constraints_fail_closed() {
    let bad_profile = Extensions::builder()
        .register(schema(false), |_| text("x").into_element())
        .unwrap()
        .freeze(Profile {
            os: "linux".into(),
            host: "web".into(),
        })
        .unwrap();
    assert!(
        bad_profile
            .store()
            .apply(Batch::decode(&oracle()["wire"].to_string()).unwrap())
            .is_err()
    );
    let mut unknown = schema(false);
    unknown.extension_children.push("missing".into());
    assert!(
        Extensions::builder()
            .register(unknown, |_| text("x").into_element())
            .unwrap()
            .freeze(profile())
            .is_err()
    );
    let mut store = registry().store();
    assert!(
        store
            .apply(batch(
                1,
                json!([
        {"op":"create-node","id":1,"kind":"text-field"},
        {"op":"create-extension","id":2,"identifier":"app-oracle","fingerprint":""},
        {"op":"set-extension-prop","id":2,"property":"count","value":1},
        {"op":"insert-child","parent":1,"child":2,"index":0}])
            ))
            .is_err()
    );
    assert!(
        store
            .apply(batch(
                1,
                json!([
        {"op":"create-extension","id":1,"identifier":"app-oracle-tint","fingerprint":""},
        {"op":"set-extension-prop","id":1,"property":"width","value":10.0},
        {"op":"create-node","id":2,"kind":"root"},
        {"op":"insert-child","parent":1,"child":2,"index":0}])
            ))
            .is_err()
    );
}

#[derive(Clone)]
struct Fixture {
    mounts: Arc<AtomicUsize>,
    drops: Arc<AtomicUsize>,
    events: Arc<Mutex<Vec<String>>>,
}
#[component]
fn NativeExtensions() -> impl IntoElement {
    let fixture = engine_context::<Fixture>().unwrap();
    let saved = Rc::new(RefCell::new(None::<ExtensionEmitter>));
    let capture = saved.clone();
    let mounts = fixture.mounts.clone();
    let drops = fixture.drops.clone();
    let registry = Extensions::builder()
        .register(schema(false), move |context| {
            mounts.fetch_add(1, Ordering::SeqCst);
            let drops = drops.clone();
            cleanup(move || {
                drops.fetch_add(1, Ordering::SeqCst);
            });
            *capture.borrow_mut() = Some(context.emitter.clone());
            let title = context.clone();
            view()
                .w(px(200.0))
                .h(px(100.0))
                .child(text(move || {
                    title
                        .property("title")
                        .unwrap()
                        .as_str()
                        .unwrap()
                        .to_owned()
                }))
                .child(context.children.element())
                .test_id("extension-body")
                .into_element()
        })
        .unwrap()
        .register_tweak(schema(true), |context, target| {
            target
                .state_inline_style(move || {
                    nsh_core::element::Style::from_decls([nsh_core::StyleDecl::Set(
                        nsh_core::StyleKey::Width,
                        nsh_core::StyleKey::Width
                            .parse_value(nsh_core::StyleValue::Number(
                                context.property("width").unwrap().as_f64().unwrap() as f32,
                            ))
                            .unwrap(),
                    )])
                })
                .into_element()
        })
        .unwrap()
        .freeze(profile())
        .unwrap();
    let generation = Rc::new(Cell::new(1));
    let event_generation = generation.clone();
    let events = fixture.events.clone();
    let renderer = Renderer::with_extensions(registry, move |event, renderer| match event {
        Event::Text(id, text) => {
            let next = event_generation.get() + 1;
            renderer
                .apply(batch(
                    next,
                    json!([{"op":"set-prop","id":id,"property":"text","value":text}]),
                ))
                .unwrap();
            event_generation.set(next);
        }
        Event::Extension { name, .. } => events.lock().unwrap().push(name),
        _ => {}
    });
    renderer
        .apply(batch(
            1,
            json!([
        {"op":"create-extension","id":1,"identifier":"app-oracle","fingerprint":""},
        {"op":"set-extension-prop","id":1,"property":"count","value":1},
        {"op":"create-extension","id":2,"identifier":"app-oracle-tint","fingerprint":""},
        {"op":"set-extension-prop","id":2,"property":"width","value":180.0},
        {"op":"create-node","id":3,"kind":"text-field"},
        {"op":"set-prop","id":3,"property":"text","value":"draft"},
        {"op":"set-prop","id":3,"property":"accessibility-label","value":"Extension editor"},
        {"op":"set-prop","id":3,"property":"change-enabled","value":true},
        {"op":"insert-child","parent":2,"child":3,"index":0},
        {"op":"insert-child","parent":1,"child":2,"index":0}]),
        ))
        .unwrap();
    renderer.set_root(1).unwrap();
    let update = renderer.clone();
    let emit = saved.clone();
    let remove = renderer.clone();
    let update_generation = generation.clone();
    view()
        .child(renderer.element())
        .child(
            nsh_base::button()
                .child(text("Update extension"))
                .on_press(move || {
                    let next = update_generation.get() + 1;
                    update
                        .apply(batch(
                            next,
                            json!([
                {"op":"set-extension-prop","id":1,"property":"title","value":"Updated"},
                {"op":"set-extension-prop","id":2,"property":"width","value":120.0}]),
                        ))
                        .unwrap();
                    update_generation.set(next);
                }),
        )
        .child(
            nsh_base::button()
                .child(text("Emit extension"))
                .on_press(move || {
                    emit.borrow()
                        .as_ref()
                        .unwrap()
                        .emit("changed", json!({"count":7}).as_object().unwrap().clone())
                        .unwrap();
                    assert!(
                        emit.borrow()
                            .as_ref()
                            .unwrap()
                            .emit("changed", json!({"count":7.0}).as_object().unwrap().clone())
                            .is_err()
                    );
                }),
        )
        .child(
            nsh_base::button()
                .child(text("Drop extension"))
                .on_press(move || {
                    remove
                        .apply(batch(
                            generation.get() + 1,
                            json!([{"op":"detach-subtree","id":1}]),
                        ))
                        .unwrap();
                    assert!(
                        !saved
                            .borrow()
                            .as_ref()
                            .unwrap()
                            .try_emit("changed", json!({"count":7}).as_object().unwrap().clone())
                            .unwrap()
                    );
                    assert!(
                        saved
                            .borrow()
                            .as_ref()
                            .unwrap()
                            .emit("changed", json!({"count":7}).as_object().unwrap().clone())
                            .is_err()
                    );
                }),
        )
}
#[test]
fn retained_factory_tweak_root_geometry_draft_and_event_lifetimes() {
    let mounts = Arc::new(AtomicUsize::new(0));
    let drops = Arc::new(AtomicUsize::new(0));
    let events = Arc::new(Mutex::new(Vec::new()));
    let mut app = Headless::start(EngineConfig {
        context: EngineContext::default().with(Fixture {
            mounts: mounts.clone(),
            drops: drops.clone(),
            events: events.clone(),
        }),
        ..EngineConfig::new(Root::of::<NativeExtensions>())
    })
    .unwrap();
    app.wait_for("Default").unwrap();
    let before = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some("lui-3"))
        .unwrap();
    assert!((before.bounds.size.width.0 - 180.0).abs() < 0.1);
    app.type_text("Extension editor", "draftx").unwrap();
    app.press("Update extension").unwrap();
    app.wait_for("Updated").unwrap();
    let after = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some("lui-3"))
        .unwrap();
    assert_eq!(before.id, after.id);
    assert!((after.bounds.size.width.0 - 120.0).abs() < 0.1);
    assert_eq!(mounts.load(Ordering::SeqCst), 1);
    app.press("Emit extension").unwrap();
    assert_eq!(*events.lock().unwrap(), vec!["changed"]);
    app.press("Drop extension").unwrap();
    assert_eq!(drops.load(Ordering::SeqCst), 1);
}
