//! Extension visual host: how `create-extension` nodes render.
//!
//! Identifier namespaces (ADR 0002): extensions are app-scoped, kebab-case.
//! `gpui-*` is reserved for gpui-specific components — apps register a
//! specialized [`ExtensionRenderer`] per identifier on `LuiShared`, or fall
//! back to the generic host below (children in a labeled container).

use gpui_kit::component::theme::ActiveTheme;
use gpui_kit::component::v_flex;
use gpui_kit::gpui::{div, AnyElement, Context, IntoElement, ParentElement, Styled, Window};
use lui_core::store::NodeIdentity;
use lui_core::Property;

use crate::dom;
use crate::node_view::{LuiNodeView, NodeSnapshot};
use crate::style;

/// Renders one extension node into an element. Registered per identifier on
/// `LuiShared::extension_renderers`; takes the owning view (for child entity
/// embedding) and the node snapshot.
pub type ExtensionRenderer = for<'a, 'b, 'c> fn(
    &mut LuiNodeView,
    &NodeSnapshot,
    &mut Window,
    &mut Context<LuiNodeView>,
) -> AnyElement;

pub fn render(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let NodeIdentity::Extension { identifier, .. } = &node.identity else {
        return div().into_any_element();
    };
    let identifier = identifier.clone();

    // `logseq-*` is the app's DOM-ish tag family — routed to the dedicated
    // dom.rs renderer (transparent containers + style-class + dom-event),
    // never the generic warning host.
    if identifier.starts_with("logseq-") {
        return dom::render(view, node, window, cx);
    }

    // A registered specialized renderer wins (this is how `gpui-*`
    // components plug in).
    let renderer = view
        .shared
        .borrow()
        .extension_renderers
        .get(&identifier)
        .copied();
    if let Some(render_extension) = renderer {
        return render_extension(view, node, window, cx);
    }

    let spec = view
        .shared
        .borrow()
        .registry
        .get(&identifier)
        .map(|spec| spec.flavor);

    let children = view.child_elements(node, cx);
    match spec {
        // ADR 0003 tweaks wrap their child with platform behaviour; the
        // generic host passes the child through unchanged.
        Some(lui_core::extension::ExtensionFlavor::Tweak) if children.len() == 1 => {
            children.into_iter().next().unwrap()
        }
        _ => {
            // Generic host: visible frame so unimplemented extensions are
            // never silently blank.
            let mut element = v_flex();
            element = element
                .border_1()
                .border_color(cx.theme().warning)
                .rounded_md()
                .p_2()
                .gap_2();
            let mut element = element
                .child(
                    div()
                        .text_xs()
                        .text_color(cx.theme().warning)
                        .child(format!("[{identifier}]")),
                )
                .children(children);
            element = style::all(element, node);
            element.into_any_element()
        }
    }
}

/// Icon/prop fallback marker used by kinds that need a future visual
/// (images, pickers). Reads `text`/`path`/`url` when present.
pub fn placeholder_box(
    view: &LuiNodeView,
    node: &NodeSnapshot,
    label: &str,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let detail = node
        .string_prop(Property::TextValue)
        .or_else(|| node.string_prop(Property::PathValue))
        .or_else(|| node.string_prop(Property::UrlValue))
        .unwrap_or_default();
    let _ = view;
    div()
        .border_1()
        .border_color(cx.theme().border)
        .rounded_md()
        .px_2()
        .py_1()
        .text_xs()
        .text_color(cx.theme().muted_foreground)
        .child(if detail.is_empty() {
            format!("[{label}]")
        } else {
            format!("[{label} {detail}]")
        })
        .into_any_element()
}

// ---------------------------------------------------------------------------
// Builtin `gpui-*` renderers.
//
// The `gpui-*` namespace exposes gpui-kit components that have no
// cross-platform LUI kind. Signals drive them exactly like standard nodes:
// set-extension-prop ops dirty the node, this render reads the new props.
// Interactive components fire events through `lui_ocaml_extension_event`.

use std::ffi::CString;

use gpui_kit::component::chart::BarChart;
use gpui_kit::component::color_picker::{ColorPicker, ColorPickerEvent, ColorPickerState};
use gpui_kit::component::empty::{Empty, EmptyDescription, EmptyHeader, EmptyTitle};
use gpui_kit::component::rating::Rating;
use gpui_kit::component::table::{Column, DataTable, TableDelegate, TableState};
use gpui_kit::component::tag::{Tag, TagVariant};
use gpui_kit::gpui::{px, App, AppContext, Rgba, SharedString};
use lui_core::bridge;
use lui_core::wire::Value;

use crate::backend::{drain_pending, Shared};

fn ext_string<'a>(node: &'a NodeSnapshot, name: &str) -> Option<&'a str> {
    node.extension_props.get(name).and_then(Value::as_str)
}

fn ext_int(node: &NodeSnapshot, name: &str) -> Option<i64> {
    node.extension_props.get(name).and_then(Value::as_int)
}

fn ext_bool(node: &NodeSnapshot, name: &str) -> Option<bool> {
    node.extension_props.get(name).and_then(Value::as_bool)
}

/// Push one extension event back into the OCaml runtime and apply any
/// resulting patches on the spot.
pub(crate) fn fire_extension(
    shared: &Shared,
    node_id: i64,
    identifier: &std::ffi::CStr,
    name: &std::ffi::CStr,
    values: String,
    cx: &mut App,
) {
    let sending = CString::new(values).unwrap_or_default();
    unsafe {
        bridge::lui_ocaml_extension_event(
            node_id,
            identifier.as_ptr(),
            name.as_ptr(),
            sending.as_ptr(),
        )
    };
    drain_pending(shared, cx);
}

/// Register the builtin `gpui-*` renderers on the shared state.
pub fn register_builtin_renderers(shared: &Shared) {
    let mut shared = shared.borrow_mut();
    for (identifier, renderer) in [
        ("gpui-rating", gpui_rating as ExtensionRenderer),
        ("gpui-color-picker", gpui_color_picker),
        ("gpui-empty", gpui_empty),
        ("gpui-tag", gpui_tag),
        ("gpui-chart-bar", gpui_chart_bar),
        ("gpui-table", gpui_table),
        // Standard cross-host extensions with a dedicated GPUI surface.
        ("split-view", crate::dock::split_view),
    ] {
        shared
            .extension_renderers
            .insert(identifier.into(), renderer);
    }
}

/// `gpui-rating` — props `value` (int), `max` (int, default 5); fires
/// `change` with `{"value": int}` when the user picks a rating.
fn gpui_rating(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    _window: &mut Window,
    _cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let shared = view.shared.clone();
    let node_id = node.id;
    let element = Rating::new(("gpui-rating", node_id as usize))
        .value(ext_int(node, "value").unwrap_or(0) as usize)
        .max(ext_int(node, "max").unwrap_or(5) as usize)
        .disabled(!node.enabled())
        .on_click(move |value: &usize, _window, cx| {
            fire_extension(
                &shared,
                node_id,
                c"gpui-rating",
                c"change",
                format!("{{\"value\":{value}}}"),
                cx,
            );
        });
    style::all(div().child(element), node).into_any_element()
}

fn parse_hex_color(text: &str) -> Option<gpui_kit::gpui::Hsla> {
    let digits = text.trim().trim_start_matches('#');
    let raw = u32::from_str_radix(digits, 16).ok()?;
    let rgba = match digits.len() {
        6 => raw << 8 | 0xff,
        8 => raw,
        _ => return None,
    };
    Some(gpui_kit::gpui::rgba(rgba).into())
}

/// `gpui-color-picker` — prop `value` ("#rrggbb" / "#rrggbbaa"); fires
/// `change` with `{"color": "#rrggbbaa"}` when the picked color changes.
fn gpui_color_picker(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let node_id = node.id;
    if view.states.color_picker.is_none() {
        let state = cx.new(|cx| ColorPickerState::new(window, cx));
        let shared = view.shared.clone();
        let subscription = cx.subscribe(
            &state,
            move |_this, _state, event: &ColorPickerEvent, cx| {
                if let ColorPickerEvent::Change(Some(color)) = event {
                    let rgba: Rgba = (*color).into();
                    fire_extension(
                        &shared,
                        node_id,
                        c"gpui-color-picker",
                        c"change",
                        format!("{{\"color\":\"#{:08x}\"}}", u32::from(rgba)),
                        cx,
                    );
                }
            },
        );
        view.states.subscriptions.push(subscription);
        view.states.color_picker = Some(state);
    }
    let state = view.states.color_picker.clone().expect("initialized");
    let value = ext_string(node, "value").unwrap_or_default();
    if *view.states.color_picker_input.borrow() != value {
        *view.states.color_picker_input.borrow_mut() = value.to_string();
        if let Some(color) = parse_hex_color(value) {
            state.update(cx, |state, cx| state.set_value(color, window, cx));
        }
    }
    let element = ColorPicker::new(&state);
    style::all(div().child(element), node).into_any_element()
}

/// `gpui-empty` — props `title`, `description`; standard children render in
/// the action slot below the header.
fn gpui_empty(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    _window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let mut header = EmptyHeader::new();
    if let Some(title) = ext_string(node, "title") {
        header = header.title(EmptyTitle::new().child(title.to_string()));
    }
    if let Some(description) = ext_string(node, "description") {
        header = header.description(EmptyDescription::new().child(description.to_string()));
    }
    let children = view.child_elements(node, cx);
    let element = Empty::new().header(header).children(children);
    style::all(div().child(element), node).into_any_element()
}

/// `gpui-tag` — props `text`, `variant` (primary|secondary|danger|success|
/// warning|info).
fn gpui_tag(
    _view: &mut LuiNodeView,
    node: &NodeSnapshot,
    _window: &mut Window,
    _cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let variant = match ext_string(node, "variant").unwrap_or_default() {
        "secondary" => TagVariant::Secondary,
        "danger" => TagVariant::Danger,
        "success" => TagVariant::Success,
        "warning" => TagVariant::Warning,
        "info" => TagVariant::Info,
        _ => TagVariant::Primary,
    };
    let element = Tag::new()
        .with_variant(variant)
        .child(ext_string(node, "text").unwrap_or_default().to_string());
    style::all(div().child(element), node).into_any_element()
}

/// `gpui-chart-bar` — props `name`, `data` ("Label:Value,Label:Value,…").
fn gpui_chart_bar(
    _view: &mut LuiNodeView,
    node: &NodeSnapshot,
    _window: &mut Window,
    _cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let data: Vec<(SharedString, f32)> = ext_string(node, "data")
        .unwrap_or_default()
        .split(',')
        .filter_map(|pair| {
            let (label, value) = pair.split_once(':')?;
            let label = SharedString::from(label.trim().to_string());
            let value = value.trim().parse::<f32>().ok()?;
            Some((label, value))
        })
        .collect();
    let element = BarChart::new(data)
        .band(|(label, _)| label.clone())
        .value(|(_, value)| *value)
        .name(ext_string(node, "name").unwrap_or_default().to_string())
        .id(("gpui-chart-bar", node.id as usize))
        .value_axis(true);
    style::all(div().w_full().h(px(240.)).child(element), node).into_any_element()
}

/// Flat data delegate for `gpui-table`: props carry the whole dataset as
/// `columns` ("Name,Role,Status") and `rows` ("Ada,Eng,Active;Bo,Des,Away").
/// Semicolon-separated rows, comma-separated cells.
pub struct LuiTableDelegate {
    pub columns: Vec<SharedString>,
    pub rows: Vec<Vec<SharedString>>,
}

impl LuiTableDelegate {
    fn parse(columns: &str, rows: &str) -> Self {
        let columns = columns
            .split(',')
            .map(|cell| SharedString::from(cell.trim().to_string()))
            .collect();
        let rows = rows
            .split(';')
            .filter(|row| !row.trim().is_empty())
            .map(|row| {
                row.split(',')
                    .map(|cell| SharedString::from(cell.trim().to_string()))
                    .collect()
            })
            .collect();
        LuiTableDelegate { columns, rows }
    }
}

impl TableDelegate for LuiTableDelegate {
    fn columns_count(&self, _: &App) -> usize {
        self.columns.len()
    }

    fn rows_count(&self, _: &App) -> usize {
        self.rows.len()
    }

    fn column(&self, col_ix: usize, _: &App) -> Column {
        Column::new(col_ix.to_string(), self.columns[col_ix].clone())
    }

    fn render_td(
        &mut self,
        row_ix: usize,
        col_ix: usize,
        _window: &mut Window,
        _cx: &mut Context<TableState<Self>>,
    ) -> impl IntoElement {
        self.rows
            .get(row_ix)
            .and_then(|row| row.get(col_ix))
            .cloned()
            .unwrap_or_default()
    }

    fn cell_text(&self, row_ix: usize, col_ix: usize, _: &App) -> String {
        self.rows
            .get(row_ix)
            .and_then(|row| row.get(col_ix))
            .map(|cell| cell.to_string())
            .unwrap_or_default()
    }
}

/// `gpui-table` — props `columns`, `rows`, `bordered`, `stripe`. Sorting,
/// resizing and column moves stay Rust-side inside `TableState`.
fn gpui_table(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let columns = ext_string(node, "columns").unwrap_or_default().to_string();
    let rows = ext_string(node, "rows").unwrap_or_default().to_string();
    if view.states.table.is_none() {
        let state =
            cx.new(|cx| TableState::new(LuiTableDelegate::parse(&columns, &rows), window, cx));
        *view.states.table_input.borrow_mut() = format!("{columns}\u{1f}{rows}");
        view.states.table = Some(state);
    }
    let state = view.states.table.clone().expect("initialized");
    let signature = format!("{columns}\u{1f}{rows}");
    if *view.states.table_input.borrow() != signature {
        *view.states.table_input.borrow_mut() = signature;
        let delegate = LuiTableDelegate::parse(&columns, &rows);
        state.update(cx, |state, cx| {
            *state.delegate_mut() = delegate;
            state.refresh(cx);
        });
    }
    let element = DataTable::new(&state)
        .bordered(ext_bool(node, "bordered").unwrap_or(true))
        .stripe(ext_bool(node, "stripe").unwrap_or(true));
    style::all(div().w_full().h(px(320.)).child(element), node).into_any_element()
}
