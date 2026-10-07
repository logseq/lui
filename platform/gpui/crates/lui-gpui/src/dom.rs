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
    div, px, AnyElement, Bounds, Context, ElementId, InteractiveElement,
    IntoElement, ParentElement, Pixels, SharedString,
    StatefulInteractiveElement, Styled, Window,
};
use lui_core::bridge;
use lui_core::store::{Node, NodeIdentity, Store};
use lui_core::Property;

use crate::backend::Shared;
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
    "a", "abbr", "b", "code", "data", "del", "dfn", "em", "em-emoji", "i", "ins", "kbd", "label",
    "mark", "q", "s", "samp", "small", "span", "strong", "sub", "sup", "time", "u", "var",
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

/// Whether an extension node renders through a plain flex container arm —
/// `Some(false)` for the `v_flex` arms (block/table/unknown tags),
/// `Some(true)` for the `h_flex` inline arm, `None` for non-extension
/// nodes and the leaf arms. Used by wrapper elision to match an
/// extension wrapper's direction against its parent's. Takes a bare
/// identity — usable on `NodeSnapshot`s and store nodes alike.
pub(crate) fn ext_flex_direction_of(identity: &NodeIdentity) -> Option<bool> {
    let NodeIdentity::Extension { identifier, .. } = identity else {
        return None;
    };
    let tag = identifier.strip_prefix("logseq-").unwrap_or(identifier);
    if tag == "button" || BLOCK_TAGS.contains(&tag) || TABLE_TAGS.contains(&tag) {
        return Some(false);
    }
    if INLINE_TAGS.contains(&tag) {
        return Some(true);
    }
    if matches!(tag, "raw-text" | "br" | "hr" | "input" | "textarea")
        || VOID_TAGS.contains(&tag)
    {
        return None;
    }
    // The unknown-tag catch-all arm renders a plain `v_flex`.
    Some(false)
}

fn classes(node: &NodeSnapshot) -> &str {
    node.extension_string_prop("style-class").unwrap_or("")
}

fn has_class(node: &NodeSnapshot, name: &str) -> bool {
    let classes = classes(node);
    classes.split_whitespace().any(|t| t == name)
        || crate::style::class_has_utility(classes, name)
}

/// One attribute's string value on a store `Node` — same merge rules as
/// [`attr`] (extension `attrs` JSON wins, then the `DataAttrs` record
/// list). Used where only the store node is in hand (menu nav walks).
pub(crate) fn store_attr(node: &lui_core::store::Node, name: &str) -> Option<String> {
    if let Some(raw) = node.extension_props.get("attrs").and_then(|v| v.as_str()) {
        let attrs: serde_json::Value = serde_json::from_str(raw).ok()?;
        return attrs.get(name)?.as_str().map(str::to_string);
    }
    node.string_prop(Property::DataAttrs)?
        .split('\x1e')
        .find_map(|record| {
            let (key, value) = record.split_once('\x1f')?;
            (key == name).then(|| value.to_string())
        })
}

/// One attribute's string value. Extension `attrs` is a JSON object;
/// the standard `DataAttrs` prop is the \x1e/\x1f record list.
pub(crate) fn attr(node: &NodeSnapshot, name: &str) -> Option<String> {
    if let Some(raw) = node.extension_string_prop("attrs") {
        let attrs: serde_json::Value = serde_json::from_str(raw).ok()?;
        return attrs.get(name)?.as_str().map(str::to_string);
    }
    node.string_prop(Property::DataAttrs)?
        .split('\x1e')
        .find_map(|record| {
            let (key, value) = record.split_once('\x1f')?;
            (key == name).then(|| value.to_string())
        })
}

/// The `attrs` slot has two encodings by source: extension `attrs` is a
/// JSON object ({name: value}); the standard `DataAttrs` prop is the
/// \x1e/\x1f record list produced by data_attrs_encode. Both can coexist
/// (a dom-ops `set-attr` writes the extension slot on a standard node),
/// so merge them — extension attrs win on key collision.
fn parsed_attrs(node: &Node) -> serde_json::Map<String, serde_json::Value> {
    let mut map = node
        .string_prop(Property::DataAttrs)
        .map(|raw| {
            raw.split('\x1e')
                .filter_map(|record| {
                    let (name, value) = record.split_once('\x1f')?;
                    Some((
                        name.to_string(),
                        serde_json::Value::String(value.to_string()),
                    ))
                })
                .collect::<serde_json::Map<String, serde_json::Value>>()
        })
        .unwrap_or_default();
    if let Some(raw) = node.extension_props.get("attrs").and_then(|v| v.as_str()) {
        if let Ok(serde_json::Value::Object(extra)) = serde_json::from_str::<serde_json::Value>(raw)
        {
            for (key, value) in extra {
                map.insert(key, value);
            }
        }
    }
    map
}

/// DOM-shaped element snapshot — mirrors imperative_dom.ml's
/// flat_snapshot: handlers compare fields like tag/class/id and walk the
/// `ancestors` chain for closest()/scope resolution.
/// Standard kinds present the HTML tag their DOM twin would carry —
/// delegated selectors (`a.page-ref`, `a.tag`, `button.x`) match on it.
fn dom_tag_of_kind(kind: lui_core::wire_schema::NodeKind) -> String {
    use lui_core::wire_schema::NodeKind;
    match kind {
        NodeKind::Link => "a",
        NodeKind::Button | NodeKind::ToggleButton => "button",
        NodeKind::Input | NodeKind::TextField | NodeKind::SearchField
        | NodeKind::SecureField | NodeKind::NumberStepper => "input",
        NodeKind::Textarea => "textarea",
        NodeKind::Select | NodeKind::Combobox => "select",
        NodeKind::MenuItem => "menuitem",
        NodeKind::FileImage | NodeKind::Image | NodeKind::FilePreview => "img",
        NodeKind::ListItem => "li",
        NodeKind::BottomTab => "button",
        kind => return kind.wire_name().to_uppercase(),
    }
    .to_uppercase()
}

fn shallow_snapshot(node: &Node) -> serde_json::Value {
    let tag = match &node.identity {
        NodeIdentity::Extension { identifier, .. } => identifier
            .strip_prefix("logseq-")
            .unwrap_or(identifier)
            .to_uppercase(),
        NodeIdentity::Standard(kind) => dom_tag_of_kind(*kind),
    };
    // Standard props are the only carrier of id/class/attrs/text on plain
    // elements — extension_props is empty for them, so a click target or
    // doc-query snapshot must read the standard table too.
    let class = node
        .extension_props
        .get("style-class")
        .and_then(|v| v.as_str())
        .or_else(|| node.string_prop(Property::StyleClass))
        .unwrap_or("");
    let acc_id = node
        .extension_props
        .get("accessibility-identifier")
        .and_then(|v| v.as_str())
        .or_else(|| node.string_prop(Property::AccessibilityIdentifier))
        .unwrap_or("");
    let mut attrs = parsed_attrs(node);
    // The typed accessibility props are the DOM attrs a real element
    // would carry — delegated selectors (`[aria-label]`) and the
    // tooltip reader look for them in attrs, not in the prop table.
    if let Some(label) = node.string_prop(Property::AccessibilityLabel) {
        attrs.insert(
            "aria-label".to_string(),
            serde_json::Value::String(label.to_string()),
        );
    }
    // Link props surface as the attrs a DOM `<a>` would carry — selectors
    // (`a[target=_blank]`) and the default-action href lookup read them.
    if node.identity.kind() == Some(lui_core::wire_schema::NodeKind::Link) {
        if let Some(url) = node.string_prop(Property::UrlValue) {
            attrs.insert(
                "href".to_string(),
                serde_json::Value::String(url.to_string()),
            );
        }
        if let Some(target) = node.string_prop(Property::TargetValue) {
            attrs.insert(
                "target".to_string(),
                serde_json::Value::String(target.to_string()),
            );
        }
    }
    let dom_id = attrs
        .get("id")
        .and_then(|v| v.as_str())
        .unwrap_or(acc_id)
        .to_string();
    let ref_handle = if dom_id.is_empty() {
        format!("node-{}", node.id)
    } else {
        dom_id.clone()
    };
    let mut el = serde_json::json!({
        "tag": tag,
        "class": class,
        "id": dom_id,
        "#ref": ref_handle,
        "ref-id": dom_id,
        "#new": node.id,
        "node-id": node.id,
        "attrs": serde_json::Value::Object(attrs),
        "text": node
            .extension_props
            .get("text")
            .and_then(|v| v.as_str())
            .or_else(|| node.string_prop(Property::TextValue))
            .unwrap_or(""),
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
/// Painted bounds ride along as "rect" on the target and every ancestor
/// so OCaml `bounding_rect` resolves synchronously on event targets
/// (popup anchors) instead of round-tripping a measure-node dom-op.
fn target_snapshot(
    store: &Store,
    node_bounds: &std::collections::HashMap<i64, Bounds<Pixels>>,
    node_id: i64,
) -> serde_json::Value {
    let Some(node) = store.node(node_id) else {
        return serde_json::Value::Null;
    };
    let mut ancestors = Vec::new();
    let mut parent = node.parent;
    while let Some(id) = parent {
        match store.node(id) {
            Some(p) => {
                let mut snap = shallow_snapshot(p);
                if let Some(b) = node_bounds.get(&p.id) {
                    snap["rect"] = crate::domops::bounds_json(Some(*b));
                }
                ancestors.push(snap);
                parent = p.parent;
            }
            None => break,
        }
    }
    ancestors.reverse();
    let mut target = shallow_snapshot(node);
    if let Some(b) = node_bounds.get(&node_id) {
        target["rect"] = crate::domops::bounds_json(Some(*b));
    }
    target["ancestors"] = serde_json::json!(ancestors);
    target
}

/// Emit a DOM event to OCaml as `dom-event` {name, payload}. `payload` is
/// a JSON *string* (StringScalar on the schema) carrying `nodeId` (drives
/// the bubble walk), `target` (element snapshot for closest()/scope), and
/// any event fields.

/// Nearest ancestor-or-self of `from` that is a `logseq-*` extension node,
/// falling back to the first one in the tree. dom-events only reach OCaml
/// through extension carriers whose logseq_dom handler accepts the
/// `logseq-` identifier prefix.
/// Non-DOM `logseq-*` extensions — widget conduits and surfaces that own
/// their input through dedicated conduit events. A `dom-event` routed to
/// one of these (or carrying one as its target) feeds document keydowns
/// into the wrong model — the invisible `logseq-editor` sink in
/// particular would absorb every unbound keystroke and write it into its
/// block buffer.
const LOGSEQ_CONDUIT_IDENTS: &[&str] = &[
    "logseq-editor",
    "logseq-codemirror",
    "logseq-em-emoji",
    "logseq-katex",
    "logseq-virt",
];

pub(crate) fn is_dom_carrier(identifier: &str) -> bool {
    identifier.starts_with("logseq-") && !LOGSEQ_CONDUIT_IDENTS.contains(&identifier)
}

pub(crate) fn logseq_carrier(shared: &Shared, from: Option<i64>) -> Option<(i64, String)> {
    let shared = shared.borrow();
    let store = &shared.store;
    let ident_of = |id: i64| -> Option<String> {
        match &store.node(id)?.identity {
            NodeIdentity::Extension { identifier, .. }
                if is_dom_carrier(identifier) =>
            {
                Some(identifier.clone())
            }
            _ => None,
        }
    };
    let mut cursor = from;
    while let Some(id) = cursor {
        if let Some(ident) = ident_of(id) {
            return Some((id, ident));
        }
        cursor = store.node(id).and_then(|n| n.parent);
    }
    let mut stack = store.root.into_iter().collect::<Vec<_>>();
    while let Some(id) = stack.pop() {
        if let Some(node) = store.node(id) {
            if let Some(ident) = ident_of(id) {
                return Some((id, ident));
            }
            stack.extend(node.children.iter().copied());
        }
    }
    None
}

/// A `pointer-events` setting inside one inline-style value string —
/// `Some(false)` for `none`, `Some(true)` otherwise.
fn inline_pointer_events(style: &str) -> Option<bool> {
    for decl in style.split(';') {
        if let Some((prop, value)) = decl.split_once(':') {
            if prop.trim().eq_ignore_ascii_case("pointer-events") {
                return Some(value.trim() != "none");
            }
        }
    }
    None
}

/// Explicit `pointer-events` on one node — from a literal class token, a
/// dictionary-registered semantic class, or an inline `style`
/// declaration. `None` means inherit (CSS default `auto`).
fn pointer_events_explicit(node: &lui_core::store::Node) -> Option<bool> {
    let classes = node
        .string_prop(Property::StyleClass)
        .or_else(|| node.extension_props.get("style-class").and_then(|v| v.as_str()))
        .unwrap_or("");
    for token in classes.split_whitespace() {
        match token {
            "pointer-events-none" => return Some(false),
            "pointer-events-auto" => return Some(true),
            _ => {}
        }
        if let Some(enabled) = crate::style::class_pointer_events(token) {
            return Some(enabled);
        }
    }
    if let Some(raw) = node.extension_props.get("attrs").and_then(|v| v.as_str()) {
        if let Ok(attrs) = serde_json::from_str::<serde_json::Value>(raw) {
            for key in ["style", "data-style"] {
                if let Some(style) = attrs.get(key).and_then(|v| v.as_str()) {
                    if let Some(enabled) = inline_pointer_events(style) {
                        return Some(enabled);
                    }
                }
            }
        }
    }
    if let Some(raw) = node.string_prop(Property::DataAttrs) {
        for record in raw.split('\x1e') {
            if let Some((name, value)) = record.split_once('\x1f') {
                if matches!(name, "style" | "data-style") {
                    if let Some(enabled) = inline_pointer_events(value) {
                        return Some(enabled);
                    }
                }
            }
        }
    }
    None
}

/// Structural `pointer-events` implied by the node's own shape — an
/// always-mounted cover `popover` is a positioning shell, not a surface:
/// it must not swallow clicks meant for the content below, while its
/// floating children (point-anchored popovers, dialogs, sheets, drawers,
/// toasts) and any node that registered pointer handlers stay hittable.
/// `None` means inherit.
fn pointer_events_implicit(node: &lui_core::store::Node) -> Option<bool> {
    use lui_core::wire_schema::NodeKind;
    if let NodeIdentity::Standard(kind) = &node.identity {
        match kind {
            // No popup-x prop => cover shell (positions children above the
            // page, owns no surface of its own).
            NodeKind::Popover => return Some(node.float_prop(Property::PopupX).is_some()),
            NodeKind::Dialog | NodeKind::Drawer | NodeKind::Sheet | NodeKind::Toast => {
                return Some(true)
            }
            _ => {}
        }
    }
    if node.flag(Property::PointerEnabled) || node.flag(Property::PressEnabled) {
        return Some(true);
    }
    None
}

/// Whether `position` hits through `id` — `pointer-events` inherits, so
/// the nearest ancestor's explicit setting decides.
fn hit_transparent(shared: &std::cell::Ref<'_, crate::backend::LuiShared>, id: i64) -> bool {
    let mut cursor = Some(id);
    while let Some(current) = cursor {
        let Some(node) = shared.store.node(current) else {
            break;
        };
        if let Some(enabled) = pointer_events_explicit(node).or_else(|| pointer_events_implicit(node))
        {
            return !enabled;
        }
        cursor = node.parent;
    }
    false
}

/// Painted node under `position` — the DOM click target. Document order
/// is paint order: children cover their parent and later siblings cover
/// earlier ones (the overlay layer is mounted last), so a depth-first
/// walk in child order that keeps the LAST node containing the point
/// reproduces topmost-first hit testing. `pointer-events: none` nodes
/// (the always-mounted overlay shells) are skipped with their inherited
/// state resolved along the ancestor chain.
pub(crate) fn deepest_hit(
    shared: &Shared,
    position: gpui_kit::gpui::Point<gpui_kit::gpui::Pixels>,
) -> Option<i64> {
    let shared = shared.borrow();
    let mut best: Option<i64> = None;
    let mut stack: Vec<i64> = Vec::new();
    // Imperative overlay roots paint in the topmost window layer — seed
    // them below the document root (reversed, so the last-attached root
    // is hit-tested last) so their subtree always wins the hit.
    stack.extend(shared.imperative_roots.iter().rev().copied());
    if let Some(root) = shared.store.root {
        stack.push(root);
    }
    while let Some(id) = stack.pop() {
        let Some(node) = shared.store.node(id) else {
            continue;
        };
        if shared
            .node_bounds
            .get(&id)
            .is_some_and(|bounds| bounds.contains(&position))
            && !hit_transparent(&shared, id)
        {
            best = Some(id);
        }
        // Push children reversed so the pop order is document order.
        stack.extend(node.children.iter().rev().copied());
    }
    best
}

pub fn dom_event(
    shared: &Shared,
    node_id: i64,
    identifier: &str,
    name: &str,
    fields: serde_json::Value,
    cx: &mut gpui_kit::gpui::App,
) {
    dom_event_via(shared, node_id, identifier, node_id, name, fields, cx);
}

/// Emit a `dom-event` through `carrier_id` — which must be an extension
/// node, since OCaml drops extension events on standard nodes — while the
/// payload's `nodeId`/`target` point at `target_id`, which may be a
/// standard node. Used by the window-level click monitor: every DOM click
/// targets the deepest hit element, not the listening ancestor.
pub fn dom_event_via(
    shared: &Shared,
    carrier_id: i64,
    identifier: &str,
    target_id: i64,
    name: &str,
    fields: serde_json::Value,
    cx: &mut gpui_kit::gpui::App,
) {
    // The wired `on_click` handler and the root-level mouse-up monitor can
    // both report one click in a single frame. Drop a same-target repeat
    // inside the coalescing window OCaml applies anyway — hosts see one
    // event per click regardless of which path wins the frame.
    if name == "click" {
        let now = std::time::Instant::now();
        let mut guard = shared.borrow_mut();
        if let Some((last_target, at)) = guard.last_click_emit {
            if last_target == target_id && now.duration_since(at).as_millis() < 60 {
                return;
            }
        }
        guard.last_click_emit = Some((target_id, now));
    }
    let target = {
        let guard = shared.borrow();
        target_snapshot(&guard.store, &guard.node_bounds, target_id)
    };
    if std::env::var_os("LUI_GPUI_DUMP_DOM").is_some() {
        eprintln!("dom-event {name} target={target_id} snap={target}");
    }
    let mut payload = serde_json::json!({
        "name": name,
        "nodeId": target_id,
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
    // Host-initiated — bypass `event_allowed` (it admits ExtensionEvent
    // only for extension nodes; a `dom-event` may legitimately target a
    // standard node, e.g. the root for document keydown).
    let rc = unsafe {
        bridge::lui_ocaml_extension_event(
            carrier_id,
            identifier.as_ptr(),
            event.as_ptr(),
            values.as_ptr(),
        )
    };
    if std::env::var_os("LUI_GPUI_DUMP_LAZY").is_some() {
        eprintln!("ext-event {name} carrier={carrier_id} rc={rc}");
    }
    crate::backend::drain_pending(shared, cx);
}

/// Attach DOM listeners declared in the `events` prop (space-separated
/// names). Context menus use the window observer so one pointer press
/// cannot emit through both an element listener and its root.
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
                    // DOM parity: the event target is the deepest painted
                    // element under the cursor, not the listening ancestor —
                    // document listeners resolve closest() from it.
                    let (carrier, ident, target) =
                        match deepest_hit(&shared, position) {
                            Some(hit) => match logseq_carrier(&shared, Some(hit)) {
                                Some((carrier, ident)) => (carrier, ident, hit),
                                None => (node_id, identifier.clone(), hit),
                            },
                            None => (node_id, identifier.clone(), node_id),
                        };
                    dom_event_via(
                        &shared,
                        carrier,
                        &ident,
                        target,
                        "click",
                        serde_json::json!({
                            "clientX": f64::from(position.x),
                            "clientY": f64::from(position.y),
                        }),
                        cx,
                    );
                });
            }
            _ => {}
        }
    }
    element
}

/// Font semantics of inline HTML tags — see `style::inline_tag_style`.
fn tag_semantic_style<E: Styled>(element: E, tag: &str, cx: &mut Context<LuiNodeView>) -> E {
    style::inline_tag_style(element, tag, cx.theme())
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
/// `data-emoji` carries the em-emoji glyph — the web stylesheet lifts it
/// into rendered content, so it is plain text here.
fn with_text<E: ParentElement>(element: E, node: &NodeSnapshot) -> E {
    let text = text_prop(node);
    if text.is_empty() {
        match attr(node, "data-emoji") {
            Some(glyph) => element.child(SharedString::from(glyph)),
            None => element,
        }
    } else {
        element.child(SharedString::from(text.to_string()))
    }
}

/// Render one `logseq-<tag>` extension node.
/// Overscan margin matching the web IntersectionObserver rootMargin —
/// lazy rows mount before they reach the viewport edge.
const VIEWPORT_OVERSCAN: f64 = 254.;

/// `lazy-mount`/`virt-end` opt-ins from the `events` prop mark the node
/// for the per-frame viewport sweep — the LUI native lazy contract: a
/// `data-lazy-mount` row mounts its content when the host reports it
/// near the viewport, a `virt-end` list paginates when its last child
/// appears.
fn register_viewport_watches(view: &LuiNodeView, node: &NodeSnapshot) {
    let Some(events) = node.extension_string_prop("events") else {
        return;
    };
    let mut lazy = false;
    let mut end = false;
    for name in events.split_whitespace() {
        match name {
            "lazy-mount" => lazy = true,
            "virt-end" => end = true,
            _ => {}
        }
    }
    if !(lazy || end) {
        return;
    }
    let mut shared = view.shared.borrow_mut();
    if let Some(uuid) = lazy.then(|| attr(node, "data-lazy-mount")).flatten() {
        shared
            .viewport_watched
            .entry(node.id)
            .or_insert(crate::backend::ViewportWatch {
                event: "lazy-mount",
                identifier: identifier_of(node),
                last_end_child: None,
                lazy_uuid: uuid,
            });
    }
    if end {
        shared
            .viewport_watched
            .entry(node.id)
            .or_insert(crate::backend::ViewportWatch {
                event: "virt-end",
                identifier: identifier_of(node),
                last_end_child: None,
                lazy_uuid: String::new(),
            });
    }
}

/// Store-node twin of `register_viewport_watches` — prepaint re-arms a
/// `lazy-mount`/`virt-end` watch the render path never (re)installed:
/// a lazy row that republishes identical props keeps its node id and
/// never re-renders, so after its first fire consumed the watch entry
/// nothing registers a new one and the row stays collapsed forever
/// (`g h` back onto the same page hits exactly this). Called from
/// `LuiNodeView::prepaint`, which runs for every live node each frame.
pub fn rearm_viewport_watch(shared: &mut crate::backend::LuiShared, id: i64) {
    if shared.viewport_watched.contains_key(&id) {
        return;
    }
    let Some(node) = shared.store.node(id) else {
        return;
    };
    let Some(events) = node
        .extension_props
        .get("events")
        .and_then(|v| v.as_str())
    else {
        return;
    };
    let mut lazy = false;
    let mut end = false;
    for name in events.split_whitespace() {
        match name {
            "lazy-mount" => lazy = true,
            "virt-end" => end = true,
            _ => {}
        }
    }
    if !(lazy || end) {
        return;
    }
    let identifier = match &node.identity {
        lui_core::store::NodeIdentity::Extension { identifier, .. } => identifier.clone(),
        _ => String::new(),
    };
    // A mounted row keeps its `data-lazy-mount` attr; only re-arm the
    // lazy watch while the placeholder is still childless — otherwise a
    // consumed watch would re-fire every frame against real content.
    if lazy && node.children.is_empty() {
        if let Some(uuid) = parsed_attrs(node)
            .get("data-lazy-mount")
            .and_then(|v| v.as_str())
            .map(str::to_string)
        {
            shared.viewport_watched.insert(
                id,
                crate::backend::ViewportWatch {
                    event: "lazy-mount",
                    identifier: identifier.clone(),
                    last_end_child: None,
                    lazy_uuid: uuid,
                },
            );
        }
    }
    if end {
        shared.viewport_watched.insert(
            id,
            crate::backend::ViewportWatch {
                event: "virt-end",
                identifier,
                last_end_child: None,
                lazy_uuid: String::new(),
            },
        );
    }
}

/// Fire `lazy-mount`/`virt-end` dom-events for watched nodes whose
/// recorded bounds intersect the viewport (plus overscan). Runs once
/// per frame from the host's UI tick; a lazy row fires exactly once —
/// the OCaml `near` latch then republishes it as real content.
pub fn fire_viewport_events(shared: &Shared, window: &Window, cx: &mut gpui_kit::gpui::App) {
    let viewport_h = f64::from(window.viewport_size().height);
    let mut drop_ids: Vec<i64> = Vec::new();
    // lazy-mount hits grouped by parent node id → one dom-event each
    // carrying all sibling uuids (one OCaml publish per list, not per row).
    let mut lazy_groups: std::collections::HashMap<i64, (Vec<String>, Vec<i64>)> =
        std::collections::HashMap::new();
    // watched nodes whose parent declares no batch handler fire singly.
    let mut singles: Vec<(i64, String)> = Vec::new();
    let mut end_fires: Vec<(i64, String, i64)> = Vec::new();
    {
        let shared_ref = shared.borrow();
        for (&id, watch) in &shared_ref.viewport_watched {
            match watch.event {
                "lazy-mount" => {
                    // Republished without the marker → the row is real now.
                    let still_lazy = shared_ref
                        .store
                        .node(id)
                        .and_then(|n| n.extension_props.get("attrs"))
                        .and_then(|v| v.as_str())
                        .map(|raw| raw.contains("data-lazy-mount"))
                        .unwrap_or(false);
                    if !still_lazy {
                        drop_ids.push(id);
                        continue;
                    }
                    let Some(bounds) = shared_ref.node_bounds.get(&id) else {
                        continue;
                    };
                    let top = f64::from(bounds.origin.y);
                    let bottom = f64::from(bounds.bottom());
                    if !(top < viewport_h + VIEWPORT_OVERSCAN && bottom > -VIEWPORT_OVERSCAN) {
                        continue;
                    }
                    // Batch through the parent only when it opted into the
                    // lazy-mount event itself (the lazy-rows container);
                    // other parents keep per-node dispatch.
                    let batched = shared_ref
                        .store
                        .node(id)
                        .and_then(|n| n.parent)
                        .and_then(|pid| shared_ref.store.node(pid))
                        .filter(|p| {
                            p.extension_props
                                .get("events")
                                .and_then(|v| v.as_str())
                                .map(|events| events.split_whitespace().any(|e| e == "lazy-mount"))
                                .unwrap_or(false)
                        })
                        .map(|p| p.id);
                    match batched {
                        Some(pid) => {
                            let entry = lazy_groups.entry(pid).or_default();
                            entry.0.push(watch.lazy_uuid.clone());
                            entry.1.push(id);
                        }
                        None => singles.push((id, watch.identifier.clone())),
                    }
                }
                "virt-end" => {
                    let Some(node) = shared_ref.store.node(id) else {
                        drop_ids.push(id);
                        continue;
                    };
                    let Some(&last) = node.children.last() else {
                        continue;
                    };
                    if watch.last_end_child == Some(last) {
                        continue;
                    }
                    let Some(bounds) = shared_ref.node_bounds.get(&last) else {
                        continue;
                    };
                    let top = f64::from(bounds.origin.y);
                    if top < viewport_h + VIEWPORT_OVERSCAN {
                        end_fires.push((id, watch.identifier.clone(), last));
                    }
                }
                _ => {}
            }
        }
    }
    let mut shared_mut = shared.borrow_mut();
    for id in drop_ids {
        shared_mut.viewport_watched.remove(&id);
    }
    for (_, ids) in lazy_groups.values() {
        for id in ids {
            shared_mut.viewport_watched.remove(id);
        }
    }
    for (id, _) in &singles {
        shared_mut.viewport_watched.remove(id);
    }
    for (id, _, last) in &end_fires {
        if let Some(w) = shared_mut.viewport_watched.get_mut(id) {
            w.last_end_child = Some(*last);
        }
    }
    drop(shared_mut);
    if std::env::var_os("LUI_GPUI_DUMP_LAZY").is_some()
        && (!lazy_groups.is_empty() || !singles.is_empty() || !end_fires.is_empty())
    {
        eprintln!(
            "lazy-sweep groups={} singles={} ends={} watched={}",
            lazy_groups.len(),
            singles.len(),
            end_fires.len(),
            shared.borrow().viewport_watched.len()
        );
    }
    for (pid, (uuids, _)) in lazy_groups {
        let identifier = {
            let shared_ref = shared.borrow();
            shared_ref
                .store
                .node(pid)
                .map(|n| match &n.identity {
                    lui_core::store::NodeIdentity::Extension { identifier, .. } => {
                        identifier.clone()
                    }
                    _ => String::new(),
                })
                .unwrap_or_default()
        };
        dom_event(
            shared,
            pid,
            &identifier,
            "lazy-mount",
            serde_json::json!({ "uuids": uuids }),
            cx,
        );
    }
    for (id, identifier) in singles {
        dom_event(
            shared,
            id,
            &identifier,
            "lazy-mount",
            serde_json::json!({}),
            cx,
        );
    }
    for (id, identifier, _) in end_fires {
        dom_event(
            shared,
            id,
            &identifier,
            "virt-end",
            serde_json::json!({}),
            cx,
        );
    }
}

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

    register_viewport_watches(view, node);

    let children = view.child_elements(node, cx);
    let shared = view.shared.clone();

    match tag.as_str() {
        // Text leaf: a bare run. Empty raw-text nodes act as zero-size
        // structural anchors (the DOM observer's `nil` placeholders).
        "raw-text" => {
            // The text lands either via the `text` extension prop
            // (`set_extension_prop`) or as the `data-raw-text` attr —
            // the latter is the emit-side encoding the web backend
            // swaps into a Text node.
            let text = text_prop(node).to_string();
            let text = if text.is_empty() {
                attr(node, "data-raw-text").unwrap_or_default()
            } else {
                text
            };
            let mut element = div();
            if !text.is_empty() {
                element = element.child(SharedString::from(text));
            }
            style::all(element, node, cx.theme()).into_any_element()
        }
        "br" => div().h(px(6.)).into_any_element(),
        "hr" => {
            let mut element = div().py_1().w_full().child(Separator::horizontal());
            element = style::all(element, node, cx.theme());
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
            element = style::all(element, node, cx.theme());
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
            // Plain v_flex container — wrapper elision applies. `multi`
            // requires no gap source (class token, `gap` prop, or the
            // same-named extension prop) between the children.
            let multi = LuiNodeView::gapless(node)
                && !classes(node)
                    .split_whitespace()
                    .any(|t| t == "gap" || t.starts_with("gap-"))
                && node.extension_prop("gap").is_none();
            let horizontal = crate::node_view::snapshot_flex_direction(node).unwrap_or(false);
            let mut element = v_flex().id(ElementId::Integer(node.id as u64));
            element = with_text(element, node);
            element = element.children(view.child_elements_flat(node, horizontal, multi, cx));
            element = style::all(element, node, cx.theme());
            element = with_scroll(element, node);
            if CLICKABLE_TAGS.contains(&tag.as_str()) || has_class(node, "cursor-pointer") {
                element = element.cursor_pointer();
            }
            with_dom_events(element, &shared, node).into_any_element()
        }
        _ if INLINE_TAGS.contains(&tag.as_str()) => {
            // `<br>` splits the run into stacked lines (one h_flex each
            // inside a v_flex). Flex-wrap would be the DOM-accurate shape,
            // but taffy's hypothetical-cross-size pass re-lays-out every
            // child per wrap line and explodes on nested wrap containers.
            let br_at: Vec<bool> = {
                let store = view.shared.borrow();
                node.children
                    .iter()
                    .filter(|cid| store.store.node(**cid).is_some())
                    .map(|cid| {
                        NodeSnapshot::snapshot(&store.store, *cid)
                            .map(|n| {
                                matches!(
                                    n.identity,
                                    NodeIdentity::Standard(
                                        lui_core::wire_schema::NodeKind::Br
                                    )
                                ) || tag_of(&n) == "br"
                            })
                            .unwrap_or(false)
                    })
                    .collect()
            };
            if br_at.iter().any(|b| *b) {
                let mut lines: Vec<Vec<gpui_kit::gpui::AnyElement>> = vec![Vec::new()];
                for (is_br, child) in br_at.into_iter().zip(children) {
                    if is_br {
                        lines.push(Vec::new());
                    } else {
                        lines.last_mut().unwrap().push(child);
                    }
                }
                let mut element = v_flex().id(ElementId::Integer(node.id as u64));
                element = with_text(element, node);
                element = element.children(
                    lines
                        .into_iter()
                        .map(|line| h_flex().items_start().children(line).into_any_element()),
                );
                element = tag_semantic_style(element, &tag, cx);
                element = style::all(element, node, cx.theme());
                element = with_scroll(element, node);
                if CLICKABLE_TAGS.contains(&tag.as_str()) {
                    element = element.cursor_pointer();
                }
                with_dom_events(element, &shared, node).into_any_element()
            } else {
                let mut element = h_flex()
                    .id(ElementId::Integer(node.id as u64))
                    .items_start();
                element = with_text(element, node);
                element = element.children(children);
                element = tag_semantic_style(element, &tag, cx);
                element = style::all(element, node, cx.theme());
                element = with_scroll(element, node);
                if CLICKABLE_TAGS.contains(&tag.as_str()) {
                    element = element.cursor_pointer();
                }
                with_dom_events(element, &shared, node).into_any_element()
            }
        }
        // Unknown logseq-* tag: transparent passthrough, never a warning
        // frame — the logseq family is understood vocabulary, not "missing".
        _ => {
            let multi = LuiNodeView::gapless(node)
                && !classes(node)
                    .split_whitespace()
                    .any(|t| t == "gap" || t.starts_with("gap-"))
                && node.extension_prop("gap").is_none();
            let horizontal = crate::node_view::snapshot_flex_direction(node).unwrap_or(false);
            let mut element = v_flex();
            element = with_text(element, node);
            element = element.children(view.child_elements_flat(node, horizontal, multi, cx));
            element = style::all(element, node, cx.theme());
            element.into_any_element()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use gpui_kit::gpui::Overflow;
    use lui_core::wire::Value;
    use lui_core::wire_schema::Property;
    use std::collections::BTreeMap;

    fn ext_node(
        id: i64,
        identifier: &str,
        extension_props: &[(&str, Value)],
        props: &[(Property, Value)],
    ) -> Node {
        Node {
            id,
            identity: NodeIdentity::Extension {
                identifier: identifier.to_string(),
                fingerprint: "fp".to_string(),
            },
            props: props.iter().cloned().collect(),
            extension_props: extension_props
                .iter()
                .map(|(k, v)| ((*k).to_string(), v.clone()))
                .collect::<BTreeMap<_, _>>(),
            children: Vec::new(),
            parent: None,
        }
    }

    fn snapshot_of(node: &Node) -> NodeSnapshot {
        NodeSnapshot {
            id: node.id,
            identity: node.identity.clone(),
            props: node.props.clone(),
            extension_props: node.extension_props.clone(),
            children: node.children.clone(),
            parent: node.parent,
        }
    }

    fn link(store: &mut Store, parent: i64, child: i64) {
        store.nodes.get_mut(&parent).unwrap().children.push(child);
        store.nodes.get_mut(&child).unwrap().parent = Some(parent);
    }

    #[test]
    fn tag_of_strips_the_logseq_prefix() {
        assert_eq!(tag_of(&snapshot_of(&ext_node(1, "logseq-div", &[], &[]))), "div");
        assert_eq!(
            tag_of(&snapshot_of(&ext_node(1, "logseq-button", &[], &[]))),
            "button"
        );
        // Other namespaces pass through untouched.
        assert_eq!(tag_of(&snapshot_of(&ext_node(1, "gpui-table", &[], &[]))), "gpui-table");
        // Standard kinds carry no tag.
        let standard = Node {
            id: 9,
            identity: NodeIdentity::Standard(lui_core::wire_schema::NodeKind::Text),
            props: BTreeMap::new(),
            extension_props: BTreeMap::new(),
            children: Vec::new(),
            parent: None,
        };
        assert_eq!(tag_of(&snapshot_of(&standard)), "");
    }

    #[test]
    fn attrs_parse_from_the_json_prop() {
        let node = ext_node(
            1,
            "logseq-input",
            &[(
                "attrs",
                Value::Str(r#"{"id": "q", "value": "abc", "data-x": 1}"#.into()),
            )],
            &[],
        );
        assert_eq!(attr(&snapshot_of(&node), "id").as_deref(), Some("q"));
        assert_eq!(attr(&snapshot_of(&node), "value").as_deref(), Some("abc"));
        // Non-string members and missing keys yield None.
        assert!(attr(&snapshot_of(&node), "data-x").is_none());
        assert!(attr(&snapshot_of(&node), "missing").is_none());
        // Broken JSON is not an error — just no attrs.
        let bad = ext_node(
            2,
            "logseq-div",
            &[("attrs", Value::Str("{oops".into()))],
            &[],
        );
        assert!(attr(&snapshot_of(&bad), "id").is_none());
    }

    #[test]
    fn shallow_snapshot_shapes_the_dom_element() {
        let node = ext_node(
            7,
            "logseq-button",
            &[
                ("style-class", Value::Str("flex p-2".into())),
                (
                    "attrs",
                    Value::Str(r#"{"id": "save", "value": "v1", "checked": ""}"#.into()),
                ),
            ],
            &[],
        );
        let store = Store {
            nodes: [(7i64, node)].into_iter().collect(),
            root: Some(7),
            generation: 1,
        };
        let snap = shallow_snapshot(store.node(7).unwrap());
        assert_eq!(snap["tag"], "BUTTON");
        assert_eq!(snap["class"], "flex p-2");
        assert_eq!(snap["id"], "save");
        assert_eq!(snap["#ref"], "save");
        assert_eq!(snap["node-id"], 7);
        assert_eq!(snap["#new"], 7);
        assert_eq!(snap["attrs"]["data-x"], serde_json::Value::Null);
        assert_eq!(snap["attrs"]["id"], "save");
        // value/checked are lifted to top-level fields like the web DOM.
        assert_eq!(snap["value"], "v1");
        assert_eq!(snap["checked"], true);
    }

    #[test]
    fn target_snapshot_carries_the_ancestor_chain_root_first() {
        let mut store = Store::default();
        let root = ext_node(
            1,
            "logseq-main",
            &[("attrs", Value::Str(r#"{"id": "app"}"#.into()))],
            &[],
        );
        let mid = ext_node(2, "logseq-ul", &[], &[]);
        let leaf = ext_node(
            3,
            "logseq-li",
            &[("attrs", Value::Str(r#"{"id": "item-3"}"#.into()))],
            &[],
        );
        store.nodes.insert(1, root);
        store.nodes.insert(2, mid);
        store.nodes.insert(3, leaf);
        link(&mut store, 1, 2);
        link(&mut store, 2, 3);
        let snap = target_snapshot(&store, &std::collections::HashMap::new(), 3);
        assert_eq!(snap["tag"], "LI");
        assert_eq!(snap["id"], "item-3");
        let ancestors = snap["ancestors"].as_array().expect("ancestors array");
        assert_eq!(ancestors.len(), 2);
        assert_eq!(ancestors[0]["tag"], "MAIN");
        assert_eq!(ancestors[0]["id"], "app");
        assert_eq!(ancestors[1]["tag"], "UL");
        // Missing node -> JSON null (the host reports Null upstream).
        assert_eq!(
            target_snapshot(&store, &std::collections::HashMap::new(), 99),
            serde_json::Value::Null
        );
    }

    #[test]
    fn class_helpers_read_the_extension_prop() {
        let node = ext_node(
            1,
            "logseq-div",
            &[(
                "style-class",
                Value::Str("flex p-4 overflow-y-scroll".into()),
            )],
            &[],
        );
        let snap = snapshot_of(&node);
        assert_eq!(classes(&snap), "flex p-4 overflow-y-scroll");
        assert!(has_class(&snap, "overflow-y-scroll"));
        assert!(!has_class(&snap, "overflow-x-scroll"));
    }

    #[test]
    fn scroll_classes_turn_on_the_matching_axes() {
        let node = ext_node(
            1,
            "logseq-div",
            &[("style-class", Value::Str("overflow-y-auto".into()))],
            &[],
        );
        let mut element = with_scroll(v_flex().id(ElementId::Integer(1)), &snapshot_of(&node));
        assert_eq!(element.style().overflow.y, Some(Overflow::Scroll));
        assert_ne!(element.style().overflow.x, Some(Overflow::Scroll));
        let node = ext_node(
            1,
            "logseq-div",
            &[("style-class", Value::Str("overflow-auto".into()))],
            &[],
        );
        let mut element = with_scroll(v_flex().id(ElementId::Integer(1)), &snapshot_of(&node));
        assert_eq!(element.style().overflow.x, Some(Overflow::Scroll));
        assert_eq!(element.style().overflow.y, Some(Overflow::Scroll));
        let plain = ext_node(1, "logseq-div", &[], &[]);
        let mut element = with_scroll(v_flex().id(ElementId::Integer(1)), &snapshot_of(&plain));
        assert_ne!(element.style().overflow.x, Some(Overflow::Scroll));
        assert_ne!(element.style().overflow.y, Some(Overflow::Scroll));
    }

    #[test]
    fn text_prop_reads_the_text_extension_value() {
        let node = ext_node(1, "logseq-span", &[("text", Value::Str("hi".into()))], &[]);
        assert_eq!(text_prop(&snapshot_of(&node)), "hi");
        assert_eq!(
            text_prop(&snapshot_of(&ext_node(1, "logseq-div", &[], &[]))),
            ""
        );
    }
}
