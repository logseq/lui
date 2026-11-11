//! The canonical adapter keeps native MenuItem behavior while parts update.
use crate::{
    render::{Event, Renderer},
    wire::Batch,
};
use nsh_core::{NodeId, ViewKind, prelude::*};
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::{Headless, LayoutNode};
use serde_json::{Value, json};
use std::sync::{Arc, Mutex};

struct Observed(Arc<Mutex<Vec<Event>>>);
fn publish(renderer: &Renderer, generation: &Signal<u64>, operations: Value) {
    let next = generation.get_untracked() + 1;
    renderer
        .apply(Batch::decode(&json!({"generation":next,"ops":operations}).to_string()).unwrap())
        .unwrap();
    generation.set(next);
}
#[component]
fn MenuPartsScenario() -> impl IntoElement {
    let observed = engine_context::<Observed>().unwrap().0.clone();
    let generation = signal(0);
    let renderer = Renderer::new(move |event, renderer| {
        observed.lock().unwrap().push(event.clone());
        if let Event::Text(id, text) = event {
            publish(
                &renderer,
                &generation,
                json!([
                    {"op":"set-prop","id":id,"property":"text","value":text}
                ]),
            );
        }
    });
    publish(
        &renderer,
        &generation,
        json!([
            {"op":"create-node","id":1,"kind":"column"},
            {"op":"set-prop","id":1,"property":"width","value":360},
            {"op":"create-node","id":2,"kind":"menu-trigger"},
            {"op":"set-prop","id":2,"property":"text","value":"Options"},
            {"op":"create-node","id":3,"kind":"dropdown-menu"},
            {"op":"set-prop","id":3,"property":"width","value":300},
            {"op":"create-node","id":10,"kind":"menu-item"},
            {"op":"set-prop","id":10,"property":"text","value":"Save 中文"},
            {"op":"set-prop","id":10,"property":"icon","value":"plus"},
            {"op":"set-prop","id":10,"property":"selection-placement","value":"leading"},
            {"op":"set-prop","id":10,"property":"selected","value":true},
            {"op":"set-prop","id":10,"property":"variant","value":"destructive"},
            {"op":"set-prop","id":10,"property":"tooltip-keys","value":"⌘ S"},
            {"op":"set-prop","id":10,"property":"press-enabled","value":true},
            {"op":"create-node","id":11,"kind":"menu-item"},
            {"op":"set-prop","id":11,"property":"text","value":"Blocked"},
            {"op":"set-prop","id":11,"property":"enabled","value":false},
            {"op":"set-prop","id":11,"property":"press-enabled","value":true},
            {"op":"create-node","id":12,"kind":"menu-item"},
            {"op":"set-prop","id":12,"property":"text","value":"Last"},
            {"op":"set-prop","id":12,"property":"press-enabled","value":true},
            {"op":"create-node","id":20,"kind":"text"},
            {"op":"set-prop","id":20,"property":"text","value":"Extra"},
            {"op":"create-node","id":30,"kind":"text-field"},
            {"op":"set-prop","id":30,"property":"text","value":"draft"},
            {"op":"set-prop","id":30,"property":"change-enabled","value":true},
            {"op":"insert-child","parent":10,"child":20,"index":0},
            {"op":"insert-child","parent":3,"child":10,"index":0},
            {"op":"insert-child","parent":3,"child":11,"index":1},
            {"op":"insert-child","parent":3,"child":12,"index":2},
            {"op":"insert-child","parent":2,"child":3,"index":0},
            {"op":"insert-child","parent":1,"child":2,"index":0},
            {"op":"insert-child","parent":1,"child":30,"index":1}
        ]),
    );
    renderer.set_root(1).unwrap();
    for (key, operations) in [
        (
            "f5",
            json!([
                {"op":"set-prop","id":10,"property":"text","value":"Renamed 中文"},
                {"op":"set-prop","id":10,"property":"icon","value":"x"},
                {"op":"set-prop","id":10,"property":"selection-placement","value":"trailing"},
                {"op":"set-prop","id":10,"property":"selected","value":false},
                {"op":"set-prop","id":10,"property":"size","value":"lg"},
                {"op":"set-prop","id":10,"property":"variant","value":"primary"},
                {"op":"set-prop","id":10,"property":"tooltip-keys","value":"Ctrl R"}
            ]),
        ),
        (
            "f6",
            json!([
                {"op":"set-prop","id":10,"property":"selection-placement","value":"top"},
                {"op":"set-prop","id":10,"property":"selected","value":true}
            ]),
        ),
        (
            "f7",
            json!([
                {"op":"set-prop","id":10,"property":"font-size","value":"19px"},
                {"op":"set-prop","id":10,"property":"foreground","value":"#123456"}
            ]),
        ),
        (
            "f8",
            json!([
                {"op":"remove-prop","id":10,"property":"selected"},
                {"op":"remove-prop","id":10,"property":"icon"},
                {"op":"remove-prop","id":10,"property":"tooltip-keys"}
            ]),
        ),
        (
            "f9",
            json!([
                {"op":"set-prop","id":10,"property":"selected","value":true},
                {"op":"set-prop","id":10,"property":"icon","value":"plus"},
                {"op":"set-prop","id":10,"property":"tooltip-keys","value":"⌘ S"}
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
            move |_| {
                publish(&renderer, &generation, operations.clone());
            },
        );
    }
    view()
        .child(renderer.element())
        .child(text("Destructive reference").text_color(|| nsh_base::theme().destructive))
        .child(text("Primary reference").text_color(|| nsh_base::theme().primary_foreground))
}
fn start() -> (Headless, Arc<Mutex<Vec<Event>>>) {
    let observed = Arc::new(Mutex::new(Vec::new()));
    let mut config = EngineConfig {
        context: EngineContext::default().with(Observed(observed.clone())),
        ..EngineConfig::new(Root::of::<MenuPartsScenario>())
    };
    config.environment.reduce_motion = true;
    config.environment.os = nsh_core::platform::Os::Linux;
    let mut app = Headless::start(config).unwrap();
    app.wait_for("id:lui-30").unwrap();
    (app, observed)
}
fn native(app: &Headless, id: u64) -> LayoutNode {
    let id = format!("lui-{id}");
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some(id.as_str()))
        .unwrap()
}
fn by_native(app: &Headless, id: NodeId) -> LayoutNode {
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.id == id)
        .unwrap()
}
fn label(app: &Headless, text: &str) -> LayoutNode {
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| {
            node.text
                .as_ref()
                .is_some_and(|value| value.text.text == text)
        })
        .unwrap()
}
fn glyphs(app: &Headless) -> Vec<LayoutNode> {
    app.screen()
        .layout_nodes()
        .into_iter()
        .filter(|node| {
            node.kind == ViewKind::Canvas
                && !node.hidden
                && node.bounds.size.width > px(0.0)
                && node.bounds.size.height > px(0.0)
        })
        .collect()
}
#[test]
fn menu_item_icon_check_hint_size_and_variant_update_without_replacing_children() {
    let (mut app, _) = start();
    app.type_text("id:lui-30", " retained").unwrap();
    let editor = native(&app, 30).id;
    app.press("id:lui-2").unwrap();
    app.wait_for("id:lui-10").unwrap();
    let item = native(&app, 10).id;
    let child = native(&app, 20).id;
    let old_label = label(&app, "Save 中文").id;
    let mut marks = glyphs(&app);
    marks.sort_by(|left, right| left.bounds.origin.x.0.total_cmp(&right.bounds.origin.x.0));
    assert_eq!(marks.len(), 2);
    let (check, icon) = (marks[0].id, marks[1].id);
    assert!(marks[0].bounds.origin.x < marks[1].bounds.origin.x);
    assert_eq!(marks[1].bounds.size.width, px(16.0));
    let shortcut = label(&app, "⌘ S").id;
    assert_eq!(
        app.screen().span_style("text:Save 中文").unwrap().color,
        app.screen()
            .span_style("text:Destructive reference")
            .unwrap()
            .color
    );
    app.press_key("f5").unwrap();
    app.wait_for("text:Renamed 中文").unwrap();
    assert_eq!(
        (
            native(&app, 10).id,
            native(&app, 20).id,
            native(&app, 30).id
        ),
        (item, child, editor)
    );
    assert_eq!(label(&app, "Renamed 中文").id, old_label);
    assert_eq!(label(&app, "Ctrl R").id, shortcut);
    assert_eq!(by_native(&app, icon).bounds.size.width, px(20.0));
    assert!(by_native(&app, check).bounds.origin.x > by_native(&app, icon).bounds.origin.x);
    assert_eq!(
        app.screen()
            .accessibility_state("id:lui-10")
            .unwrap()
            .checked,
        Some(nsh_core::Checked::False)
    );
    assert_eq!(
        app.screen().span_style("text:Renamed 中文").unwrap().color,
        app.screen()
            .span_style("text:Primary reference")
            .unwrap()
            .color
    );
    assert_eq!(
        app.screen().input_text("id:lui-30").unwrap(),
        Some("draft retained")
    );
    app.press_key("f6").unwrap();
    assert!(by_native(&app, check).bounds.origin.y < by_native(&app, icon).bounds.origin.y);
    assert_eq!(native(&app, 10).id, item);
    app.press_key("f7").unwrap();
    let styled = app.screen().span_style("text:Renamed 中文").unwrap();
    assert_eq!(styled.font_size, px(19.0));
    assert_eq!(styled.color, nsh_core::Color(0x123456ff));
}
#[test]
fn menu_item_optional_parts_restore_in_place_after_removal() {
    let (mut app, _) = start();
    app.press("id:lui-2").unwrap();
    app.wait_for("id:lui-10").unwrap();
    let item = native(&app, 10).id;
    let marks = glyphs(&app)
        .into_iter()
        .map(|node| node.id)
        .collect::<Vec<_>>();
    let shortcut = label(&app, "⌘ S").id;
    app.press_key("f8").unwrap();
    assert_eq!(
        app.screen()
            .accessibility_state("id:lui-10")
            .unwrap()
            .checked,
        None
    );
    app.press_key("f9").unwrap();
    assert_eq!(native(&app, 10).id, item);
    assert_eq!(
        glyphs(&app)
            .into_iter()
            .map(|node| node.id)
            .collect::<Vec<_>>(),
        marks
    );
    assert_eq!(label(&app, "⌘ S").id, shortcut);
    assert_eq!(
        app.screen()
            .accessibility_state("id:lui-10")
            .unwrap()
            .checked,
        Some(nsh_core::Checked::True)
    );
}
#[test]
fn decorated_menu_items_keep_native_disabled_traversal_and_controlled_checks() {
    let (mut app, observed) = start();
    app.press("id:lui-2").unwrap();
    app.wait_for("id:lui-10").unwrap();
    app.hover("id:lui-10").unwrap();
    app.press_key("down").unwrap();
    app.press_key("enter").unwrap();
    assert!(observed.lock().unwrap().contains(&Event::Press(12)));
    assert!(!observed.lock().unwrap().contains(&Event::Press(11)));
    app.press_key("down").unwrap();
    app.wait_for("id:lui-10").unwrap();
    app.press_key("enter").unwrap();
    assert!(observed.lock().unwrap().contains(&Event::Press(10)));
    app.press_key("down").unwrap();
    app.wait_for("id:lui-10").unwrap();
    // Selection is controlled by the source, even when the native item closes
    // its menu; an absent application update must not flip its checked state.
    assert_eq!(
        app.screen()
            .accessibility_state("id:lui-10")
            .unwrap()
            .checked,
        Some(nsh_core::Checked::True)
    );
}
