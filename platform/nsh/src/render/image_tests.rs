//! Headless checks cover retention/transactions; native decode is qualified separately.
use super::*;
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
use serde_json::json;
use std::sync::Mutex;

fn patch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}

#[component]
fn FractionalImageScenario() -> impl IntoElement {
    let renderer = Renderer::new(|_, _| {});
    renderer.apply(patch(1, json!([
        {"op":"create-node","id":1,"kind":"column"},
        {"op":"create-node","id":2,"kind":"image"},
        {"op":"set-prop","id":2,"property":"url","value":"file:///tmp/fractional.png"},
        {"op":"set-prop","id":2,"property":"width","value":92},
        {"op":"set-prop","id":2,"property":"height","value":63.25},
        {"op":"set-prop","id":2,"property":"max-width","value":127.75},
        {"op":"set-prop","id":2,"property":"max-height","value":200.5},
        {"op":"insert-child","parent":1,"child":2,"index":0}
    ]))).unwrap();
    renderer.set_root(1).unwrap();
    let change = renderer.clone();
    view().child(renderer.element()).child(nsh_base::button()
        .child(text("Update fractional geometry")).on_press(move || {
            let node = change.0.borrow().store.nodes[&2].incarnation;
            assert!(change.apply(patch(2, json!([
                {"op":"set-prop","id":2,"property":"max-height","value":63}
            ]))).is_err());
            assert_eq!(change.0.borrow().store.generation, 1);
            change.apply(patch(2, json!([
                {"op":"set-prop","id":2,"property":"height","value":64.125},
                {"op":"set-prop","id":2,"property":"max-width","value":128.125},
                {"op":"set-prop","id":2,"property":"max-height","value":201.25}
            ]))).unwrap();
            assert_eq!(change.0.borrow().store.nodes[&2].incarnation, node);
        }))
}

#[test]
fn fractional_image_geometry_is_exact_and_updates_without_native_remount() {
    let mut app = Headless::start(EngineConfig::new(Root::of::<FractionalImageScenario>())).unwrap();
    app.wait_for("id:lui-2").unwrap();
    let before = app.screen().layout_nodes().into_iter()
        .find(|node| node.test_id.as_deref() == Some("lui-2")).unwrap();
    assert_eq!(before.bounds.size.width, px(92.0));
    assert_eq!(before.bounds.size.height, px(63.25));
    app.press("Update fractional geometry").unwrap();
    let after = app.screen().layout_nodes().into_iter()
        .find(|node| node.test_id.as_deref() == Some("lui-2")).unwrap();
    assert_eq!(after.id, before.id);
    assert_eq!(after.bounds.size.height, px(64.125));
}

#[component]
fn ImageScenario() -> impl IntoElement {
    let loads = Arc::new(Mutex::new(Vec::new()));
    let seen = loads.clone();
    let renderer = Renderer::new(move |event, _| seen.lock().unwrap().push(event));
    renderer
        .apply(patch(
            1,
            json!([
                {"op":"create-node","id":1,"kind":"column"},
                {"op":"create-node","id":2,"kind":"image"},
                {"op":"set-prop","id":2,"property":"url","value":"file:///tmp/image-a.png"},
                {"op":"set-prop","id":2,"property":"alt","value":"Canonical image"},
                {"op":"set-prop","id":2,"property":"width","value":100},
                {"op":"set-prop","id":2,"property":"height","value":60},
                {"op":"create-node","id":3,"kind":"text-field"},
                {"op":"set-prop","id":3,"property":"text","value":"retained draft"},
                {"op":"insert-child","parent":1,"child":2,"index":0},
                {"op":"insert-child","parent":1,"child":3,"index":1}
            ]),
        ))
        .unwrap();
    renderer.set_root(1).unwrap();
    let change = renderer.clone();
    let reject = renderer.clone();
    let recreate = renderer.clone();
    view().child(renderer.element())
        .child(nsh_base::button().child(text("Change image")).on_press(move || {
            change.apply(patch(2,json!([
                {"op":"set-prop","id":2,"property":"url","value":"file:///tmp/image-b.png"},
                {"op":"set-prop","id":2,"property":"image-fit","value":"fit"},
                {"op":"set-prop","id":2,"property":"alt","value":"Updated image"}
            ]))).unwrap();
            assert_eq!(crate::images::source(&change.0.borrow().nodes[&2].node.get_untracked()),
                nsh_core::element::ImageSrc::from("file:///tmp/image-b.png"));
        }))
        .child(nsh_base::button().child(text("Reject image")).on_press(move || {
            let image = reject.0.borrow().nodes[&2].node.get_untracked();
            let editor = reject.0.borrow().nodes[&3].node.get_untracked();
            for properties in [
                json!({"image":0}), json!({"image":42}),
                json!({"source-x":0.0,"source-y":0.0,"source-width":10.0,"source-height":10.0}),
                json!({"loading":"lazy"}), json!({"referrer-policy":"no-referrer"})
            ] {
                let mut ops = vec![json!({"op":"set-prop","id":3,"property":"text","value":"must not publish"})];
                ops.extend(properties.as_object().unwrap().iter().map(|(property,value)|
                    json!({"op":"set-prop","id":2,"property":property,"value":value})));
                assert!(reject.apply(patch(3,Value::Array(ops))).is_err());
                assert_eq!(reject.0.borrow().store.generation,2);
                assert!(Arc::ptr_eq(&image,&reject.0.borrow().nodes[&2].node.get_untracked()));
                assert!(Arc::ptr_eq(&editor,&reject.0.borrow().nodes[&3].node.get_untracked()));
            }
            reject.apply(patch(3,json!([
                {"op":"set-prop","id":2,"property":"loading","value":"eager"},
                {"op":"set-prop","id":2,"property":"image-fit","value":"fill"}
            ]))).unwrap();
        }))
        .child(nsh_base::button().child(text("Recreate image")).on_press(move || {
            let old = recreate.0.borrow().store.nodes[&2].incarnation;
            recreate.apply(patch(4,json!([
                {"op":"drop-node","id":2},
                {"op":"create-node","id":2,"kind":"image"},
                {"op":"set-prop","id":2,"property":"url","value":"file:///tmp/image-c.png"},
                {"op":"set-prop","id":2,"property":"width","value":100},
                {"op":"set-prop","id":2,"property":"height","value":60},
                {"op":"insert-child","parent":1,"child":2,"index":0}
            ]))).unwrap();
            recreate.emit(2,old,Event::Load(2));
            assert!(loads.lock().unwrap().is_empty());
            let current = recreate.0.borrow().store.nodes[&2].incarnation;
            assert_ne!(old,current);
            recreate.emit(2,current,Event::Load(2));
            assert_eq!(*loads.lock().unwrap(),[Event::Load(2)]);
        }))
}

#[test]
fn url_fit_and_atomic_rejections_keep_the_image_and_editor_native_identity() {
    let mut app = Headless::start(EngineConfig::new(Root::of::<ImageScenario>())).unwrap();
    app.wait_for("id:lui-2").unwrap();
    let before = app.screen().layout_nodes();
    let image = before
        .iter()
        .find(|node| node.test_id.as_deref() == Some("lui-2"))
        .unwrap()
        .id;
    let editor = before
        .iter()
        .find(|node| node.test_id.as_deref() == Some("lui-3"))
        .unwrap()
        .id;
    app.type_text("id:lui-3", " edited").unwrap();
    app.press("text:Change image").unwrap();
    app.wait_for("label:Updated image").unwrap();
    app.press("text:Reject image").unwrap();
    let after = app.screen().layout_nodes();
    assert_eq!(
        after
            .iter()
            .find(|node| node.test_id.as_deref() == Some("lui-2"))
            .unwrap()
            .id,
        image
    );
    assert_eq!(
        after
            .iter()
            .find(|node| node.test_id.as_deref() == Some("lui-3"))
            .unwrap()
            .id,
        editor
    );
    assert_eq!(
        app.screen().input_text("id:lui-3").unwrap(),
        Some("retained draft edited")
    );
    app.press("text:Recreate image").unwrap();
    app.wait_for("id:lui-2").unwrap();
    assert_ne!(
        app.screen()
            .layout_nodes()
            .iter()
            .find(|node| node.test_id.as_deref() == Some("lui-2"))
            .unwrap()
            .id,
        image
    );
}
