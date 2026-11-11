//! Native visibility supplies the AX subtree exclusion that zero layout frames lack.
use super::*;
use crate::{
    render::{Event, Renderer},
    wire::Batch,
};
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use serde_json::json;
use std::{cell::Cell, rc::Rc, sync::Mutex};

#[derive(Clone)]
struct Presses(Arc<Mutex<Vec<u64>>>);

fn patch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}

#[component]
fn VisibilityScenario() -> impl IntoElement {
    let presses = engine_context::<Presses>().unwrap();
    let generation = Rc::new(Cell::new(1));
    let text_generation = generation.clone();
    let renderer = Renderer::new(move |event, renderer| match event {
        Event::Press(id) => presses.0.lock().unwrap().push(id),
        Event::Text(id, text) => {
            let next = text_generation.get() + 1;
            renderer
                .apply(patch(
                    next,
                    json!([
                        {"op":"set-prop","id":id,"property":"text","value":text}
                    ]),
                ))
                .unwrap();
            text_generation.set(next);
        }
        _ => {}
    });
    let mut operations = vec![
        json!({"op":"create-node","id":1,"kind":"column"}),
        json!({"op":"set-prop","id":1,"property":"gap","value":4}),
        json!({"op":"create-node","id":10,"kind":"box"}),
        json!({"op":"set-prop","id":10,"property":"display","value":"block"}),
        json!({"op":"create-node","id":11,"kind":"box"}),
        json!({"op":"set-prop","id":11,"property":"display","value":"block"}),
        json!({"op":"insert-child","parent":10,"child":11,"index":0}),
        json!({"op":"create-node","id":13,"kind":"text-field"}),
        json!({"op":"set-prop","id":13,"property":"text","value":"Draft"}),
        json!({"op":"set-prop","id":13,"property":"change-enabled","value":true}),
        json!({"op":"set-prop","id":13,"property":"width","value":200}),
    ];
    for (id, label) in [(2, "Before"), (12, "Nested action"), (20, "After")] {
        operations.extend([
            json!({"op":"create-node","id":id,"kind":"button"}),
            json!({"op":"set-prop","id":id,"property":"text","value":label}),
            json!({"op":"set-prop","id":id,"property":"press-enabled","value":true}),
            json!({"op":"set-prop","id":id,"property":"pointer-enabled","value":true}),
            json!({"op":"set-prop","id":id,"property":"width","value":200}),
            json!({"op":"set-prop","id":id,"property":"height","value":40}),
        ]);
    }
    operations.extend([
        json!({"op":"insert-child","parent":11,"child":12,"index":0}),
        json!({"op":"insert-child","parent":11,"child":13,"index":1}),
        json!({"op":"insert-child","parent":1,"child":2,"index":0}),
        json!({"op":"insert-child","parent":1,"child":10,"index":1}),
        json!({"op":"insert-child","parent":1,"child":20,"index":2}),
    ]);
    renderer.apply(patch(1, Value::Array(operations))).unwrap();
    renderer.set_root(1).unwrap();
    for (key, operations) in [
        (
            "f6",
            json!([{"op":"set-prop","id":10,"property":"display","value":"none"}]),
        ),
        (
            "f7",
            json!([{"op":"set-prop","id":10,"property":"display","value":"block"}]),
        ),
        (
            "f8",
            json!([
                {"op":"remove-prop","id":10,"property":"display"},
                {"op":"set-prop","id":11,"property":"display","value":"none"}
            ]),
        ),
        (
            "f9",
            json!([{"op":"remove-prop","id":11,"property":"display"}]),
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
            move |_| {
                let next = generation.get() + 1;
                renderer.apply(patch(next, operations.clone())).unwrap();
                generation.set(next);
            },
        );
    }
    renderer.element()
}

fn native(app: &Headless, id: u64) -> nsh_testing::LayoutNode {
    let name = format!("lui-{id}");
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some(name.as_str()))
        .unwrap()
}

#[test]
fn display_none_visibility_is_local_and_normal_display_does_not_override_ancestors() {
    let theme = ThemeView::new(
        Arc::new(nsh_base::Theme::default().tokens().clone()),
        false,
        false,
    );
    let mut node = Node {
        kind: "box".into(),
        ..Default::default()
    };
    for display in [Some("none"), Some("block"), None] {
        node.props.clear();
        if let Some(value) = display {
            node.props.insert("display".into(), json!(value));
        }
        let compiled = compile(&node, &theme, Size::default()).unwrap();
        let visibility = compiled
            .decls()
            .iter()
            .filter_map(|decl| match decl {
                StyleDecl::Set(StyleKey::Visibility, PropertyValue::Bool(value)) => Some(*value),
                _ => None,
            })
            .collect::<Vec<_>>();
        assert_eq!(
            visibility,
            if display == Some("none") {
                vec![true]
            } else {
                Vec::new()
            }
        );
    }
}

#[test]
fn display_none_projects_native_ax_visibility_excludes_focus_and_restores_retained_children() {
    let presses = Arc::new(Mutex::new(Vec::new()));
    let mut config = EngineConfig::new(Root::of::<VisibilityScenario>());
    config.context = EngineContext::default().with(Presses(presses.clone()));
    config.environment.os = nsh_core::platform::Os::MacOs;
    let mut app = Headless::start(config).unwrap();
    app.wait_for("Nested action").unwrap();
    let parent = native(&app, 10).id;
    let inner = native(&app, 11).id;
    let button = native(&app, 12).id;
    let editor = native(&app, 13).id;
    let visibility = Arc::new(Mutex::new(Vec::new()));
    let observed = visibility.clone();
    app.observe(move |_, batch| {
        for item in &batch.items {
            if let nsh_core::MountItem::ViewStyle { id, style } = item {
                observed.lock().unwrap().push((*id, style.hidden));
            }
        }
    });
    app.type_text("id:lui-13", " retained").unwrap();
    let draft = app
        .screen()
        .input_text("id:lui-13")
        .unwrap()
        .unwrap()
        .to_owned();
    app.press_key("tab").unwrap();
    app.press_key("enter").unwrap();
    assert_eq!(*presses.lock().unwrap(), [20]);
    app.press_key("f6").unwrap();
    assert!(visibility.lock().unwrap().contains(&(parent, true)));
    // The native AX implementations prune this same hidden ViewStyle before
    // walking its descendants. Headless exposes its mount projection, not OS AX.
    for id in [10, 11, 12, 13] {
        assert!(
            native(&app, id).hidden,
            "ordinary block/explicit pointer Auto cannot unhide descendants"
        );
    }
    assert!(!app.screen().matches("role:button[Nested action]").unwrap());
    assert!(app.press("Nested action").is_err());
    presses.lock().unwrap().clear();
    app.press_key("tab").unwrap();
    app.press_key("enter").unwrap();
    app.press_key("tab").unwrap();
    app.press_key("enter").unwrap();
    assert_eq!(
        *presses.lock().unwrap(),
        [2, 20],
        "Tab skips the hidden control and editor"
    );
    app.press_key("f7").unwrap();
    assert!(visibility.lock().unwrap().contains(&(parent, false)));
    assert!(app.screen().matches("role:button[Nested action]").unwrap());
    assert_eq!(native(&app, 12).id, button);
    assert_eq!(native(&app, 13).id, editor);
    assert_eq!(
        app.screen().input_text("id:lui-13").unwrap(),
        Some(draft.as_str())
    );
    app.press_key("tab").unwrap();
    app.press_key("tab").unwrap();
    app.press_key("enter").unwrap();
    assert_eq!(presses.lock().unwrap().last(), Some(&12));
    app.press_key("f8").unwrap();
    assert!(!native(&app, 10).hidden);
    assert!(native(&app, 11).hidden);
    assert!(visibility.lock().unwrap().contains(&(inner, true)));
    app.press_key("f9").unwrap();
    for id in [10, 11, 12, 13] {
        assert!(!native(&app, id).hidden);
    }
    assert!(visibility.lock().unwrap().contains(&(inner, false)));
    assert_eq!(native(&app, 10).id, parent);
    assert_eq!(native(&app, 11).id, inner);
    assert_eq!(native(&app, 12).id, button);
    assert_eq!(native(&app, 13).id, editor);
    assert_eq!(
        app.screen().input_text("id:lui-13").unwrap(),
        Some(draft.as_str())
    );
    app.press("Nested action").unwrap();
    assert_eq!(presses.lock().unwrap().last(), Some(&12));
}
