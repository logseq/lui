//! Optional native dialog labels must not reserve empty layout slots.
use crate::{
    render::{Event, Renderer},
    wire::Batch,
};
use nsh_core::prelude::*;
use nsh_engine::{EngineConfig, Root};
use nsh_testing::{Headless, LayoutNode};
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
};

fn publish(renderer: &Renderer, generation: Signal<u64>, ops: Value) {
    let next = generation.get_untracked() + 1;
    renderer
        .apply(Batch::decode(&json!({"generation":next,"ops":ops}).to_string()).unwrap())
        .unwrap();
    generation.set(next);
}

#[component]
fn OptionalHeaders() -> impl IntoElement {
    let generation = signal(0);
    let renderer = Renderer::new(move |event, renderer| {
        if let Event::Text(id, value) = event {
            publish(
                &renderer,
                generation,
                json!([
                    {"op":"set-prop","id":id,"property":"text","value":value}
                ]),
            );
        }
    });
    publish(
        &renderer,
        generation,
        json!([
            {"op":"create-node","id":1,"kind":"dialog"},
            {"op":"set-prop","id":1,"property":"width","value":400},
            {"op":"set-prop","id":1,"property":"padding","value":0},
            {"op":"set-prop","id":1,"property":"gap","value":17},
            {"op":"create-node","id":2,"kind":"input"},
            {"op":"set-prop","id":2,"property":"width","value":280},
            {"op":"set-prop","id":2,"property":"height","value":32},
            {"op":"set-prop","id":2,"property":"text","value":"draft"},
            {"op":"set-prop","id":2,"property":"change-enabled","value":true},
            {"op":"insert-child","parent":1,"child":2,"index":0}
        ]),
    );
    renderer.set_root(1).unwrap();
    for (key, ops) in [
        (
            "f2",
            json!([
                {"op":"set-prop","id":1,"property":"text","value":"Dialog title"}
            ]),
        ),
        (
            "f3",
            json!([
                {"op":"set-prop","id":1,"property":"description","value":"Dialog description"}
            ]),
        ),
        (
            "f4",
            json!([
                {"op":"set-prop","id":1,"property":"text","value":""}
            ]),
        ),
        (
            "f5",
            json!([
                {"op":"remove-prop","id":1,"property":"description"}
            ]),
        ),
    ] {
        let renderer = renderer.clone();
        on_key_with(
            key,
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| publish(&renderer, generation, ops.clone()),
        );
    }
    renderer.element()
}

fn input(app: &Headless) -> LayoutNode {
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some("lui-2"))
        .expect("retained authored input")
}
fn panel(app: &Headless) -> LayoutNode {
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.is_none() && (node.bounds.size.width.0 - 400.).abs() < 0.01)
        .expect("native dialog panel with authored width")
}
fn panel_height(app: &Headless) -> f32 {
    panel(app).bounds.size.height.0
}
fn text_height(app: &Headless, value: &str) -> f32 {
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| {
            node.text
                .as_ref()
                .is_some_and(|text| text.text.text.as_str() == value)
        })
        .expect("present dialog label")
        .bounds
        .size
        .height
        .0
}
fn near(actual: f32, expected: f32) {
    assert!(
        (actual - expected).abs() <= 1.,
        "actual={actual}, expected={expected}"
    );
}
fn retained(app: &Headless, initial: &LayoutNode, draft: &str) {
    assert_eq!(input(app).id, initial.id);
    assert_eq!(app.screen().input_text("id:lui-2").unwrap(), Some(draft));
}

#[test]
fn absent_live_dialog_headers_reserve_no_gap_and_retain_authored_editor() {
    let mut config = EngineConfig::new(Root::of::<OptionalHeaders>());
    config.viewport = nsh_core::geometry::Size::new(Points(640.), Points(480.));
    config.environment.os = nsh_core::platform::Os::MacOs;
    config.environment.idiom = nsh_core::platform::Idiom::Desktop;
    config.environment.reduce_motion = true;
    let mut app = Headless::start(config).unwrap();
    let styles = Arc::new(Mutex::new(HashMap::new()));
    let observed = styles.clone();
    app.observe(move |_, batch| {
        for item in &batch.items {
            if let nsh_core::MountItem::ViewStyle { id, style } = item {
                observed.lock().unwrap().insert(*id, style.borders.widths);
            }
        }
    });
    app.wait_for("id:lui-2").unwrap();
    let initial = input(&app);
    let empty_panel = panel(&app);
    let empty_height = empty_panel.bounds.size.height.0;
    let borders = styles.lock().unwrap()[&empty_panel.id];
    // Padding is authored as zero. Derive both border insets from the actual
    // native mount style, so a reserved empty header/gap cannot hide in them.
    near(
        empty_height,
        initial.bounds.size.height.0 + borders.top.0 + borders.bottom.0,
    );
    let top_inset = initial.bounds.origin.y.0 - empty_panel.bounds.origin.y.0;
    let bottom_inset = empty_panel.bounds.origin.y.0 + empty_height
        - initial.bounds.origin.y.0
        - initial.bounds.size.height.0;
    assert!((top_inset - borders.top.0).abs() < 0.01);
    assert!((bottom_inset - borders.bottom.0).abs() < 0.01);
    app.type_text("id:lui-2", " retained").unwrap();
    let draft = app
        .screen()
        .input_text("id:lui-2")
        .unwrap()
        .unwrap()
        .to_owned();

    app.press_key("f2").unwrap();
    app.wait_for("text:Dialog title").unwrap();
    let title_height = text_height(&app, "Dialog title");
    near(panel_height(&app), empty_height + title_height + 17.);
    retained(&app, &initial, &draft);
    // Header insertion must not steal the actual editing focus.
    app.press_key("x").unwrap();
    let edited = app
        .screen()
        .input_text("id:lui-2")
        .unwrap()
        .unwrap()
        .to_owned();
    assert_ne!(edited, draft);

    app.press_key("f3").unwrap();
    app.wait_for("text:Dialog description").unwrap();
    let description_height = text_height(&app, "Dialog description");
    near(
        panel_height(&app),
        empty_height + title_height + description_height + 34.,
    );
    retained(&app, &initial, &edited);
    app.press_key("f4").unwrap();
    near(panel_height(&app), empty_height + description_height + 17.);
    retained(&app, &initial, &edited);
    app.press_key("f5").unwrap();
    near(panel_height(&app), empty_height);
    retained(&app, &initial, &edited);
}
