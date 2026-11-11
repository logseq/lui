use lui_nsh::{render::Renderer, wire::Batch};
use nsh_core::prelude::*;
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;

#[component]
fn SpacedRow() -> impl IntoElement {
    let renderer = Renderer::new(|_, _| {});
    renderer
        .apply(
            Batch::decode(
                r#"{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"row"},
            {"op":"set-prop","id":1,"property":"width","value":300},
            {"op":"set-prop","id":1,"property":"height","value":20},
            {"op":"set-prop","id":1,"property":"main","value":"space_between"},
            {"op":"create-node","id":2,"kind":"text"},
            {"op":"set-prop","id":2,"property":"text","value":"A"},
            {"op":"set-prop","id":2,"property":"width","value":20},
            {"op":"set-prop","id":2,"property":"height","value":20},
            {"op":"create-node","id":3,"kind":"text"},
            {"op":"set-prop","id":3,"property":"text","value":"B"},
            {"op":"set-prop","id":3,"property":"width","value":20},
            {"op":"set-prop","id":3,"property":"height","value":20},
            {"op":"insert-child","parent":1,"child":2,"index":0},
            {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}"#,
            )
            .unwrap(),
        )
        .unwrap();
    renderer.set_root(1).unwrap();
    renderer.element()
}

#[test]
fn canonical_space_between_places_children_at_opposite_edges() {
    let mut app = Headless::start(EngineConfig::new(Root::of::<SpacedRow>())).unwrap();
    app.wait_for("text:B").unwrap();
    let nodes = app.screen().layout_nodes();
    let first = nodes
        .iter()
        .find(|node| node.test_id.as_deref() == Some("lui-2"))
        .unwrap();
    let second = nodes
        .iter()
        .find(|node| node.test_id.as_deref() == Some("lui-3"))
        .unwrap();
    assert!((second.bounds.origin.x.0 - first.bounds.origin.x.0 - 280.0).abs() < 0.1);
}

#[component]
fn RejectedLayout() -> impl IntoElement {
    let renderer = Renderer::new(|_, _| {});
    renderer
        .apply(
            Batch::decode(
                r#"{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"text"},
            {"op":"set-prop","id":1,"property":"text","value":"accepted"}
        ]}"#,
            )
            .unwrap(),
        )
        .unwrap();
    renderer.set_root(1).unwrap();
    let rejected = renderer.apply(
        Batch::decode(
            r#"{"generation":2,"ops":[
        {"op":"set-prop","id":1,"property":"text","value":"must not appear"},
        {"op":"create-node","id":2,"kind":"text"},
        {"op":"set-prop","id":2,"property":"white-space","value":"pre-line"}
    ]}"#,
        )
        .unwrap(),
    );
    assert!(rejected.unwrap_err().contains("white-space"));
    renderer
        .apply(
            Batch::decode(
                r#"{"generation":2,"ops":[
            {"op":"set-prop","id":1,"property":"text","value":"next accepted"}
        ]}"#,
            )
            .unwrap(),
        )
        .unwrap();
    renderer.element()
}

#[test]
fn unsupported_layout_rejection_keeps_the_committed_tree_and_generation() {
    let mut app = Headless::start(EngineConfig::new(Root::of::<RejectedLayout>())).unwrap();
    app.wait_for("text:next accepted").unwrap();
    assert_eq!(app.screen().count("text:must not appear").unwrap(), 0);
    assert_eq!(app.screen().count("id:lui-2").unwrap(), 0);
}
