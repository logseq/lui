//! `NodeKind` -> gpui-kit element dispatch. Every container embeds children
//! as `Entity<LuiNodeView>` handles so per-node redraw isolation holds.

use gpui_kit::base::{Align, ElementExt, Placement, Positioner, StyledExt};
use gpui_kit::component::alert::{Alert, AlertVariant};
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::checkbox::Checkbox;
use gpui_kit::component::combobox::{Combobox, ComboboxEvent, ComboboxState};
use gpui_kit::component::input::{Input, InputEvent, InputState, Textarea, TextareaState};
use gpui_kit::component::link::Link;
use gpui_kit::component::progress::Progress;
use gpui_kit::component::radio::Radio;
use gpui_kit::component::select::{Select, SelectEvent, SelectState};
use gpui_kit::component::separator::Separator;
use gpui_kit::component::slider::{Slider, SliderEvent, SliderState, SliderValue};
use gpui_kit::component::spinner::Spinner;
use gpui_kit::component::switch::Switch;
use gpui_kit::component::theme::ActiveTheme;
use gpui_kit::component::Icon;
use gpui_kit::component::{h_flex, v_flex, Disableable, Sizable};
use gpui_kit::gpui::{
    anchored, deferred, div, point, px, Anchor, AnyElement, App, AppContext, ClickEvent, Context,
    ElementId, FontWeight, InteractiveElement, IntoElement, Modifiers, MouseButton,
    MouseDownEvent, ParentElement, PathPromptOptions, Pixels, Point,
    StatefulInteractiveElement, Styled, Window,
};
use lui_core::bridge;
use lui_core::store::NodeIdentity;
use lui_core::{EventKind, NodeKind, Property};

use crate::backend::{fire, LuiShared, Shared};
use crate::extension;
use crate::node_view::{LuiNodeView, LuiOption, NodeSnapshot};
use crate::style;

fn element_id(node_id: i64) -> ElementId {
    // Element ids live inside the entity's own id space — per-node ids are
    // unique and stable across renders.
    ElementId::Name(format!("lui-{node_id}").into())
}

fn text_of(node: &NodeSnapshot) -> String {
    node.text()
}

/// The `modifiers` bitmask shared with `PressModifiers`: 1=ctrl, 2=shift,
/// 4=platform (command on macOS), 8=secondary (right) button.
fn pointer_modifier_mask(modifiers: &Modifiers, button: MouseButton) -> i32 {
    (if modifiers.control { 1 } else { 0 })
        | (if modifiers.shift { 2 } else { 0 })
        | (if modifiers.platform { 4 } else { 0 })
        | (if button == MouseButton::Right { 8 } else { 0 })
}

/// Browser-style button index: 0 primary, 1 auxiliary (middle), 2 secondary.
fn pointer_button_index(button: MouseButton) -> i32 {
    match button {
        MouseButton::Middle => 1,
        MouseButton::Right => 2,
        _ => 0,
    }
}

/// Emit the shared pointer-detail payload via the C bridge. `target_class`
/// stays empty — there is no DOM hit element on this host.
fn fire_pointer_detail<F>(
    shared: &Shared,
    node_id: i64,
    event: EventKind,
    cx: &mut App,
    position: Point<Pixels>,
    button: MouseButton,
    modifiers: &Modifiers,
    call: F,
) -> i32
where
    F: FnOnce(f64, f64, i32, i32) -> i32,
{
    let x = f64::from(f32::from(position.x));
    let y = f64::from(f32::from(position.y));
    let modifiers = pointer_modifier_mask(modifiers, button);
    let button = pointer_button_index(button);
    fire(shared, node_id, event, cx, || call(x, y, modifiers, button))
}

/// Fire `Press` on a node when the gate allows it.
fn press_handler(
    view: &LuiNodeView,
    node_id: i64,
) -> impl Fn(&ClickEvent, &mut Window, &mut App) + 'static {
    let shared = view.shared.clone();
    move |event, _, cx| {
        fire(&shared, node_id, EventKind::Press, cx, || unsafe {
            bridge::lui_ocaml_press(node_id)
        });
        // `fire` re-gates admission (pointer-enabled + kind), so a click on
        // a non-pointer node only reports the plain Press. Keyboard/touch
        // activations report the primary button index (0).
        let button = match event {
            ClickEvent::Mouse(mouse) => mouse.down.button,
            _ => MouseButton::Left,
        };
        let position = event.position();
        let modifiers = event.modifiers();
        fire_pointer_detail(
            &shared,
            node_id,
            EventKind::PressDetail,
            cx,
            position,
            button,
            &modifiers,
            |x, y, modifiers, button| unsafe {
                bridge::lui_ocaml_press_detail(
                    node_id, x, y, modifiers, button, c"".as_ptr(),
                )
            },
        );
    }
}

fn toggle_handler(
    view: &LuiNodeView,
    node_id: i64,
) -> impl Fn(&bool, &mut Window, &mut App) + 'static {
    let shared = view.shared.clone();
    move |checked, _, cx| {
        let checked = *checked;
        fire(&shared, node_id, EventKind::ToggleChanged, cx, || unsafe {
            bridge::lui_ocaml_toggle_changed(node_id, checked as i32)
        });
    }
}

fn radio_handler(
    view: &LuiNodeView,
    node_id: i64,
) -> impl Fn(&bool, &mut Window, &mut App) + 'static {
    let shared = view.shared.clone();
    move |checked, _, cx| {
        if !*checked {
            return;
        }
        fire(&shared, node_id, EventKind::Change, cx, || unsafe {
            bridge::lui_ocaml_radio_changed(node_id)
        });
    }
}

/// Shared container render: direction + press gate + style props + children
/// as per-node entities.
fn container(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    _kind: NodeKind,
    horizontal: bool,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    // `on_children_prepainted` is a `Div` method — attach before `.id()`
    // (which wraps the element in `Stateful`).
    let base = if horizontal {
        h_flex()
            .on_children_prepainted(view.bounds_recorder(node))
            .id(element_id(node.id))
    } else {
        v_flex()
            .on_children_prepainted(view.bounds_recorder(node))
            .id(element_id(node.id))
    };
    let mut element = base;
    if !node.enabled() {
        element = element.opacity(0.5);
    }
    // Any container kind may carry `pressable` (the model enables the
    // PressEnabled prop) — the gate decides, not the kind.
    if press_gate(view, node.id) {
        element = element
            .cursor_pointer()
            .on_click(press_handler(view, node.id));
    }
    let element = style::all(element, node);
    element
        .children(view.child_elements(node, cx))
        .into_any_element()
}

/// Cheap gate peek (same rule as `fire`, avoids wiring dead handlers).
fn event_gate(view: &LuiNodeView, node_id: i64, event: EventKind) -> bool {
    let shared = view.shared.borrow();
    shared
        .store
        .node(node_id)
        .map(|node| lui_core::event_allowed(node, event))
        .unwrap_or(false)
}

fn press_gate(view: &LuiNodeView, node_id: i64) -> bool {
    event_gate(view, node_id, EventKind::Press)
}

fn dismiss_handler(
    view: &LuiNodeView,
    node_id: i64,
) -> impl Fn(&MouseDownEvent, &mut Window, &mut App) + 'static {
    let shared = view.shared.clone();
    move |_, _, cx| {
        fire(&shared, node_id, EventKind::Dismiss, cx, || unsafe {
            bridge::lui_ocaml_dismiss(node_id)
        });
    }
}

fn variant_of(node: &NodeSnapshot) -> &str {
    node.string_prop(Property::VariantValue)
        .unwrap_or("default")
}

fn button_variant(button: Button, node: &NodeSnapshot) -> Button {
    match variant_of(node) {
        "primary" => button.primary(),
        "secondary" => button.secondary(),
        "outline" => button.outline(),
        "ghost" => button.ghost(),
        "destructive" => button.danger(),
        "link" => button.link(),
        _ => button,
    }
}

fn button_size(button: Button, node: &NodeSnapshot) -> Button {
    match node.string_prop(Property::SizeValue) {
        Some("sm") => button.small(),
        Some("lg") => button.large(),
        _ => button,
    }
}

fn button(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    _cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let node_id = node.id;
    let icon_size = node.string_prop(Property::SizeValue) == Some("icon");
    let label = if icon_size {
        String::new()
    } else {
        text_of(node)
    };
    let mut button = Button::new(element_id(node_id)).label(label);
    button = button_variant(button, node);
    button = button_size(button, node);
    if icon_size {
        button = button.compact();
    }
    if let Some(icon) =
        icon_name(node, Property::InlineIconName).or_else(|| icon_name(node, Property::IconName))
    {
        button = button.icon(icon);
    }
    button = button.disabled(!node.enabled());
    button = button.on_click(press_handler(view, node_id));
    style::all(button, node).into_any_element()
}

fn icon_name(node: &NodeSnapshot, property: Property) -> Option<gpui_kit::assets::IconName> {
    let name = node.string_prop(property)?;
    Some(match name {
        "alert" => gpui_kit::assets::IconName::TriangleAlert,
        "archive" => gpui_kit::assets::IconName::Archive,
        "arrow-down" => gpui_kit::assets::IconName::ArrowDown,
        "arrow-right" => gpui_kit::assets::IconName::ArrowRight,
        "arrow-up" => gpui_kit::assets::IconName::ArrowUp,
        "check" => gpui_kit::assets::IconName::Check,
        "check-circle" => gpui_kit::assets::IconName::CircleCheck,
        "chevron-down" => gpui_kit::assets::IconName::ChevronDown,
        "chevron-left" => gpui_kit::assets::IconName::ChevronLeft,
        "chevron-right" => gpui_kit::assets::IconName::ChevronRight,
        "chevron-up" => gpui_kit::assets::IconName::ChevronUp,
        "circle-dot" => gpui_kit::assets::IconName::CircleDot,
        "clock" => gpui_kit::assets::IconName::Clock,
        "copy" => gpui_kit::assets::IconName::Copy,
        "download" => gpui_kit::assets::IconName::Download,
        "edit" => gpui_kit::assets::IconName::Pencil,
        "ellipsis" => gpui_kit::assets::IconName::Ellipsis,
        "external-link" => gpui_kit::assets::IconName::ExternalLink,
        "eye" => gpui_kit::assets::IconName::Eye,
        "file-text" => gpui_kit::assets::IconName::FileText,
        "folder" => gpui_kit::assets::IconName::Folder,
        "folder-open" => gpui_kit::assets::IconName::FolderOpen,
        "git-branch" => gpui_kit::assets::IconName::GitBranch,
        "git-merge" => gpui_kit::assets::IconName::GitMerge,
        "git-pull-request" => gpui_kit::assets::IconName::GitPullRequest,
        "info" => gpui_kit::assets::IconName::Info,
        "menu" => gpui_kit::assets::IconName::Menu,
        "mic" => gpui_kit::assets::IconName::Mic,
        "moon" => gpui_kit::assets::IconName::Moon,
        "music" => gpui_kit::assets::IconName::Music,
        "panel-left" => gpui_kit::assets::IconName::PanelLeft,
        "panel-right" => gpui_kit::assets::IconName::PanelRight,
        "pause" => gpui_kit::assets::IconName::Pause,
        "play" => gpui_kit::assets::IconName::Play,
        "plus" => gpui_kit::assets::IconName::Plus,
        "refresh-cw" => gpui_kit::assets::IconName::RefreshCw,
        "repeat" => gpui_kit::assets::IconName::Repeat,
        "save" => gpui_kit::assets::IconName::Save,
        "search" => gpui_kit::assets::IconName::Search,
        "send" => gpui_kit::assets::IconName::Send,
        "settings" => gpui_kit::assets::IconName::Settings,
        "shuffle" => gpui_kit::assets::IconName::Shuffle,
        "skip-back" => gpui_kit::assets::IconName::SkipBack,
        "skip-forward" => gpui_kit::assets::IconName::SkipForward,
        "sun" => gpui_kit::assets::IconName::Sun,
        "terminal" => gpui_kit::assets::IconName::Terminal,
        "trash" => gpui_kit::assets::IconName::Trash,
        "volume" => gpui_kit::assets::IconName::Volume2,
        "wrench" => gpui_kit::assets::IconName::Wrench,
        "x" => gpui_kit::assets::IconName::X,
        "x-circle" => gpui_kit::assets::IconName::CircleX,
        _ => return None,
    })
}

fn text_element(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    _cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let mut element = div().id(element_id(node.id)).child(text_of(node));
    // Press-capable text kinds (text, list-item content handled elsewhere).
    if press_gate(view, node.id) {
        element = element
            .cursor_pointer()
            .on_click(press_handler(view, node.id));
    }
    element = style::all(element, node);
    element.into_any_element()
}

fn input(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    kind: NodeKind,
    window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let node_id = node.id;
    if view.states.input.is_none() {
        let placeholder = node
            .string_prop(Property::PlaceholderValue)
            .unwrap_or("")
            .to_string();
        let value = node
            .string_prop(Property::ProgressValue)
            .or_else(|| node.string_prop(Property::TextValue))
            .unwrap_or("")
            .to_string();
        let masked = kind == NodeKind::SecureField;
        let state = cx.new(|cx| {
            let mut state = InputState::new(window, cx).placeholder(placeholder);
            if masked {
                state = state.masked(true);
            }
            if !value.is_empty() {
                state = state.default_value(value.clone());
            }
            state
        });
        let shared = view.shared.clone();
        let subscription =
            cx.subscribe(
                &state,
                move |_this, state, event: &InputEvent, cx| match event {
                    InputEvent::Change => {
                        let text = state.read(cx).value().to_string();
                        let sending = std::ffi::CString::new(text.clone()).unwrap_or_default();
                        fire(&shared, node_id, EventKind::TextChanged, cx, || unsafe {
                            bridge::lui_ocaml_text_changed(node_id, sending.as_ptr())
                        });
                    }
                    InputEvent::PressEnter { .. } => {
                        fire(&shared, node_id, EventKind::Submit, cx, || unsafe {
                            bridge::lui_ocaml_submit(node_id)
                        });
                    }
                    _ => {}
                },
            );
        view.states.subscriptions.push(subscription);
        view.states.input = Some(state);
    }
    let state = view.states.input.clone().expect("initialized");
    // Controlled-value echo: push wire `value` into the state when it drifts.
    if let Some(value) = node
        .string_prop(Property::ProgressValue)
        .or_else(|| node.string_prop(Property::TextValue))
    {
        let current = state.read(cx).value().to_string();
        if value != current {
            state.update(cx, |state, cx| {
                state.set_value(value.to_string(), window, cx)
            });
        }
    }
    let mut input = Input::new(&state);
    if !node.enabled() {
        input = input.disabled(true);
    }
    style::all(input, node).into_any_element()
}

fn textarea(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let node_id = node.id;
    if view.states.textarea.is_none() {
        let placeholder = node
            .string_prop(Property::PlaceholderValue)
            .unwrap_or("")
            .to_string();
        let value = node
            .string_prop(Property::ProgressValue)
            .or_else(|| node.string_prop(Property::TextValue))
            .unwrap_or("")
            .to_string();
        let state = cx.new(|cx| {
            let mut state = TextareaState::new(window, cx).placeholder(placeholder);
            if !value.is_empty() {
                state = state.default_value(value);
            }
            state
        });
        let shared = view.shared.clone();
        let subscription = cx.subscribe(&state, move |_this, state, event: &InputEvent, cx| {
            if let InputEvent::Change = event {
                let text = state.read(cx).value().to_string();
                let sending = std::ffi::CString::new(text).unwrap_or_default();
                fire(&shared, node_id, EventKind::TextChanged, cx, || unsafe {
                    bridge::lui_ocaml_text_changed(node_id, sending.as_ptr())
                });
            }
        });
        view.states.subscriptions.push(subscription);
        view.states.textarea = Some(state);
    }
    let state = view.states.textarea.clone().expect("initialized");
    Textarea::new(&state).into_any_element()
}

fn slider(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let node_id = node.id;
    if view.states.slider.is_none() {
        let min = node.float_prop(Property::MinValue).unwrap_or(0.0) as f32;
        let max = node.float_prop(Property::MaxValue).unwrap_or(1.0) as f32;
        let step = node.float_prop(Property::StepValue).unwrap_or(0.0) as f32;
        let value = node.float_prop(Property::ProgressValue).unwrap_or(0.0) as f32;
        let state = cx.new(|cx| {
            let mut state = SliderState::new().min(min).max(max);
            if step > 0.0 {
                state = state.step(step);
            }
            state.set_value(value, window, cx);
            state
        });
        let shared = view.shared.clone();
        let subscription = cx.subscribe(&state, move |_this, _state, event: &SliderEvent, cx| {
            if let SliderEvent::Change(SliderValue::Single(value))
            | SliderEvent::Release(SliderValue::Single(value)) = event
            {
                let value = *value as f64;
                fire(&shared, node_id, EventKind::ValueChanged, cx, || unsafe {
                    bridge::lui_ocaml_slider_changed(node_id, value)
                });
            }
        });
        view.states.subscriptions.push(subscription);
        view.states.slider = Some(state);
    }
    let state = view.states.slider.clone().expect("initialized");
    // Sync wire `value` into the state when OCaml drives it (set_value only
    // notifies — no event — so no echo loop).
    if let Some(value) = node.float_prop(Property::ProgressValue) {
        let current = match state.read(cx).value() {
            SliderValue::Single(value) => value,
            SliderValue::Range(start, _) => start,
        };
        if (value as f32 - current).abs() > f32::EPSILON {
            state.update(cx, |state, cx| state.set_value(value as f32, window, cx));
        }
    }
    let mut slider = Slider::new(&state);
    if node.string_prop(Property::OrientationValue) == Some("vertical") {
        slider = slider.vertical();
    }
    slider = slider.disabled(!node.enabled());
    style::all(slider, node).into_any_element()
}

/// `menu-item` children of `node` as selectable options. Children are the
/// option source for the native searchable list; an empty list means the
/// model uses its own mounted menu instead.
fn option_items(view: &LuiNodeView, node: &NodeSnapshot) -> Vec<LuiOption> {
    let shared = view.shared.borrow();
    node.children
        .iter()
        .filter_map(|child_id| {
            shared
                .store
                .node(*child_id)
                .filter(|child| child.identity.kind() == Some(NodeKind::MenuItem))
                .map(|child| LuiOption {
                    node_id: *child_id,
                    title: child
                        .string_prop(Property::TextValue)
                        .or_else(|| child.string_prop(Property::TitleValue))
                        .unwrap_or("")
                        .into(),
                    disabled: !child.enabled(),
                })
        })
        .collect()
}

/// Push the option list into the state's delegate only when the source
/// node ids changed — re-setting items mid-render resets the search
/// query otherwise.
fn sync_options(view: &LuiNodeView, items: Vec<LuiOption>, set: impl FnOnce(Vec<LuiOption>)) {
    let ids: Vec<i64> = items.iter().map(|item| item.node_id).collect();
    if *view.states.options_cache.borrow() != ids {
        *view.states.options_cache.borrow_mut() = ids;
        set(items);
    }
}

/// `select`: native gpui-kit Select with a searchable list when the model
/// mounts `menu-item` children as the option source; confirming fires
/// `Press` on the source item so the model's own handler runs. Without
/// option children it stays a trigger whose `press` opens the model-owned
/// menu (e.g. a `dropdown-menu` sibling).
fn select_picker(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let node_id = node.id;
    let items = option_items(view, node);
    if items.is_empty() {
        // Trigger-shaped outline button; `press` opens the model-owned
        // menu (usually mounted as a `dropdown-menu` sibling).
        let mut element = Button::new(element_id(node_id))
            .label(if text_of(node).is_empty() {
                "Select…".to_string()
            } else {
                text_of(node)
            })
            .outline()
            .icon(gpui_kit::assets::IconName::ChevronDown);
        element = element.disabled(!node.enabled());
        element = element.on_click(press_handler(view, node_id));
        element = style::all(element, node);
        return element.into_any_element();
    }
    if view.states.select.is_none() {
        let state = cx
            .new(|cx| SelectState::new(Vec::<LuiOption>::new(), None, window, cx).searchable(true));
        let shared = view.shared.clone();
        let subscription = cx.subscribe(
            &state,
            move |_this, _state, event: &SelectEvent<Vec<LuiOption>>, cx| {
                if let SelectEvent::Confirm(Some(item_id)) = event {
                    let item_id = *item_id;
                    fire(&shared, item_id, EventKind::Press, cx, || unsafe {
                        bridge::lui_ocaml_press(item_id)
                    });
                }
            },
        );
        view.states.subscriptions.push(subscription);
        view.states.select = Some(state);
    }
    let state = view.states.select.clone().expect("initialized");
    sync_options(view, items, |items| {
        state.update(cx, |state, cx| state.set_items(items, window, cx));
    });
    let mut element = Select::new(&state);
    element = element.placeholder(if text_of(node).is_empty() {
        "Select…".to_string()
    } else {
        text_of(node)
    });
    element = element.disabled(!node.enabled());
    style::all(element, node).into_any_element()
}

/// `combobox`: native gpui-kit Combobox (editable + searchable) when
/// `menu-item` children are mounted; confirming reports `text_changed`
/// with the item title then `Press` on the item node. Without options it
/// stays an input whose `press` opens the model-owned menu.
fn combobox_picker(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    kind: NodeKind,
    window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let node_id = node.id;
    let items = option_items(view, node);
    if items.is_empty() {
        // Editable field: input events feed `text_changed`/`submit`,
        // clicks also fire `press` so the model can open its menu.
        let field = input(view, node, kind, window, cx);
        return if press_gate(view, node_id) {
            div()
                .id(ElementId::Name(format!("lui-{}-combo", node_id).into()))
                .on_click(press_handler(view, node_id))
                .child(field)
                .into_any_element()
        } else {
            field
        };
    }
    if view.states.combobox.is_none() {
        let state = cx.new(|cx| {
            ComboboxState::new(Vec::<LuiOption>::new(), Vec::new(), window, cx).searchable(true)
        });
        let shared = view.shared.clone();
        let subscription = cx.subscribe(
            &state,
            move |_this, _state, event: &ComboboxEvent<Vec<LuiOption>>, cx| {
                let item_id = match event {
                    ComboboxEvent::Confirm(values) | ComboboxEvent::Change(values) => {
                        values.first().copied()
                    }
                };
                if let Some(item_id) = item_id {
                    let title = shared
                        .borrow()
                        .store
                        .node(item_id)
                        .map(|item| {
                            item.string_prop(Property::TextValue)
                                .or_else(|| item.string_prop(Property::TitleValue))
                                .unwrap_or("")
                                .to_string()
                        })
                        .unwrap_or_default();
                    if event_gate_id(&shared, node_id, EventKind::TextChanged) {
                        let sending = std::ffi::CString::new(title).unwrap_or_default();
                        fire(&shared, node_id, EventKind::TextChanged, cx, || unsafe {
                            bridge::lui_ocaml_text_changed(node_id, sending.as_ptr())
                        });
                    }
                    fire(&shared, item_id, EventKind::Press, cx, || unsafe {
                        bridge::lui_ocaml_press(item_id)
                    });
                }
            },
        );
        view.states.subscriptions.push(subscription);
        view.states.combobox = Some(state);
    }
    let state = view.states.combobox.clone().expect("initialized");
    sync_options(view, items, |items| {
        state.update(cx, |state, cx| state.set_items(items, window, cx));
    });
    let mut element = Combobox::new(&state);
    let label = text_of(node);
    let placeholder = node
        .string_prop(Property::PlaceholderValue)
        .unwrap_or(if label.is_empty() {
            "Select…"
        } else {
            &label
        });
    element = element.placeholder(placeholder);
    element = element.disabled(!node.enabled());
    style::all(element, node).into_any_element()
}

/// `overlay`/`stack`: first child lays out in-flow (sizing the stack to the
/// trigger), the rest overlay absolutely on top of it.
fn stacked(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let mut children = view.child_elements(node, cx).into_iter();
    let mut element = div()
        .relative()
        .on_children_prepainted(view.bounds_recorder(node))
        .id(element_id(node.id));
    if let Some(first) = children.next() {
        element = element.child(first);
    }
    element = element.children(children.map(|child| {
        div()
            .absolute()
            .top_0()
            .left_0()
            .size_full()
            .child(child)
            .into_any_element()
    }));
    style::all(element, node).into_any_element()
}

/// Full-window backdrop that swallows outside clicks into `Dismiss`.
fn backdrop(view: &LuiNodeView, node_id: i64, window: &Window) -> gpui_kit::gpui::Div {
    let viewport = window.viewport_size();
    let mut layer = div()
        .absolute()
        .top_0()
        .left_0()
        .w(viewport.width)
        .h(viewport.height)
        .occlude();
    if event_gate(view, node_id, EventKind::Dismiss) {
        layer = layer.on_mouse_down(MouseButton::Left, dismiss_handler(view, node_id));
    }
    layer
}

/// Deferred layer covering the whole window at (0,0).
fn window_layer(content: impl IntoElement, priority: usize) -> impl IntoElement {
    deferred(
        anchored()
            .position(point(px(0.), px(0.)))
            .snap_to_window()
            .child(content),
    )
    .with_priority(priority)
}

/// Dialog/Drawer/Sheet/Toast: model-owned nodes emitted only while open —
/// the host renders them as a deferred full-window overlay; backdrop clicks
/// and the model's own dismiss both drain through `lui_ocaml_dismiss`.
fn overlay_modal(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    kind: NodeKind,
    window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let viewport = window.viewport_size();
    let children = view.child_elements(node, cx);

    let mut card = v_flex()
        .gap_2()
        .bg(cx.theme().popover)
        .border_1()
        .border_color(cx.theme().border);
    if !text_of(node).is_empty() {
        card = card.child(div().font_weight(FontWeight::SEMIBOLD).child(text_of(node)));
    }
    if let Some(description) = node.string_prop(Property::DescriptionValue) {
        card = card.child(
            div()
                .text_sm()
                .text_color(cx.theme().muted_foreground)
                .child(description.to_string()),
        );
    }
    card = card.children(children);

    let surface = match kind {
        NodeKind::Dialog => card
            .w(node
                .float_prop(Property::WidthValue)
                .map(|w| px(w as f32))
                .unwrap_or(px(400.)))
            .p_4()
            .rounded_lg()
            .shadow_lg()
            .into_any_element(),
        NodeKind::Drawer => card
            .w(node
                .float_prop(Property::WidthValue)
                .map(|w| px(w as f32))
                .unwrap_or(px(320.)))
            .h_full()
            .p_4()
            .shadow_lg()
            .into_any_element(),
        NodeKind::Sheet => card
            .w_full()
            .h(node
                .float_prop(Property::HeightValue)
                .map(|h| px(h as f32))
                .unwrap_or(px(360.)))
            .p_4()
            .rounded_t_lg()
            .shadow_lg()
            .into_any_element(),
        _ => card
            .max_w(px(360.))
            .p_3()
            .rounded_lg()
            .shadow_lg()
            .into_any_element(),
    };

    let mut layer = div()
        .relative()
        .w(viewport.width)
        .h(viewport.height)
        .child(backdrop(view, node.id, window));
    layer = match kind {
        NodeKind::Sheet => layer.v_flex().justify_end().child(surface),
        NodeKind::Drawer => layer.h_flex().justify_end().child(surface),
        NodeKind::Toast => layer.child(div().absolute().top_4().right_4().child(surface)),
        _ => layer
            .v_flex()
            .items_center()
            .justify_center()
            .child(surface),
    };

    div()
        .id(element_id(node.id))
        .size_0()
        .child(window_layer(layer, 2))
        .into_any_element()
}

/// Popover-styled box wrapping menu children (dropdown/context menus).
fn menu_box(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    cx: &mut Context<LuiNodeView>,
) -> gpui_kit::gpui::Div {
    let mut element = v_flex()
        .gap_0p5()
        .p_1()
        .bg(cx.theme().popover)
        .border_1()
        .border_color(cx.theme().border)
        .rounded_md()
        .shadow_lg();
    let min_width = node.float_prop(Property::MinWidth).unwrap_or(160.).max(0.);
    element = element.min_w(px(min_width as f32));
    element.children(view.child_elements(node, cx))
}

/// `dropdown-menu`: mounted inside a `stack` while open — the overlay tracks
/// the stack bounds on prepaint and the deferred popup resolves against them
/// via `Positioner::side` (side/alignment/offset from `anchor` props, flip +
/// viewport clamp built in). `anchor-alignment:stretch` widens the menu to
/// the trigger's width. A press outside the menu box fires `Dismiss` (the
/// model then drops the node).
fn dropdown_menu(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    _window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let offset = node.float_prop(Property::AnchorOffset).unwrap_or(0.) as f32;
    let placement = match node.string_prop(Property::AnchorValue) {
        Some("above") => Placement::Top,
        Some("left") => Placement::Left,
        Some("right") => Placement::Right,
        _ => Placement::Bottom,
    };
    let (align, stretch) = match node.string_prop(Property::AnchorAlignmentValue) {
        Some("end") => (Align::End, false),
        Some("center") => (Align::Center, false),
        Some("stretch") => (Align::Start, true),
        _ => (Align::Start, false),
    };
    let mut menu = menu_box(view, node, cx);
    if event_gate(view, node.id, EventKind::Dismiss) {
        let shared = view.shared.clone();
        let node_id = node.id;
        menu = menu.on_mouse_down_out(move |_, _, cx| {
            fire(&shared, node_id, EventKind::Dismiss, cx, || unsafe {
                bridge::lui_ocaml_dismiss(node_id)
            });
        });
    }
    let trigger_bounds = view.states.menu_bounds.get();
    let mut popup = Positioner::side(trigger_bounds.unwrap_or_default())
        .placement(placement)
        .align(align)
        .offset(px(offset))
        .occlude();
    if stretch {
        if let Some(bounds) = trigger_bounds {
            menu = menu.w(bounds.size.width);
        }
    }
    popup = popup.child(menu.into_any_element());
    div()
        .id(element_id(node.id))
        .absolute()
        .size_full()
        .on_prepaint({
            let entity_id = cx.entity().entity_id();
            let menu_bounds = view.states.menu_bounds.clone();
            move |bounds, _, cx| {
                if menu_bounds.get() != Some(bounds) {
                    menu_bounds.set(Some(bounds));
                    cx.notify(entity_id);
                }
            }
        })
        .child(deferred(popup).with_priority(2))
        .into_any_element()
}

/// `list-item`/`treeitem` row: indent by `tree-level`, disclosure chevron
/// driving `toggle_changed`, leading icon, selected background, press and
/// right-click context menu.
fn list_item(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    _window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let hover_bg = cx.theme().accent;
    let selected = node.flag(Property::Selected);
    let mut row = h_flex()
        .id(element_id(node.id))
        .w_full()
        .items_center()
        .gap_2()
        .px_2()
        .py_1()
        .rounded_md()
        .hover(move |style| style.bg(hover_bg));
    if selected {
        row = row.bg(cx.theme().accent);
    }

    let level = node.int_prop(Property::TreeLevel).unwrap_or(0).max(0);
    if level > 1 {
        row = row.pl(px(16. * (level - 1) as f32));
    }

    // Disclosure chevron for expandable tree items.
    if node.is_treeitem() && event_gate(view, node.id, EventKind::ToggleChanged) {
        let expanded = node.flag(Property::Expanded);
        let icon = if expanded {
            gpui_kit::assets::IconName::ChevronDown
        } else {
            gpui_kit::assets::IconName::ChevronRight
        };
        let shared = view.shared.clone();
        let node_id = node.id;
        row = row.child(
            div()
                .id(ElementId::Name(format!("lui-{}-twisty", node.id).into()))
                .cursor_pointer()
                .child(
                    Icon::new(icon)
                        .size_4()
                        .text_color(cx.theme().muted_foreground),
                )
                .on_click(move |_, _, cx| {
                    fire(&shared, node_id, EventKind::ToggleChanged, cx, || unsafe {
                        bridge::lui_ocaml_toggle_changed(node_id, (!expanded) as i32)
                    });
                }),
        );
    }
    if let Some(icon) =
        icon_name(node, Property::InlineIconName).or_else(|| icon_name(node, Property::IconName))
    {
        row = row.child(Icon::new(icon).size_4());
    }

    if !text_of(node).is_empty() {
        row = row.child(div().flex_1().min_w_0().child(text_of(node)));
    }

    // Context-menu children render as a deferred menu at the click point;
    // the row itself stays the trigger.
    let mut menu_node_id: Option<i64> = None;
    let mut menu_children: Vec<AnyElement> = Vec::new();
    for child_id in &node.children {
        let is_menu = {
            let shared = view.shared.borrow();
            shared
                .store
                .node(*child_id)
                .map(|n| n.identity.kind() == Some(NodeKind::ContextMenu))
                .unwrap_or(false)
        };
        if is_menu {
            menu_node_id = Some(*child_id);
            menu_children = {
                let shared = view.shared.borrow();
                shared
                    .store
                    .node(*child_id)
                    .map(|n| n.children.clone())
                    .unwrap_or_default()
                    .into_iter()
                    .map(|grandchild| view.child_view(grandchild, cx).into_any_element())
                    .collect()
            };
        } else {
            row = row.child(view.child_view(*child_id, cx).into_any_element());
        }
    }

    if !node.enabled() {
        row = row.opacity(0.5);
    }
    if press_gate(view, node.id) {
        row = row.cursor_pointer().on_click(press_handler(view, node.id));
    }

    if !menu_children.is_empty() {
        let open = view.states.overlay.clone();
        let entity = cx.entity().entity_id();
        let shared_menu = view.shared.clone();
        let node_id_menu = node.id;
        row = row.on_mouse_down(MouseButton::Right, move |event, _, cx| {
            open.set(Some(event.position));
            cx.notify(entity);
            fire_pointer_detail(
                &shared_menu,
                node_id_menu,
                EventKind::ContextMenuPress,
                cx,
                event.position,
                event.button,
                &event.modifiers,
                |x, y, modifiers, button| unsafe {
                    bridge::lui_ocaml_context_menu_press(
                        node_id_menu, x, y, modifiers, button, c"".as_ptr(),
                    )
                },
            );
        });
        if let Some(position) = view.states.overlay.get() {
            // Press-outside closes the popup; the menu node itself stays
            // owned by the model.
            let open = view.states.overlay.clone();
            let entity = cx.entity().entity_id();
            let menu_id = menu_node_id;
            let shared = view.shared.clone();
            let mut popup = v_flex()
                .id(ElementId::Name(format!("lui-{}-ctxmenu", node.id).into()))
                .gap_0p5()
                .p_1()
                .min_w(px(160.))
                .bg(cx.theme().popover)
                .border_1()
                .border_color(cx.theme().border)
                .rounded_md()
                .shadow_lg();
            for menu_child in menu_children {
                popup = popup.child(menu_child);
            }
            popup = popup.on_mouse_down_out(move |_, _, cx| {
                open.set(None);
                cx.notify(entity);
                if let Some(menu_id) = menu_id {
                    if event_gate_id(&shared, menu_id, EventKind::Dismiss) {
                        fire(&shared, menu_id, EventKind::Dismiss, cx, || unsafe {
                            bridge::lui_ocaml_dismiss(menu_id)
                        });
                    }
                }
            });
            row = row.child(
                deferred(anchored().position(position).snap_to_window().child(popup))
                    .with_priority(2),
            );
        }
    }

    style::all(row, node).into_any_element()
}

fn event_gate_id(shared: &crate::backend::Shared, node_id: i64, event: EventKind) -> bool {
    let shared = shared.borrow();
    shared
        .store
        .node(node_id)
        .map(|node| lui_core::event_allowed(node, event))
        .unwrap_or(false)
}

/// `menu-trigger` (a `menu`/`submenu` inside another menu): a menu-item row
/// with a trailing chevron. The model mounts its `dropdown-menu` child
/// unconditionally, so the host decides visibility: hover opens the nested
/// menu as a deferred popup at the row's right edge, an outside press fires
/// the menu node's `Dismiss`.
/// The `(owner id, open-slot)` of the nearest ancestor dropdown/context
/// menu — submenu sibling coordination: only one trigger may hold it.
fn menu_owner(
    view: &LuiNodeView,
    node: &NodeSnapshot,
    cx: &mut App,
) -> Option<(i64, std::rc::Rc<std::cell::Cell<Option<i64>>>)> {
    let parent_id = node.parent?;
    let is_menu = view
        .shared
        .borrow()
        .store
        .node(parent_id)
        .map(|n| {
            matches!(
                n.identity.kind(),
                Some(NodeKind::DropdownMenu) | Some(NodeKind::ContextMenu)
            )
        })
        .unwrap_or(false);
    if !is_menu {
        return None;
    }
    let owner = LuiShared::view_for(&view.shared, parent_id, cx);
    Some((parent_id, owner.read(cx).states.open_submenu.clone()))
}

/// Close another trigger's submenu popup (the one holding the slot).
fn close_submenu(shared: &Shared, trigger_id: i64, cx: &mut App) {
    let entity = shared.borrow().views.get(&trigger_id).cloned();
    if let Some(entity) = entity {
        let eid = entity.entity_id();
        entity.update(cx, |v, _cx| v.states.menu_open.set(false));
        cx.notify(eid);
    }
}

fn menu_trigger(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let hover_bg = cx.theme().accent;

    // The nested `dropdown-menu` child (its own entity renders empty — see
    // the dispatch arm); its children are the submenu items.
    let menu_node_id = node.children.iter().copied().find(|child_id| {
        let shared = view.shared.borrow();
        shared
            .store
            .node(*child_id)
            .map(|n| {
                matches!(
                    n.identity.kind(),
                    Some(NodeKind::DropdownMenu) | Some(NodeKind::ContextMenu)
                )
            })
            .unwrap_or(false)
    });
    let min_width = menu_node_id
        .and_then(|menu_id| {
            view.shared
                .borrow()
                .store
                .node(menu_id)
                .and_then(|n| n.float_prop(Property::MinWidth))
        })
        .unwrap_or(160.)
        .max(0.) as f32;

    let mut row = h_flex()
        .id(element_id(node.id))
        .w_full()
        .items_center()
        .gap_2()
        .px_2()
        .py_1()
        .rounded_sm()
        .hover(move |style| style.bg(hover_bg));
    row = row.child(div().w_4());
    if let Some(icon) =
        icon_name(node, Property::InlineIconName).or_else(|| icon_name(node, Property::IconName))
    {
        row = row.child(Icon::new(icon).size_4());
    }
    row = row.child(div().flex_1().child(text_of(node)));

    // Non-menu children stay inline (unusual, but keeps the node visible).
    for child_id in &node.children {
        if Some(*child_id) == menu_node_id {
            continue;
        }
        row = row.child(view.child_view(*child_id, cx).into_any_element());
    }

    row = row.child(
        Icon::new(gpui_kit::assets::IconName::ChevronRight)
            .size_4()
            .text_color(cx.theme().muted_foreground),
    );
    if !node.enabled() {
        row = row.opacity(0.5);
    }

    if let Some(menu_id) = menu_node_id {
        let owner = menu_owner(view, node, cx);
        let open = view.states.menu_open.clone();
        let entity = cx.entity().entity_id();
        let shared = view.shared.clone();
        let node_id = node.id;
        row = row.on_hover({
            let owner = owner.clone();
            move |hovered, _, cx| {
                if *hovered && !open.get() {
                    // Sibling coordination: evict whichever submenu trigger
                    // currently holds the owning menu's open slot, then
                    // claim it.
                    if let Some((_, slot)) = &owner {
                        if let Some(other) = slot.get().filter(|id| *id != node_id) {
                            close_submenu(&shared, other, cx);
                        }
                        slot.set(Some(node_id));
                    }
                    open.set(true);
                    cx.notify(entity);
                }
            }
        });
        row = row.cursor_pointer().on_click({
            let open = view.states.menu_open.clone();
            let entity = cx.entity().entity_id();
            let owner = owner.clone();
            move |_, _, cx| {
                let next = !open.get();
                if let Some((_, slot)) = &owner {
                    slot.set(next.then_some(node_id));
                }
                open.set(next);
                cx.notify(entity);
            }
        });
        if view.states.menu_open.get() {
            let items = {
                let shared = view.shared.borrow();
                shared
                    .store
                    .node(menu_id)
                    .map(|n| n.children.clone())
                    .unwrap_or_default()
                    .into_iter()
                    .map(|child_id| view.child_view(child_id, cx).into_any_element())
                    .collect::<Vec<_>>()
            };
            if !items.is_empty() {
                let open = view.states.menu_open.clone();
                let entity = cx.entity().entity_id();
                let shared = view.shared.clone();
                let mut popup = v_flex()
                    .id(ElementId::Name(format!("lui-{}-submenu", node.id).into()))
                    .gap_0p5()
                    .p_1()
                    .min_w(px(min_width))
                    .bg(cx.theme().popover)
                    .border_1()
                    .border_color(cx.theme().border)
                    .rounded_md()
                    .shadow_lg()
                    .children(items);
                popup = popup.on_mouse_down_out({
                    let owner = owner.clone();
                    let node_id = node.id;
                    move |_, _, cx| {
                        if let Some((_, slot)) = &owner {
                            if slot.get() == Some(node_id) {
                                slot.set(None);
                            }
                        }
                        open.set(false);
                        cx.notify(entity);
                        if event_gate_id(&shared, menu_id, EventKind::Dismiss) {
                            fire(&shared, menu_id, EventKind::Dismiss, cx, || unsafe {
                                bridge::lui_ocaml_dismiss(menu_id)
                            });
                        }
                    }
                });
                row = row.child(
                    div().absolute().top_0().right_0().size_0().child(
                        deferred(
                            anchored()
                                .anchor(Anchor::TopLeft)
                                .offset(point(px(-2.), px(-4.)))
                                .snap_to_window()
                                .child(popup),
                        )
                        .with_priority(3),
                    ),
                );
            }
        }
    }

    style::all(row, node).into_any_element()
}

/// `edge_inset`: last child is the pinned bar — overlaid at the `edge`
/// (`top`|`bottom`) while the other children fill the frame behind it.
/// `visible` hides the bar without dropping it.
fn edge_inset(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let edge = node.string_prop(Property::EdgeValue).unwrap_or("top");
    let visible = node.bool_prop(Property::Visible).unwrap_or(true);
    let mut children = view.child_elements(node, cx);
    let pinned = children.pop();
    let mut element = div()
        .id(element_id(node.id))
        .relative()
        .child(v_flex().size_full().children(children));
    if visible {
        if let Some(bar) = pinned {
            let mut layer = div().absolute().left_0().w_full().child(bar);
            layer = if edge == "bottom" {
                layer.bottom_0()
            } else {
                layer.top_0()
            };
            element = element.child(layer);
        }
    }
    style::all(element, node).into_any_element()
}

/// `split`: two retained panes over a model-owned `value` fraction
/// (first pane seeded at fraction × viewport, second fills). Drags
/// report back as `ValueChanged` — the `on_resize` channel.
fn split(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let node_id = node.id;
    let fraction = node.float_prop(Property::ProgressValue).unwrap_or(0.5) as f32;
    let mut children = view.child_elements(node, cx).into_iter();
    let first = children.next();
    let second = children.next();
    let viewport = window.viewport_size();
    let first_px = px((f32::from(viewport.width) * fraction).max(48.));
    let shared = view.shared.clone();
    let group = gpui_kit::component::h_resizable(element_id(node_id))
        .on_resize(move |state, _window, cx| {
            let sizes: Vec<f32> = {
                let state = state.read(cx);
                state.sizes().iter().map(|size| f32::from(*size)).collect()
            };
            let total: f32 = sizes.iter().sum();
            let fraction = if total > 0. {
                (sizes.first().copied().unwrap_or(0.) / total).clamp(0., 1.)
            } else {
                0.
            };
            fire(&shared, node_id, EventKind::ValueChanged, cx, || unsafe {
                bridge::lui_ocaml_slider_changed(node_id, fraction as f64)
            });
        })
        .child(
            gpui_kit::component::resizable_panel()
                .size(first_px)
                .size_range(px(48.)..gpui_kit::gpui::Pixels::MAX)
                .child(first.unwrap_or_else(|| div().into_any_element())),
        )
        .child(
            gpui_kit::component::resizable_panel()
                .child(second.unwrap_or_else(|| div().into_any_element())),
        );
    style::all(div().size_full().child(group), node).into_any_element()
}

/// `resizable`: one resizable pane (`width` seeds, `min-width`/`max-width`
/// clamp) followed by a flexible remainder — gpui-base owns the drag.
fn resizable(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let width = node.float_prop(Property::WidthValue).unwrap_or(240.) as f32;
    let min = node.float_prop(Property::MinWidth).unwrap_or(0.).max(0.) as f32;
    let max = node
        .float_prop(Property::MaxWidth)
        .map(|v| px(v as f32))
        .unwrap_or(gpui_kit::gpui::Pixels::MAX);
    let group = gpui_kit::component::h_resizable(element_id(node.id))
        .child(
            gpui_kit::component::resizable_panel()
                .size(px(width))
                .size_range(px(min)..max)
                .children(view.child_elements(node, cx)),
        )
        .child(gpui_kit::component::resizable_panel().child(div().size_full().into_any_element()));
    style::all(div().size_full().child(group), node).into_any_element()
}

/// `stepper`: horizontal step indicator — one circle + label per `step`
/// child, connector lines between circles. `active` marks the current
/// index: earlier steps read complete, later ones upcoming.
fn stepper(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let accent = cx.theme().accent;
    let border_color = cx.theme().border;
    let mut element = h_flex()
        .id(element_id(node.id))
        .w_full()
        .items_center()
        .gap_1();
    let active = node.int_prop(Property::ActiveIndex).unwrap_or(0) as usize;
    let step_count = node
        .children
        .iter()
        .filter(|child_id| {
            view.shared
                .borrow()
                .store
                .node(**child_id)
                .map(|n| n.identity.kind() == Some(NodeKind::Step))
                .unwrap_or(false)
        })
        .count();
    let mut seen = 0usize;
    for child_id in &node.children {
        let is_step = view
            .shared
            .borrow()
            .store
            .node(*child_id)
            .map(|n| n.identity.kind() == Some(NodeKind::Step))
            .unwrap_or(false);
        element = element.child(view.child_view(*child_id, cx).into_any_element());
        if is_step {
            seen += 1;
            if seen < step_count.max(1) && step_count > 0 {
                element = element.child(div().flex_1().h(px(1.)).bg(if seen <= active {
                    accent
                } else {
                    border_color
                }));
            }
        }
    }
    style::all(element, node).into_any_element()
}

/// `step`: one stepper entry — numbered circle (check when the parent
/// stepper's `active` index is past it) + label.
fn step(view: &mut LuiNodeView, node: &NodeSnapshot, cx: &mut Context<LuiNodeView>) -> AnyElement {
    let (index, active) = {
        let shared = view.shared.borrow();
        node.parent
            .and_then(|parent_id| shared.store.node(parent_id))
            .map(|parent| {
                let index = parent
                    .children
                    .iter()
                    .filter(|child_id| {
                        shared
                            .store
                            .node(**child_id)
                            .map(|n| n.identity.kind() == Some(NodeKind::Step))
                            .unwrap_or(false)
                    })
                    .position(|child_id| *child_id == node.id)
                    .unwrap_or(0);
                (
                    index,
                    parent.int_prop(Property::ActiveIndex).unwrap_or(0) as usize,
                )
            })
            .unwrap_or((0, 0))
    };
    let complete = index < active;
    let current = index == active;

    let accent = cx.theme().accent;
    let accent_fg = cx.theme().accent_foreground;
    let muted = cx.theme().muted_foreground;
    let border_color = if complete || current {
        accent
    } else {
        cx.theme().border
    };
    let mut badge = div()
        .w(px(20.))
        .h(px(20.))
        .rounded_full()
        .border_1()
        .border_color(border_color)
        .flex()
        .items_center()
        .justify_center()
        .text_xs();
    if complete {
        badge = badge
            .bg(accent)
            .text_color(accent_fg)
            .child(Icon::new(gpui_kit::assets::IconName::Check).size_3());
    } else {
        badge = badge
            .text_color(if current { accent } else { muted })
            .child(format!("{}", index + 1));
    }
    let mut label = div()
        .text_color(if current || complete {
            cx.theme().foreground
        } else {
            muted
        })
        .child(text_of(node));
    if current {
        label = label.font_weight(gpui_kit::gpui::FontWeight::SEMIBOLD);
    }
    let mut row = h_flex()
        .id(element_id(node.id))
        .items_center()
        .gap_2()
        .child(badge)
        .child(label);
    if !node.enabled() {
        row = row.opacity(0.5);
    }
    style::all(row, node).into_any_element()
}

/// `timeline-item`: indicator column (icon badge + optional connector
/// segment) next to title / description / meta lines.
fn timeline_item(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let accent = cx.theme().accent;
    let muted = cx.theme().muted_foreground;
    let icon =
        icon_name(node, Property::InlineIconName).unwrap_or(gpui_kit::assets::IconName::Circle);
    let selected = node.flag(Property::Selected);
    let connector = node.flag(Property::Connector);

    let mut indicator = v_flex().items_center().child(
        div()
            .w(px(20.))
            .h(px(20.))
            .rounded_full()
            .bg(if selected {
                accent
            } else {
                cx.theme().secondary
            })
            .flex()
            .items_center()
            .justify_center()
            .child(Icon::new(icon).size_3().text_color(if selected {
                cx.theme().accent_foreground
            } else {
                cx.theme().secondary_foreground
            })),
    );
    if connector {
        indicator = indicator.child(div().flex_1().w(px(1.)).bg(cx.theme().border));
    }

    let mut body = v_flex().gap_0p5().flex_1().min_w_0();
    let title = node
        .string_prop(Property::TitleValue)
        .map(str::to_owned)
        .unwrap_or_else(|| text_of(node));
    if !title.is_empty() {
        body = body.child(
            div()
                .font_weight(gpui_kit::gpui::FontWeight::SEMIBOLD)
                .child(title),
        );
    }
    if let Some(description) = node.string_prop(Property::DescriptionValue) {
        if !description.is_empty() {
            body = body.child(
                div()
                    .text_sm()
                    .text_color(muted)
                    .child(description.to_owned()),
            );
        }
    }
    if let Some(meta) = node.string_prop(Property::MetaValue) {
        if !meta.is_empty() {
            body = body.child(div().text_xs().text_color(muted).child(meta.to_owned()));
        }
    }

    let mut row = h_flex()
        .id(element_id(node.id))
        .items_start()
        .gap_2()
        .child(indicator)
        .child(body)
        .children(view.child_elements(node, cx));
    if !node.enabled() {
        row = row.opacity(0.5);
    }
    if press_gate(view, node.id) {
        row = row.cursor_pointer().on_click(press_handler(view, node.id));
    }
    style::all(row, node).into_any_element()
}

/// `menu-item`: accent-hover row with check slot, icon, label and press.
fn menu_item(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let hover_bg = cx.theme().accent;
    let selected = node.flag(Property::Selected);
    let mut row = h_flex()
        .id(element_id(node.id))
        .w_full()
        .items_center()
        .gap_2()
        .px_2()
        .py_1()
        .rounded_sm()
        .hover(move |style| style.bg(hover_bg));
    row = row.child(div().w_4().child(if selected {
        div()
            .child(Icon::new(gpui_kit::assets::IconName::Check).size_4())
            .into_any_element()
    } else {
        div().into_any_element()
    }));
    if let Some(icon) =
        icon_name(node, Property::InlineIconName).or_else(|| icon_name(node, Property::IconName))
    {
        row = row.child(Icon::new(icon).size_4());
    }
    row = row.child(div().flex_1().child(text_of(node)));
    row = row.children(view.child_elements(node, cx));
    if !node.enabled() {
        row = row.opacity(0.5);
    }
    // Hovering a plain item closes the sibling submenu that currently
    // holds the owning menu's open slot.
    let owner = menu_owner(view, node, cx);
    let shared = view.shared.clone();
    row = row.on_hover(move |hovered, _, cx| {
        if *hovered {
            if let Some((_, slot)) = &owner {
                if let Some(other) = slot.get() {
                    close_submenu(&shared, other, cx);
                    slot.set(None);
                }
            }
        }
    });
    if press_gate(view, node.id) {
        row = row.cursor_pointer().on_click(press_handler(view, node.id));
    }
    style::all(row, node).into_any_element()
}

/// `accordion`: disclosure header (chevron + text, click fires
/// `toggle_changed` with the inverse of `selected`) plus children kept
/// mounted but hidden while collapsed.
fn accordion(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let expanded = node.flag(Property::Selected);
    let shared = view.shared.clone();
    let node_id = node.id;
    let chevron = if expanded {
        gpui_kit::assets::IconName::ChevronDown
    } else {
        gpui_kit::assets::IconName::ChevronRight
    };
    let mut element = v_flex()
        .id(element_id(node.id))
        .w_full()
        .border_1()
        .border_color(cx.theme().border)
        .rounded_md()
        .child(
            h_flex()
                .id(ElementId::Name(format!("lui-{}-accordion", node.id).into()))
                .w_full()
                .items_center()
                .gap_2()
                .px_3()
                .py_2()
                .cursor_pointer()
                .child(
                    Icon::new(chevron)
                        .size_4()
                        .text_color(cx.theme().muted_foreground),
                )
                .child(
                    div()
                        .flex_1()
                        .font_weight(FontWeight::SEMIBOLD)
                        .child(text_of(node)),
                )
                .on_click(move |_, _, cx| {
                    fire(&shared, node_id, EventKind::ToggleChanged, cx, || unsafe {
                        bridge::lui_ocaml_toggle_changed(node_id, (!expanded) as i32)
                    });
                }),
        );
    if expanded {
        element = element.child(
            v_flex()
                .gap_1()
                .px_3()
                .pb_3()
                .children(view.child_elements(node, cx)),
        );
    }
    style::all(element, node).into_any_element()
}

/// `file-picker`: button opens the platform path prompt; chosen paths go
/// back through `lui_ocaml_picked` as a JSON array.
fn file_picker(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    _window: &mut Window,
    _cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let node_id = node.id;
    let shared = view.shared.clone();
    let multiple = node.flag(Property::PickerMultiple);
    let label = if text_of(node).is_empty() {
        "Choose file…".to_string()
    } else {
        text_of(node)
    };
    let mut button = Button::new(element_id(node_id)).label(label);
    button = button_variant(button, node);
    button = button.disabled(!node.enabled());
    button = button.on_click(move |_, window, cx| {
        let rx = cx.prompt_for_paths(PathPromptOptions {
            files: true,
            directories: false,
            multiple,
            prompt: None,
        });
        let shared = shared.clone();
        window
            .spawn(cx, move |cx: &mut gpui_kit::gpui::AsyncWindowContext| {
                let mut cx = cx.clone();
                async move {
                    let Ok(Ok(result)) = rx.await else {
                        return;
                    };
                    let payload = match result {
                        Some(paths) => serde_json::to_string(
                            &paths
                                .iter()
                                .map(|path| path.to_string_lossy().to_string())
                                .collect::<Vec<_>>(),
                        )
                        .unwrap_or_else(|_| "[]".to_string()),
                        None => "[]".to_string(),
                    };
                    let _ = cx.update(move |_window, cx| {
                        let sending = std::ffi::CString::new(payload).unwrap_or_default();
                        fire(&shared, node_id, EventKind::Picked, cx, || unsafe {
                            bridge::lui_ocaml_picked(node_id, sending.as_ptr())
                        });
                    });
                }
            })
            .detach();
    });
    style::all(button, node).into_any_element()
}

pub fn render_node(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let kind = match &node.identity {
        NodeIdentity::Standard(kind) => *kind,
        NodeIdentity::Extension { .. } => return extension::render(view, node, window, cx),
    };
    match kind {
        // Containers -----------------------------------------------------
        NodeKind::Root => {
            let mut element = v_flex()
                .on_children_prepainted(view.bounds_recorder(node))
                .id(element_id(node.id))
                .size_full()
                .bg(cx.theme().background)
                .text_color(cx.theme().foreground);
            element = style::all(element, node);
            element
                .children(view.child_elements(node, cx))
                .into_any_element()
        }
        NodeKind::Row
        | NodeKind::ButtonGroup
        | NodeKind::ToggleGroup
        | NodeKind::InputGroup
        | NodeKind::InputGroupActions
        | NodeKind::Breadcrumb
        | NodeKind::Toolbar
        | NodeKind::RadioGroup
        | NodeKind::Pagination
        | NodeKind::TableRow => container(view, node, kind, true, cx),
        NodeKind::StatusBar | NodeKind::BottomTabs => {
            let mut element = h_flex()
                .id(element_id(node.id))
                .w_full()
                .border_t_1()
                .border_color(cx.theme().border)
                .bg(cx.theme().background);
            element = style::all(element, node);
            element
                .child(div().flex_1().min_w_0().child(text_of(node)))
                .children(view.child_elements(node, cx))
                .into_any_element()
        }
        NodeKind::Column
        | NodeKind::TableCell
        | NodeKind::Box
        | NodeKind::Table
        | NodeKind::Tree
        | NodeKind::ListSection
        | NodeKind::SwipeActions
        | NodeKind::Timeline => container(view, node, kind, false, cx),
        NodeKind::Split => split(view, node, window, cx),
        NodeKind::Resizable => resizable(view, node, cx),
        NodeKind::Stepper => stepper(view, node, cx),
        NodeKind::Step => step(view, node, cx),
        NodeKind::TimelineItem => timeline_item(view, node, cx),
        NodeKind::ListContainer | NodeKind::VirtualList => {
            // Scrollable collection container — the model slices children
            // (`visible-range` events land with native virtualization).
            view.states.scroll_tracked = true;
            let mut element = v_flex()
                .size_full()
                .on_children_prepainted(view.bounds_recorder(node))
                .id(element_id(node.id))
                .overflow_y_scroll()
                .track_scroll(&view.states.scroll);
            element = style::all(element, node);
            element
                .children(view.child_elements(node, cx))
                .into_any_element()
        }
        NodeKind::ListItem => list_item(view, node, window, cx),
        NodeKind::MenuItem => menu_item(view, node, cx),
        NodeKind::MenuTrigger => menu_trigger(view, node, cx),
        NodeKind::DropdownMenu => {
            let parent_kind = node.parent.and_then(|parent_id| {
                view.shared
                    .borrow()
                    .store
                    .node(parent_id)
                    .and_then(|n| n.identity.kind())
            });
            match parent_kind {
                // A `dropdown-menu` nested under a `menu-trigger` (the
                // `menu`/`submenu` element) is rendered by the trigger row
                // itself — it stays an invisible mount point here.
                Some(NodeKind::MenuTrigger) => {
                    div().id(element_id(node.id)).size_0().into_any_element()
                }
                // Mounted inside a `stack`/`overlay` (trigger + menu
                // siblings): render as a deferred popover under the stack.
                Some(NodeKind::Stack) | Some(NodeKind::Overlay) => {
                    dropdown_menu(view, node, window, cx)
                }
                // Mounted inline (e.g. a section showcasing menu items):
                // render the menu box in place.
                _ => {
                    let mut box_ = menu_box(view, node, cx);
                    if event_gate(view, node.id, EventKind::Dismiss) {
                        let shared = view.shared.clone();
                        let node_id = node.id;
                        box_ = box_.on_mouse_down_out(move |_, _, cx| {
                            fire(&shared, node_id, EventKind::Dismiss, cx, || unsafe {
                                bridge::lui_ocaml_dismiss(node_id)
                            });
                        });
                    }
                    div().id(element_id(node.id)).child(box_).into_any_element()
                }
            }
        }
        NodeKind::ContextMenu => {
            // Rendered by the owning `list-item` at the click point.
            div().id(element_id(node.id)).size_0().into_any_element()
        }
        NodeKind::Accordion => accordion(view, node, cx),
        NodeKind::Panel => {
            let mut element = v_flex()
                .id(element_id(node.id))
                .rounded_lg()
                .border_1()
                .border_color(cx.theme().border)
                .bg(cx.theme().background);
            element = style::all(element, node);
            element
                .children(view.child_elements(node, cx))
                .into_any_element()
        }
        NodeKind::Card => {
            let mut element = v_flex()
                .id(element_id(node.id))
                .rounded_lg()
                .border_1()
                .border_color(cx.theme().border)
                .bg(cx.theme().popover)
                .p_4()
                .gap_2();
            element = style::all(element, node);
            element
                .children(view.child_elements(node, cx))
                .into_any_element()
        }
        NodeKind::Bubble => {
            let mut element = v_flex()
                .id(element_id(node.id))
                .rounded_lg()
                .bg(cx.theme().accent)
                .p_3()
                .gap_1();
            element = style::all(element, node);
            element
                .children(view.child_elements(node, cx))
                .into_any_element()
        }
        NodeKind::Grid => {
            let columns = node.int_prop(Property::GridColumns).unwrap_or(0).max(0);
            let mut element = div().id(element_id(node.id)).v_flex().gap_2();
            element = style::all(element, node);
            if columns > 0 {
                let mut rows: Vec<AnyElement> = Vec::new();
                let mut row: Vec<AnyElement> = Vec::new();
                for child in view.child_elements(node, cx) {
                    row.push(child);
                    if row.len() == columns as usize {
                        let cells = row
                            .drain(..)
                            .map(|cell| div().flex_1().child(cell).into_any_element());
                        rows.push(h_flex().gap_2().w_full().children(cells).into_any_element());
                    }
                }
                if !row.is_empty() {
                    let cells = row
                        .into_iter()
                        .map(|cell| div().flex_1().child(cell).into_any_element());
                    rows.push(h_flex().gap_2().w_full().children(cells).into_any_element());
                }
                element.children(rows).into_any_element()
            } else {
                element
                    .children(view.child_elements(node, cx))
                    .into_any_element()
            }
        }
        NodeKind::Stack | NodeKind::Overlay => stacked(view, node, cx),
        NodeKind::EdgeInset => edge_inset(view, node, cx),
        // First-fit selection: render the widest variant; alternate
        // children are fallbacks for narrower hosts.
        NodeKind::ViewThatFits => {
            let mut element = div().id(element_id(node.id));
            if let Some(first) = view.child_elements(node, cx).into_iter().next() {
                element = element.child(first);
            }
            style::all(element, node).into_any_element()
        }
        NodeKind::Scroll => {
            view.states.scroll_tracked = true;
            let mut element = v_flex()
                .size_full()
                .on_children_prepainted(view.bounds_recorder(node))
                .id(element_id(node.id))
                .overflow_y_scroll()
                .track_scroll(&view.states.scroll);
            element = style::all(element, node);
            element
                .children(view.child_elements(node, cx))
                .into_any_element()
        }
        NodeKind::ListSectionHeader => {
            let mut element = div()
                .id(element_id(node.id))
                .w_full()
                .px_2()
                .py_1()
                .text_xs()
                .font_weight(FontWeight::SEMIBOLD)
                .text_color(cx.theme().muted_foreground)
                .child(text_of(node));
            element = style::all(element, node);
            element.into_any_element()
        }
        NodeKind::ListSectionFooter => {
            let mut element = div()
                .id(element_id(node.id))
                .w_full()
                .px_2()
                .py_1()
                .text_xs()
                .text_color(cx.theme().muted_foreground)
                .child(text_of(node));
            element = style::all(element, node);
            element.into_any_element()
        }

        // Text ------------------------------------------------------------
        NodeKind::Text | NodeKind::Label => text_element(view, node, cx),
        NodeKind::Paragraph => {
            let mut element = div()
                .id(element_id(node.id))
                .text_color(cx.theme().foreground)
                .child(text_of(node));
            if node.string_prop(Property::TextAlignment) == Some("center") {
                element = element.text_center();
            }
            element = style::all(element, node);
            element.into_any_element()
        }
        NodeKind::Heading => {
            let level = node
                .int_prop(Property::HeadingLevel)
                .unwrap_or(1)
                .clamp(1, 4);
            let mut element = div().id(element_id(node.id)).font_weight(FontWeight::BOLD);
            element = match level {
                1 => element.text_2xl(),
                2 => element.text_xl(),
                3 => element.text_lg(),
                _ => element.text_base(),
            };
            element = style::all(element, node);
            element.child(text_of(node)).into_any_element()
        }

        // Controls --------------------------------------------------------
        NodeKind::Button | NodeKind::ToggleButton | NodeKind::BottomTab => button(view, node, cx),
        NodeKind::SwipeAction => container(view, node, kind, false, cx),
        NodeKind::Checkbox => {
            let mut element = Checkbox::new(element_id(node.id))
                .label(text_of(node))
                .checked(node.flag(Property::Checked))
                .disabled(!node.enabled())
                .on_click(toggle_handler(view, node.id));
            element = style::all(element, node);
            element.into_any_element()
        }
        NodeKind::SwitchControl | NodeKind::Toggle => {
            let mut element = Switch::new(element_id(node.id))
                .checked(node.flag(Property::Checked))
                .disabled(!node.enabled())
                .on_click(toggle_handler(view, node.id));
            element = style::all(element, node);
            element.into_any_element()
        }
        NodeKind::Radio => {
            let mut element = Radio::new(element_id(node.id))
                .label(text_of(node))
                .checked(node.flag(Property::Selected) || node.flag(Property::Checked))
                .disabled(!node.enabled())
                .on_click(radio_handler(view, node.id));
            element = style::all(element, node);
            element.into_any_element()
        }
        NodeKind::Slider => slider(view, node, window, cx),
        NodeKind::NumberStepper => input(view, node, kind, window, cx),
        NodeKind::TextField | NodeKind::SecureField | NodeKind::Input | NodeKind::SearchField => {
            input(view, node, kind, window, cx)
        }
        NodeKind::Textarea => textarea(view, node, window, cx),
        NodeKind::Progress => {
            let value = node.float_prop(Property::ProgressValue).unwrap_or(0.0) as f32;
            let mut element = Progress::new(element_id(node.id)).value(value);
            element = style::all(element, node);
            element.into_any_element()
        }
        NodeKind::Divider => {
            let horizontal = node.string_prop(Property::OrientationValue) != Some("vertical");
            let mut element = if horizontal {
                Separator::horizontal()
            } else {
                Separator::vertical()
            };
            element = style::all(element, node);
            element.into_any_element()
        }
        NodeKind::Spacer => div().flex_1().into_any_element(),
        NodeKind::Spinner => Spinner::new().into_any_element(),
        NodeKind::Icon => match icon_name(node, Property::InlineIconName)
            .or_else(|| icon_name(node, Property::IconName))
        {
            Some(icon) => {
                let mut element = Icon::new(icon);
                element = style::all(element, node);
                element.into_any_element()
            }
            None => extension::placeholder_box(view, node, "icon", cx),
        },
        NodeKind::Avatar => {
            let mut element = gpui_kit::component::avatar::Avatar::new().name(text_of(node));
            if let Some(url) = node.string_prop(Property::UrlValue) {
                element = element.src(url.to_string());
            }
            element = style::all(element, node);
            element.into_any_element()
        }
        NodeKind::Link => {
            let mut element = Link::new(element_id(node.id))
                .child(text_of(node))
                .on_click(press_handler(view, node.id));
            element = style::all(element, node);
            element.into_any_element()
        }
        NodeKind::Kbd => {
            let element = match gpui_kit::gpui::Keystroke::parse(&text_of(node)) {
                Ok(stroke) => gpui_kit::component::kbd::Kbd::new(stroke).into_any_element(),
                // Unparseable stroke still shows the raw label.
                Err(_) => div()
                    .px_1p5()
                    .rounded_sm()
                    .border_1()
                    .border_color(cx.theme().border)
                    .text_xs()
                    .child(text_of(node))
                    .into_any_element(),
            };
            style::all(div().child(element), node).into_any_element()
        }
        NodeKind::Alert => {
            let variant = match variant_of(node) {
                "destructive" | "error" => AlertVariant::Error,
                "warning" => AlertVariant::Warning,
                "success" => AlertVariant::Success,
                _ => AlertVariant::Info,
            };
            let mut element = Alert::new(element_id(node.id), text_of(node)).with_variant(variant);
            if let Some(description) = node.string_prop(Property::DescriptionValue) {
                element = element.title(description.to_string());
            }
            element = style::all(element, node);
            element.into_any_element()
        }
        NodeKind::Tooltip => {
            // Anchored tooltips live inside a `stack` over their trigger:
            // an invisible hover layer pops a deferred bubble above/below.
            // Without an anchor the model uses the node as a static label.
            if node.string_prop(Property::AnchorValue).is_none() {
                let children = view.child_elements(node, cx);
                children
                    .into_iter()
                    .next()
                    .unwrap_or_else(|| div().child(text_of(node)).into_any_element())
            } else {
                let visible = view.states.tooltip.clone();
                let entity = cx.entity().entity_id();
                let mut layer = div()
                    .id(element_id(node.id))
                    .absolute()
                    .size_full()
                    .on_hover(move |hovered, _, cx| {
                        if visible.get() != *hovered {
                            visible.set(*hovered);
                            cx.notify(entity);
                        }
                    });
                if view.states.tooltip.get() {
                    let above = node.string_prop(Property::AnchorValue) != Some("below");
                    let offset = node.float_prop(Property::AnchorOffset).unwrap_or(4.) as f32;
                    let mut tip = div()
                        .px_2()
                        .py_1()
                        .text_sm()
                        .bg(cx.theme().popover)
                        .border_1()
                        .border_color(cx.theme().border)
                        .rounded_md()
                        .shadow_md()
                        .child(text_of(node));
                    let children = view.child_elements(node, cx);
                    for child in children {
                        tip = tip.child(child);
                    }
                    let marker = if above {
                        div()
                            .absolute()
                            .top_0()
                            .left(px(24.))
                            .size_0()
                            .child(
                                deferred(
                                    anchored()
                                        .anchor(Anchor::BottomLeft)
                                        .offset(point(px(0.), px(-offset)))
                                        .snap_to_window()
                                        .child(tip),
                                )
                                .with_priority(3),
                            )
                            .into_any_element()
                    } else {
                        div()
                            .absolute()
                            .bottom_0()
                            .left(px(24.))
                            .size_0()
                            .child(
                                deferred(
                                    anchored()
                                        .anchor(Anchor::TopLeft)
                                        .offset(point(px(0.), px(offset)))
                                        .snap_to_window()
                                        .child(tip),
                                )
                                .with_priority(3),
                            )
                            .into_any_element()
                    };
                    layer = layer.child(marker);
                }
                layer.into_any_element()
            }
        }
        NodeKind::Tabs => {
            // LUI models own the tab buttons and their selected state; the
            // host only owns list layout (horizontal or vertical strip).
            let vertical = node.string_prop(Property::OrientationValue) == Some("vertical");
            let mut element = if vertical {
                v_flex().id(element_id(node.id)).gap_1()
            } else {
                h_flex().id(element_id(node.id)).gap_1()
            };
            element = style::all(element, node);
            element
                .children(view.child_elements(node, cx))
                .into_any_element()
        }
        NodeKind::Dialog | NodeKind::Drawer | NodeKind::Sheet | NodeKind::Toast => {
            overlay_modal(view, node, kind, window, cx)
        }
        NodeKind::FilePicker => file_picker(view, node, window, cx),
        NodeKind::Select => select_picker(view, node, window, cx),
        NodeKind::Combobox => combobox_picker(view, node, kind, window, cx),
        NodeKind::FileImage => match node.string_prop(Property::PathValue) {
            Some(path) => {
                let mut element = div()
                    .id(element_id(node.id))
                    .child(gpui_kit::gpui::img(std::path::PathBuf::from(path)));
                element = style::all(element, node);
                element.into_any_element()
            }
            None => extension::placeholder_box(view, node, "file-image", cx),
        },
        // `image`/`media_surface`/`file_preview` reference host-owned
        // registries (image ids, surface ids) — no bytes reach the wire.
        NodeKind::Image | NodeKind::MediaSurface | NodeKind::FilePreview => {
            extension::placeholder_box(view, node, kind.wire_name(), cx)
        }
        // Line-break leaf: no native representation; renders nothing.
        NodeKind::Br => div().id(element_id(node.id)).size_0().into_any_element(),
        // Native popover positioning is not implemented yet: render the
        // children inline so the content stays reachable.
        NodeKind::Popover => container(view, node, kind, false, cx),
    }
}
