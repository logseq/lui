//! Actual nested native spans: display:none removes characters, visibility keeps space.
use super::*;
use crate::{
    render::{Event, Renderer},
    wire::Batch,
};
use nsh_core::{Affinity, ApproxTextEngine, NodeId, TextEngine, TextPosition};
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::{Headless, LayoutNode};
use serde_json::{Value, json};
use std::{cell::Cell, rc::Rc, sync::Mutex};

type Snapshot = (Vec<NodeId>, Vec<String>);
#[derive(Clone)]
struct Observed(Arc<Mutex<Vec<Snapshot>>>);
fn patch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}
fn record(renderer: Renderer, observed: Arc<Observed>) {
    after_answer(move || {
        let sources = (2..=8)
            .map(|id| renderer.node_snapshot(id).unwrap())
            .collect::<Vec<_>>();
        let ids = sources
            .iter()
            .map(|node| {
                renderer
                    .native_reference(node.id, node.incarnation)
                    .unwrap()
                    .node()
                    .unwrap()
            })
            .collect();
        let text = sources
            .iter()
            .map(|node| node.string("text").to_owned())
            .collect();
        observed.0.lock().unwrap().push((ids, text));
    });
}
#[component]
fn CollapsedText() -> impl IntoElement {
    let observed = engine_context::<Observed>().unwrap();
    let revision = Rc::new(Cell::new(1));
    let writing = revision.clone();
    let renderer = Renderer::new(move |event, renderer| {
        if let Event::Text(id, text) = event {
            let next = writing.get() + 1;
            renderer
                .apply(patch(
                    next,
                    json!([{"op":"set-prop","id":id,"property":"text","value":text}]),
                ))
                .unwrap();
            writing.set(next);
        }
    });
    renderer
        .apply(patch(
            1,
            json!([
                {"op":"create-node","id":1,"kind":"column"},
                {"op":"set-prop","id":1,"property":"width","value":600},
                {"op":"set-prop","id":1,"property":"cross","value":"start"},
                {"op":"create-node","id":2,"kind":"text"},
                {"op":"set-prop","id":2,"property":"white-space","value":"pre-wrap"},
                {"op":"set-prop","id":2,"property":"font-size","value":"20px"},
                {"op":"insert-child","parent":1,"child":2,"index":0},
                {"op":"create-node","id":3,"kind":"text"},
                {"op":"set-prop","id":3,"property":"text","value":"L"},
                {"op":"insert-child","parent":2,"child":3,"index":0},
                {"op":"create-node","id":4,"kind":"text"},
                {"op":"set-prop","id":4,"property":"text","value":"["},
                {"op":"insert-child","parent":2,"child":4,"index":1},
                {"op":"create-node","id":5,"kind":"text"},
                {"op":"set-prop","id":5,"property":"text","value":"**"},
                {"op":"set-prop","id":5,"property":"display","value":"block"},
                {"op":"insert-child","parent":4,"child":5,"index":0},
                {"op":"create-node","id":6,"kind":"text"},
                {"op":"set-prop","id":6,"property":"text","value":"]"},
                {"op":"insert-child","parent":4,"child":6,"index":1},
                {"op":"create-node","id":7,"kind":"text"},
                {"op":"set-prop","id":7,"property":"text","value":"R"},
                {"op":"insert-child","parent":2,"child":7,"index":2},
                {"op":"create-node","id":8,"kind":"text-field"},
                {"op":"set-prop","id":8,"property":"text","value":"draft  intact"},
                {"op":"set-prop","id":8,"property":"change-enabled","value":true},
                {"op":"set-prop","id":8,"property":"width","value":200},
                {"op":"insert-child","parent":1,"child":8,"index":1}
            ]),
        ))
        .unwrap();
    renderer.set_root(1).unwrap();
    for (key, ops) in [
        (
            "f2",
            json!([{"op":"set-prop","id":5,"property":"display","value":"none"}]),
        ),
        (
            "f3",
            json!([{"op":"set-prop","id":5,"property":"display","value":"block"}]),
        ),
        (
            "f4",
            json!([{"op":"set-prop","id":4,"property":"display","value":"none"}]),
        ),
        (
            "f5",
            json!([{"op":"set-prop","id":4,"property":"display","value":"block"}]),
        ),
        (
            "f6",
            json!([{"op":"set-prop","id":5,"property":"font-size","value":"28px"}]),
        ),
    ] {
        let renderer = renderer.clone();
        let revision = revision.clone();
        let observed = observed.clone();
        on_key_with(
            key,
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| {
                let next = revision.get() + 1;
                renderer.apply(patch(next, ops.clone())).unwrap();
                revision.set(next);
                record(renderer.clone(), observed.clone());
            },
        );
    }
    let recording = renderer.clone();
    on_key_with(
        "f1",
        KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| {
            record(recording.clone(), observed.clone());
        },
    );
    view().flex_col().child(renderer.element()).child(
        text("")
            .test_id("visibility-control")
            .text_size(px(20.0))
            .child(text("L"))
            .child(text("**").invisible())
            .child(text("R")),
    )
}
fn node(app: &Headless, id: &str) -> LayoutNode {
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some(id))
        .unwrap()
}
fn rendered(app: &Headless) -> (String, f32, f32) {
    let native = node(app, "lui-2");
    let text = &native.text.as_ref().unwrap().text;
    let engine = ApproxTextEngine;
    let prepared = engine.prepare(text);
    let size = engine.measure(&prepared, None);
    // This is the public engine Headless actually uses, not a guessed glyph width.
    assert!((native.bounds.size.width.0 - size.width.0).abs() <= 1.0);
    let layout = engine.layout(&prepared, size);
    let right = text
        .test_ids
        .iter()
        .find(|span| span.test_id.as_ref() == "lui-7")
        .unwrap();
    let caret = engine
        .caret_rect(
            &layout,
            TextPosition::new(right.start, Affinity::Downstream),
        )
        .unwrap();
    let mut range = Vec::new();
    engine.range_rects(&layout, right.start..right.end, &mut range);
    assert_eq!(range.len(), 1);
    assert_eq!(range[0].origin, caret.origin);
    (text.text.clone(), size.width.0, caret.origin.x.0)
}
#[test]
fn nested_display_none_removes_advances_and_restores_same_native_spans_and_logical_text() {
    let observed = Observed(Arc::new(Mutex::new(Vec::new())));
    let mut app = Headless::start(EngineConfig {
        context: EngineContext::default().with(observed.clone()),
        ..EngineConfig::new(Root::of::<CollapsedText>())
    })
    .unwrap();
    // Qualify populated keyed descendants before the initial identity record.
    app.wait_for("text:L[**]R").unwrap();
    app.wait_for("id:lui-8").unwrap();
    app.press_key("f1").unwrap();
    let initial = rendered(&app);
    assert_eq!(initial.0, "L[**]R");
    app.type_text("id:lui-8", " retained").unwrap();
    let draft = app
        .screen()
        .input_text("id:lui-8")
        .unwrap()
        .unwrap()
        .to_owned();
    app.press_key("f2").unwrap();
    let own = rendered(&app);
    assert_eq!(own.0, "L[]R");
    assert!(own.1 < initial.1 && own.2 < initial.2);
    app.press_key("f3").unwrap();
    assert_eq!(rendered(&app), initial);
    app.press_key("f4").unwrap();
    let ancestor = rendered(&app);
    assert_eq!(
        ancestor.0, "LR",
        "a display:block descendant cannot escape a collapsed ancestor"
    );
    assert!(ancestor.1 < own.1 && ancestor.2 < own.2);
    app.press_key("f6").unwrap();
    assert_eq!(
        rendered(&app),
        ancestor,
        "an unrelated hidden style edit cannot republish its source"
    );
    app.press_key("f5").unwrap();
    assert_eq!(rendered(&app).0, initial.0);
    assert_eq!(
        app.screen().span_style("id:lui-5").unwrap().font_size,
        px(28.0)
    );
    app.press_key("x").unwrap();
    assert_eq!(
        app.screen().input_text("id:lui-8").unwrap(),
        Some(format!("{draft}x").as_str())
    );
    let recorded = observed.0.lock().unwrap();
    assert_eq!(recorded.len(), 6);
    assert!(recorded.windows(2).all(|pair| pair[0].0 == pair[1].0));
    for (_, logical) in recorded.iter() {
        assert_eq!(&logical[..6], ["", "L", "[", "**", "]", "R"]);
    }
}
#[test]
fn native_visibility_hidden_still_keeps_character_advances() {
    let observed = Observed(Arc::new(Mutex::new(Vec::new())));
    let mut app = Headless::start(EngineConfig {
        context: EngineContext::default().with(observed),
        ..EngineConfig::new(Root::of::<CollapsedText>())
    })
    .unwrap();
    app.wait_for("id:visibility-control").unwrap();
    let native = node(&app, "visibility-control");
    let text = &native.text.unwrap().text;
    assert_eq!(text.text, "L**R");
    assert_eq!(text.visible_text(), "LR");
    let engine = ApproxTextEngine;
    let width = engine.measure(&engine.prepare(text), None).width;
    let mut visible = text.as_ref().clone();
    visible.text = "LR".into();
    // Compare at the same inherited size, rather than a default-font estimate.
    visible.spans.truncate(1);
    visible.spans[0].end = 2;
    visible.spans[0].style.hidden = false;
    visible.test_ids.clear();
    assert!(width > engine.measure(&engine.prepare(&visible), None).width);
}
