use super::*;
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use serde_json::json;
use std::sync::Mutex;

#[derive(Clone, Default)]
struct Seen(Arc<Mutex<Vec<Event>>>);

fn batch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}

#[component]
fn LocalImages() -> impl IntoElement {
    let seen = engine_context::<Seen>().unwrap();
    let renderer = Renderer::new(move |event, _| seen.0.lock().unwrap().push(event));
    renderer.apply(batch(1, json!([
        {"op":"create-node","id":1,"kind":"column"},
        {"op":"create-node","id":2,"kind":"file-image"},
        {"op":"set-prop","id":2,"property":"path","value":"Assets/composer.png"},
        {"op":"set-prop","id":2,"property":"max-pixel-size","value":384},
        {"op":"set-prop","id":2,"property":"image-fit","value":"fill"},
        {"op":"set-prop","id":2,"property":"width","value":128},
        {"op":"set-prop","id":2,"property":"height","value":128},
        {"op":"set-prop","id":2,"property":"accessibility-label","value":"Composer attachment"},
        {"op":"set-prop","id":2,"property":"press-enabled","value":true},
        {"op":"create-node","id":3,"kind":"text-field"},
        {"op":"set-prop","id":3,"property":"text","value":"draft"},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":3,"index":1}
    ]))).unwrap();
    renderer.set_root(1).unwrap();
    let update = renderer.clone();
    let reject = renderer.clone();
    view().child(renderer.element())
        .child(nsh_base::button().child(text("Journal image")).on_press(move || {
            update.apply(batch(2, json!([
                {"op":"set-prop","id":2,"property":"path","value":"Assets/journal.png"},
                {"op":"set-prop","id":2,"property":"max-pixel-size","value":1024},
                {"op":"set-prop","id":2,"property":"width","value":190},
                {"op":"set-prop","id":2,"property":"height","value":90},
                {"op":"set-prop","id":2,"property":"accessibility-label","value":"Journal attachment"}
            ]))).unwrap();
        }))
        .child(nsh_base::button().child(text("Reject unsupported file source")).on_press(move || {
            let before = reject.0.borrow().nodes[&2].node.get_untracked();
            for (property, value) in [("path", json!("https://example.com/a.png")), ("max-pixel-size", json!(4097))] {
                assert!(reject.apply(batch(3, json!([
                    {"op":"set-prop","id":3,"property":"text","value":"must not publish"},
                    {"op":"set-prop","id":2,"property":property,"value":value}
                ]))).is_err());
                assert_eq!(reject.0.borrow().store.generation, 2);
                assert!(Arc::ptr_eq(&before, &reject.0.borrow().nodes[&2].node.get_untracked()));
            }
        }))
}

#[test]
fn file_image_live_path_cap_and_fit_keep_native_host_and_reject_atomically() {
    let seen = Seen::default();
    let mut config = EngineConfig::new(Root::of::<LocalImages>());
    config.context = EngineContext::default().with(seen.clone());
    let mut app = Headless::start(config).unwrap();
    app.wait_for("id:lui-2").unwrap();
    let ids = |app: &Headless| {
        ["lui-2", "lui-3"].map(|id| {
            app.screen()
                .layout_nodes()
                .iter()
                .find(|node| node.test_id.as_deref() == Some(id))
                .unwrap()
                .id
        })
    };
    let before = ids(&app);
    app.press("id:lui-2").unwrap();
    assert_eq!(*seen.0.lock().unwrap(), [Event::Press(2)]);
    app.type_text("id:lui-3", " edited").unwrap();
    app.press("text:Journal image").unwrap();
    app.wait_for("label:Journal attachment").unwrap();
    app.press("text:Reject unsupported file source").unwrap();
    assert_eq!(ids(&app), before);
    assert_eq!(
        app.screen().input_text("id:lui-3").unwrap(),
        Some("draft edited")
    );
    let image = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some("lui-2"))
        .unwrap();
    assert_eq!(image.bounds.size.width, px(190.0));
    assert_eq!(image.bounds.size.height, px(90.0));
}
