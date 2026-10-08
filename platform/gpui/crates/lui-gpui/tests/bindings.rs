mod support;

use gpui_kit::gpui::{
    point, px, Focusable, LongPressEvent, Modifiers, MouseButton, MouseDownEvent, TestAppContext,
};
use lui_gpui::{apply_batch_json, LuiRootView, LuiShared};
use support::RecordedEvent;

static LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

macro_rules! mount {
    ($cx:ident, $shared:ident, $window:ident, $json:expr) => {
        let _guard = LOCK.lock().unwrap_or_else(|error| error.into_inner());
        let _ = support::take_events();
        $cx.update(lui_gpui::init);
        let $shared = LuiShared::new();
        $cx.update(|app| {
            apply_batch_json(&$shared, $json, app).unwrap();
        });
        let build = $shared.clone();
        let (_, $window) = $cx.add_window_view(move |_, _| LuiRootView::new(build));
        $window.update(|window, _| window.refresh());
        $window.run_until_parked();
    };
}

#[gpui_kit::test]
fn textarea_preserves_edits_and_accepts_explicit_model_updates(cx: &mut TestAppContext) {
    mount!(
        cx,
        shared,
        window,
        r#"{"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"root"},
        {"op":"create-node","id":2,"kind":"textarea"},
        {"op":"set-prop","id":2,"property":"text","value":""},
        {"op":"insert-child","parent":1,"child":2,"index":0}]}"#
    );
    window.update(|window, app| {
        let state = shared.borrow().views[&2]
            .read(app)
            .states
            .textarea
            .as_ref()
            .unwrap()
            .clone();
        state.update(app, |state, cx| state.set_value("typed", window, cx));
        window.refresh();
    });
    window.run_until_parked();
    window.update(|_, app| {
        let view = shared.borrow().views[&2].clone();
        assert_eq!(
            view.read(app)
                .states
                .textarea
                .as_ref()
                .unwrap()
                .read(app)
                .value()
                .as_ref(),
            "typed"
        );
        apply_batch_json(
            &shared,
            r#"{"generation":2,"ops":[
            {"op":"set-prop","id":2,"property":"text","value":""}]}"#,
            app,
        )
        .unwrap();
    });
    window.run_until_parked();
    window.update(|_, app| {
        let view = shared.borrow().views[&2].clone();
        assert_eq!(
            view.read(app)
                .states
                .textarea
                .as_ref()
                .unwrap()
                .read(app)
                .value()
                .as_ref(),
            ""
        );
        apply_batch_json(
            &shared,
            r#"{"generation":3,"ops":[
            {"op":"set-prop","id":2,"property":"text","value":"model"}]}"#,
            app,
        )
        .unwrap();
    });
    window.run_until_parked();
    window.update(|_, app| {
        let view = shared.borrow().views[&2].clone();
        assert_eq!(
            view.read(app)
                .states
                .textarea
                .as_ref()
                .unwrap()
                .read(app)
                .value()
                .as_ref(),
            "model"
        );
    });
}

#[gpui_kit::test]
fn input_applies_repeated_explicit_clear_without_resetting_edits_on_repaint(
    cx: &mut TestAppContext,
) {
    mount!(
        cx,
        shared,
        window,
        r#"{"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"root"},
        {"op":"create-node","id":2,"kind":"input"},
        {"op":"set-prop","id":2,"property":"text","value":""},
        {"op":"insert-child","parent":1,"child":2,"index":0}]}"#
    );
    window.update(|window, app| {
        let state = shared.borrow().views[&2]
            .read(app)
            .states
            .input
            .as_ref()
            .unwrap()
            .clone();
        state.update(app, |state, cx| state.set_value("typed", window, cx));
        window.refresh();
    });
    window.run_until_parked();
    window.update(|_, app| {
        let view = shared.borrow().views[&2].clone();
        assert_eq!(
            view.read(app)
                .states
                .input
                .as_ref()
                .unwrap()
                .read(app)
                .value()
                .as_ref(),
            "typed"
        );
        apply_batch_json(
            &shared,
            r#"{"generation":2,"ops":[
            {"op":"set-prop","id":2,"property":"text","value":""}]}"#,
            app,
        )
        .unwrap();
    });
    window.run_until_parked();
    window.update(|_, app| {
        let view = shared.borrow().views[&2].clone();
        assert_eq!(
            view.read(app)
                .states
                .input
                .as_ref()
                .unwrap()
                .read(app)
                .value()
                .as_ref(),
            ""
        );
    });
}

#[gpui_kit::test]
fn number_stepper_displays_model_value_and_emits_numeric_changes(cx: &mut TestAppContext) {
    mount!(
        cx,
        shared,
        window,
        r#"{"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"root"},
        {"op":"create-node","id":2,"kind":"number-stepper"},
        {"op":"set-prop","id":2,"property":"value","value":42.0},
        {"op":"set-prop","id":2,"property":"min","value":0.0},
        {"op":"set-prop","id":2,"property":"max","value":50.0},
        {"op":"set-prop","id":2,"property":"step","value":2.0},
        {"op":"insert-child","parent":1,"child":2,"index":0}]}"#
    );
    window.update(|window, app| {
        let state = shared.borrow().views[&2]
            .read(app)
            .states
            .input
            .as_ref()
            .unwrap()
            .clone();
        assert_eq!(state.read(app).value().as_ref(), "42");
        state.read(app).focus_handle(app).focus(window, app);
    });
    let _ = support::take_events();
    window.simulate_keystrokes("up");
    window.run_until_parked();
    assert!(
        support::take_events().contains(&RecordedEvent::SliderChanged {
            node: 2,
            fraction: 44.0
        })
    );
    window.update(|_, app| {
        apply_batch_json(
            &shared,
            r#"{"generation":2,"ops":[
            {"op":"set-prop","id":2,"property":"max","value":45.0},
            {"op":"set-prop","id":2,"property":"step","value":10.0}]}"#,
            app,
        )
        .unwrap();
    });
    window.run_until_parked();
    window.simulate_keystrokes("up");
    window.run_until_parked();
    assert!(
        support::take_events().contains(&RecordedEvent::SliderChanged {
            node: 2,
            fraction: 45.0
        })
    );
    window.update(|window, app| {
        let state = shared.borrow().views[&2]
            .read(app)
            .states
            .input
            .as_ref()
            .unwrap()
            .clone();
        state.update(app, |state, cx| state.set_value("invalid", window, cx));
    });
    window.run_until_parked();
    assert!(
        support::take_events().is_empty(),
        "invalid numbers must not cross the ABI"
    );
}

#[gpui_kit::test]
fn picker_accepts_options_and_combobox_commits_once(cx: &mut TestAppContext) {
    mount!(
        cx,
        shared,
        window,
        r#"{"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"root"},
        {"op":"create-node","id":2,"kind":"combobox"},
        {"op":"create-node","id":3,"kind":"menu-item"},
        {"op":"set-prop","id":3,"property":"text","value":"Option"},
        {"op":"insert-child","parent":2,"child":3,"index":0},
        {"op":"insert-child","parent":1,"child":2,"index":0}]}"#
    );
    let _ = support::take_events();
    window.update(|_, app| {
        let state = shared.borrow().views[&2]
            .read(app)
            .states
            .combobox
            .as_ref()
            .unwrap()
            .clone();
        // gpui-kit emits both notifications for one single-selection commit.
        state.update(app, |_, cx| {
            cx.emit(gpui_kit::component::combobox::ComboboxEvent::Change(vec![
                3,
            ]));
            cx.emit(gpui_kit::component::combobox::ComboboxEvent::Confirm(vec![
                3,
            ]));
        });
    });
    window.run_until_parked();
    let events = support::take_events();
    assert_eq!(
        events
            .iter()
            .filter(|event| matches!(event, RecordedEvent::Press(3)))
            .count(),
        1,
        "{events:?}"
    );
    window.update(|_, app| {
        let state = shared.borrow().views[&2]
            .read(app)
            .states
            .combobox
            .as_ref()
            .unwrap()
            .clone();
        state.update(app, |_, cx| {
            cx.emit(gpui_kit::component::combobox::ComboboxEvent::Confirm(vec![
                3,
            ]));
        });
    });
    window.run_until_parked();
    assert!(
        support::take_events().is_empty(),
        "closing a popup with an unchanged selection must not activate it again"
    );
}

#[gpui_kit::test]
fn mounted_node_emits_appear_once_and_pointer_events(cx: &mut TestAppContext) {
    mount!(
        cx,
        shared,
        window,
        r#"{"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"root"},
        {"op":"create-node","id":2,"kind":"text"},
        {"op":"set-prop","id":2,"property":"text","value":"Mounted"},
        {"op":"set-prop","id":2,"property":"appear-enabled","value":true},
        {"op":"set-prop","id":2,"property":"pointer-enabled","value":true},
        {"op":"insert-child","parent":1,"child":2,"index":0}]}"#
    );
    assert_eq!(support::take_events(), vec![RecordedEvent::Appear(2)]);
    window.update(|window, _| window.refresh());
    window.run_until_parked();
    assert!(support::take_events().is_empty());
    let position = shared.borrow().node_bounds[&2].center();
    window.simulate_mouse_move(position, None::<MouseButton>, Default::default());
    window.simulate_mouse_down(position, MouseButton::Left, Default::default());
    window.simulate_mouse_up(position, MouseButton::Left, Default::default());
    window.simulate_mouse_move(
        point(px(-10.), px(-10.)),
        None::<MouseButton>,
        Default::default(),
    );
    window.run_until_parked();
    let events = support::take_events();
    for event in [
        RecordedEvent::PointerEnter(2),
        RecordedEvent::PointerDown(2),
        RecordedEvent::PointerUp(2),
        RecordedEvent::PointerLeave(2),
    ] {
        assert!(events.contains(&event), "missing {event:?} from {events:?}");
    }
}

#[gpui_kit::test]
fn closing_the_last_root_releases_retained_views_and_shared_state(cx: &mut TestAppContext) {
    let _guard = LOCK.lock().unwrap_or_else(|error| error.into_inner());
    cx.update(lui_gpui::init);
    let shared = LuiShared::new();
    let weak = std::rc::Rc::downgrade(&shared);
    let root = LuiRootView::new(shared.clone());
    let other_root = LuiRootView::new(shared.clone());
    cx.update(|app| {
        LuiShared::view_for(&shared, 1, app);
    });
    drop(root);
    assert_eq!(
        shared.borrow().views.len(),
        1,
        "another live root still owns the session"
    );
    drop(other_root);
    assert!(
        shared.borrow().views.is_empty(),
        "last root must dispose retained entities"
    );
    drop(shared);
    // Entity releases are collected at the end of an App update.
    cx.update(|_| {});
    cx.run_until_parked();
    assert!(
        weak.upgrade().is_none(),
        "Shared survives after its rendering session ends"
    );
}

#[gpui_kit::test]
fn closing_window_releases_stateful_controls(cx: &mut TestAppContext) {
    mount!(
        cx,
        shared,
        window,
        r#"{"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"root"},
        {"op":"create-node","id":2,"kind":"input"},
        {"op":"create-node","id":3,"kind":"textarea"},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":3,"index":1}]}"#
    );
    let weak = std::rc::Rc::downgrade(&shared);
    window.update(|window, _| window.remove_window());
    window.run_until_parked();
    drop(shared);
    cx.update(|_| {});
    cx.run_until_parked();
    assert!(
        weak.upgrade().is_none(),
        "stateful callbacks retained the closed session"
    );
}

#[gpui_kit::test]
fn semantic_toolbar_and_named_wrappers_keep_geometry(cx: &mut TestAppContext) {
    mount!(
        cx,
        shared,
        window,
        r#"{"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"root"},
        {"op":"create-node","id":2,"kind":"row"},
        {"op":"create-node","id":3,"kind":"toolbar"},
        {"op":"set-prop","id":3,"property":"accessibility-identifier","value":"toolbar"},
        {"op":"create-node","id":4,"kind":"text"},
        {"op":"set-prop","id":4,"property":"text","value":"Label"},
        {"op":"insert-child","parent":3,"child":4,"index":0},
        {"op":"insert-child","parent":2,"child":3,"index":0},
        {"op":"insert-child","parent":1,"child":2,"index":0}]}"#
    );
    let guard = shared.borrow();
    let toolbar = guard
        .node_bounds
        .get(&3)
        .expect("semantic toolbar must not be elided");
    assert!(
        toolbar.size.height > guard.node_bounds[&4].size.height,
        "toolbar padding must survive"
    );
}

#[gpui_kit::test]
fn named_layout_wrappers_remain_measurable(cx: &mut TestAppContext) {
    mount!(
        cx,
        shared,
        window,
        r#"{"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"root"},
        {"op":"create-node","id":2,"kind":"column"},
        {"op":"set-prop","id":2,"property":"accessibility-identifier","value":"wrapper"},
        {"op":"create-extension","id":3,"identifier":"logseq-div","fingerprint":"fp"},
        {"op":"set-extension-prop","id":3,"property":"attrs","value":"{\"id\":\"anchor\"}"},
        {"op":"create-node","id":4,"kind":"text"},
        {"op":"set-prop","id":4,"property":"text","value":"Label"},
        {"op":"insert-child","parent":3,"child":4,"index":0},
        {"op":"insert-child","parent":2,"child":3,"index":0},
        {"op":"insert-child","parent":1,"child":2,"index":0}]}"#
    );
    for id in [2, 3] {
        assert!(
            shared.borrow().node_bounds.contains_key(&id),
            "named wrapper {id} lost its geometry"
        );
    }
}

#[gpui_kit::test]
fn spacer_applies_explicit_dimensions(cx: &mut TestAppContext) {
    mount!(
        cx,
        shared,
        window,
        r#"{"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"root"},
        {"op":"create-node","id":2,"kind":"spacer"},
        {"op":"set-prop","id":2,"property":"width","value":40.0},
        {"op":"set-prop","id":2,"property":"height","value":40.0},
        {"op":"insert-child","parent":1,"child":2,"index":0}]}"#
    );
    assert_eq!(f32::from(shared.borrow().node_bounds[&2].size.height), 40.0);
}

#[gpui_kit::test]
fn picker_refreshes_option_labels_and_disabled_state(cx: &mut TestAppContext) {
    let executor = cx.background_executor.clone();
    mount!(
        cx,
        shared,
        window,
        r#"{"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"root"},
        {"op":"create-node","id":2,"kind":"select"},
        {"op":"set-prop","id":2,"property":"text","value":"Choose"},
        {"op":"create-node","id":3,"kind":"menu-item"},
        {"op":"set-prop","id":3,"property":"text","value":"Old"},
        {"op":"insert-child","parent":2,"child":3,"index":0},
        {"op":"insert-child","parent":1,"child":2,"index":0}]}"#
    );
    window.update(|_, app| {
        apply_batch_json(
            &shared,
            r#"{"generation":2,"ops":[
            {"op":"set-prop","id":3,"property":"text","value":"Renamed"}]}"#,
            app,
        )
        .unwrap();
    });
    window.run_until_parked();
    let position = shared.borrow().node_bounds[&2].origin + point(px(16.), px(16.));
    window.simulate_click(position, Default::default());
    window.run_until_parked();
    window.simulate_input("Renamed");
    window.run_until_parked();
    executor.advance_clock(std::time::Duration::from_millis(150));
    window.run_until_parked();
    window.update(|_, app| {
        apply_batch_json(
            &shared,
            r#"{"generation":3,"ops":[
            {"op":"set-prop","id":3,"property":"text","value":"Renamed again"}]}"#,
            app,
        )
        .unwrap();
    });
    window.run_until_parked();
    window.simulate_keystrokes("enter");
    window.run_until_parked();
    let events = support::take_events();
    assert!(
        events.contains(&RecordedEvent::Press(3)),
        "renamed option must be searchable: {events:?}"
    );
    window.update(|_, app| {
        apply_batch_json(
            &shared,
            r#"{"generation":4,"ops":[
            {"op":"set-prop","id":3,"property":"enabled","value":false}]}"#,
            app,
        )
        .unwrap();
    });
    window.run_until_parked();
    window.simulate_click(position, Default::default());
    window.run_until_parked();
    window.simulate_keystrokes("enter");
    window.run_until_parked();
    assert!(
        !support::take_events().contains(&RecordedEvent::Press(3)),
        "disabled option must not activate"
    );
}

#[gpui_kit::test]
fn combobox_refresh_preserves_selection_outside_active_search(cx: &mut TestAppContext) {
    mount!(
        cx,
        shared,
        window,
        r#"{"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"root"},
        {"op":"create-node","id":2,"kind":"combobox"},
        {"op":"create-node","id":3,"kind":"menu-item"},
        {"op":"set-prop","id":3,"property":"text","value":"Alpha"},
        {"op":"create-node","id":4,"kind":"menu-item"},
        {"op":"set-prop","id":4,"property":"text","value":"Beta"},
        {"op":"insert-child","parent":2,"child":3,"index":0},
        {"op":"insert-child","parent":2,"child":4,"index":1},
        {"op":"insert-child","parent":1,"child":2,"index":0}]}"#
    );
    window.update(|window, app| {
        let state = shared.borrow().views[&2]
            .read(app)
            .states
            .combobox
            .as_ref()
            .unwrap()
            .clone();
        state.update(app, |state, cx| {
            state.set_selected_values(&[3], window, cx);
            state.set_query("Beta", window, cx);
        });
    });
    window.run_until_parked();
    window.update(|_, app| {
        apply_batch_json(
            &shared,
            r#"{"generation":2,"ops":[
            {"op":"set-prop","id":3,"property":"text","value":"Renamed"}]}"#,
            app,
        )
        .unwrap();
    });
    window.run_until_parked();
    window.update(|_, app| {
        let state = shared.borrow().views[&2]
            .read(app)
            .states
            .combobox
            .as_ref()
            .unwrap()
            .clone();
        assert_eq!(state.read(app).query(app).as_ref(), "Beta");
        assert_eq!(state.read(app).selected_values(), vec![3]);
        assert_eq!(state.read(app).selection()[0].1.title.as_ref(), "Renamed");
    });
}

#[gpui_kit::test]
fn long_double_and_modified_presses_reach_the_bridge(cx: &mut TestAppContext) {
    mount!(
        cx,
        shared,
        window,
        r#"{"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"root"},
        {"op":"create-node","id":2,"kind":"list-item"},
        {"op":"set-prop","id":2,"property":"text","value":"Row"},
        {"op":"set-prop","id":2,"property":"long-press-enabled","value":true},
        {"op":"set-prop","id":2,"property":"double-press-enabled","value":true},
        {"op":"insert-child","parent":1,"child":2,"index":0}]}"#
    );
    let position = shared.borrow().node_bounds[&2].center();
    window.simulate_event(LongPressEvent {
        position,
        ..Default::default()
    });
    window.simulate_event(MouseDownEvent {
        position,
        button: MouseButton::Left,
        click_count: 2,
        modifiers: Default::default(),
        first_mouse: false,
    });
    window.simulate_mouse_up(position, MouseButton::Left, Default::default());
    window.simulate_click(
        position,
        Modifiers {
            control: true,
            ..Default::default()
        },
    );
    window.run_until_parked();
    let events = support::take_events();
    assert!(events.contains(&RecordedEvent::LongPress(2)), "{events:?}");
    assert!(
        events.contains(&RecordedEvent::DoublePress(2)),
        "{events:?}"
    );
    assert!(
        events.contains(&RecordedEvent::PressModifiers {
            node: 2,
            modifiers: 1
        }),
        "{events:?}"
    );
    window.update(|_, app| {
        apply_batch_json(
            &shared,
            r#"{"generation":2,"ops":[
            {"op":"set-prop","id":2,"property":"enabled","value":false}]}"#,
            app,
        )
        .unwrap();
    });
    window.run_until_parked();
    window.simulate_event(LongPressEvent {
        position,
        ..Default::default()
    });
    window.simulate_event(MouseDownEvent {
        position,
        button: MouseButton::Left,
        click_count: 2,
        modifiers: Default::default(),
        first_mouse: false,
    });
    window.run_until_parked();
    assert!(
        support::take_events().is_empty(),
        "disabled gestures must stay silent"
    );
}

#[gpui_kit::test]
fn bubbling_preserves_press_modifiers(cx: &mut TestAppContext) {
    mount!(
        cx,
        shared,
        window,
        r#"{"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"root"},
        {"op":"create-node","id":2,"kind":"column"},
        {"op":"set-prop","id":2,"property":"accessibility-identifier","value":"parent"},
        {"op":"create-node","id":3,"kind":"link"},
        {"op":"set-prop","id":3,"property":"text","value":"Child"},
        {"op":"insert-child","parent":2,"child":3,"index":0},
        {"op":"insert-child","parent":1,"child":2,"index":0}]}"#
    );
    let position = shared.borrow().node_bounds[&3].center();
    window.simulate_click(
        position,
        Modifiers {
            control: true,
            ..Default::default()
        },
    );
    window.run_until_parked();
    let events = support::take_events();
    assert!(
        !events.contains(&RecordedEvent::Press(2)),
        "modifier mask was lost while bubbling: {events:?}"
    );
    for node in [2] {
        assert!(
            events.contains(&RecordedEvent::PressModifiers { node, modifiers: 1 }),
            "{events:?}"
        );
    }
}

#[gpui_kit::test]
fn mouse_hold_emits_long_press_and_release_cancels_it(cx: &mut TestAppContext) {
    let executor = cx.background_executor.clone();
    mount!(
        cx,
        shared,
        window,
        r#"{"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"root"},
        {"op":"create-node","id":2,"kind":"button"},
        {"op":"set-prop","id":2,"property":"text","value":"Hold"},
        {"op":"set-prop","id":2,"property":"long-press-enabled","value":true},
        {"op":"insert-child","parent":1,"child":2,"index":0}]}"#
    );
    let position = shared.borrow().node_bounds[&2].center();
    window.simulate_mouse_down(position, MouseButton::Left, Default::default());
    window.run_until_parked();
    executor.advance_clock(std::time::Duration::from_millis(550));
    window.run_until_parked();
    assert_eq!(support::take_events(), vec![RecordedEvent::LongPress(2)]);
    window.simulate_mouse_up(position, MouseButton::Left, Default::default());
    window.run_until_parked();
    let _ = support::take_events();
    window.simulate_mouse_down(position, MouseButton::Left, Default::default());
    window.simulate_mouse_up(position, MouseButton::Left, Default::default());
    window.run_until_parked();
    let _ = support::take_events();
    executor.advance_clock(std::time::Duration::from_millis(550));
    window.run_until_parked();
    assert!(support::take_events().is_empty());
    // A new hold at the same point must not inherit the canceled timer.
    window.simulate_mouse_down(position, MouseButton::Left, Default::default());
    window.run_until_parked();
    executor.advance_clock(std::time::Duration::from_millis(250));
    window.run_until_parked();
    window.simulate_mouse_up(position, MouseButton::Left, Default::default());
    window.simulate_mouse_down(position, MouseButton::Left, Default::default());
    window.run_until_parked();
    let _ = support::take_events();
    executor.advance_clock(std::time::Duration::from_millis(300));
    window.run_until_parked();
    assert!(support::take_events().is_empty());
    executor.advance_clock(std::time::Duration::from_millis(250));
    window.run_until_parked();
    assert_eq!(support::take_events(), vec![RecordedEvent::LongPress(2)]);
}

#[test]
fn context_menu_leaf_hosts_accept_their_menu_children() {
    use lui_core::{store::Store, wire::decode_batch};
    for kind in [
        "toggle-button",
        "toggle",
        "radio",
        "slider",
        "number-stepper",
        "text-field",
        "secure-field",
        "input",
        "search-field",
        "textarea",
        "checkbox",
        "switch",
    ] {
        let mut store = Store::default();
        let batch = decode_batch(
            &serde_json::json!({"generation":1,"ops":[
                {"op":"create-node","id":1,"kind":kind},
                {"op":"create-node","id":2,"kind":"context-menu"},
                {"op":"insert-child","parent":1,"child":2,"index":0}
            ]})
            .to_string(),
        )
        .unwrap();
        assert!(
            store.apply(&batch).is_ok(),
            "{kind} must accept its context menu"
        );
    }
}

#[gpui_kit::test]
fn imperative_input_updates_preserve_runtime_generation(cx: &mut TestAppContext) {
    mount!(
        cx,
        shared,
        window,
        r#"{"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"root"},
        {"op":"create-node","id":2,"kind":"input"},
        {"op":"set-prop","id":2,"property":"value","value":""},
        {"op":"insert-child","parent":1,"child":2,"index":0}]}"#
    );
    for value in ["imperative", "", ""] {
        window.update(|window, app| {
            let input = shared.borrow().views[&2]
                .read(app)
                .states
                .input
                .as_ref()
                .unwrap()
                .clone();
            input.update(app, |state, cx| state.set_value("typed", window, cx));
            lui_gpui::domops::handle_dom_op(
                &shared,
                "set-value",
                &serde_json::json!({"ref":{"node-id":2},"value":value}).to_string(),
                window,
                app,
            );
            assert_eq!(
                shared
                    .borrow()
                    .store
                    .node(2)
                    .unwrap()
                    .string_prop(lui_core::Property::ProgressValue),
                Some(value)
            );
            assert_eq!(input.read(app).value().as_ref(), value);
            assert_eq!(shared.borrow().store.generation, 1);
        });
        window.run_until_parked();
        window.update(|_, app| {
            let input = shared.borrow().views[&2]
                .read(app)
                .states
                .input
                .as_ref()
                .unwrap()
                .clone();
            assert_eq!(input.read(app).value().as_ref(), value);
        });
    }
    window.update(|_, app| {
        apply_batch_json(
            &shared,
            r#"{"generation":2,"ops":[
        {"op":"set-prop","id":2,"property":"value","value":"model"}]}"#,
            app,
        )
        .unwrap();
        assert!(apply_batch_json(&shared, r#"{"generation":0,"ops":[]}"#, app).is_err());
        assert!(apply_batch_json(&shared, r#"{"generation":4,"ops":[]}"#, app).is_err());
        assert_eq!(shared.borrow().store.generation, 2);
    });
}

#[gpui_kit::test]
fn imperative_dom_mutations_preserve_runtime_generation(cx: &mut TestAppContext) {
    mount!(
        cx,
        shared,
        window,
        r#"{"generation":1,"ops":[
        {"op":"create-node","id":1,"kind":"root"},
        {"op":"create-node","id":2,"kind":"text"},
        {"op":"insert-child","parent":1,"child":2,"index":0}]}"#
    );
    window.update(|window, app| {
        for (op, body) in [
            ("class-add", r#"{"ref":{"node-id":2},"class":"accent"}"#),
            ("set-text", r#"{"ref":{"node-id":2},"text":"updated"}"#),
            (
                "style-set-property",
                r#"{"ref":{"node-id":2},"property":"color","value":"red"}"#,
            ),
            (
                "style-set-property",
                r#"{"property":"--gpui-binding-test-color","value":"blue"}"#,
            ),
        ] {
            lui_gpui::domops::handle_dom_op(&shared, op, body, window, app);
        }
        {
            let guard = shared.borrow();
            let node = guard.store.node(2).unwrap();
            assert_eq!(
                node.string_prop(lui_core::Property::StyleClass),
                Some("accent")
            );
            assert_eq!(
                node.string_prop(lui_core::Property::TextValue),
                Some("updated")
            );
            let attrs: serde_json::Value =
                serde_json::from_str(node.extension_props["attrs"].as_str().unwrap()).unwrap();
            assert_eq!(attrs["style"], "color:red");
            assert!(guard
                .store
                .node(1)
                .unwrap()
                .extension_props
                .contains_key("css-vars-rev"));
            assert_eq!(guard.store.generation, 1);
        }
        lui_gpui::domops::handle_dom_op(&shared, "remove", r#"{"ref":{"node-id":2}}"#, window, app);
        assert!(shared.borrow().store.node(2).is_none());
        assert!(!shared.borrow().views.contains_key(&2));
        assert_eq!(shared.borrow().store.generation, 1);
        apply_batch_json(&shared, r#"{"generation":2,"ops":[]}"#, app).unwrap();
    });
}
