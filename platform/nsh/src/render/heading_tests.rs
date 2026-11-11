//! Native heading semantics and identity, independent of OS screen-reader output.
use crate::{
    render::{Event, Renderer},
    wire::Batch,
};
use nsh_core::prelude::*;
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
use serde_json::{Value, json};
use std::{cell::Cell, rc::Rc};

fn publish(renderer: &Renderer, revision: &Cell<u64>, operations: Value) -> Result<(), String> {
    let next = revision.get() + 1;
    renderer
        .apply(Batch::decode(&json!({"generation":next,"ops":operations}).to_string()).unwrap())?;
    revision.set(next);
    Ok(())
}

#[component]
fn HeadingScenario() -> impl IntoElement {
    let revision = Rc::new(Cell::new(0));
    let edited = revision.clone();
    let renderer = Renderer::new(move |event, renderer| {
        if let Event::Text(id, text) = event {
            publish(
                &renderer,
                &edited,
                json!([
                    {"op":"set-prop","id":id,"property":"text","value":text}
                ]),
            )
            .unwrap();
        }
    });
    publish(&renderer, &revision, json!([
        {"op":"create-node","id":1,"kind":"column"},
        {"op":"create-node","id":2,"kind":"heading"},
        {"op":"set-prop","id":2,"property":"text","value":"Heading"},
        {"op":"set-prop","id":2,"property":"accessibility-identifier","value":"retained-heading"},
        {"op":"create-node","id":3,"kind":"text-field"},
        {"op":"set-prop","id":3,"property":"text","value":"draft"},
        {"op":"set-prop","id":3,"property":"change-enabled","value":true},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":3,"index":1}
    ])).unwrap();
    renderer.set_root(1).unwrap();
    let mut controls = Vec::new();
    for level in 1..=6 {
        let change = renderer.clone();
        let revision = revision.clone();
        controls.push(
            nsh_base::button()
                .child(text(format!("Level {level}")))
                .on_press(move || {
                    publish(
                        &change,
                        &revision,
                        json!([
                            {"op":"set-prop","id":2,"property":"heading-level","value":level}
                        ]),
                    )
                    .unwrap();
                })
                .into_element(),
        );
    }
    let authored = renderer.clone();
    let source = revision.clone();
    controls.push(
        nsh_base::button()
            .child(text("Author typography"))
            .on_press(move || {
                publish(
                    &authored,
                    &source,
                    json!([
                        {"op":"set-prop","id":2,"property":"font-size","value":"19px"},
                        {"op":"set-prop","id":2,"property":"font-weight","value":500},
                        {"op":"set-prop","id":2,"property":"foreground","value":"#123456"}
                    ]),
                )
                .unwrap();
            })
            .into_element(),
    );
    let reset = renderer.clone();
    let source = revision.clone();
    controls.push(
        nsh_base::button()
            .child(text("Restore defaults"))
            .on_press(move || {
                publish(
                    &reset,
                    &source,
                    json!([
                        {"op":"remove-prop","id":2,"property":"heading-level"},
                        {"op":"remove-prop","id":2,"property":"font-size"},
                        {"op":"remove-prop","id":2,"property":"font-weight"},
                        {"op":"remove-prop","id":2,"property":"foreground"},
                        {"op":"set-prop","id":2,"property":"text","value":"Renamed heading"}
                    ]),
                )
                .unwrap();
            })
            .into_element(),
    );
    let reject = renderer.clone();
    controls.push(nsh_base::button().child(text("Reject invalid heading")).on_press(move || {
        for invalid in [json!({"heading-level":0}), json!({"heading-level":7}),
                        json!({"accessibility-label":"Unsupported label"})] {
            let mut operations = vec![json!({"op":"set-prop","id":3,"property":"text","value":"must not publish"})];
            operations.extend(invalid.as_object().unwrap().iter().map(|(property,value)|
                json!({"op":"set-prop","id":2,"property":property,"value":value})));
            assert!(publish(&reject, &revision, Value::Array(operations)).is_err());
        }
        publish(&reject, &revision, json!([
            {"op":"set-prop","id":2,"property":"heading-level","value":3}
        ])).unwrap();
    }).into_element());
    view()
        .flex_col()
        .child(renderer.element())
        .child(view().flex_row().flex_wrap().child(controls))
}

fn native_id(app: &Headless, identifier: &str) -> nsh_core::NodeId {
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some(identifier))
        .unwrap()
        .id
}

#[test]
fn heading_default_and_live_levels_keep_the_actual_text_and_editor_identity() {
    let mut app = Headless::start(EngineConfig::new(Root::of::<HeadingScenario>())).unwrap();
    app.wait_for("role:header[Heading]").unwrap();
    assert_eq!(
        app.screen()
            .accessibility_level("id:retained-heading")
            .unwrap(),
        Some(2)
    );
    let defaults = app.screen().span_style("text:Heading").unwrap();
    assert_eq!(defaults.font_size.0, 24.0);
    assert_eq!(defaults.font_weight, 700);
    let heading = native_id(&app, "retained-heading");
    let editor = native_id(&app, "lui-3");
    app.type_text("id:lui-3", " kept").unwrap();
    for (level, size) in [
        (1, 30.0),
        (2, 24.0),
        (3, 20.0),
        (4, 18.0),
        (5, 16.0),
        (6, 14.0),
    ] {
        app.press(&format!("text:Level {level}")).unwrap();
        assert_eq!(
            app.screen()
                .accessibility_level("id:retained-heading")
                .unwrap(),
            Some(level)
        );
        let style = app.screen().span_style("text:Heading").unwrap();
        assert_eq!(style.font_size.0, size);
        assert_eq!(style.font_weight, 700);
        assert_eq!(native_id(&app, "retained-heading"), heading);
        assert_eq!(native_id(&app, "lui-3"), editor);
        assert_eq!(
            app.screen().input_text("id:lui-3").unwrap(),
            Some("draft kept")
        );
    }
}

#[test]
fn heading_authored_styles_override_presets_and_invalid_changes_roll_back_atomically() {
    let mut app = Headless::start(EngineConfig::new(Root::of::<HeadingScenario>())).unwrap();
    app.wait_for("role:header[Heading]").unwrap();
    let heading = native_id(&app, "retained-heading");
    app.type_text("id:lui-3", " kept").unwrap();
    app.press("text:Author typography").unwrap();
    app.press("text:Level 1").unwrap();
    let style = app.screen().span_style("text:Heading").unwrap();
    assert_eq!(style.font_size.0, 19.0);
    assert_eq!(style.font_weight, 500);
    assert_eq!(style.color, nsh_core::Color::parse("#123456").unwrap());
    assert_eq!(
        app.screen()
            .accessibility_level("id:retained-heading")
            .unwrap(),
        Some(1)
    );
    app.press("text:Restore defaults").unwrap();
    app.wait_for("role:header[Renamed heading]").unwrap();
    let style = app.screen().span_style("text:Renamed heading").unwrap();
    assert_eq!(style.font_size.0, 24.0);
    assert_eq!(style.font_weight, 700);
    assert_eq!(
        app.screen()
            .accessibility_level("id:retained-heading")
            .unwrap(),
        Some(2)
    );
    app.press("text:Reject invalid heading").unwrap();
    assert_eq!(
        app.screen()
            .accessibility_level("id:retained-heading")
            .unwrap(),
        Some(3)
    );
    assert_eq!(native_id(&app, "retained-heading"), heading);
    assert_eq!(
        app.screen().input_text("id:lui-3").unwrap(),
        Some("draft kept")
    );
    assert_eq!(app.screen().count("text:Unsupported label").unwrap(), 0);
}
