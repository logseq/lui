//! `logseq-*` DOM-ish extension family.
//!
//! The OCaml app (logseq_dom.ml) ships every HTML tag as a `logseq-<tag>`
//! extension node; the visual contract lives in extension props:
//!
//! - `style-class`: Tailwind-ish utility string (resolved by style.rs)
//! - `text`:      text content (for raw-text / buttons / labels)
//! - `attrs`:     JSON object of HTML attributes
//! - `events`:    space-separated DOM event names the app listens for
//!   ("click input …"); the host reports them as `dom-event`
//!   {name, payload} extension events.
//!
//! Mapping is deliberately DOM-shaped, not widget-shaped: block tags become
//! column flex containers, inline tags become baseline-aligned rows, void /
//! media / SVG tags become labeled placeholders until a real surface exists.

use std::ffi::CString;

use gpui_kit::component::separator::Separator;
use gpui_kit::component::theme::ActiveTheme;
use gpui_kit::component::{h_flex, v_flex};
use gpui_kit::gpui::{
    div, px, AnyElement, Context, ElementId, InteractiveElement, IntoElement, MouseButton,
    ParentElement, SharedString, StatefulInteractiveElement, Styled, Window,
};
use lui_core::bridge;
use lui_core::store::{Node, NodeIdentity, Store};
use lui_core::EventKind;

use crate::backend::{fire, Shared};
use crate::extension::placeholder_box;
use crate::node_view::{LuiNodeView, NodeSnapshot};
use crate::style;

/// Block-level tags -> vertical flex containers.
const BLOCK_TAGS: &[&str] = &[
    "article",
    "aside",
    "body",
    "dd",
    "details",
    "div",
    "dl",
    "dt",
    "fieldset",
    "figcaption",
    "figure",
    "footer",
    "form",
    "h1",
    "h2",
    "h3",
    "h4",
    "h5",
    "h6",
    "header",
    "legend",
    "li",
    "main",
    "nav",
    "ol",
    "p",
    "pre",
    "section",
    "summary",
    "ul",
];

/// Inline tags -> horizontal baseline row (approximation of inline flow;
/// true text-run mixing lands with the real DOM renderer milestone).
const INLINE_TAGS: &[&str] = &[
    "a", "abbr", "b", "code", "data", "dfn", "em", "em-emoji", "i", "kbd", "label", "mark", "q",
    "s", "samp", "small", "span", "strong", "sub", "sup", "time", "u", "var",
];

/// Tags that behave as clickable controls.
const CLICKABLE_TAGS: &[&str] = &["a", "button", "label", "option", "summary"];

/// Table family renders as block containers (a real grid layout is the
/// table milestone; rows stay stacked so content remains readable).
const TABLE_TAGS: &[&str] = &[
    "caption", "col", "colgroup", "table", "tbody", "td", "tfoot", "th", "thead", "tr",
];

/// SVG + media + replaced-content tags — no pixel source on the wire yet.
const VOID_TAGS: &[&str] = &[
    "audio", "canvas", "circle", "defs", "ellipse", "g", "iframe", "img", "line", "object", "path",
    "pdf", "polygon", "polyline", "rect", "source", "svg", "track", "use", "video",
];

fn tag_of(node: &NodeSnapshot) -> String {
    match &node.identity {
        NodeIdentity::Extension { identifier, .. } => identifier
            .strip_prefix("logseq-")
            .unwrap_or(identifier)
            .to_string(),
        _ => String::new(),
    }
}

fn identifier_of(node: &NodeSnapshot) -> String {
    match &node.identity {
        NodeIdentity::Extension { identifier, .. } => identifier.clone(),
        _ => String::new(),
    }
}

fn classes(node: &NodeSnapshot) -> &str {
    node.extension_string_prop("style-class").unwrap_or("")
}

fn has_class(node: &NodeSnapshot, name: &str) -> bool {
    classes(node).split_whitespace().any(|t| t == name)
}

/// `attrs` is a JSON object string; return one attribute's string value.
fn attr(node: &NodeSnapshot, name: &str) -> Option<String> {
    let raw = node.extension_string_prop("attrs")?;
    let attrs: serde_json::Value = serde_json::from_str(raw).ok()?;
    attrs.get(name)?.as_str().map(str::to_string)
}

fn parsed_attrs(node: &Node) -> serde_json::Map<String, serde_json::Value> {
    node.extension_props
        .get("attrs")
        .and_then(|v| v.as_str())
        .and_then(|raw| serde_json::from_str::<serde_json::Value>(raw).ok())
        .and_then(|v| v.as_object().cloned())
        .unwrap_or_default()
}

/// DOM-shaped element snapshot — mirrors imperative_dom.ml's
/// flat_snapshot: handlers compare fields like tag/class/id and walk the
/// `ancestors` chain for closest()/scope resolution.
fn shallow_snapshot(node: &Node) -> serde_json::Value {
    let tag = match &node.identity {
        NodeIdentity::Extension { identifier, .. } => identifier
            .strip_prefix("logseq-")
            .unwrap_or(identifier)
            .to_uppercase(),
        NodeIdentity::Standard(kind) => kind.wire_name().to_uppercase(),
    };
    let class = node
        .extension_props
        .get("style-class")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let attrs = parsed_attrs(node);
    let dom_id = attrs
        .get("id")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let mut el = serde_json::json!({
        "tag": tag,
        "class": class,
        "id": dom_id,
        "#ref": dom_id,
        "ref-id": dom_id,
        "#new": node.id,
        "node-id": node.id,
        "attrs": serde_json::Value::Object(attrs),
    });
    if let Some(value) = el["attrs"].get("value").and_then(|v| v.as_str()) {
        el["value"] = serde_json::json!(value);
    }
    if el["attrs"].get("checked").is_some() {
        el["checked"] = serde_json::json!(true);
    }
    el
}

/// Full target snapshot: shallow element + ancestor chain (root first).
fn target_snapshot(store: &Store, node_id: i64) -> serde_json::Value {
    let Some(node) = store.node(node_id) else {
        return serde_json::Value::Null;
    };
    let mut ancestors = Vec::new();
    let mut parent = node.parent;
    while let Some(id) = parent {
        match store.node(id) {
            Some(p) => {
                ancestors.push(shallow_snapshot(p));
                parent = p.parent;
            }
            None => break,
        }
    }
    ancestors.reverse();
    let mut target = shallow_snapshot(node);
    target["ancestors"] = serde_json::json!(ancestors);
    target
}

/// Emit a DOM event to OCaml as `dom-event` {name, payload}. `payload` is
/// a JSON *string* (StringScalar on the schema) carrying `nodeId` (drives
/// the bubble walk), `target` (element snapshot for closest()/scope), and
/// any event fields.
fn dom_event(
    shared: &Shared,
    node_id: i64,
    identifier: &str,
    name: &str,
    fields: serde_json::Value,
    cx: &mut gpui_kit::gpui::App,
) {
    let target = target_snapshot(&shared.borrow().store, node_id);
    let mut payload = serde_json::json!({
        "name": name,
        "nodeId": node_id,
        "target": target,
    });
    if let serde_json::Value::Object(extra) = fields {
        for (k, v) in extra {
            payload[k] = v;
        }
    }
    let identifier = CString::new(identifier).unwrap_or_default();
    let event = CString::new("dom-event").unwrap();
    let values = serde_json::json!({
        "name": name,
        "payload": payload.to_string(),
    });
    let values = CString::new(values.to_string()).unwrap_or_default();
    fire(shared, node_id, EventKind::ExtensionEvent, cx, || unsafe {
        bridge::lui_ocaml_extension_event(
            node_id,
            identifier.as_ptr(),
            event.as_ptr(),
            values.as_ptr(),
        )
    });
}

/// Attach DOM listeners declared in the `events` prop (space-separated
/// names). The scaffold wires pointer/click; the rest arrive with the
/// input/focus milestone.
fn with_dom_events<E: StatefulInteractiveElement>(
    element: E,
    shared: &Shared,
    node: &NodeSnapshot,
) -> E {
    let Some(events) = node.extension_string_prop("events") else {
        return element;
    };
    let identifier = identifier_of(node);
    let mut element = element;
    for name in events.split_whitespace() {
        match name {
            "click" => {
                let shared = shared.clone();
                let identifier = identifier.clone();
                let node_id = node.id;
                element = element.on_click(move |event: &gpui_kit::gpui::ClickEvent, _, cx| {
                    let position = event.position();
                    dom_event(
                        &shared,
                        node_id,
                        &identifier,
                        "click",
                        serde_json::json!({
                            "clientX": f64::from(position.x),
                            "clientY": f64::from(position.y),
                        }),
                        cx,
                    );
                });
            }
            "contextmenu" => {
                let shared = shared.clone();
                let identifier = identifier.clone();
                let node_id = node.id;
                element = element.on_mouse_down(
                    MouseButton::Right,
                    move |event: &gpui_kit::gpui::MouseDownEvent, _, cx| {
                        let position = event.position;
                        dom_event(
                            &shared,
                            node_id,
                            &identifier,
                            "contextmenu",
                            serde_json::json!({
                                "clientX": f64::from(position.x),
                                "clientY": f64::from(position.y),
                            }),
                            cx,
                        );
                    },
                );
            }
            _ => {}
        }
    }
    element
}

/// Text content of the node: the `text` extension prop carries the payload.
fn text_prop(node: &NodeSnapshot) -> &str {
    node.extension_string_prop("text").unwrap_or("")
}

/// `overflow-*-scroll/auto` needs a scroll handle — only stateful elements
/// carry one, so this runs after style::all on the identified containers.
fn with_scroll<E: StatefulInteractiveElement>(element: E, node: &NodeSnapshot) -> E {
    let scroll_x = has_class(node, "overflow-x-scroll") || has_class(node, "overflow-x-auto");
    let scroll_y = has_class(node, "overflow-y-scroll") || has_class(node, "overflow-y-auto");
    let both = has_class(node, "overflow-scroll") || has_class(node, "overflow-auto");
    let element = if scroll_x || both {
        element.overflow_x_scroll()
    } else {
        element
    };
    if scroll_y || both {
        element.overflow_y_scroll()
    } else {
        element
    }
}

/// Push the node's `text` prop as a leading text child when present.
fn with_text<E: ParentElement>(element: E, node: &NodeSnapshot) -> E {
    let text = text_prop(node);
    if text.is_empty() {
        element
    } else {
        element.child(SharedString::from(text.to_string()))
    }
}

/// Render one `logseq-<tag>` extension node.
pub fn render(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    _window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let tag = tag_of(node);
    // display:none — `hidden` removes the node from layout entirely.
    if has_class(node, "hidden") {
        return div().into_any_element();
    }

    let children = view.child_elements(node, cx);
    let shared = view.shared.clone();

    match tag.as_str() {
        // Text leaf: a bare run. Empty raw-text nodes act as zero-size
        // structural anchors (the DOM observer's `nil` placeholders).
        "raw-text" => {
            let text = text_prop(node).to_string();
            let mut element = div();
            if !text.is_empty() {
                element = element.child(SharedString::from(text));
            }
            style::all(element, node).into_any_element()
        }
        "br" => div().h(px(6.)).into_any_element(),
        "hr" => {
            let mut element = div().py_1().w_full().child(Separator::horizontal());
            element = style::all(element, node);
            element.into_any_element()
        }
        // Text entry — the InputState-backed editor lands with the editor
        // milestone; render the current value/placeholder read-only.
        "input" | "textarea" => {
            let value = attr(node, "value").unwrap_or_else(|| text_prop(node).to_string());
            let placeholder = attr(node, "placeholder").unwrap_or_default();
            let mut element = div()
                .w_full()
                .px_2()
                .py_1()
                .border_1()
                .rounded_md()
                .border_color(cx.theme().border);
            element = element.child(if value.is_empty() {
                div()
                    .text_color(cx.theme().muted_foreground)
                    .child(placeholder)
                    .into_any_element()
            } else {
                div().child(SharedString::from(value)).into_any_element()
            });
            element = style::all(element, node);
            element.into_any_element()
        }
        _ if VOID_TAGS.contains(&tag.as_str()) => {
            let label = attr(node, "alt")
                .or_else(|| attr(node, "src"))
                .or_else(|| attr(node, "title"))
                .unwrap_or_else(|| tag.to_string());
            placeholder_box(view, node, &label, cx)
        }
        _ if BLOCK_TAGS.contains(&tag.as_str())
            || TABLE_TAGS.contains(&tag.as_str())
            || tag == "button" =>
        {
            let mut element = v_flex().id(ElementId::Integer(node.id as u64));
            element = with_text(element, node);
            element = element.children(children);
            element = style::all(element, node);
            element = with_scroll(element, node);
            if CLICKABLE_TAGS.contains(&tag.as_str()) || has_class(node, "cursor-pointer") {
                element = element.cursor_pointer();
            }
            with_dom_events(element, &shared, node).into_any_element()
        }
        _ if INLINE_TAGS.contains(&tag.as_str()) => {
            let mut element = h_flex()
                .id(ElementId::Integer(node.id as u64))
                .items_baseline();
            element = with_text(element, node);
            element = element.children(children);
            element = style::all(element, node);
            element = with_scroll(element, node);
            if CLICKABLE_TAGS.contains(&tag.as_str()) {
                element = element.cursor_pointer();
            }
            with_dom_events(element, &shared, node).into_any_element()
        }
        // Unknown logseq-* tag: transparent passthrough, never a warning
        // frame — the logseq family is understood vocabulary, not "missing".
        _ => {
            let mut element = v_flex();
            element = with_text(element, node);
            element = element.children(children);
            element = style::all(element, node);
            element.into_any_element()
        }
    }
}
