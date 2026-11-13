//! Exercise the actual native axis, retained content and atomic axis changes.
use super::*;
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use serde_json::json;

struct ScrollProbe(bool);
fn patch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}

#[component]
fn ScrollAxes() -> impl IntoElement {
    let horizontal = engine_context::<ScrollProbe>().unwrap().0;
    let renderer = Renderer::new(|_, _| {});
    let mut ops = json!([
        {"op":"create-node","id":1,"kind":"column"},
        {"op":"create-node","id":2,"kind":"scroll"},
        {"op":"set-prop","id":2,"property":"width","value":200},
        {"op":"set-prop","id":2,"property":"height","value":100},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"create-node","id":3,"kind":"column"},
        {"op":"set-prop","id":3,"property":"width","value":600},
        {"op":"set-prop","id":3,"property":"height","value":300},
        {"op":"insert-child","parent":2,"child":3,"index":0},
        {"op":"create-node","id":4,"kind":"text-field"},
        {"op":"set-prop","id":4,"property":"width","value":160},
        {"op":"set-prop","id":4,"property":"text","value":"draft"},
        {"op":"insert-child","parent":3,"child":4,"index":0}
    ])
    .as_array()
    .unwrap()
    .clone();
    if horizontal {
        ops.push(json!({"op":"set-prop","id":2,"property":"orientation","value":"horizontal"}));
    }
    renderer.apply(patch(1, Value::Array(ops))).unwrap();
    renderer.set_root(1).unwrap();
    let editing = renderer.clone();
    on_key_with(
        "f2",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            // Explicit vertical and absence mean the same native axis.
            let orientation = if horizontal { "horizontal" } else { "vertical" };
            editing
                .apply(patch(
                    2,
                    json!([
                        {"op":"set-prop","id":2,"property":"orientation","value":orientation}
                    ]),
                ))
                .unwrap();
            let before = editing.0.borrow().nodes[&4].node.get_untracked();
            assert!(editing.apply(patch(3,json!([
            {"op":"set-prop","id":4,"property":"text","value":"must not publish"},
            {"op":"set-prop","id":2,"property":"orientation","value":if horizontal {"vertical"} else {"horizontal"}}
        ]))).unwrap_err().contains("orientation is fixed"));
            assert_eq!(editing.0.borrow().store.generation, 2);
            assert!(Arc::ptr_eq(
                &before,
                &editing.0.borrow().nodes[&4].node.get_untracked()
            ));
        },
    );
    renderer.element()
}

fn layout(app: &Headless, identifier: &str) -> nsh_testing::LayoutNode {
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some(identifier))
        .unwrap()
}

#[test]
fn native_scroll_uses_the_authored_axis_and_keeps_editor_identity_and_draft() {
    for horizontal in [false, true] {
        let mut app = Headless::start(EngineConfig {
            context: EngineContext::default().with(ScrollProbe(horizontal)),
            ..EngineConfig::new(Root::of::<ScrollAxes>())
        })
        .unwrap();
        app.wait_for("id:lui-4").unwrap();
        app.type_text("id:lui-4", " retained").unwrap();
        let text = app
            .screen()
            .input_text("id:lui-4")
            .unwrap()
            .unwrap()
            .to_owned();
        let before = layout(&app, "lui-3");
        let input = layout(&app, "lui-4").id;
        app.scroll("id:lui-2", px(100.0)).unwrap();
        let after = layout(&app, "lui-3");
        assert_eq!(after.id, before.id);
        let delta = after.bounds.origin - before.bounds.origin;
        if horizontal {
            assert!(
                delta.x.0.abs() > 10.0,
                "authored horizontal scroll moved: {delta:?}"
            );
            assert_eq!(delta.y, px(0.0));
        } else {
            assert!(
                delta.y.0.abs() > 10.0,
                "default vertical scroll moved: {delta:?}"
            );
            assert_eq!(delta.x, px(0.0));
        }
        app.press_key("f2").unwrap();
        assert_eq!(layout(&app, "lui-4").id, input);
        assert_eq!(
            app.screen().input_text("id:lui-4").unwrap(),
            Some(text.as_str())
        );
        assert_eq!(layout(&app, "lui-3").bounds.origin, after.bounds.origin);
    }
}

struct ContentProbe {
    kind: &'static str,
    horizontal: bool,
    natural: bool,
    padding: i64,
}

#[component]
fn CanonicalScrollContent() -> impl IntoElement {
    let fixture = engine_context::<ContentProbe>().unwrap();
    let kind = fixture.kind;
    let renderer = Renderer::new(|_, _| {});
    let mut ops = vec![
        json!({"op":"create-node","id":1,"kind":if kind == "bottom-tab" {"bottom-tabs"} else {"column"}}),
        json!({"op":"set-prop","id":1,"property":"width","value":240}),
        json!({"op":"set-prop","id":1,"property":"height","value":180}),
        json!({"op":"create-node","id":2,"kind":kind}),
        json!({"op":"set-prop","id":2,"property":"width","value":200}),
        json!({"op":"set-prop","id":2,"property":"height","value":100}),
        json!({"op":"set-prop","id":2,"property":"padding","value":fixture.padding}),
        json!({"op":"insert-child","parent":1,"child":2,"index":0}),
        json!({"op":"create-node","id":3,"kind":"column"}),
        json!({"op":"set-prop","id":3,"property":"width","value":400}),
        json!({"op":"insert-child","parent":2,"child":3,"index":0}),
        json!({"op":"create-node","id":4,"kind":"column"}),
        json!({"op":"set-prop","id":4,"property":"width","value":250}),
        json!({"op":"set-prop","id":4,"property":"height","value":250}),
        json!({"op":"insert-child","parent":2,"child":4,"index":1}),
    ];
    if kind == "bottom-tab" {
        ops.retain(|operation| operation["id"] != 2 || operation["op"] != "set-prop");
        ops.extend([
            json!({"op":"set-prop","id":1,"property":"accessibility-label","value":"Private scroll pages"}),
            json!({"op":"set-prop","id":2,"property":"title","value":"Scroll page"}),
            json!({"op":"set-prop","id":2,"property":"press-enabled","value":true}),
        ]);
    }
    if fixture.horizontal {
        ops.push(json!({"op":"set-prop","id":2,"property":"orientation","value":"horizontal"}));
    }
    if fixture.natural {
        for (index, id) in [30, 31].into_iter().enumerate() {
            ops.extend([
                json!({"op":"create-node","id":id,"kind":"text"}),
                json!({"op":"set-prop","id":id,"property":"height","value":220}),
                json!({"op":"set-prop","id":id,"property":"text","value":format!("Natural row {index}")}),
                json!({"op":"insert-child","parent":3,"child":id,"index":index}),
            ]);
        }
    } else {
        ops.push(json!({"op":"set-prop","id":3,"property":"height","value":400}));
    }
    renderer.apply(patch(1, json!(ops))).unwrap();
    renderer.set_root(1).unwrap();
    renderer.element()
}

fn content_app(kind: &'static str, horizontal: bool, natural: bool, padding: i64) -> Headless {
    let mut app = Headless::start(EngineConfig {
        context: EngineContext::default().with(ContentProbe {
            kind,
            horizontal,
            natural,
            padding,
        }),
        ..EngineConfig::new(Root::of::<CanonicalScrollContent>())
    })
    .unwrap();
    app.first_render().unwrap();
    let ready = app.wait_until(
        &format!("{kind} canonical content retains its full document"),
        std::time::Duration::from_secs(2),
        |screen| {
            screen.layout_nodes().iter().any(|node| {
                node.test_id.as_deref() == Some("lui-3")
                    && node.bounds.size.height == px(if natural { 440.0 } else { 400.0 })
            })
        },
    );
    if let Err(error) = ready {
        panic!(
            "{kind}: {error}; actual native layout: {:?}",
            app.screen().layout_nodes()
        );
    }
    app
}

#[test]
fn canonical_scroll_children_share_one_intrinsic_grid_cell_on_both_axes() {
    for horizontal in [false, true] {
        let mut app = content_app("scroll", horizontal, false, 10);
        let viewport = layout(&app, "lui-2");
        let first = layout(&app, "lui-3");
        let second = layout(&app, "lui-4");
        assert_eq!(
            first.bounds.origin, second.bounds.origin,
            "direct Scroll children occupy the same cell"
        );
        assert_eq!(
            first.bounds.origin.x - viewport.bounds.origin.x,
            px(10.0),
            "leading padding is applied once"
        );
        assert_eq!(
            first.bounds.origin.y - viewport.bounds.origin.y,
            px(10.0),
            "top padding is applied once"
        );
        app.scroll("id:lui-2", px(100.0)).unwrap();
        let moved = layout(&app, "lui-3");
        assert_eq!(moved.id, first.id);
        assert_eq!(layout(&app, "lui-4").id, second.id);
        let delta = moved.bounds.origin - first.bounds.origin;
        if horizontal {
            assert_eq!(delta.x, px(-100.0));
            assert_eq!(delta.y, px(0.0));
        } else {
            assert_eq!(delta.y, px(-100.0));
            assert_eq!(delta.x, px(0.0));
        }
    }
}

#[test]
fn canonical_scroll_natural_column_keeps_full_fixed_rows() {
    let mut app = content_app("scroll", false, true, 0);
    for id in [30, 31] {
        assert_eq!(
            layout(&app, &format!("lui-{id}")).bounds.size.height,
            px(220.0)
        );
    }
    let before = layout(&app, "lui-3");
    app.scroll("id:lui-2", px(100.0)).unwrap();
    assert_eq!(
        layout(&app, "lui-3").bounds.origin.y,
        before.bounds.origin.y - px(100.0)
    );
}

#[test]
fn list_and_bottom_tab_content_remain_sequential_not_same_cell() {
    for kind in ["list", "bottom-tab"] {
        let mut app = content_app(kind, false, false, 0);
        let first = layout(&app, "lui-3");
        let second = layout(&app, "lui-4");
        assert_eq!(
            second.bounds.origin.y - first.bounds.origin.y,
            px(400.0),
            "{kind} keeps normal sequential flow"
        );
        app.scroll("id:lui-2", px(100.0)).unwrap();
        assert_eq!(
            layout(&app, "lui-3").bounds.origin.y,
            first.bounds.origin.y - px(100.0)
        );
    }
}
