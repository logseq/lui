//! A nested application stack must pass its assigned cell size to retained content.
use crate::{
    render::{Event, Renderer},
    wire::Batch,
};
use nsh_core::prelude::*;
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use serde_json::json;
use std::sync::{Arc, Mutex};

#[derive(Clone)]
struct Presses(Arc<Mutex<Vec<u64>>>);

#[component]
fn NestedShell() -> impl IntoElement {
    let presses = engine_context::<Presses>().unwrap();
    let renderer = Renderer::new(move |event, _| {
        if let Event::Press(id) = event {
            presses.0.lock().unwrap().push(id);
        }
    });
    renderer
        .apply(
            Batch::decode(
                &json!({"generation":1,"ops":[
                    {"op":"create-node","id":1,"kind":"stack"},
                    {"op":"set-prop","id":1,"property":"width","value":1440},
                    {"op":"set-prop","id":1,"property":"height","value":900},
                    {"op":"create-node","id":2,"kind":"stack"},
                    {"op":"insert-child","parent":1,"child":2,"index":0},
                    {"op":"create-node","id":3,"kind":"column"},
                    {"op":"set-prop","id":3,"property":"grow","value":1},
                    {"op":"set-prop","id":3,"property":"min-height","value":0},
                    {"op":"insert-child","parent":2,"child":3,"index":0},
                    {"op":"create-node","id":4,"kind":"button"},
                    {"op":"set-prop","id":4,"property":"text","value":"Shell header"},
                    {"op":"set-prop","id":4,"property":"height","value":48},
                    {"op":"set-prop","id":4,"property":"press-enabled","value":true},
                    {"op":"insert-child","parent":3,"child":4,"index":0},
                    {"op":"create-node","id":5,"kind":"row"},
                    {"op":"set-prop","id":5,"property":"grow","value":1},
                    {"op":"set-prop","id":5,"property":"min-height","value":0},
                    {"op":"set-prop","id":5,"property":"cross","value":"stretch"},
                    {"op":"insert-child","parent":3,"child":5,"index":1},
                    {"op":"create-node","id":6,"kind":"text-field"},
                    {"op":"set-prop","id":6,"property":"text","value":"Draft"},
                    {"op":"set-prop","id":6,"property":"height","value":28},
                    {"op":"set-prop","id":6,"property":"width","value":240},
                    {"op":"insert-child","parent":5,"child":6,"index":0},
                    {"op":"create-node","id":7,"kind":"overlay"},
                    {"op":"set-prop","id":7,"property":"pointer-enabled","value":false},
                    {"op":"insert-child","parent":1,"child":7,"index":1}
                ]})
                .to_string(),
            )
            .unwrap(),
        )
        .unwrap();
    renderer.set_root(1).unwrap();
    let resize = renderer.clone();
    on_key_with(
        "f8",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            resize
                .apply(
                    Batch::decode(
                        &json!({"generation":2,"ops":[
                            {"op":"set-prop","id":1,"property":"height","value":620}
                        ]})
                        .to_string(),
                    )
                    .unwrap(),
                )
                .unwrap();
        },
    );
    renderer.element()
}

#[test]
fn nested_stack_fills_available_cell_and_keeps_editor_through_resize() {
    let presses = Arc::new(Mutex::new(Vec::new()));
    let mut config = EngineConfig::new(Root::of::<NestedShell>());
    config.context = EngineContext::default().with(Presses(presses.clone()));
    config.environment.os = nsh_core::platform::Os::MacOs;
    let mut app = Headless::start(config).unwrap();
    app.first_render().unwrap();
    let find = |app: &Headless, id: u64| {
        app.screen()
            .layout_nodes()
            .into_iter()
            .find(|node| node.test_id.as_deref() == Some(format!("lui-{id}").as_str()))
            .unwrap()
    };
    let editor = find(&app, 6).id;
    assert_eq!(find(&app, 2).bounds.size.height, px(900.0));
    assert_eq!(find(&app, 3).bounds.size.height, px(900.0));
    assert_eq!(find(&app, 4).bounds.size.height, px(48.0));
    assert_eq!(find(&app, 5).bounds.size.height, px(852.0));
    app.press("Shell header").unwrap();
    assert_eq!(*presses.lock().unwrap(), [4]);
    app.type_text("id:lui-6", "Edited").unwrap();
    let draft = app
        .screen()
        .input_text("id:lui-6")
        .unwrap()
        .unwrap()
        .to_owned();
    app.press_key("f8").unwrap();
    assert_eq!(find(&app, 2).bounds.size.height, px(620.0));
    assert_eq!(find(&app, 3).bounds.size.height, px(620.0));
    assert_eq!(find(&app, 5).bounds.size.height, px(572.0));
    assert_eq!(find(&app, 6).id, editor);
    app.press_key("x").unwrap();
    assert_eq!(
        app.screen().input_text("id:lui-6").unwrap(),
        Some(format!("{draft}x").as_str())
    );
}
