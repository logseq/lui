//! `NodeKind` -> gpui-kit element dispatch. Every container embeds children
//! as retained entity handles, caching explicitly sized stateless leaves.

use gpui_kit::base::{
    Align, ElementExt, InteractiveElementExt, Placement, Positioner, StyledExt,
};
use gpui_kit::component::alert::{Alert, AlertVariant};
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::checkbox::Checkbox;
use gpui_kit::component::combobox::{Combobox, ComboboxEvent, ComboboxState};
use gpui_kit::component::input::{
    Input, InputEvent, InputState, NumberInput, NumberStep, Textarea, TextareaState,
};
use gpui_kit::component::link::Link;
use gpui_kit::component::progress::Progress;
use gpui_kit::component::radio::Radio;
use gpui_kit::component::searchable_list::SearchableListDelegate;
use gpui_kit::component::select::{Select, SelectEvent, SelectState};
use gpui_kit::component::separator::Separator;
use gpui_kit::component::slider::{Slider, SliderEvent, SliderState, SliderValue};
use gpui_kit::component::spinner::Spinner;
use gpui_kit::component::switch::Switch;
use gpui_kit::component::theme::ActiveTheme;
use gpui_kit::component::Icon;
use gpui_kit::component::{h_flex, v_flex, Disableable, Selectable, Sizable};
use gpui_kit::gpui::{
    anchored, deferred, div, img, point, px, Anchor, Animation, AnimationExt, AnyElement, App,
    AppContext, Bounds, ClickEvent, Context, ElementId, Focusable, FontWeight, ImageSource,
    InteractiveElement, IntoElement, Modifiers, MouseButton, MouseDownEvent, ParentElement,
    PathPromptOptions, Pixels, Point, RenderImage, StatefulInteractiveElement, Styled, SvgSize,
    Window, WindowControlArea,
};
use gpui_kit::prelude::FluentBuilder;
use lui_core::bridge;
use lui_core::store::NodeIdentity;
use lui_core::{EventKind, NodeKind, Property};
use std::collections::HashMap;
use std::sync::{Arc, LazyLock, Mutex};

use crate::backend::{fire, LuiShared, OverlayEntry, Shared};
use crate::dom;
use crate::extension;
use crate::node_view::{LuiNodeView, LuiOption, LuiOptions, NodeSnapshot};
use crate::style;

#[cfg(test)]
mod icon_tests {
    use super::*;
    use lui_core::wire::decode_batch;
    use serde_json::json;
    use std::rc::Rc;

    #[gpui_kit::test]
    fn application_icons_render_their_foreground_after_property_changes(
        cx: &mut gpui_kit::TestAppContext,
    ) {
        cx.update(gpui_kit::init);
        let shared = LuiShared::new();
        shared.borrow_mut().app_icon_svg = Some(Rc::new(|_| {
            Some(r#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="currentColor"/></svg>"#.into())
        }));
        let batch = decode_batch(&json!({"generation": 1, "ops": [
            {"op": "create-node", "id": 99501, "kind": "icon"},
            {"op": "set-prop", "id": 99501, "property": "name", "value": "app:foreground-regression"}
        ]}).to_string()).unwrap();
        shared.borrow_mut().store.apply(&batch).unwrap();
        let fixture = shared.clone();
        let (view, cx) = cx.add_window_view(move |_, _| LuiNodeView::new(99501, fixture));
        for (step, (color, expected)) in [
            ("#858585", [133, 133, 133]),
            ("#5bb98c", [140, 185, 91]),
            ("#eb9091", [145, 144, 235]),
        ].into_iter().enumerate() {
            let batch = decode_batch(&json!({"generation": step + 2, "ops": [
                {"op": "set-prop", "id": 99501, "property": "foreground", "value": color}
            ]}).to_string()).unwrap();
            shared.borrow_mut().store.apply(&batch).unwrap();
            let image = cx.update(|window, app| view.update(app, |view, cx| {
                app_icon_image(view, &view.snapshot().unwrap(), "foreground-regression", window, cx).unwrap()
            }));
            let pixel = image.as_bytes(0).unwrap().chunks_exact(4)
                .find(|pixel| pixel[3] == 255).expect("the SVG must paint opaque pixels");
            for channel in 0..3 {
                assert!(pixel[channel].abs_diff(expected[channel]) <= 1,
                    "icon foreground {color}: expected BGRA {expected:?}, got {pixel:?}");
            }
        }
    }
}

fn element_id(node_id: i64) -> ElementId {
    // Element ids live inside the entity's own id space — per-node ids are
    // unique and stable across renders. Keep them numeric so every ancestor
    // in GPUI's state path does not allocate and hash a formatted string.
    ElementId::Integer(node_id as u64)
}

pub(crate) fn animated_popup(kind: NodeKind) -> bool {
    matches!(
        kind,
        NodeKind::Dialog
            | NodeKind::Drawer
            | NodeKind::Sheet
            | NodeKind::Toast
            | NodeKind::Popover
            | NodeKind::DropdownMenu
    )
}

pub(crate) fn popup_duration(node: &NodeSnapshot) -> std::time::Duration {
    let millis = match node.identity.kind() {
        Some(NodeKind::Toast) => 500,
        Some(NodeKind::Dialog) => 150,
        Some(NodeKind::Drawer | NodeKind::Sheet) => 200,
        Some(NodeKind::Popover)
            if node.float_prop(Property::PopupX).is_none()
                && node.string_prop(Property::AnchorValue).is_none() =>
        {
            150
        }
        _ => 130,
    };
    std::time::Duration::from_millis(millis)
}

fn popup_motion<E: IntoElement + Styled + 'static>(
    surface: E,
    node: &NodeSnapshot,
    shared: &Shared,
) -> AnyElement {
    let closing = shared.borrow().closing_nodes.contains_key(&node.id);
    surface
        .with_animation(
            ElementId::Name(
                format!("lui-{}-{}", node.id, if closing { "exit" } else { "enter" }).into(),
            ),
            Animation::new(popup_duration(node))
                .with_easing(|progress| 1. - (1. - progress).powi(3)),
            move |surface, progress| {
                surface.opacity(if closing { 1. - progress } else { progress })
            },
        )
        .into_any_element()
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
/// is the deepest painted node's style class — the DOM click target's
/// class list, which model handlers use to distinguish row-body clicks
/// from clicks on nested action buttons.
pub(crate) fn fire_pointer_detail<F>(
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
    F: FnOnce(f64, f64, i32, i32, *const std::ffi::c_char) -> i32,
{
    let x = f64::from(f32::from(position.x));
    let y = f64::from(f32::from(position.y));
    let modifiers = pointer_modifier_mask(modifiers, button);
    let button = pointer_button_index(button);
    let target_class = {
        let hit = dom::deepest_hit(shared, position).unwrap_or(node_id);
        let shared_ref = shared.borrow();
        shared_ref
            .store
            .node(hit)
            .and_then(|n| {
                n.string_prop(Property::StyleClass).or_else(|| {
                    n.extension_props
                        .get("style-class")
                        .and_then(lui_core::wire::Value::as_str)
                })
            })
            .unwrap_or_default()
            .to_string()
    };
    let target_class = bridge::c_string(&target_class);
    fire(shared, node_id, event, cx, || {
        call(x, y, modifiers, button, target_class.as_ptr())
    })
}

fn fire_press(
    shared: &Shared,
    node_id: i64,
    modifiers: &Modifiers,
    button: MouseButton,
    cx: &mut App,
) {
    let mask = pointer_modifier_mask(modifiers, button);
    fire(shared, node_id, EventKind::PressModifiers, cx, || unsafe {
        if mask == 0 {
            bridge::lui_ocaml_press(node_id)
        } else {
            bridge::lui_ocaml_press_ex(node_id, mask)
        }
    });
}

/// Emulate DOM click bubbling up the store's parent chain: some kit
/// elements (Link, buttons) stop MouseDown propagation, so ancestor
/// nodes never see the click — fire `Press`/`PressDetail` on each
/// ancestor the gate admits. The deepest node's own press already
/// fired; pass its id as `from` to start above it.
fn bubble_press(
    shared: &Shared,
    from: i64,
    cx: &mut App,
    position: Point<Pixels>,
    button: MouseButton,
    modifiers: &Modifiers,
) {
    let mut next = {
        let shared_ref = shared.borrow();
        shared_ref.store.node(from).and_then(|n| n.parent)
    };
    while let Some(pid) = next {
        next = {
            let shared_ref = shared.borrow();
            shared_ref.store.node(pid).and_then(|n| n.parent)
        };
        fire_press(shared, pid, modifiers, button, cx);
        fire_pointer_detail(
            shared,
            pid,
            EventKind::PressDetail,
            cx,
            position,
            button,
            modifiers,
            |x, y, modifiers, button, target_class| unsafe {
                bridge::lui_ocaml_press_detail(pid, x, y, modifiers, button, target_class)
            },
        );
    }
}

/// Fire `Press` on a node when the gate allows it.
fn press_handler(
    view: &LuiNodeView,
    node_id: i64,
) -> impl Fn(&ClickEvent, &mut Window, &mut App) + 'static {
    let shared = view.shared.clone();
    move |event, _, cx| {
        fire_press(&shared, node_id, &event.modifiers(), MouseButton::Left, cx);
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
            |x, y, modifiers, button, target_class| unsafe {
                bridge::lui_ocaml_press_detail(node_id, x, y, modifiers, button, target_class)
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
    kind: NodeKind,
    horizontal: bool,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    // Apply wrapper elision for this plain flex container. `multi` allows
    // a same-direction wrapper to expand several children into its slot,
    // which is only safe when this parent introduces no gap of its own
    // (neither a prop/class token nor the kind-level chrome below).
    let multi = LuiNodeView::gapless(node)
        && !matches!(
            kind,
            NodeKind::ButtonGroup
                | NodeKind::ToggleGroup
                | NodeKind::Breadcrumb
                | NodeKind::Pagination
                | NodeKind::RadioGroup
                | NodeKind::InputGroupActions
        );
    // `flex-row`/`flex-col` class tokens applied by `style::all` override
    // the kind's direction — child elision must match the direction that
    // actually renders.
    let flat_horizontal = crate::node_view::snapshot_flex_direction(node).unwrap_or(horizontal);
    let pressable = press_gate(view, node.id);
    let titlebar = dom::attr(node, "data-window-titlebar").is_some();
    let role = dom::attr(node, "role");
    // Retained node views already scope their children by entity identity.
    // Plain layout needs no second state boundary: allocating one makes
    // every descendant copy and hash an unnecessarily deep element path.
    if matches!(kind, NodeKind::Row | NodeKind::Column | NodeKind::Box)
        && !pressable
        && !titlebar
        && role.as_deref() != Some("menuitem")
    {
        let base = if horizontal { h_flex() } else { v_flex() };
        let mut element = style::all(base, node, cx.theme());
        if !node.enabled() {
            element = element.opacity(0.5);
        }
        return element
            .children(view.child_elements_flat(node, flat_horizontal, multi, cx))
            .into_any_element();
    }
    let base = if horizontal {
        h_flex().id(element_id(node.id))
    } else {
        v_flex().id(element_id(node.id))
    };
    // Theme-carried default chrome per kind; explicit wire props and
    // style-class applied by `style::all` below still win.
    let mut element = match kind {
        NodeKind::ButtonGroup | NodeKind::ToggleGroup | NodeKind::Breadcrumb => {
            base.items_center().gap_1()
        }
        NodeKind::Pagination => base.items_center().gap_0p5(),
        NodeKind::RadioGroup => base.items_center().gap_2(),
        NodeKind::InputGroupActions => base.items_center().gap_1p5().px_2().pt_1().pb_2(),
        NodeKind::InputGroup => base
            .overflow_hidden()
            .rounded(cx.theme().radius)
            .border_1()
            .border_color(cx.theme().input)
            .bg(cx.theme().background),
        NodeKind::Toolbar => base
            .items_center()
            .p_1()
            .rounded(cx.theme().radius_lg)
            .border_1()
            .border_color(cx.theme().border)
            .bg(cx.theme().tokens.popover),
        NodeKind::TableRow => {
            let last = is_last_sibling(view, node);
            let hover_bg = cx.theme().accent;
            base.w_full()
                .when(!last, |element| {
                    element.border_b_1().border_color(cx.theme().border)
                })
                .hover(move |style| style.bg(hover_bg))
        }
        NodeKind::TableCell => base
            .py_3()
            .text_sm()
            .text_color(cx.theme().foreground),
        NodeKind::Table => base.w_full(),
        _ => base,
    };
    if !node.enabled() {
        element = element.opacity(0.5);
    }
    // role=menuitem container rows join the host menu's roving
    // highlight (menu_item_ids collects them); paint it with the
    // accent the menu-item kind uses.
    element = element.when(
        role.as_deref() == Some("menuitem")
            && view.shared.borrow().menu_highlight == Some(node.id),
        |element| element.bg(cx.theme().accent),
    );
    // Any container kind may carry `pressable` (the model enables the
    // PressEnabled prop) — the gate decides, not the kind.
    if pressable {
        element = element
            .cursor_pointer()
            .on_click(press_handler(view, node.id));
    }
    let mut element = style::all_interactive(element, node, cx.theme());
    // `data-window-titlebar` marks the container as the platform titlebar
    // region: dragging uncovered areas moves the window and a double-click
    // zooms it (hosts opt in via a transparent/merged titlebar).
    if titlebar {
        element = element
            .window_control_area(WindowControlArea::Drag)
            .on_double_click(|_, window, _| {
                #[cfg(target_os = "macos")]
                window.titlebar_double_click();
                #[cfg(not(target_os = "macos"))]
                window.zoom_window();
            });
    }
    // `table-cell` carries its label in the `text` prop rather than a
    // text child — render it like the other text-bearing kinds.
    if kind == NodeKind::TableCell {
        element = element.child(text_of(node));
    }
    element
        .children(view.child_elements_flat(node, flat_horizontal, multi, cx))
        .into_any_element()
}

/// The parent node's kind (for context-sensitive defaults like a button
/// rendered as a tab pill inside `tabs`).
fn parent_kind(view: &LuiNodeView, node: &NodeSnapshot) -> Option<NodeKind> {
    let shared = view.shared.borrow();
    node.parent
        .and_then(|parent_id| shared.store.node(parent_id))
        .and_then(|parent| parent.identity.kind())
}

/// Whether the node is its parent's last child — used for row rules like
/// the table's "every row but the last draws a bottom border".
fn is_last_sibling(view: &LuiNodeView, node: &NodeSnapshot) -> bool {
    let shared = view.shared.borrow();
    node.parent
        .and_then(|parent_id| shared.store.node(parent_id))
        .and_then(|parent| parent.children.last().copied())
        .map(|last| last == node.id)
        .unwrap_or(false)
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
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    // A `button` mounted under `tabs` is a segmented-control entry, not a
    // standalone push button — render it as a tab pill.
    if parent_kind(view, node) == Some(NodeKind::Tabs) {
        return tab_button(view, node, cx);
    }
    let node_id = node.id;
    let icon_size = node.string_prop(Property::SizeValue) == Some("icon");
    let mut button = Button::new(element_id(node_id));
    // gpui-component sizes an icon-only button as a square only when the
    // label is absent — an empty label string reads as a text button and
    // gets text-button padding. Leave it unset for `size:"icon"` and
    // drop empty labels on regular buttons for the same reason.
    if !icon_size {
        let label = text_of(node);
        if !label.is_empty() {
            button = button.label(label);
        }
    }
    button = button_variant(button, node);
    button = button_size(button, node);
    if let Some(icon) =
        icon_name(node, Property::InlineIconName).or_else(|| icon_name(node, Property::IconName))
    {
        button = button.icon(icon);
    } else if let Some(data) = app_icon_data(view, node) {
        // `app:` names resolve through the host — raw svg data keeps
        // `currentColor` bound to the button's text color.
        button = button.icon(Icon::default().data(&data));
    }
    button = button.selected(node.flag(Property::Selected));
    button = button.disabled(!node.enabled());
    button = button.on_click(press_handler(view, node_id));
    // Structured children render inside the button (e.g. the font
    // picker's ls-font Ag/name column) — the web twin mounts them in the
    // <button> body, so the label prop is not a substitute.
    for child_id in &node.children {
        button = button.child(view.child_view(*child_id, cx).into_any_element());
    }
    style::all(button, node, cx.theme()).into_any_element()
}

/// `button` inside `tabs`: a segmented-control pill per the gpui-component
/// tab design — unselected pills read as secondary labels, the selected one
/// gets the active surface and a resting shadow. The model owns `selected`
/// and `on_press`; the host only paints the state.
fn tab_button(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let selected = node.flag(Property::Selected);
    let theme = cx.theme();
    let active_bg = theme.tokens.tab_active;
    let active_fg = theme.tab_active_foreground;
    let mut element = h_flex()
        .id(element_id(node.id))
        .items_center()
        .justify_center()
        .gap_1p5()
        .h_8()
        .px_3()
        .rounded(theme.radius)
        .text_sm();
    if selected {
        element = element.bg(active_bg).text_color(active_fg).shadow_sm();
    } else {
        element = element
            .text_color(theme.tab_foreground)
            .hover(move |style| {
                style
                    .bg(active_bg.background.opacity(0.6))
                    .text_color(active_fg)
            });
    }
    if let Some(icon) =
        icon_name(node, Property::InlineIconName).or_else(|| icon_name(node, Property::IconName))
    {
        element = element.child(Icon::new(icon).size_4());
    }
    let label = text_of(node);
    if !label.is_empty() {
        element = element.child(label);
    }
    if !node.enabled() {
        element = element.opacity(0.5);
    }
    if press_gate(view, node.id) {
        element = element
            .cursor_pointer()
            .on_click(press_handler(view, node.id));
    }
    let element = style::all_interactive(element, node, cx.theme());
    element.into_any_element()
}

/// Raw icon-name prop — `app:<name>` is an application icon; bare names
/// map onto gpui-kit's built-in IconName set.
fn icon_name_raw(node: &NodeSnapshot) -> Option<&str> {
    node.string_prop(Property::InlineIconName)
        .or_else(|| node.string_prop(Property::IconName))
}

/// Rasterize an `app:` icon name through the host's `app_icon_svg`
/// resolver (e.g. a bundled tabler table). `currentColor` is bound to
/// the node's styled foreground so the glyph follows its surface props.
/// Cached per (name, color, scale): icons are immutable.
fn app_icon_image(
    view: &LuiNodeView,
    node: &NodeSnapshot,
    name: &str,
    window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> Option<Arc<RenderImage>> {
    static CACHE: LazyLock<Mutex<HashMap<(String, u32, u32), Arc<RenderImage>>>> =
        LazyLock::new(|| Mutex::new(HashMap::new()));
    let resolver = view.shared.borrow().app_icon_svg.clone()?;
    let mut styled = style::all(div(), node, cx.theme());
    let color = styled.style().text.color.unwrap_or(cx.theme().foreground);
    let rgb = color.to_rgb();
    let hex = format!(
        "#{:02x}{:02x}{:02x}",
        (rgb.r * 255.) as u8,
        (rgb.g * 255.) as u8,
        (rgb.b * 255.) as u8
    );
    let scale = (window.scale_factor() * 4.).round() as u32;
    let color_key = ((rgb.r * 255.) as u32) << 16
        | ((rgb.g * 255.) as u32) << 8
        | (rgb.b * 255.) as u32;
    let key = (name.to_string(), color_key, scale);
    if let Some(image) = CACHE.lock().ok().and_then(|c| c.get(&key).cloned()) {
        return Some(image);
    }
    let svg = resolver(name)?.replace("currentColor", &hex);
    let parsed = cx.svg_renderer().parse_svg(svg.as_bytes()).ok()?;
    let image = cx
        .svg_renderer()
        .render_parsed(&parsed, SvgSize::ScaleFactor(window.scale_factor()))
        .ok()?;
    if let Ok(mut cache) = CACHE.lock() {
        cache.insert(key, image.clone());
    }
    Some(image)
}

fn icon_name(node: &NodeSnapshot, property: Property) -> Option<gpui_kit::assets::IconName> {
    node.string_prop(property).and_then(icon_for)
}

/// Raw svg bytes for an `app:` icon name via the host's `app_icon_svg`
/// resolver — `currentColor` is left in place so the consumer's text
/// color binds it (unlike `app_icon_image`, which pre-bakes the styled
/// foreground into a bitmap for standalone image slots).
fn app_icon_data(view: &LuiNodeView, node: &NodeSnapshot) -> Option<Vec<u8>> {
    let name = icon_name_raw(node)?.strip_prefix("app:")?;
    let resolver = view.shared.borrow().app_icon_svg.clone()?;
    Some(resolver(name)?.into_bytes())
}

/// Map a wire icon name (`app:`-prefix already allowed) onto gpui-kit's
/// built-in IconName set. `app:` names are host-resolved; strip the prefix
/// so app names that coincide with built-ins still hit the fast path.
fn icon_for(raw: &str) -> Option<gpui_kit::assets::IconName> {
    let name = raw.strip_prefix("app:").unwrap_or(raw);
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
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let children = view.child_elements(node, cx);
    let mut element = div().id(element_id(node.id));
    // `label` is a form caption — smaller medium-weight text; `text` keeps
    // the body default.
    if node.identity.kind() == Some(NodeKind::Label) {
        element = element
            .text_sm()
            .font_weight(FontWeight::MEDIUM);
    }
    if children.is_empty() {
        element = element.child(crate::measured_text::MeasuredText::new(
            text_of(node), node.id, view.shared.clone(),
        ));
    } else {
        // Inline run: a `text` node can carry element children (logseq-*
        // spans — page refs, katex slots — plus nested `text` runs). Lay
        // the node's own text first, then children, in one baseline row.
        // `br` children split the run into stacked lines — flex-wrap
        // would be the DOM-accurate shape, but taffy's
        // hypothetical-cross-size pass explodes on nested wrap containers.
        let br_at: Vec<bool> = {
            let store = view.shared.borrow();
            node.children
                .iter()
                .filter(|cid| store.store.node(**cid).is_some())
                .map(|cid| {
                    NodeSnapshot::snapshot(&store.store, *cid)
                        .map(|n| matches!(n.identity, NodeIdentity::Standard(NodeKind::Br)))
                        .unwrap_or(false)
                })
                .collect()
        };
        let text = text_of(node);
        if br_at.iter().any(|b| *b) {
            let mut lines: Vec<Vec<AnyElement>> = vec![Vec::new()];
            if !text.is_empty() {
                lines[0].push(div().child(text).into_any_element());
            }
            for (is_br, child) in br_at.into_iter().zip(children) {
                if is_br {
                    lines.push(Vec::new());
                } else {
                    lines.last_mut().unwrap().push(child);
                }
            }
            element = element.children(
                lines
                    .into_iter()
                    .map(|line| h_flex().items_start().children(line).into_any_element()),
            );
        } else {
            let mut flow = h_flex().items_start();
            if !text.is_empty() {
                flow = flow.child(text);
            }
            element = element.child(flow.children(children));
        }
    }
    // `as` carries the semantic inline tag (code/strong/em/mark/…) — the
    // same styling table as the logseq-* extension elements.
    if let Some(as_tag) = node.string_prop(Property::As) {
        element = style::inline_tag_style(element, as_tag, cx.theme());
    }
    // Press-capable text kinds (text, list-item content handled elsewhere).
    if press_gate(view, node.id) {
        element = element
            .cursor_pointer()
            .on_click(press_handler(view, node.id));
    }
    element = style::all_interactive(element, node, cx.theme());
    element.into_any_element()
}

fn input_model_value(node: &NodeSnapshot) -> String {
    if node.identity.kind() == Some(NodeKind::NumberStepper) {
        return node
            .float_prop(Property::ProgressValue)
            .unwrap_or(0.0)
            .to_string();
    }
    node.string_prop(Property::ProgressValue)
        .or_else(|| node.string_prop(Property::TextValue))
        .unwrap_or_default()
        .to_string()
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
        let value = input_model_value(node);
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
                        if kind == NodeKind::NumberStepper {
                            if let Ok(value) = text.trim().parse::<f64>() {
                                if value.is_finite() {
                                    fire(
                                        &shared,
                                        node_id,
                                        EventKind::ValueChanged,
                                        cx,
                                        || unsafe {
                                            bridge::lui_ocaml_slider_changed(node_id, value)
                                        },
                                    );
                                }
                            }
                        } else {
                            fire(&shared, node_id, EventKind::TextChanged, cx, || unsafe {
                                bridge::lui_ocaml_text_changed_utf8(
                                    node_id,
                                    text.as_ptr() as *const std::ffi::c_char,
                                    text.len() as std::ffi::c_int,
                                )
                            });
                        }
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
    let placeholder = node.string_prop(Property::PlaceholderValue).unwrap_or("");
    if state.read(cx).presentation().placeholder().as_ref() != placeholder {
        state.update(cx, |state, cx| {
            state.set_placeholder(placeholder.to_string(), window, cx)
        });
    }
    // Register the field's focus handle so the root keydown forwarder
    // can target keydowns at this node (document.activeElement parity).
    let handle = state.read(cx).focus_handle(cx);
    view.shared.borrow_mut().register_focus(node_id, handle.clone());
    // Edge-triggered autofocus: the first render of a node carrying
    // `autofocus` takes focus; re-emits don't steal focus back.
    if node.flag(Property::Autofocus) && !view.states.autofocus_done {
        view.states.autofocus_done = true;
        window.defer(cx, move |window, cx| handle.focus(window, cx));
    }
    // A model write is an instruction even when its value is unchanged.
    // Unrelated redraws leave the local edit and selection untouched.
    view.states
        .sync_input_value(input_model_value(node), node.value_revision, window, cx);
    if kind == NodeKind::NumberStepper {
        state.update(cx, |state, cx| {
            state.set_min(node.float_prop(Property::MinValue), window, cx);
            state.set_max(node.float_prop(Property::MaxValue), window, cx);
            state.set_step(
                Some(NumberStep::from(
                    node.float_prop(Property::StepValue).unwrap_or(1.0),
                )),
                window,
                cx,
            );
        });
        return style::all(
            NumberInput::new(&state).disabled(!node.enabled()),
            node,
            cx.theme(),
        )
        .into_any_element();
    }
    let mut input = Input::new(&state);
    if !node.enabled() {
        input = input.disabled(true);
    }
    // Inside an `input-group` the group container owns the bordered surface;
    // the field drops its own chrome. `data-appearance="none"` opts the
    // field out anywhere else (borderless in-dialog search fields).
    if parent_kind(view, node) == Some(NodeKind::InputGroup)
        || crate::dom::attr(node, "data-appearance").as_deref() == Some("none")
    {
        input = input.appearance(false);
    }
    style::all(input, node, cx.theme()).into_any_element()
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
                fire(&shared, node_id, EventKind::TextChanged, cx, || unsafe {
                    bridge::lui_ocaml_text_changed_utf8(
                        node_id,
                        text.as_ptr() as *const std::ffi::c_char,
                        text.len() as std::ffi::c_int,
                    )
                });
            }
        });
        view.states.subscriptions.push(subscription);
        view.states.textarea = Some(state);
    }
    let state = view.states.textarea.clone().expect("initialized");
    let handle = state.read(cx).focus_handle(cx);
    view.shared.borrow_mut().register_focus(node_id, handle.clone());
    // Edge-triggered autofocus: the first render of a node carrying
    // `autofocus` takes focus; re-emits don't steal focus back.
    if node.flag(Property::Autofocus) && !view.states.autofocus_done {
        view.states.autofocus_done = true;
        window.defer(cx, move |window, cx| handle.focus(window, cx));
    }
    let placeholder = node.string_prop(Property::PlaceholderValue).unwrap_or("");
    if state.read(cx).presentation().placeholder().as_ref() != placeholder {
        state.update(cx, |state, cx| {
            state.set_placeholder(placeholder.to_string(), window, cx)
        });
    }
    view.states
        .sync_input_value(input_model_value(node), node.value_revision, window, cx);
    let mut element = Textarea::new(&state).disabled(!node.enabled());
    if parent_kind(view, node) == Some(NodeKind::InputGroup) {
        element = element.appearance(false);
    }
    style::all(element, node, cx.theme()).into_any_element()
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
    style::all(slider, node, cx.theme()).into_any_element()
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
/// option contents changed. Stable delegates preserve the active search.
fn sync_options(view: &LuiNodeView, items: Vec<LuiOption>, set: impl FnOnce(Vec<LuiOption>)) {
    if *view.states.options_cache.borrow() != items {
        *view.states.options_cache.borrow_mut() = items.clone();
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
        // Web select triggers read `label … chevron-down` (trailing
        // chevron); gpui-component's `icon` paints before the label, so
        // use the dropdown caret instead.
        let mut element = Button::new(element_id(node_id))
            .label(if text_of(node).is_empty() {
                "Select…".to_string()
            } else {
                text_of(node)
            })
            .outline()
            .dropdown_caret(true);
        element = element.disabled(!node.enabled());
        element = element.on_click(press_handler(view, node_id));
        element = style::all(element, node, cx.theme());
        return element.into_any_element();
    }
    if view.states.select.is_none() {
        let query = view.states.options_query.clone();
        let state = cx.new(|cx| {
            let items = LuiOptions::new(Vec::new(), query, window, cx);
            SelectState::new(items, None, window, cx).searchable(true)
        });
        let shared = view.shared.clone();
        let subscription = cx.subscribe(
            &state,
            move |_this, _state, event: &SelectEvent<LuiOptions>, cx| {
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
    let query = view.states.options_query.clone();
    sync_options(view, items, |items| {
        state.update(cx, |state, cx| {
            let selected = state.selected_value().copied();
            let selected_exists = selected.is_some_and(|id| items.iter().any(|item| item.node_id == id));
            let items = LuiOptions::new(items, query, window, cx);
            let index = selected.and_then(|value| items.position(&value));
            state.set_items(items, window, cx);
            // Preserve the list's uncommitted search cursor and selections
            // temporarily excluded by the query.
            if selected.is_some() && (index.is_some() || !selected_exists) {
                state.set_selected_index(index, window, cx);
            }
            cx.notify();
        });
    });
    let mut element = Select::new(&state);
    element = element.placeholder(if text_of(node).is_empty() {
        "Select…".to_string()
    } else {
        text_of(node)
    });
    element = element.disabled(!node.enabled());
    style::all(element, node, cx.theme()).into_any_element()
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
        let query = view.states.options_query.clone();
        let state = cx.new(|cx| {
            let items = LuiOptions::new(Vec::new(), query, window, cx);
            ComboboxState::new(items, Vec::new(), window, cx).searchable(true)
        });
        let shared = view.shared.clone();
        let subscription = cx.subscribe(
            &state,
            move |_this, _state, event: &ComboboxEvent<LuiOptions>, cx| {
                let item_id = match event {
                    ComboboxEvent::Change(values) => values.first().copied(),
                    // Confirm is also emitted when closing/canceling the popup.
                    ComboboxEvent::Confirm(_) => None,
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
                        fire(&shared, node_id, EventKind::TextChanged, cx, || unsafe {
                            bridge::lui_ocaml_text_changed_utf8(
                                node_id,
                                title.as_ptr() as *const std::ffi::c_char,
                                title.len() as std::ffi::c_int,
                            )
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
    let query = view.states.options_query.clone();
    sync_options(view, items, |items| {
        state.update(cx, |state, cx| {
            let selected = state.selected_values();
            let search = state.query(cx).to_string();
            state.set_items(LuiOptions::new(items, query, window, cx), window, cx);
            // Resolve committed values in the full list, then restore the
            // user's search so hidden selections survive option patches.
            state.set_selected_values(&selected, window, cx);
            if !search.is_empty() {
                state.set_query(search, window, cx);
            }
        });
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
    style::all(element, node, cx.theme()).into_any_element()
}

/// `overlay`/`stack`: first child lays out in-flow (sizing the stack to the
/// trigger), the rest overlay absolutely on top of it.
fn stacked(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let mut children = view.child_elements(node, cx).into_iter();
    let mut element = div().relative().id(element_id(node.id));
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
    style::all_interactive(element, node, cx.theme()).into_any_element()
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
pub(crate) fn window_layer(content: impl IntoElement, priority: usize) -> impl IntoElement {
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
        // The backdrop's hitbox is only visually under the card — without
        // an occluding hitbox of its own, mouse-downs on the card surface
        // still reach the backdrop and dismiss the modal.
        .occlude()
        .bg(cx.theme().tokens.background)
        .text_color(cx.theme().foreground)
        .border_1()
        .border_color(cx.theme().border);
    if !text_of(node).is_empty() {
        let mut title = div().font_weight(FontWeight::SEMIBOLD).child(text_of(node));
        if kind == NodeKind::Dialog {
            title = title.text_lg();
        }
        card = card.child(title);
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
    let shadows = cx.theme().shadow_tokens().lg;

    let surface = match kind {
        // No .p_4() here: dialog padding is class-owned on the web twin
        // (ui__dialog-content padding:1.5rem, ls-dialog-cmdk padding:0)
        // — a baked pad would double up under class padding and can
        // never be zeroed by ls-dialog-* overrides
        NodeKind::Dialog => card
            .w(node
                .float_prop(Property::WidthValue)
                .map(|w| px(w as f32))
                .unwrap_or(px(400.)))
            .rounded(cx.theme().radius_lg)
            .shadow(shadows)
            .into_any_element(),
        NodeKind::Drawer => card
            .w(node
                .float_prop(Property::WidthValue)
                .map(|w| px(w as f32))
                .unwrap_or(px(320.)))
            .h_full()
            .p_4()
            .shadow(shadows)
            .into_any_element(),
        NodeKind::Sheet => card
            .w_full()
            .h(node
                .float_prop(Property::HeightValue)
                .map(|h| px(h as f32))
                .unwrap_or(px(360.)))
            .p_4()
            .rounded_t(cx.theme().radius_lg)
            .shadow(shadows)
            .into_any_element(),
        _ => style::all(
            card.max_w(px(360.))
                .p_3()
                .rounded(cx.theme().radius_lg)
                .shadow(shadows),
            node,
            cx.theme(),
        )
        .into_any_element(),
    };

    let mut layer = div().relative().w(viewport.width).h(viewport.height);
    // Modal surfaces dim the content behind them and swallow outside clicks
    // into `Dismiss`; a toast is transient chrome and leaves the window
    // interactive.
    if kind != NodeKind::Toast {
        let backdrop = backdrop(view, node.id, window).bg(cx.theme().overlay);
        layer = layer.child(backdrop);
    }
    layer = match kind {
        NodeKind::Sheet => layer.v_flex().justify_end().child(surface),
        NodeKind::Drawer => layer.h_flex().justify_end().child(surface),
        NodeKind::Toast => {
            // Toasts share the top-right viewport: each stacks below the
            // ones opened before it, offset by their painted heights
            // (a height that hasn't painted yet falls back to a slot
            // estimate and corrects itself on the next frame).
            let closing = view.shared.borrow().closing_nodes.contains_key(&node.id);
            let offset = if closing {
                view.shared
                    .borrow()
                    .toast_bounds
                    .get(&node.id)
                    .map(|bounds| f32::from(bounds.origin.y) - 16.)
                    .expect("closing toast must retain its painted bounds")
            } else {
                let mut shared_ref = view.shared.borrow_mut();
                let fresh = !shared_ref.toasts.contains(&node.id);
                if fresh {
                    shared_ref.toasts.push(node.id);
                }
                // Web parity: a positive `duration` auto-dismisses; a
                // spawned timer ticks the remaining budget down (paused
                // while the pointer rests on the toast) and fires
                // `Dismiss` at zero — the same path Close takes.
                let duration_ms = node.float_prop(Property::DurationValue).unwrap_or(0.);
                if fresh && duration_ms > 0. && shared_ref.toast_timers.insert(node.id) {
                    shared_ref.toast_remaining_ms.insert(node.id, duration_ms);
                    let shared = view.shared.clone();
                    let toast_id = node.id;
                    window
                        .spawn(cx, move |cx: &mut gpui_kit::gpui::AsyncWindowContext| {
                            let mut cx = cx.clone();
                            async move {
                                loop {
                                    cx.background_executor()
                                        .timer(std::time::Duration::from_millis(80))
                                        .await;
                                    let done = cx
                                        .update(|_window, cx| {
                                            let mut shared_ref = shared.borrow_mut();
                                            let gone = !shared_ref.toasts.contains(&toast_id)
                                                || shared_ref.store.node(toast_id).is_none();
                                            if gone {
                                                shared_ref.toast_timers.remove(&toast_id);
                                                shared_ref.toast_remaining_ms.remove(&toast_id);
                                                shared_ref.toast_paused.remove(&toast_id);
                                                return true;
                                            }
                                            if shared_ref.toast_paused.contains(&toast_id) {
                                                return false;
                                            }
                                            let remaining = shared_ref
                                                .toast_remaining_ms
                                                .get(&toast_id)
                                                .copied()
                                                .unwrap_or(0.)
                                                - 80.;
                                            shared_ref
                                                .toast_remaining_ms
                                                .insert(toast_id, remaining);
                                            if remaining > 0. {
                                                return false;
                                            }
                                            shared_ref.toast_timers.remove(&toast_id);
                                            shared_ref.toast_remaining_ms.remove(&toast_id);
                                            drop(shared_ref);
                                            crate::backend::fire(
                                                &shared,
                                                toast_id,
                                                EventKind::Dismiss,
                                                cx,
                                                || unsafe { bridge::lui_ocaml_dismiss(toast_id) },
                                            );
                                            true
                                        })
                                        .unwrap_or(true);
                                    if done {
                                        break;
                                    }
                                }
                            }
                        })
                        .detach();
                }
                shared_ref
                    .toasts
                    .iter()
                    .take_while(|id| **id != node.id)
                    .map(|id| shared_ref.toast_heights.get(id).copied().unwrap_or(80.) + 8.)
                    .sum::<f32>()
            };
            layer.child(
                div()
                    .absolute()
                    .top(px(16. + offset))
                    .right_4()
                    .child(surface)
                    .on_prepaint({
                        let shared = view.shared.clone();
                        let node_id = node.id;
                        move |bounds, _, cx| {
                            let height: f32 = bounds.size.height.into();
                            let mut shared_ref = shared.borrow_mut();
                            // Deferred-anchored children prepaint in the
                            // anchor's pre-offset space; the node's own
                            // `node_bounds` entry records that offset (the
                            // size-0 anchor sits where the layer's origin
                            // lands). Subtract it to recover window-space
                            // bounds for swipe/hover hit-testing.
                            let anchor = shared_ref
                                .node_bounds
                                .get(&node_id)
                                .map(|b| b.origin)
                                .unwrap_or_default();
                            shared_ref.toast_bounds.insert(
                                node_id,
                                Bounds {
                                    origin: bounds.origin - anchor,
                                    size: bounds.size,
                                },
                            );
                            if shared_ref.toast_heights.get(&node_id) != Some(&height) {
                                shared_ref.toast_heights.insert(node_id, height);
                                // Toasts below re-resolve their offset next frame.
                                for id in &shared_ref.toasts {
                                    if *id != node_id {
                                        if let Some(view) = shared_ref.views.get(id) {
                                            cx.notify(view.entity_id());
                                        }
                                    }
                                }
                            }
                        }
                    }),
            )
        }
        _ => layer
            .v_flex()
            .items_center()
            .justify_center()
            .child(surface),
    };

    if kind != NodeKind::Toast {
        view.shared
            .borrow_mut()
            .push_overlay(node.id, OverlayEntry::Node);
    }
    div()
        .id(element_id(node.id))
        .size_0()
        .child(window_layer(popup_motion(layer, node, &view.shared), 2))
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
        // Occluding hitbox: without it mouse-downs on the menu surface
        // pass through to elements painted beneath the deferred layer.
        .occlude()
        .bg(cx.theme().tokens.popover)
        .text_color(cx.theme().popover_foreground)
        .border_1()
        .border_color(cx.theme().border)
        .rounded(cx.theme().radius)
        .shadow(cx.theme().shadow_tokens().lg);
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
/// The rect a non-positioned `dropdown-menu` anchors to: the menu mounts
/// right after its trigger, so the previous sibling's painted rect (or,
/// when the menu is the first/only child of an unpainted wrapper, the
/// nearest painted ancestor's rect) is the anchor.
fn menu_anchor_bounds(
    shared: &Shared,
    node_id: i64,
    parent: Option<i64>,
) -> Option<gpui_kit::gpui::Bounds<gpui_kit::gpui::Pixels>> {
    let prev_sibling = parent.and_then(|parent_id| {
        shared.borrow().store.node(parent_id).and_then(|p| {
            p.children
                .iter()
                .position(|child| *child == node_id)
                .filter(|i| *i > 0)
                .and_then(|i| p.children.get(i - 1).copied())
        })
    });
    let mut cursor = prev_sibling.or(parent);
    loop {
        match cursor {
            Some(id) => match shared.borrow().node_bounds.get(&id) {
                Some(bounds) => break Some(*bounds),
                None => cursor = shared.borrow().store.node(id).and_then(|n| n.parent),
            },
            None => break None,
        }
    }
}

fn dropdown_menu(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    _window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    // `~at` programmatic anchor (web position_at_point parity): the menu
    // mounts at a computed viewport point instead of a DOM sibling rect.
    if node.float_prop(Property::PopupX).is_some() {
        let x = node.float_prop(Property::PopupX).unwrap_or(0.) as f32;
        let y = node.float_prop(Property::PopupY).unwrap_or(0.) as f32;
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
        view.shared
            .borrow_mut()
            .push_overlay(node.id, OverlayEntry::Node);
        let layer = anchored()
            .position(point(px(x), px(y)))
            .anchor(Anchor::TopLeft)
            .snap_to_window()
            .child(popup_motion(menu, node, &view.shared));
        return div()
            .id(element_id(node.id))
            .size_0()
            .child(deferred(layer).with_priority(5))
            .into_any_element();
    }
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
    view.shared
        .borrow_mut()
        .push_overlay(node.id, OverlayEntry::Node);
    // The mount slot resolves the anchor: under a `stack`/`overlay` the
    // wrapper is `.absolute().size_full()` over the (positioned) trigger
    // wrap, so the whole trigger rect anchors the popup. Under any other
    // parent the menu sits in flow right after its trigger — a zero-size
    // slot there anchors the popup to the point directly beneath it
    // without needing a positioned ancestor.
    let positioned = matches!(
        node.parent.and_then(|parent_id| {
            view.shared
                .borrow()
                .store
                .node(parent_id)
                .and_then(|n| n.identity.kind())
        }),
        Some(NodeKind::Stack) | Some(NodeKind::Overlay)
    );
    // Seed the anchor at mount from the last painted anchor rect — the
    // prepaint watcher only has to track drift afterwards.
    let trigger_bounds = view
        .states
        .menu_bounds
        .get()
        .or_else(|| menu_anchor_bounds(&view.shared, node.id, node.parent));
    let mut popup = Positioner::side(trigger_bounds.unwrap_or_default())
        .placement(placement)
        .align(align)
        .offset(px(offset))
        .occlude();
    if stretch {
        if let Some(bounds) = trigger_bounds {
            if bounds.size.width > px(0.) {
                menu = menu.w(bounds.size.width);
            }
        }
    }
    popup = popup.child(popup_motion(menu, node, &view.shared));
    let mut slot = div().id(element_id(node.id));
    slot = if positioned {
        slot.absolute().size_full()
    } else {
        slot.size_0()
    };
    let shared_for_prepaint = view.shared.clone();
    let node_id = node.id;
    let parent_node = node.parent;
    slot.on_prepaint({
        let entity_id = cx.entity().entity_id();
        let menu_bounds = view.states.menu_bounds.clone();
        move |bounds, _, cx| {
            // Non-positioned mounts anchor to the trigger sibling /
            // painted ancestor, not to this zero-size slot's point.
            let anchor = if positioned {
                Some(bounds)
            } else {
                menu_anchor_bounds(&shared_for_prepaint, node_id, parent_node)
            };
            if menu_bounds.get() != anchor {
                menu_bounds.set(anchor);
                cx.notify(entity_id);
            }
        }
    })
    // Menus are the topmost transient surface: they can open inside
    // imperative-root subtrees (priority 4, e.g. dialogs), which
    // must not paint over them.
    .child(deferred(popup).with_priority(5))
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
        .px_3()
        .py_2()
        .text_sm()
        .rounded(cx.theme().radius)
        .hover(move |style| style.bg(hover_bg));
    if selected {
        row = row
            .bg(cx.theme().accent)
            .text_color(cx.theme().accent_foreground);
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
    } else if let Some(data) = app_icon_data(view, node) {
        // `app:` names (settings nav, etc.) rasterize through the host's
        // icon resolver, same as Button.
        row = row.child(Icon::default().data(&data).size_4());
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
            let grandchild_ids = {
                let shared = view.shared.borrow();
                shared
                    .store
                    .node(*child_id)
                    .map(|n| n.children.clone())
                    .unwrap_or_default()
            };
            menu_children = grandchild_ids
                .into_iter()
                .map(|grandchild| view.child_view(grandchild, cx).into_any_element())
                .collect()
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
                |x, y, modifiers, button, target_class| unsafe {
                    bridge::lui_ocaml_context_menu_press(
                        node_id_menu, x, y, modifiers, button, target_class,
                    )
                },
            );
        });
        if let Some(position) = view.states.overlay.get() {
            // Press-outside closes the popup; the menu node itself stays
            // owned by the model.
            view.shared
                .borrow_mut()
                .push_overlay(node.id, OverlayEntry::ContextMenu);
            let open = view.states.overlay.clone();
            let entity = cx.entity().entity_id();
            let menu_id = menu_node_id;
            let shared = view.shared.clone();
            let mut popup = v_flex()
                .id(ElementId::Name(format!("lui-{}-ctxmenu", node.id).into()))
                .gap_0p5()
                .p_1()
                // Occluding hitbox — keep presses on the menu surface
                // from reaching rows painted beneath the deferred layer.
                .occlude()
                .min_w(px(160.))
                .bg(cx.theme().tokens.popover)
                .text_color(cx.theme().popover_foreground)
                .border_1()
                .border_color(cx.theme().border)
                .rounded(cx.theme().radius)
                .shadow(cx.theme().shadow_tokens().lg);
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
                deferred(
                    anchored()
                        .position(position)
                        .snap_to_window()
                        .child(popup),
                )
                // Above imperative roots (4) — context menus can open
                // inside dialogs and other imperative subtrees.
                .with_priority(5),
            );
        }
    }

    style::all(row, node, cx.theme()).into_any_element()
}

/// Pressing a `menu-item` that sits inside a host-owned menu (a
/// context-menu point popup or a `menu`/`submenu` trigger's mounted
/// `dropdown-menu`) must collapse the whole popup chain like the web
/// backend's native menus do. A `popover` ancestor hosting the items is
/// a model-owned menu surface — it closes by firing its registered
/// `Dismiss` event. Model-owned `dropdown-menu` layers — ones mounted
/// under a `stack`/`overlay` so the model decides when they drop — are
/// left alone, and an item rendered inline (no menu ancestor) closes
/// nothing at all.
fn close_host_menus(shared: &Shared, node_id: i64, cx: &mut App) {
    let mut trigger_ids = Vec::new();
    let mut menu_ids = Vec::new();
    let mut context_host_ids = Vec::new();
    let mut popover_ids = Vec::new();
    {
        let shared = shared.borrow();
        let mut next = shared.store.node(node_id).and_then(|n| n.parent);
        while let Some(id) = next {
            let Some(parent) = shared.store.node(id) else {
                break;
            };
            next = parent.parent;
            match parent.identity.kind() {
                Some(NodeKind::MenuTrigger) => trigger_ids.push(id),
                Some(NodeKind::DropdownMenu) => menu_ids.push(id),
                Some(NodeKind::ContextMenu) => {
                    menu_ids.push(id);
                    if let Some(host) = parent.parent {
                        // The context-menu popup is point state on the host
                        // node's view (`states.overlay`).
                        context_host_ids.push(host);
                    }
                }
                // A `popover` hosting menu items is a menu surface too —
                // model-owned, so it closes through its Dismiss event.
                Some(NodeKind::Popover) => popover_ids.push(id),
                _ => {}
            }
        }
    }
    if menu_ids.is_empty() && popover_ids.is_empty() {
        return;
    }
    for popover_id in popover_ids {
        if event_gate_id(shared, popover_id, EventKind::Dismiss) {
            fire(shared, popover_id, EventKind::Dismiss, cx, || unsafe {
                bridge::lui_ocaml_dismiss(popover_id)
            });
        }
    }
    let set_state = {
        let shared = shared.clone();
        move |id: i64, cx: &mut App, apply: &dyn Fn(&mut LuiNodeView)| {
            let entity = shared.borrow().views.get(&id).cloned();
            if let Some(entity) = entity {
                let entity_id = entity.entity_id();
                entity.update(cx, |v, _cx| apply(v));
                cx.notify(entity_id);
            }
        }
    };
    for trigger_id in trigger_ids {
        set_state(trigger_id, cx, &|v| {
            v.states.menu_open.set(false);
            // The pointer still rests on the trigger (or just did on the
            // activated item) — keep the hover-open path disarmed until
            // the pointer leaves.
            v.states.submenu_suppress.set(true);
        });
    }
    for menu_id in menu_ids {
        set_state(menu_id, cx, &|v| v.states.open_submenu.set(None));
    }
    for host_id in context_host_ids {
        set_state(host_id, cx, &|v| v.states.overlay.set(None));
    }
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
/// The `(owner id, open-slot)` of the nearest ancestor menu surface —
/// submenu sibling coordination: only one trigger may hold it. The
/// surface is a dropdown/context menu node, or a `popover` declared
/// with `role: "menu"`; plain containers between the trigger and the
/// surface are skipped.
fn menu_owner(
    view: &LuiNodeView,
    node: &NodeSnapshot,
    cx: &mut App,
) -> Option<(i64, std::rc::Rc<std::cell::Cell<Option<i64>>>)> {
    let owner_id = {
        let shared = view.shared.borrow();
        let mut ancestor = node.parent;
        loop {
            let id = ancestor?;
            let n = match shared.store.node(id) {
                Some(n) => n,
                None => break None,
            };
            let is_menu_surface = match n.identity.kind() {
                Some(NodeKind::DropdownMenu) | Some(NodeKind::ContextMenu) => true,
                Some(NodeKind::Popover) => n.string_prop(Property::RoleValue) == Some("menu"),
                _ => false,
            };
            if is_menu_surface {
                break Some(id);
            }
            ancestor = n.parent;
        }
    }?;
    let owner = LuiShared::view_for(&view.shared, owner_id, cx);
    Some((owner_id, owner.read(cx).states.open_submenu.clone()))
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

/// Enabled items of `menu_id` in render order — `menu-item` and
/// `menu-trigger` rows. A trigger is itself an item; its popup menu
/// lives in a sibling layer, never among its own children, so the walk
/// never descends past triggers or items. Separators/groups are
/// skipped but descended.
fn menu_item_ids(shared: &Shared, menu_id: i64) -> Vec<i64> {
    let shared_ref = shared.borrow();
    let mut items = Vec::new();
    let mut stack: Vec<i64> = shared_ref
        .store
        .node(menu_id)
        .into_iter()
        .flat_map(|node| node.children.iter().rev().copied())
        .collect();
    while let Some(id) = stack.pop() {
        let Some(node) = shared_ref.store.node(id) else {
            continue;
        };
        match node.identity.kind() {
            Some(NodeKind::MenuItem) | Some(NodeKind::MenuTrigger) => {
                if node.enabled() {
                    items.push(id);
                }
            }
            // Model-owned menus mark rows with role=menuitem in data
            // attrs (ghost-button rows that are not the menu-item kind);
            // they join the roving highlight too. They terminate the
            // walk like real items — a menuitem never nests another.
            _ if crate::dom::store_attr(node, "role").as_deref() == Some("menuitem") => {
                if node.enabled() {
                    items.push(id);
                }
            }
            _ => stack.extend(node.children.iter().rev().copied()),
        }
    }
    items
}

/// Open a menu-trigger's submenu for Right/Enter — the same state
/// writes as its hover path: claim the owning menu's open-sub-menu
/// slot (evicting a sibling), set the trigger's open flag, and
/// register the layer for Escape.
fn open_menu_trigger(shared: &Shared, trigger_id: i64, cx: &mut App) {
    let owner_slot = {
        let shared_ref = shared.borrow();
        shared_ref
            .store
            .node(trigger_id)
            .and_then(|node| node.parent)
            .filter(|parent| {
                shared_ref
                    .store
                    .node(*parent)
                    .map(|n| {
                        matches!(
                            n.identity.kind(),
                            Some(NodeKind::DropdownMenu) | Some(NodeKind::ContextMenu)
                        )
                    })
                    .unwrap_or(false)
            })
            .and_then(|parent| shared_ref.views.get(&parent).cloned())
            .map(|view| view.read(cx).states.open_submenu.clone())
    };
    if let Some(slot) = owner_slot {
        if let Some(other) = slot.get().filter(|id| *id != trigger_id) {
            close_submenu(shared, other, cx);
        }
        slot.set(Some(trigger_id));
    }
    if let Some(view) = shared.borrow().views.get(&trigger_id).cloned() {
        view.read(cx).states.menu_open.set(true);
        view.read(cx).states.submenu_suppress.set(false);
        cx.notify(view.entity_id());
    }
    shared
        .borrow_mut()
        .push_overlay(trigger_id, crate::backend::OverlayEntry::Submenu);
}

/// Activate a menu item for Enter — the same Press/PressDetail pair a
/// pointer click reports (primary button, item center), then closes
/// the menus owning it.
fn activate_menu_item(shared: &Shared, node_id: i64, cx: &mut App) {
    if !event_gate_id(shared, node_id, EventKind::Press) {
        return;
    }
    fire(shared, node_id, EventKind::Press, cx, || unsafe {
        bridge::lui_ocaml_press(node_id)
    });
    let position = shared
        .borrow()
        .node_bounds
        .get(&node_id)
        .map(|bounds| bounds.center())
        .unwrap_or(point(px(0.), px(0.)));
    fire_pointer_detail(
        shared,
        node_id,
        EventKind::PressDetail,
        cx,
        position,
        MouseButton::Left,
        &Modifiers::default(),
        |x, y, modifiers, button, target_class| unsafe {
            bridge::lui_ocaml_press_detail(node_id, x, y, modifiers, button, target_class)
        },
    );
    close_host_menus(shared, node_id, cx);
}

/// Arrow/Enter keyboard navigation for the topmost open host menu —
/// gpui's counterpart of the web menu's roving focus. Up/Down move a
/// highlighted item (wrapping), Right opens a highlighted submenu
/// trigger, Enter activates a highlighted item (a trigger opens its
/// submenu), Left collapses a submenu back to its trigger row. Escape
/// keeps the layered `dismiss_topmost_overlay` behavior. Returns
/// whether a menu handled the key — the keydown still reaches document
/// listeners afterward (web parity).
pub(crate) fn menu_nav_key(shared: &Shared, key: &str, cx: &mut App) -> bool {
    if !matches!(key, "up" | "down" | "left" | "right" | "enter") {
        return false;
    }
    let Some((menu_id, trigger_id)) = crate::backend::topmost_menu(shared, cx) else {
        return false;
    };
    let items = menu_item_ids(shared, menu_id);
    if items.is_empty() {
        return true;
    }
    let index = shared
        .borrow()
        .menu_highlight
        .and_then(|id| items.iter().position(|item| *item == id));
    match key {
        "up" | "down" => {
            let next = match (index, key) {
                (None, "down") => 0,
                (None, _) => items.len() - 1,
                (Some(i), "down") => (i + 1) % items.len(),
                (Some(i), _) => {
                    if i == 0 {
                        items.len() - 1
                    } else {
                        i - 1
                    }
                }
            };
            crate::backend::set_menu_highlight(shared, Some(items[next]), cx);
        }
        "left" => {
            if trigger_id.is_some() {
                // Collapse only this submenu layer; the highlight
                // returns to the trigger row.
                crate::backend::dismiss_topmost_overlay(shared, cx);
                crate::backend::set_menu_highlight(shared, trigger_id, cx);
            }
        }
        "right" | "enter" => {
            let Some(id) = index.map(|i| items[i]) else {
                // Roving focus starts on the first arrow press — Enter
                // with nothing highlighted does nothing (web parity).
                return true;
            };
            let kind = shared
                .borrow()
                .store
                .node(id)
                .and_then(|node| node.identity.kind());
            if kind == Some(NodeKind::MenuTrigger) {
                open_menu_trigger(shared, id, cx);
                // Move the highlight into the submenu's first item.
                if let Some(menu_id) = crate::backend::menu_child_id(shared, id) {
                    let first = menu_item_ids(shared, menu_id).into_iter().next();
                    crate::backend::set_menu_highlight(shared, first, cx);
                }
            } else if key == "enter" {
                activate_menu_item(shared, id, cx);
            }
        }
        _ => {}
    }
    true
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
        .min_h(px(32.))
        .items_center()
        .gap_2()
        .px_2()
        .py_1p5()
        .text_sm()
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
    // Keyboard navigation paints the highlighted row with the same
    // accent as pointer hover.
    row = row.when(
        view.shared.borrow().menu_highlight == Some(node.id),
        |row| row.bg(hover_bg),
    );

    if let Some(menu_id) = menu_node_id {
        let owner = menu_owner(view, node, cx);
        let open = view.states.menu_open.clone();
        let entity = cx.entity().entity_id();
        let shared = view.shared.clone();
        let node_id = node.id;
        let suppress = view.states.submenu_suppress.clone();
        row = row.on_hover({
            let owner = owner.clone();
            move |hovered, _, cx| {
                // A programmatic close while the pointer rests on the row
                // must stick — hover-open re-arms only after the pointer
                // actually leaves the trigger.
                if !*hovered {
                    suppress.set(false);
                    return;
                }
                // Pointer hover moves the roving highlight too — one
                // highlight model for pointer and keys (web parity).
                crate::backend::set_menu_highlight(&shared, Some(node_id), cx);
                // Hover-open only applies to submenu triggers (a menu has an
                // owning dropdown/context menu). A standalone `menu` is
                // press-to-open — hover-opening here would make the
                // subsequent click's toggle immediately close it again.
                if !open.get() && owner.is_some() && !suppress.get() {
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
        let popup_bounds = view.states.popup_bounds.clone();
        row = row.cursor_pointer().on_click({
            let open = view.states.menu_open.clone();
            let entity = cx.entity().entity_id();
            let owner = owner.clone();
            let popup_bounds = popup_bounds.clone();
            move |event, _, cx| {
                // The popup can paint over the row's own bounds, so clicks
                // inside it also reach this handler — ignore those; only a
                // press on the trigger row itself toggles the menu.
                if popup_bounds
                    .get()
                    .map(|bounds| bounds.contains(&event.position()))
                    .unwrap_or(false)
                {
                    return;
                }
                let next = !open.get();
                if let Some((_, slot)) = &owner {
                    slot.set(next.then_some(node_id));
                }
                open.set(next);
                cx.notify(entity);
            }
        });
        if view.states.menu_open.get() {
            view.shared
                .borrow_mut()
                .push_overlay(node.id, OverlayEntry::Submenu);
            let item_ids = {
                let shared = view.shared.borrow();
                shared
                    .store
                    .node(menu_id)
                    .map(|n| n.children.clone())
                    .unwrap_or_default()
            };
            let items = item_ids
                .into_iter()
                .map(|child_id| view.child_view(child_id, cx).into_any_element())
                .collect::<Vec<_>>();
            if !items.is_empty() {
                let open = view.states.menu_open.clone();
                let entity = cx.entity().entity_id();
                let shared = view.shared.clone();
                let mut popup = v_flex()
                    .id(ElementId::Name(format!("lui-{}-submenu", node.id).into()))
                    .gap_0p5()
                    .p_1()
                    // Occluding hitbox — submenu rows must not leak
                    // presses to elements under the deferred layer.
                    .occlude()
                    .min_w(px(min_width))
                    .bg(cx.theme().popover)
                    .border_1()
                    .border_color(cx.theme().border)
                    .rounded_md()
                    .shadow_lg()
                    .children(items)
                    .on_prepaint(move |bounds, _, _| {
                        popup_bounds.set(Some(bounds));
                    });
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
                // Submenus open at the row's right edge; a standalone `menu`
                // (no owning menu) opens below the trigger like a pulldown.
                // The popup mounts as a *sibling* of the row — as a child it
                // would let clicks on its items bubble into the row's
                // `on_click` and toggle the submenu back open.
                let anchor_div = if owner.is_some() {
                    div().absolute().top_0().right_0().size_0()
                } else {
                    div().absolute().left_0().bottom_0().size_0()
                };
                let offset = if owner.is_some() {
                    point(px(-2.), px(-4.))
                } else {
                    point(px(0.), px(4.))
                };
                let layer = anchor_div.child(
                    deferred(
                        anchored()
                            .anchor(Anchor::TopLeft)
                            .offset(offset)
                            .snap_to_window()
                            .child(popup),
                    )
                    .with_priority(5),
                );
                let element = div().child(row).child(layer);
                return style::all(element, node, cx.theme()).into_any_element();
            }
        }
    } else {
        // Stale popup bounds from an earlier open must not mask clicks on
        // the trigger itself once the popup is gone.
        view.states.popup_bounds.set(None);
    }

    style::all(row, node, cx.theme()).into_any_element()
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
    style::all(element, node, cx.theme()).into_any_element()
}

/// Two retained panes. Reconcile the controlled fraction after measuring
/// the group's actual allocation, and only when its width or model changes.
fn split(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    _window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let node_id = node.id;
    let fraction = node.float_prop(Property::ProgressValue).unwrap_or(0.5) as f32;
    let fraction = if fraction.is_finite() {
        fraction.clamp(0., 1.)
    } else {
        0.5
    };
    let state = view
        .states
        .split
        .get_or_insert_with(|| cx.new(|_| Default::default()))
        .clone();
    let target = view.states.split_target.clone();
    let mut children = view.child_elements(node, cx).into_iter();
    let shared = view.shared.clone();
    let group = gpui_kit::component::h_resizable(element_id(node_id))
        .with_state(&state)
        .on_resize(move |state, _, cx| {
            let sizes = state.read(cx).sizes();
            let total: f32 = sizes.iter().map(|size| f32::from(*size)).sum();
            if total > 0. {
                let fraction = f32::from(sizes[0]) / total;
                fire(&shared, node_id, EventKind::ValueChanged, cx, || unsafe {
                    bridge::lui_ocaml_slider_changed(node_id, fraction as f64)
                });
            }
        })
        .child(
            gpui_kit::component::resizable_panel()
                .size_range(px(0.)..Pixels::MAX)
                .child(children.next().unwrap_or_else(|| div().into_any_element())),
        )
        .child(
            gpui_kit::component::resizable_panel()
                .size_range(px(0.)..Pixels::MAX)
                .child(children.next().unwrap_or_else(|| div().into_any_element())),
        );
    style::all(div().size_full().child(group), node, cx.theme())
        .on_children_prepainted(move |bounds, window, cx| {
            let Some(bounds) = bounds.first() else { return };
            let width = bounds.size.width;
            if target.get() == Some((width, fraction)) {
                return;
            }
            target.set(Some((width, fraction)));
            let state = state.clone();
            window.defer(cx, move |window, cx| {
                state.update(cx, |state, cx| {
                    state.resize_panel(0, width * fraction, window, cx)
                });
            });
        })
        .into_any_element()
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
    style::all(div().size_full().child(group), node, cx.theme()).into_any_element()
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
    style::all(element, node, cx.theme()).into_any_element()
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
    style::all(row, node, cx.theme()).into_any_element()
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
    style::all(row, node, cx.theme()).into_any_element()
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
        .min_h(px(32.))
        .items_center()
        .gap_2()
        .px_2()
        .py_1p5()
        .text_sm()
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
    // Keyboard navigation paints the highlighted row with the same
    // accent as pointer hover.
    row = row.when(
        view.shared.borrow().menu_highlight == Some(node.id),
        |row| row.bg(hover_bg),
    );
    // Hovering a plain item closes the sibling submenu that currently
    // holds the owning menu's open slot.
    let owner = menu_owner(view, node, cx);
    let shared = view.shared.clone();
    let node_id = node.id;
    row = row.on_hover(move |hovered, _, cx| {
        if *hovered {
            // Pointer hover moves the roving highlight too — one
            // highlight model for pointer and keys (web parity).
            crate::backend::set_menu_highlight(&shared, Some(node_id), cx);
            if let Some((_, slot)) = &owner {
                if let Some(other) = slot.get() {
                    close_submenu(&shared, other, cx);
                    slot.set(None);
                }
            }
        }
    });
    if press_gate(view, node.id) {
        let press = press_handler(view, node.id);
        let shared = view.shared.clone();
        let node_id = node.id;
        row = row
            .cursor_pointer()
            .on_click(move |event, window, cx| {
                press(event, window, cx);
                close_host_menus(&shared, node_id, cx);
            });
    }
    style::all(row, node, cx.theme()).into_any_element()
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
    // Header reads as a labeled row: title on the leading edge, disclosure
    // chevron on the trailing edge; the box itself is just a bottom rule.
    let mut element = v_flex()
        .id(element_id(node.id))
        .w_full()
        .border_b_1()
        .border_color(cx.theme().border)
        .child(
            h_flex()
                .id(ElementId::Name(format!("lui-{}-accordion", node.id).into()))
                .w_full()
                .items_center()
                .justify_between()
                .gap_2()
                .py_4()
                .cursor_pointer()
                .child(
                    div()
                        .flex_1()
                        .text_sm()
                        .font_weight(FontWeight::MEDIUM)
                        .child(text_of(node)),
                )
                .child(
                    Icon::new(chevron)
                        .size_4()
                        .text_color(cx.theme().muted_foreground),
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
                .pb_4()
                .text_sm()
                .children(view.child_elements(node, cx)),
        );
    }
    style::all(element, node, cx.theme()).into_any_element()
}

/// `file-picker`: button opens the platform path prompt; chosen paths go
/// back through `lui_ocaml_picked` as a JSON array.
fn file_picker(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    _window: &mut Window,
    cx: &mut Context<LuiNodeView>,
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
                        fire(&shared, node_id, EventKind::Picked, cx, || unsafe {
                            bridge::lui_ocaml_picked_utf8(
                                node_id,
                                payload.as_ptr() as *const std::ffi::c_char,
                                payload.len() as std::ffi::c_int,
                            )
                        });
                    });
                }
            })
            .detach();
    });
    style::all(button, node, cx.theme()).into_any_element()
}

/// `bottom-tabs`: stacked pages (the `bottom-tab` children's content, all
/// mounted so per-tab state survives switches; only the selected one is
/// visible) above a tab bar of icon+label entries. Presses go to the
/// `bottom-tab` node — the model owns which tab is `selected`.
fn bottom_tabs(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    // Collect per-tab presentation data in one store borrow; rendering the
    // grandchildren borrows again inside `child_view`.
    let tabs: Vec<(i64, String, Option<gpui_kit::assets::IconName>)> = {
        let shared = view.shared.borrow();
        node.children
            .iter()
            .filter_map(|child_id| {
                shared.store.node(*child_id).map(|child| {
                    (
                        *child_id,
                        child.string_prop(Property::TitleValue).unwrap_or("").to_string(),
                        child
                            .string_prop(Property::InlineIconName)
                            .or_else(|| child.string_prop(Property::IconName))
                            .and_then(icon_for),
                    )
                })
            })
            .collect()
    };
    let selected_id = {
        let shared = view.shared.borrow();
        node.children
            .iter()
            .copied()
            .find(|child_id| {
                shared
                    .store
                    .node(*child_id)
                    .map(|child| child.flag(Property::Selected))
                    .unwrap_or(false)
            })
            .or_else(|| node.children.first().copied())
    };

    // Only the selected page renders — its content drives the area's
    // height. Dormant pages' `LuiNodeView` entities stay alive in
    // `shared.views`, so per-tab component state survives switches.
    let mut pages = div().flex_1().min_h_0().w_full().relative();
    if let Some(selected_id) = selected_id {
        let grandchildren = {
            let shared = view.shared.borrow();
            shared
                .store
                .node(selected_id)
                .map(|child| child.children.clone())
                .unwrap_or_default()
        };
        let mut page = div()
            .id(ElementId::Name(format!("lui-{selected_id}-page").into()))
            .w_full();
        for grandchild in grandchildren {
            page = page.child(view.child_view(grandchild, cx).into_any_element());
        }
        pages = pages.child(page);
    }

    let active_fg = cx.theme().primary;
    let inactive_fg = cx.theme().muted_foreground;
    let mut bar = h_flex()
        .w_full()
        .items_stretch()
        .justify_around()
        .border_t_1()
        .border_color(cx.theme().border)
        .bg(cx.theme().tokens.tab_bar);
    for (tab_id, title, icon) in tabs {
        let active = Some(tab_id) == selected_id;
        let fg = if active { active_fg } else { inactive_fg };
        let mut item = v_flex()
            .id(ElementId::Name(format!("lui-{tab_id}-tab").into()))
            .flex_1()
            .min_w_0()
            .items_center()
            .justify_center()
            .gap_0p5()
            .py_2()
            .text_xs()
            .text_color(fg);
        if let Some(icon) = icon {
            item = item.child(Icon::new(icon).size(px(22.)).text_color(fg));
        }
        if !title.is_empty() {
            item = item.child(div().min_w_0().text_ellipsis().child(title));
        }
        let enabled = {
            let shared = view.shared.borrow();
            shared
                .store
                .node(tab_id)
                .map(|child| child.enabled())
                .unwrap_or(true)
        };
        if !enabled {
            item = item.opacity(0.5);
        } else if press_gate(view, tab_id) {
            item = item
                .cursor_pointer()
                .on_click(press_handler(view, tab_id));
        }
        bar = bar.child(item);
    }

    let mut element = v_flex().id(element_id(node.id)).w_full().flex_1();
    element = style::all(element, node, cx.theme());
    element.child(pages).child(bar).into_any_element()
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
    // display:none — a `hidden` token (literal or carried by a registered
    // semantic class) removes the node from layout, same as the
    // extension-arm check in dom.rs.
    if let Some(classes) = node.string_prop(Property::StyleClass) {
        if classes.split_whitespace().any(|t| t == "hidden")
            || crate::style::class_has_utility(classes, "hidden")
        {
            return div().into_any_element();
        }
    }
    match kind {
        // Containers -----------------------------------------------------
        NodeKind::Root => {
            let mut element = v_flex()
                .id(element_id(node.id))
                .size_full()
                .bg(cx.theme().background)
                .text_color(cx.theme().foreground)
                .font_family(cx.theme().font_family.clone());
            element = style::all(element, node, cx.theme());
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
        // `status-bar`: an inline status pill (secondary surface, caption
        // text), not window chrome — the element carries no children.
        NodeKind::StatusBar => {
            let mut element = h_flex()
                .id(element_id(node.id))
                .w_full()
                .items_center()
                .gap_1p5()
                .px_3()
                .py_1p5()
                .rounded(cx.theme().radius)
                .bg(cx.theme().tokens.secondary)
                .text_xs()
                .text_color(cx.theme().secondary_foreground);
            if node.string_prop(Property::TextAlignment) == Some("center") {
                element = element.justify_center();
            }
            element = style::all(element, node, cx.theme());
            element.child(text_of(node)).into_any_element()
        }
        NodeKind::BottomTabs => bottom_tabs(view, node, cx),
        // `bottom-tab` nodes are data for the parent `bottom-tabs` bar and
        // its pages — rendered there; standalone they mount invisibly.
        NodeKind::BottomTab => div().id(element_id(node.id)).size_0().into_any_element(),
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
        NodeKind::VirtualList => crate::virtual_list::render(view, node, cx),
        NodeKind::ListContainer => {
            // Ordinary collections retain their complete child layout.
            view.states.scroll_tracked = true;
            view
                .shared
                .borrow_mut()
                .scroll_handles
                .insert(node.id, view.states.scroll.clone());
            // Stamp wheel events so `scroll.rs` can tell a genuine
            // scroll-to-top from gpui's transient clamp-to-zero.
            let wheel_shared = view.shared.clone();
            let wheel_node = node.id;
            let mut element = v_flex()
                .size_full()
                .id(element_id(node.id))
                .overflow_y_scroll()
                .track_scroll(&view.states.scroll)
                .on_scroll_wheel(move |_, _, _| {
                    wheel_shared
                        .borrow_mut()
                        .scroll_wheel_marks
                        .insert(wheel_node, std::time::Instant::now());
                });
            element = style::all(element, node, cx.theme());
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
            // A `dropdown-menu` declaring an anchor (or dismissable — every
            // real menu registers Dismiss) is a floating menu: render it as
            // a deferred popup anchored to its mount slot rather than
            // pushing the layout inline. Only a menu with neither — e.g. a
            // section showcasing menu items — renders in place.
            let floating = matches!(parent_kind, Some(NodeKind::Stack) | Some(NodeKind::Overlay))
                || node.string_prop(Property::AnchorValue).is_some()
                || node.float_prop(Property::PopupX).is_some()
                || event_gate(view, node.id, EventKind::Dismiss);
            match parent_kind {
                // A `dropdown-menu` nested under a `menu-trigger` (the
                // `menu`/`submenu` element) is rendered by the trigger row
                // itself — it stays an invisible mount point here.
                Some(NodeKind::MenuTrigger) => {
                    div().id(element_id(node.id)).size_0().into_any_element()
                }
                // Mounted inside a `stack`/`overlay` (trigger + menu
                // siblings): render as a deferred popover under the stack.
                _ if floating => dropdown_menu(view, node, window, cx),
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
                .rounded(cx.theme().radius_tokens().xl)
                .border_1()
                .border_color(cx.theme().border)
                .bg(cx.theme().tokens.popover)
                .text_color(cx.theme().popover_foreground)
                .shadow(cx.theme().shadow_tokens().sm);
            element = style::all(element, node, cx.theme());
            element
                .children(view.child_elements(node, cx))
                .into_any_element()
        }
        NodeKind::Card => {
            let mut element = v_flex()
                .id(element_id(node.id))
                .rounded(cx.theme().radius_tokens().xl)
                .border_1()
                .border_color(cx.theme().border)
                .bg(cx.theme().tokens.popover)
                .text_color(cx.theme().popover_foreground)
                .p_6();
            element = style::all(element, node, cx.theme());
            element
                .children(view.child_elements(node, cx))
                .into_any_element()
        }
        // `bubble`: chat-style message surface — content-sized, capped at
        // 80% of the parent; `primary` inverts to the accent fill, `ghost`
        // drops the chrome entirely.
        NodeKind::Bubble => {
            let mut element = v_flex()
                .id(element_id(node.id))
                .self_start()
                .max_w(gpui_kit::gpui::relative(0.8))
                .gap_1()
                .rounded(cx.theme().radius_tokens().xl)
                .px_4()
                .py_3();
            match variant_of(node) {
                "primary" => {
                    element = element
                        .bg(cx.theme().tokens.primary)
                        .text_color(cx.theme().primary_foreground)
                        .border_1()
                        .border_color(cx.theme().primary)
                }
                "ghost" => element = element.px_0(),
                _ => {
                    element = element
                        .bg(cx.theme().tokens.popover)
                        .text_color(cx.theme().popover_foreground)
                        .border_1()
                        .border_color(cx.theme().border)
                }
            }
            element = style::all(element, node, cx.theme());
            element
                .children(view.child_elements(node, cx))
                .into_any_element()
        }
        NodeKind::Grid => {
            let columns = node.int_prop(Property::GridColumns).unwrap_or(0).max(0);
            let mut element = div().id(element_id(node.id)).v_flex().gap_2();
            element = style::all(element, node, cx.theme());
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
            style::all(element, node, cx.theme()).into_any_element()
        }
        NodeKind::Scroll => {
            view.states.scroll_tracked = true;
            if node.string_prop(Property::OrientationValue) == Some("horizontal") {
                // Wide-content scroller (e.g. the views table): bounded
                // horizontally, content-sized vertically. `h_full` inside
                // a content-sized column would collapse the viewport.
                // restrict_scroll_to_axis keeps vertical wheel deltas from
                // being remapped to a horizontal pan — they must reach an
                // outer vertical scroller instead.
                let mut element = h_flex()
                    .w_full()
                    .id(element_id(node.id))
                    .overflow_x_scroll()
                    .restrict_scroll_to_axis()
                    .track_scroll(&view.states.scroll);
                element = style::all(element, node, cx.theme());
                return element
                    .children(view.child_elements(node, cx))
                    .into_any_element();
            }
            let mut element = v_flex()
                .size_full()
                .id(element_id(node.id))
                .overflow_y_scroll()
                .track_scroll(&view.states.scroll);
            element = style::all(element, node, cx.theme());
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
            element = style::all(element, node, cx.theme());
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
            element = style::all(element, node, cx.theme());
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
            element = style::all(element, node, cx.theme());
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
            element = style::all(element, node, cx.theme());
            element.child(text_of(node)).into_any_element()
        }

        // Controls --------------------------------------------------------
        NodeKind::Button | NodeKind::ToggleButton => button(view, node, cx),
        NodeKind::SwipeAction => container(view, node, kind, false, cx),
        NodeKind::Checkbox => {
            let mut element = Checkbox::new(element_id(node.id))
                .label(text_of(node))
                .checked(node.flag(Property::Checked))
                .disabled(!node.enabled())
                .on_click(toggle_handler(view, node.id));
            element = style::all(element, node, cx.theme());
            element.into_any_element()
        }
        NodeKind::SwitchControl | NodeKind::Toggle => {
            let mut element = Switch::new(element_id(node.id))
                .checked(node.flag(Property::Checked))
                .disabled(!node.enabled())
                .on_click(toggle_handler(view, node.id));
            element = style::all(element, node, cx.theme());
            element.into_any_element()
        }
        NodeKind::Radio => {
            let mut element = Radio::new(element_id(node.id))
                .label(text_of(node))
                .checked(node.flag(Property::Selected) || node.flag(Property::Checked))
                .disabled(!node.enabled())
                .on_click(radio_handler(view, node.id));
            element = style::all(element, node, cx.theme());
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
            element = style::all(element, node, cx.theme());
            element.into_any_element()
        }
        NodeKind::Divider => {
            let horizontal = node.string_prop(Property::OrientationValue) != Some("vertical");
            let mut element = if horizontal {
                Separator::horizontal()
            } else {
                Separator::vertical()
            };
            element = style::all(element, node, cx.theme());
            element.into_any_element()
        }
        // Web renders `lui-spacer` as a plain empty div — zero-size
        // unless the view asks for growth via `~grow`/a class. Most
        // callers use it as a nil anchor (conditional "no element"
        // slots); an unconditional flex_1() inflates those anchors
        // into blank gaps (e.g. the cmdk scroller's filter/empty
        // placeholders). Explicit ~grow still lands via GrowValue.
        NodeKind::Spacer => style::all(div(), node, cx.theme()).into_any_element(),
        NodeKind::Spinner => {
            style::all(div().child(Spinner::new()), node, cx.theme()).into_any_element()
        }
        NodeKind::Icon => match icon_name(node, Property::InlineIconName)
            .or_else(|| icon_name(node, Property::IconName))
        {
            Some(icon) => {
                let mut element = Icon::new(icon);
                element = style::all(element, node, cx.theme());
                element.into_any_element()
            }
            None => match icon_name_raw(node)
                .and_then(|raw| raw.strip_prefix("app:"))
                .and_then(|name| app_icon_image(view, node, name, window, cx))
            {
                Some(image) => {
                    let mut element = div()
                        .size(px(18.))
                        .child(img(ImageSource::Render(image)).size_full());
                    element = style::all(element, node, cx.theme());
                    element.into_any_element()
                }
                None => extension::placeholder_box(view, node, "icon", cx),
            },
        },
        NodeKind::Avatar => {
            let mut element = gpui_kit::component::avatar::Avatar::new().name(text_of(node));
            if let Some(url) = node.string_prop(Property::UrlValue) {
                element = element.src(url.to_string());
            }
            element = style::all(element, node, cx.theme());
            element.into_any_element()
        }
        NodeKind::Link => {
            // Children are inline runs (external-link label pieces,
            // page-ref title text) — a bare `text_of` would drop them.
            let node_id = node.id;
            let shared = view.shared.clone();
            let mut element = Link::new(element_id(node.id));
            // An empty `text` prop still lays out a phantom line inside the
            // link's column — only attach a run when there is one.
            let text = text_of(node);
            if !text.is_empty() {
                element = element.child(text);
            }
            element = element
                .children(view.child_elements(node, cx))
                .on_click(move |event: &ClickEvent, _, cx| {
                    let button = match event {
                        ClickEvent::Mouse(mouse) => mouse.down.button,
                        _ => MouseButton::Left,
                    };
                    let position = event.position();
                    let modifiers = event.modifiers();
                    fire_press(&shared, node_id, &modifiers, button, cx);
                    fire_pointer_detail(
                        &shared,
                        node_id,
                        EventKind::PressDetail,
                        cx,
                        position,
                        button,
                        &modifiers,
                        |x, y, modifiers, button, target_class| unsafe {
                            bridge::lui_ocaml_press_detail(
                                node_id, x, y, modifiers, button, target_class,
                            )
                        },
                    );
                    // DOM-parity click: delegated document listeners
                    // (`a.page-ref`, `a.tag`, `a[target=_blank]`) match
                    // the target snapshot's tag/class/attrs.
                    let hit = dom::deepest_hit(&shared, position).unwrap_or(node_id);
                    let (carrier, ident) = match dom::logseq_carrier(&shared, Some(hit)) {
                        Some(pair) => pair,
                        None => (node_id, String::new()),
                    };
                    dom::dom_event_via(
                        &shared,
                        carrier,
                        &ident,
                        hit,
                        "click",
                        serde_json::json!({
                            "clientX": f64::from(position.x),
                            "clientY": f64::from(position.y),
                        }),
                        cx,
                    );
                    // The kit Link stops MouseDown propagation, so
                    // ancestor press handlers never see this click —
                    // bubble it manually (DOM parity).
                    bubble_press(&shared, node_id, cx, position, button, &modifiers);
                });
            element = style::all(element, node, cx.theme());
            element.into_any_element()
        }
        NodeKind::Kbd => {
            let element = match gpui_kit::gpui::Keystroke::parse(&text_of(node)) {
                Ok(stroke) => gpui_kit::component::kbd::Kbd::new(stroke).into_any_element(),
                // Unparseable stroke still shows the raw label.
                Err(_) => div()
                    .h_5()
                    .items_center()
                    .px_1p5()
                    .rounded_sm()
                    .border_1()
                    .border_color(cx.theme().border)
                    .bg(cx.theme().tokens.secondary)
                    .font_family(cx.theme().mono_font_family.clone())
                    .text_size(px(10.))
                    .font_weight(FontWeight::MEDIUM)
                    .text_color(cx.theme().muted_foreground)
                    .child(text_of(node))
                    .into_any_element(),
            };
            style::all(div().child(element), node, cx.theme()).into_any_element()
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
            element = style::all(element, node, cx.theme());
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
                    view.shared
                        .borrow_mut()
                        .push_overlay(node.id, OverlayEntry::Tooltip);
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
                                .with_priority(5),
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
                                .with_priority(5),
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
            // host owns the segmented-control strip (padded secondary pill,
            // see `tab_button` for the entry styling).
            let vertical = node.string_prop(Property::OrientationValue) == Some("vertical");
            let mut element = if vertical {
                v_flex().id(element_id(node.id)).items_stretch()
            } else {
                h_flex().id(element_id(node.id)).items_center()
            };
            element = element
                .gap_1()
                .p_1()
                .rounded(cx.theme().radius_lg)
                .bg(cx.theme().tokens.tab_bar_segmented)
                .text_color(cx.theme().secondary_foreground);
            element = style::all(element, node, cx.theme());
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
                element = style::all(element, node, cx.theme());
                element.into_any_element()
            }
            None => extension::placeholder_box(view, node, "file-image", cx),
        },
        // `image` resolves a `url` or `path` source directly; `image` ids,
        // `media_surface` and `file_preview` reference host-owned
        // registries — no bytes reach the wire for those.
        NodeKind::Image => {
            match node
                .string_prop(Property::UrlValue)
                .or_else(|| node.string_prop(Property::PathValue))
            {
                Some(source) => {
                    let mut element = div()
                        .id(element_id(node.id))
                        .child(gpui_kit::gpui::img(source.to_string()).size_full());
                    element = style::all(element, node, cx.theme());
                    element.into_any_element()
                }
                None => extension::placeholder_box(view, node, kind.wire_name(), cx),
            }
        }
        NodeKind::MediaSurface | NodeKind::FilePreview => {
            extension::placeholder_box(view, node, kind.wire_name(), cx)
        }
        // Line break: a full-width zero-height item ends the current line
        // in the wrapping inline flow (text runs lay out via flex-wrap).
        NodeKind::Br => div()
            .id(element_id(node.id))
            .w_full()
            .h(px(0.))
            .into_any_element(),
        NodeKind::Popover => popover(view, node, window, cx),
    }
}

/// `popover`: model-owned floating layer — emitted while open. With
/// `popup-x`/`popup-y` it is point-anchored (e.g. the caret rect bottom
/// for completions and the click point for menus): the content box gets
/// the dropdown-menu surface and `anchor`/`anchor-alignment` pick which
/// corner of the popup sits at the point. Without a point it is a cover
/// layer: the positioner spans the window so overlay hosts (`.cp__overlays`,
/// dialog overlay columns) float above the page instead of rendering
/// in-flow at the document tail. Outside presses fire `Dismiss` so the
/// model drops the node; `available-height` bounds the box when the model
/// pre-computed a remaining-space budget.
fn popover(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    if node.float_prop(Property::PopupX).is_none() {
        // Element-anchored popover (`anchor`/`anchor-alignment`/`anchor-offset`
        // set, no point): the node is emitted in-flow right after its trigger
        // (web anchors to the parent's last child), so a zero-size layer's own
        // origin is the trigger's bottom-left — the anchor point. `anchor`
        // picks which popup corner sits at that point; `anchor-alignment`
        // adjusts the cross axis.
        if node.string_prop(Property::AnchorValue).is_some() {
            let offset = node.float_prop(Property::AnchorOffset).unwrap_or(0.) as f32;
            let (corner, dx, dy) = match (
                node.string_prop(Property::AnchorValue),
                node.string_prop(Property::AnchorAlignmentValue),
            ) {
                // below+start: popup's top-left at the trigger's bottom-left.
                (Some("below"), Some("end")) => (Anchor::TopRight, 0., offset),
                (Some("below"), Some("center")) => (Anchor::TopCenter, 0., offset),
                (Some("below"), _) => (Anchor::TopLeft, 0., offset),
                // above/left/right: same anchor point, the popup's opposing
                // corner lands on it.
                (Some("above"), Some("end")) => (Anchor::BottomRight, 0., -offset),
                (Some("above"), Some("center")) => (Anchor::BottomCenter, 0., -offset),
                (Some("above"), _) => (Anchor::BottomLeft, 0., -offset),
                (Some("left"), _) => (Anchor::RightCenter, -offset, 0.),
                (Some("right"), _) => (Anchor::LeftCenter, offset, 0.),
                _ => (Anchor::TopLeft, 0., offset),
            };
            // Stateful wrapper so the capped menu can track its scroll
            // offset — scroll methods live on StatefulInteractiveElement.
            let mut menu = menu_box(view, node, cx).id(ElementId::Name(
                format!("lui-{}-popmenu", node.id).into(),
            ));
            if let Some(available) = node.float_prop(Property::AvailableHeight) {
                if available > 0. {
                    // Web popup content scrolls when it hits the cap
                    // (overflow-y:auto on the card) — clipping would make
                    // the tail items unreachable.
                    menu = menu
                        .max_h(px(available as f32))
                        .overflow_y_scroll()
                        .track_scroll(&view.states.scroll);
                }
            }
            if event_gate(view, node.id, EventKind::Dismiss) {
                let shared = view.shared.clone();
                let node_id = node.id;
                menu = menu.on_mouse_down_out(move |_, _, cx| {
                    fire(&shared, node_id, EventKind::Dismiss, cx, || unsafe {
                        bridge::lui_ocaml_dismiss(node_id)
                    });
                });
            }
            view.shared
                .borrow_mut()
                .push_overlay(node.id, OverlayEntry::Node);
            let layer = anchored()
                .anchor(corner)
                .offset(point(px(dx), px(dy)))
                .snap_to_window()
                .child(popup_motion(menu, node, &view.shared));
            return div()
                .id(element_id(node.id))
                .size_0()
                .child(deferred(layer).with_priority(5))
                .into_any_element();
        }
        // `size_full` inside `anchored` resolves against an indefinite
        // size and collapses to 0x0 — size the layer to the viewport
        // explicitly like `overlay_modal` does.
        let viewport = window.viewport_size();
        let content = v_flex()
            .w(viewport.width)
            .h(viewport.height)
            .children(view.child_elements(node, cx));
        view.shared
            .borrow_mut()
            .push_overlay(node.id, OverlayEntry::Node);
        return div()
            .id(element_id(node.id))
            .size_0()
            .child(window_layer(popup_motion(content, node, &view.shared), 3))
            .into_any_element();
    }
    let x = node.float_prop(Property::PopupX).unwrap_or(0.) as f32;
    let y = node.float_prop(Property::PopupY).unwrap_or(0.) as f32;
    // Stateful wrapper so the capped menu can track its scroll offset —
    // scroll methods live on StatefulInteractiveElement.
    let mut menu = menu_box(view, node, cx).id(ElementId::Name(
        format!("lui-{}-popmenu", node.id).into(),
    ));
    if let Some(available) = node.float_prop(Property::AvailableHeight) {
        if available > 0. {
            // Web popup content scrolls when it hits the cap
            // (overflow-y:auto on the card) — clipping would make the
            // tail items unreachable.
            menu = menu
                .max_h(px(available as f32))
                .overflow_y_scroll()
                .track_scroll(&view.states.scroll);
        }
    }
    if event_gate(view, node.id, EventKind::Dismiss) {
        let shared = view.shared.clone();
        let node_id = node.id;
        menu = menu.on_mouse_down_out(move |_, _, cx| {
            fire(&shared, node_id, EventKind::Dismiss, cx, || unsafe {
                bridge::lui_ocaml_dismiss(node_id)
            });
        });
        view.shared
            .borrow_mut()
            .push_overlay(node.id, OverlayEntry::Node);
    }
    // `anchor` is the side of the point the popup opens on; combined with
    // `anchor-alignment` it picks which corner of the popup sits at the
    // point (web positioner: side=above + align=end -> bottom-right).
    let corner = match (
        node.string_prop(Property::AnchorValue),
        node.string_prop(Property::AnchorAlignmentValue),
    ) {
        (Some("above"), Some("end")) => Anchor::BottomRight,
        (Some("above"), Some("center")) => Anchor::BottomCenter,
        (Some("above"), _) => Anchor::BottomLeft,
        (Some("below"), Some("end")) => Anchor::TopRight,
        (Some("below"), Some("center")) => Anchor::TopCenter,
        (Some("left"), _) => Anchor::RightCenter,
        (Some("right"), _) => Anchor::LeftCenter,
        _ => Anchor::TopLeft,
    };
    let layer = anchored()
        .position(point(px(x), px(y)))
        .anchor(corner)
        .snap_to_window()
        .child(popup_motion(menu, node, &view.shared));
    div()
        .id(element_id(node.id))
        .size_0()
        .child(deferred(layer).with_priority(5))
        .into_any_element()
}
