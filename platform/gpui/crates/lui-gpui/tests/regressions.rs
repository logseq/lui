mod support;

use gpui_kit::base::ElementExt;
use gpui_kit::gpui::TestAppContext;
use lui_gpui::{apply_batch_json, LuiRootView, LuiShared};

static TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

#[gpui_kit::test]
fn untitled_dialog_paints_its_content(cx: &mut TestAppContext) {
    let _guard = TEST_LOCK.lock().unwrap_or_else(|error| error.into_inner());
    cx.update(lui_gpui::init);
    let shared = LuiShared::new();
    cx.update(|app| {
        apply_batch_json(&shared, r#"{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"root"},
            {"op":"create-node","id":2,"kind":"dialog"},
            {"op":"set-prop","id":2,"property":"width","value":400},
            {"op":"create-node","id":3,"kind":"text"},
            {"op":"set-prop","id":3,"property":"text","value":"Search content"},
            {"op":"insert-child","parent":2,"child":3,"index":0},
            {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}"#, app).unwrap();
    });
    let build = shared.clone();
    let (_, window) = cx.add_window_view(move |_, _| LuiRootView::new(build));
    window.run_until_parked();
    let bounds = shared.borrow().node_bounds.get(&3).copied().unwrap();
    assert!(f32::from(bounds.size.width) > 0.);
    assert!(f32::from(bounds.size.height) > 0.);
}

#[gpui_kit::test]
fn empty_cover_host_paints_a_new_popup_after_model_updates(cx: &mut TestAppContext) {
    let _guard = TEST_LOCK.lock().unwrap_or_else(|error| error.into_inner());
    cx.update(lui_gpui::init);
    let shared = LuiShared::new();
    cx.update(|app| {
        apply_batch_json(&shared, r#"{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"root"},
            {"op":"create-node","id":2,"kind":"popover"},
            {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}"#, app).unwrap();
    });
    let build = shared.clone();
    let (_, window) = cx.add_window_view(move |_, _| LuiRootView::new(build));
    window.run_until_parked();
    window.update(|_, app| {
        apply_batch_json(&shared, r#"{"generation":2,"ops":[
            {"op":"create-node","id":3,"kind":"popover"},
            {"op":"set-prop","id":3,"property":"x","value":20.0},
            {"op":"set-prop","id":3,"property":"y","value":40.0},
            {"op":"create-node","id":4,"kind":"text"},
            {"op":"set-prop","id":4,"property":"text","value":"New popup"},
            {"op":"insert-child","parent":3,"child":4,"index":0},
            {"op":"insert-child","parent":2,"child":3,"index":0}
        ]}"#, app).unwrap();
    });
    window.run_until_parked();
    assert!(shared.borrow().node_bounds.contains_key(&4), "a popup inserted in a zero-size host must paint without an unrelated window refresh");
}

#[gpui_kit::test]
fn closing_popup_retains_content_then_releases_it(cx: &mut TestAppContext) {
    let _guard = TEST_LOCK.lock().unwrap_or_else(|error| error.into_inner());
    cx.update(lui_gpui::init);
    let shared = LuiShared::new();
    let clock = cx.background_executor.clone();
    cx.update(|app| {
        apply_batch_json(
            &shared,
            r#"{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"root"},
            {"op":"create-node","id":4,"kind":"column"},
            {"op":"create-node","id":2,"kind":"popover"},
            {"op":"create-node","id":3,"kind":"text"},
            {"op":"set-prop","id":3,"property":"text","value":"Retained popup content"},
            {"op":"insert-child","parent":2,"child":3,"index":0},
            {"op":"insert-child","parent":1,"child":4,"index":0},
            {"op":"insert-child","parent":4,"child":2,"index":0}
        ]}"#,
            app,
        )
        .unwrap();
    });
    let build = shared.clone();
    let (_, window) = cx.add_window_view(move |_, _| LuiRootView::new(build));
    window.run_until_parked();
    window.update(|_, app| {
        apply_batch_json(
            &shared,
            r#"{"generation":2,"ops":[{"op":"detach-subtree","id":2}]}"#,
            app,
        )
        .unwrap();
    });
    assert!(
        shared.borrow().store.node(2).is_none(),
        "dismissal removes the live model immediately"
    );
    assert!(
        shared.borrow().views.contains_key(&3),
        "closing content must stay available to paint its exit"
    );
    window.update(|_, app| {
        apply_batch_json(
            &shared,
            r#"{"generation":3,"ops":[
            {"op":"create-node","id":5,"kind":"popover"},
            {"op":"create-node","id":6,"kind":"text"},
            {"op":"set-prop","id":6,"property":"text","value":"New popup content"},
            {"op":"insert-child","parent":5,"child":6,"index":0},
            {"op":"insert-child","parent":4,"child":5,"index":0}
        ]}"#,
            app,
        )
        .unwrap();
    });
    window.run_until_parked();
    clock.advance_clock(std::time::Duration::from_millis(600));
    window.run_until_parked();
    assert!(!shared.borrow().views.contains_key(&2));
    assert!(!shared.borrow().views.contains_key(&3));
    assert!(
        shared.borrow().views.contains_key(&6),
        "an old exit must not release a newer popup"
    );
}

#[gpui_kit::test]
fn cover_popover_escape_dismisses_only_the_top_layer(cx: &mut TestAppContext) {
    let _guard = TEST_LOCK.lock().unwrap_or_else(|error| error.into_inner());
    cx.update(lui_gpui::init);
    let _ = support::take_events();
    let shared = LuiShared::new();
    cx.update(|app| {
        apply_batch_json(
            &shared,
            r#"{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"root"},
            {"op":"create-node","id":4,"kind":"column"},
            {"op":"create-node","id":2,"kind":"popover"},
            {"op":"create-node","id":3,"kind":"popover"},
            {"op":"insert-child","parent":1,"child":4,"index":0},
            {"op":"insert-child","parent":4,"child":2,"index":0},
            {"op":"insert-child","parent":4,"child":3,"index":1}
        ]}"#,
            app,
        )
        .unwrap();
    });
    let build = shared.clone();
    let (_, window) = cx.add_window_view(move |_, _| LuiRootView::new(build));
    window.run_until_parked();
    window.simulate_keystrokes("escape");
    window.run_until_parked();
    assert_eq!(
        support::take_events(),
        vec![support::RecordedEvent::Dismiss(3)]
    );
    assert!(shared.borrow().store.node(2).is_some());
}

#[gpui_kit::test]
fn toast_respects_typed_padding(cx: &mut TestAppContext) {
    let _guard = TEST_LOCK.lock().unwrap_or_else(|error| error.into_inner());
    cx.update(lui_gpui::init);
    let shared = LuiShared::new();
    cx.update(|app| {
        apply_batch_json(
            &shared,
            r#"{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"root"},
            {"op":"create-node","id":2,"kind":"toast"},
            {"op":"set-prop","id":2,"property":"padding","value":0},
            {"op":"create-node","id":3,"kind":"box"},
            {"op":"set-prop","id":3,"property":"width","value":100},
            {"op":"set-prop","id":3,"property":"height","value":20},
            {"op":"insert-child","parent":2,"child":3,"index":0},
            {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}"#,
            app,
        )
        .unwrap();
    });
    let build = shared.clone();
    let (_, window) = cx.add_window_view(move |_, _| LuiRootView::new(build));
    window.update(|window, _| window.refresh());
    window.run_until_parked();
    assert_eq!(
        shared.borrow().toast_heights[&2],
        22.,
        "only the content and border contribute to a zero-padding toast"
    );
}

static UNCHANGED_RENDERS: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

fn counting_renderer(
    _view: &mut lui_gpui::LuiNodeView,
    node: &lui_gpui::NodeSnapshot,
    _window: &mut gpui_kit::gpui::Window,
    _cx: &mut gpui_kit::gpui::Context<lui_gpui::LuiNodeView>,
) -> gpui_kit::gpui::AnyElement {
    use gpui_kit::gpui::{IntoElement, ParentElement, Styled};
    if node.id == 3 {
        UNCHANGED_RENDERS.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
    }
    gpui_kit::gpui::div()
        .w_20()
        .h_8()
        .child(node.extension_string_prop("text").unwrap_or("").to_string())
        .into_any_element()
}

#[gpui_kit::test]
fn single_node_patch_keeps_unchanged_sibling_render_cached(cx: &mut TestAppContext) {
    let _guard = TEST_LOCK.lock().unwrap_or_else(|error| error.into_inner());
    cx.update(lui_gpui::init);
    let shared = LuiShared::new();
    shared
        .borrow_mut()
        .extension_renderers
        .insert("review-counting".into(), counting_renderer);
    cx.update(|app| {
        apply_batch_json(
            &shared,
            r#"{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"root"},
            {"op":"create-node","id":4,"kind":"column"},
            {"op":"insert-child","parent":1,"child":4,"index":0},
            {"op":"create-extension","id":2,"identifier":"review-counting","fingerprint":"fp"},
            {"op":"create-extension","id":3,"identifier":"review-counting","fingerprint":"fp"},
            {"op":"set-extension-prop","id":2,"property":"style-class","value":"w-20 h-8"},
            {"op":"set-extension-prop","id":3,"property":"style-class","value":"w-20 h-8"},
            {"op":"insert-child","parent":4,"child":2,"index":0},
            {"op":"insert-child","parent":4,"child":3,"index":1}
        ]}"#,
            app,
        )
        .unwrap();
    });
    let build = shared.clone();
    let (_, window) = cx.add_window_view(move |_, _| LuiRootView::new(build));
    window.update(|window, _| window.refresh());
    window.run_until_parked();
    let before = UNCHANGED_RENDERS.load(std::sync::atomic::Ordering::SeqCst);
    assert!(before > 0);
    window.update(|_, app| {
        apply_batch_json(
            &shared,
            r#"{"generation":2,"ops":[
            {"op":"set-extension-prop","id":2,"property":"text","value":"updated"}
        ]}"#,
            app,
        )
        .unwrap();
    });
    window.run_until_parked();
    assert_eq!(
        UNCHANGED_RENDERS.load(std::sync::atomic::Ordering::SeqCst),
        before,
        "a sibling without any patch should not render again"
    );
}

#[gpui_kit::test]
fn textarea_tracks_model_updates(cx: &mut TestAppContext) {
    let _guard = TEST_LOCK.lock().unwrap_or_else(|error| error.into_inner());
    cx.update(lui_gpui::init);
    let shared = LuiShared::new();
    cx.update(|app| {
        apply_batch_json(
            &shared,
            r#"{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"root"},
            {"op":"create-node","id":2,"kind":"textarea"},
            {"op":"set-prop","id":2,"property":"text","value":"before"},
            {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}"#,
            app,
        )
        .unwrap();
    });
    let build = shared.clone();
    let (_, window) = cx.add_window_view(move |_, _| LuiRootView::new(build));
    window.update(|window, _| window.refresh());
    window.run_until_parked();
    window.update(|window, app| {
        apply_batch_json(
            &shared,
            r#"{"generation":2,"ops":[
            {"op":"set-prop","id":2,"property":"text","value":"after"}
        ]}"#,
            app,
        )
        .unwrap();
        window.refresh();
    });
    window.run_until_parked();
    window.update(|_, app| {
        let view = shared.borrow().views[&2].clone();
        let state = view.read(app).states.textarea.as_ref().unwrap();
        assert_eq!(state.read(app).value().to_string(), "after");
    });
}

#[gpui_kit::test]
fn input_accepts_feedback_patch_from_its_subscription(cx: &mut TestAppContext) {
    let _guard = TEST_LOCK.lock().unwrap_or_else(|error| error.into_inner());
    cx.update(lui_gpui::init);
    let shared = LuiShared::new();
    cx.update(|app| {
        apply_batch_json(
            &shared,
            r#"{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"root"},
            {"op":"create-node","id":2,"kind":"input"},
            {"op":"set-prop","id":2,"property":"text","value":"before"},
            {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}"#,
            app,
        )
        .unwrap();
    });
    let build = shared.clone();
    let (_, window) = cx.add_window_view(move |_, _| LuiRootView::new(build));
    window.update(|window, _| window.refresh());
    window.run_until_parked();
    // Queue the same patch a synchronous OCaml text-changed call returns.
    let patch = std::ffi::CString::new(
        r#"{"generation":2,"ops":[
        {"op":"set-prop","id":2,"property":"text","value":"after"}
    ]}"#,
    )
    .unwrap();
    unsafe { lui_core::bridge::patch_sink(patch.as_ptr()) };
    window.update(|_, app| {
        let view = shared.borrow().views[&2].clone();
        let state = view.read(app).states.input.as_ref().unwrap().clone();
        state.update(app, |_, cx| {
            cx.emit(gpui_kit::component::input::InputEvent::Change)
        });
    });
    window.run_until_parked();
}

#[gpui_kit::test]
fn card_descendant_has_measurable_bounds(cx: &mut TestAppContext) {
    let _guard = TEST_LOCK.lock().unwrap_or_else(|error| error.into_inner());
    cx.update(lui_gpui::init);
    let shared = LuiShared::new();
    cx.update(|app| {
        apply_batch_json(
            &shared,
            r#"{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"root"},
            {"op":"create-node","id":2,"kind":"card"},
            {"op":"create-node","id":3,"kind":"button"},
            {"op":"set-prop","id":3,"property":"text","value":"Click"},
            {"op":"insert-child","parent":1,"child":2,"index":0},
            {"op":"insert-child","parent":2,"child":3,"index":0}
        ]}"#,
            app,
        )
        .unwrap();
    });
    let build = shared.clone();
    let (_, window) = cx.add_window_view(move |_, _| LuiRootView::new(build));
    window.update(|window, _| window.refresh());
    window.run_until_parked();
    assert!(shared.borrow().node_bounds.contains_key(&2));
    assert!(
        shared.borrow().node_bounds.contains_key(&3),
        "visible Card child has no bounds"
    );
}

fn measured_renderer(
    view: &mut lui_gpui::LuiNodeView,
    node: &lui_gpui::NodeSnapshot,
    _window: &mut gpui_kit::gpui::Window,
    _cx: &mut gpui_kit::gpui::Context<lui_gpui::LuiNodeView>,
) -> gpui_kit::gpui::AnyElement {
    use gpui_kit::gpui::{IntoElement, Styled};
    let shared = view.shared.clone();
    let id = node.id;
    gpui_kit::gpui::div()
        .size_full()
        .on_prepaint(move |bounds, _, _| {
            shared.borrow_mut().node_bounds.insert(id, bounds);
        })
        .into_any_element()
}

#[gpui_kit::test]
fn split_ratio_is_relative_to_parent_width(cx: &mut TestAppContext) {
    let _guard = TEST_LOCK.lock().unwrap_or_else(|error| error.into_inner());
    cx.update(lui_gpui::init);
    let shared = LuiShared::new();
    shared
        .borrow_mut()
        .extension_renderers
        .insert("review-measured".into(), measured_renderer);
    cx.update(|app| {
        apply_batch_json(
            &shared,
            r#"{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"root"},
            {"op":"create-node","id":2,"kind":"split"},
            {"op":"set-prop","id":2,"property":"width","value":300},
            {"op":"set-prop","id":2,"property":"height","value":120},
            {"op":"set-prop","id":2,"property":"value","value":0.5},
            {"op":"create-extension","id":3,"identifier":"review-measured","fingerprint":"fp"},
            {"op":"create-extension","id":4,"identifier":"review-measured","fingerprint":"fp"},
            {"op":"insert-child","parent":1,"child":2,"index":0},
            {"op":"insert-child","parent":2,"child":3,"index":0},
            {"op":"insert-child","parent":2,"child":4,"index":1}
        ]}"#,
            app,
        )
        .unwrap();
    });
    let build = shared.clone();
    let (_, window) = cx.add_window_view(move |_, _| LuiRootView::new(build));
    window.update(|window, _| window.refresh());
    window.run_until_parked();
    let s = shared.borrow();
    let first = f32::from(s.node_bounds[&3].size.width);
    let second = f32::from(s.node_bounds[&4].size.width);
    assert!(
        (first / (first + second) - 0.5).abs() < 0.05,
        "ratio 0.5 should give equal panes inside a 300px parent"
    );
}

#[gpui_kit::test]
fn root_keydown_uses_carrier_identifier(cx: &mut TestAppContext) {
    let _guard = TEST_LOCK.lock().unwrap_or_else(|error| error.into_inner());
    cx.update(lui_gpui::init);
    let _ = support::take_events();
    let shared = LuiShared::new();
    cx.update(|app| {
        apply_batch_json(
            &shared,
            r#"{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"root"},
            {"op":"create-extension","id":2,"identifier":"logseq-div","fingerprint":"fp"},
            {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}"#,
            app,
        )
        .unwrap();
    });
    let build = shared.clone();
    let (_, window) = cx.add_window_view(move |_, _| LuiRootView::new(build));
    window.update(|window, _| window.refresh());
    window.run_until_parked();
    window.simulate_keystrokes("up");
    window.run_until_parked();
    let events = support::take_events();
    let support::RecordedEvent::ExtensionEvent {
        identifier, json, ..
    } = &events[0]
    else {
        panic!("expected extension event, received {events:?}");
    };
    let payload: serde_json::Value = serde_json::from_str(json).unwrap();
    let event: serde_json::Value =
        serde_json::from_str(payload["payload"].as_str().unwrap()).unwrap();
    assert_eq!(event["key"], "ArrowUp");
    assert_eq!(
        identifier, "logseq-div",
        "OCaml rejects a carrier identifier mismatch"
    );
}

#[gpui_kit::test]
fn virtual_list_renders_only_visible_rows_and_scrolls_to_unmounted_rows(cx: &mut TestAppContext) {
    let _guard = TEST_LOCK.lock().unwrap_or_else(|error| error.into_inner());
    cx.update(lui_gpui::init);
    let shared = LuiShared::new();
    let mut ops = vec![
        serde_json::json!({"op":"create-node","id":1,"kind":"root"}),
        serde_json::json!({"op":"create-node","id":2,"kind":"virtual-list"}),
        serde_json::json!({"op":"set-prop","id":2,"property":"height","value":160}),
        serde_json::json!({"op":"set-prop","id":2,"property":"width","value":300}),
        serde_json::json!({"op":"insert-child","parent":1,"child":2,"index":0}),
    ];
    for index in 0..1000 {
        let id = index + 10;
        ops.extend([
            serde_json::json!({"op":"create-node","id":id,"kind":"text"}),
            serde_json::json!({"op":"set-prop","id":id,"property":"text","value":format!("Row {index}")}),
            serde_json::json!({"op":"set-prop","id":id,"property":"height","value":24 + index % 3 * 12}),
            serde_json::json!({"op":"insert-child","parent":2,"child":id,"index":index}),
        ]);
    }
    cx.update(|app| {
        apply_batch_json(
            &shared,
            &serde_json::json!({"generation":1,"ops":ops}).to_string(),
            app,
        )
        .unwrap()
    });
    let build = shared.clone();
    let (_, window) = cx.add_window_view(move |_, _| LuiRootView::new(build));
    window.run_until_parked();
    assert!(
        shared.borrow().views.len() < 64,
        "initial render created entities for offscreen rows"
    );
    assert!(!shared.borrow().node_bounds.contains_key(&900));
    window.update(|window, app| {
        lui_gpui::domops::handle_dom_op(
            &shared,
            "scroll-into-view",
            r#"{"ref":{"node-id":900}}"#,
            window,
            app,
        );
    });
    window.run_until_parked();
    assert!(
        shared.borrow().node_bounds.contains_key(&900),
        "imperative scroll must mount its target"
    );
    assert!(
        !shared.borrow().node_bounds.contains_key(&10),
        "offscreen bounds must be retired"
    );
    let first = shared.borrow().node_bounds[&900];
    let container = shared.borrow().node_bounds[&2];
    assert!(first.origin.y < container.origin.y + container.size.height);
    window.update(|_, app| {
        apply_batch_json(
            &shared,
            r#"{"generation":2,"ops":[
        {"op":"move-child","parent":2,"child":10,"index":999}
    ]}"#,
            app,
        )
        .unwrap()
    });
    window.run_until_parked();
    assert_eq!(
        shared.borrow().node_bounds.get(&900).map(|b| b.origin.y),
        Some(first.origin.y),
        "reordering unrelated rows must preserve the visible anchor"
    );

    window.update(|_, app| {
        apply_batch_json(
            &shared,
            r#"{"generation":3,"ops":[
            {"op":"set-prop","id":900,"property":"height","value":72},
            {"op":"drop-node","id":901},
            {"op":"create-node","id":1100,"kind":"text"},
            {"op":"set-prop","id":1100,"property":"text","value":"Inserted"},
            {"op":"set-prop","id":1100,"property":"height","value":36},
            {"op":"insert-child","parent":2,"child":1100,"index":890}
        ]}"#,
            app,
        )
        .unwrap();
    });
    window.run_until_parked();
    assert_eq!(
        f32::from(shared.borrow().node_bounds[&900].size.height),
        72.
    );
    assert!(shared.borrow().node_bounds.contains_key(&1100));
    assert!(!shared.borrow().node_bounds.contains_key(&901));
    assert!(shared.borrow().views.len() < 96);
}

#[gpui_kit::test]
fn split_tracks_model_ratio_and_parent_resize(cx: &mut TestAppContext) {
    let _guard = TEST_LOCK.lock().unwrap_or_else(|error| error.into_inner());
    cx.update(lui_gpui::init);
    let shared = LuiShared::new();
    shared
        .borrow_mut()
        .extension_renderers
        .insert("review-measured".into(), measured_renderer);
    cx.update(|app| {
        apply_batch_json(
            &shared,
            r#"{"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"root"},
            {"op":"create-node","id":2,"kind":"split"},
            {"op":"set-prop","id":2,"property":"width","value":400},
            {"op":"set-prop","id":2,"property":"height","value":120},
            {"op":"set-prop","id":2,"property":"value","value":0.5},
            {"op":"create-extension","id":3,"identifier":"review-measured","fingerprint":"fp"},
            {"op":"create-extension","id":4,"identifier":"review-measured","fingerprint":"fp"},
            {"op":"insert-child","parent":1,"child":2,"index":0},
            {"op":"insert-child","parent":2,"child":3,"index":0},
            {"op":"insert-child","parent":2,"child":4,"index":1}
        ]}"#,
            app,
        )
        .unwrap();
    });
    let build = shared.clone();
    let (_, window) = cx.add_window_view(move |_, _| LuiRootView::new(build));
    window.run_until_parked();
    for (generation, width, fraction) in [(2, 400, 0.25), (3, 600, 0.25)] {
        window.update(|_, app| {
            apply_batch_json(
                &shared,
                &serde_json::json!({"generation":generation,"ops":[
                    {"op":"set-prop","id":2,"property":"width","value":width},
                    {"op":"set-prop","id":2,"property":"value","value":fraction}
                ]})
                .to_string(),
                app,
            )
            .unwrap();
        });
        window.run_until_parked();
        let s = shared.borrow();
        let first = f32::from(s.node_bounds[&3].size.width);
        let second = f32::from(s.node_bounds[&4].size.width);
        assert!((first / (first + second) - fraction).abs() < 0.01);
    }
}

#[gpui_kit::test]
fn virtual_list_keeps_focused_input_dispatch_when_scrolled_offscreen(cx: &mut TestAppContext) {
    let _guard = TEST_LOCK.lock().unwrap_or_else(|error| error.into_inner());
    cx.update(lui_gpui::init);
    let shared = LuiShared::new();
    let mut ops = vec![
        serde_json::json!({"op":"create-node","id":1,"kind":"root"}),
        serde_json::json!({"op":"create-node","id":2,"kind":"virtual-list"}),
        serde_json::json!({"op":"set-prop","id":2,"property":"height","value":120}),
        serde_json::json!({"op":"set-prop","id":2,"property":"width","value":300}),
        serde_json::json!({"op":"insert-child","parent":1,"child":2,"index":0}),
    ];
    for index in 0..100 {
        let id = index + 10;
        ops.extend([
            serde_json::json!({"op":"create-node","id":id,"kind":"input"}),
            serde_json::json!({"op":"set-prop","id":id,"property":"height","value":32}),
            serde_json::json!({"op":"insert-child","parent":2,"child":id,"index":index}),
        ]);
    }
    cx.update(|app| {
        apply_batch_json(
            &shared,
            &serde_json::json!({"generation":1,"ops":ops}).to_string(),
            app,
        )
        .unwrap()
    });
    let build = shared.clone();
    let (_, window) = cx.add_window_view(move |_, _| LuiRootView::new(build));
    window.run_until_parked();
    window.update(|window, app| {
        lui_gpui::domops::handle_dom_op(&shared, "focus", r#"{"ref":{"node-id":10}}"#, window, app);
    });
    window.run_until_parked();
    window.update(|_, app| {
        apply_batch_json(
            &shared,
            r#"{"generation":2,"ops":[
        {"op":"move-child","parent":2,"child":10,"index":5}
    ]}"#,
            app,
        )
        .unwrap()
    });
    window.run_until_parked();
    window.update(|window, app| {
        lui_gpui::domops::handle_dom_op(
            &shared,
            "scroll-into-view",
            r#"{"ref":{"node-id":90}}"#,
            window,
            app,
        );
    });
    window.run_until_parked();
    let _ = support::take_events();
    window.simulate_input("kept");
    window.run_until_parked();
    assert!(
        support::take_events().contains(&support::RecordedEvent::TextChanged {
            node: 10,
            text: "kept".into()
        }),
        "focused offscreen inputs must retain keyboard dispatch"
    );
}

#[gpui_kit::test]
fn text_fields_track_placeholder_updates(cx: &mut TestAppContext) {
    let _guard = TEST_LOCK.lock().unwrap_or_else(|error| error.into_inner());
    cx.update(lui_gpui::init);
    let shared = LuiShared::new();
    cx.update(|app| {
        apply_batch_json(
            &shared,
            r#"{"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"root"},
        {"op":"create-node","id":4,"kind":"column"},
        {"op":"insert-child","parent":1,"child":4,"index":0},
        {"op":"create-node","id":2,"kind":"textarea"},
        {"op":"create-node","id":3,"kind":"input"},
        {"op":"set-prop","id":2,"property":"placeholder","value":"Before"},
        {"op":"set-prop","id":3,"property":"placeholder","value":"Before"},
        {"op":"insert-child","parent":4,"child":2,"index":0},
        {"op":"insert-child","parent":4,"child":3,"index":1}
    ]}"#,
            app,
        )
        .unwrap()
    });
    let build = shared.clone();
    let (_, window) = cx.add_window_view(move |_, _| LuiRootView::new(build));
    window.run_until_parked();
    window.update(|_, app| {
        apply_batch_json(
            &shared,
            r#"{"generation":2,"ops":[
        {"op":"set-prop","id":2,"property":"placeholder","value":"After"},
        {"op":"remove-prop","id":3,"property":"placeholder"}
    ]}"#,
            app,
        )
        .unwrap()
    });
    window.run_until_parked();
    window.update(|_, app| {
        let guard = shared.borrow();
        let textarea = guard.views[&2].read(app).states.textarea.as_ref().unwrap();
        assert_eq!(
            textarea.read(app).presentation().placeholder().as_ref(),
            "After"
        );
        let input = guard.views[&3].read(app).states.input.as_ref().unwrap();
        assert_eq!(input.read(app).presentation().placeholder().as_ref(), "");
    });
}
