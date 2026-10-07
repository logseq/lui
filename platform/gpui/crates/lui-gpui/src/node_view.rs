//! Per-node component state, selective render caching, and geometry tracking.

use gpui_kit::component::input::{InputState, TextareaState};
use gpui_kit::component::slider::SliderState;
use gpui_kit::component::ActiveTheme;
use gpui_kit::gpui::{
    div, AnyElement, App, Bounds, Context, Element, ElementId, Entity, GlobalElementId,
    InspectorElementId, IntoElement, LayoutId, Pixels, Render, ScrollHandle, SharedString, Styled,
    Subscription, Window,
};
use lui_core::store::{NodeIdentity, Store};
use lui_core::wire::Value;
use lui_core::{NodeKind, Property};

use crate::backend::{LuiShared, Shared};
use crate::kinds;

/// Whether a child node may collapse into its same-direction flex parent.
/// Standard containers need inert standard props and no extension props;
/// `logseq-*` extension containers additionally allow `attrs` carrying
/// only metadata and layout-inert inline declarations, `style-class`
/// with no active utility tokens, and `events` every name of which some
/// `logseq-*` ancestor also subscribes (an elided node's own listeners
/// are never attached, so coverage must come from an ancestor's
/// element). The node stays in the store either way — `closest()` and
/// carrier resolution walk the store parent chain, not the render tree.
fn elidable_node(
    store: &Store,
    child: &lui_core::store::Node,
    parent_horizontal: bool,
    multi: bool,
) -> bool {
    let direction = node_flex_direction(child);
    if direction != Some(parent_horizontal) || child.children.is_empty() {
        return false;
    }
    if child.children.len() > 1 && !multi {
        return false;
    }
    let inert_class = |classes: &str| {
        classes
            .split_whitespace()
            .all(|t| !crate::style::utility_token_active(t))
    };
    let standard_props_inert = child.props.iter().all(|(p, v)| match p {
        Property::AccessibilityIdentifier => true,
        Property::StyleClass => v.as_str().map(&inert_class).unwrap_or(false),
        Property::DataAttrs => v.as_str().map(data_attrs_inert).unwrap_or(false),
        _ => false,
    });
    if !standard_props_inert {
        return false;
    }
    child
        .extension_props
        .iter()
        .all(|(name, value)| match name.as_str() {
            "attrs" | "data-style" => value.as_str().map(ext_attrs_inert).unwrap_or(false),
            "style-class" => value.as_str().map(&inert_class).unwrap_or(false),
            "events" => value.as_str().is_some_and(|events| {
                events
                    .split_whitespace()
                    .all(|name| ext_event_covered(store, child, name))
            }),
            _ => false,
        })
}

/// Whether some `logseq-*` ancestor also subscribes the dom-event `name`
/// — an elided wrapper's own listener is never attached, so its event
/// coverage must come from an ancestor element's handler. (Hit
/// resolution already walks store ancestors to the nearest carrier.)
fn ext_event_covered(store: &Store, node: &lui_core::store::Node, name: &str) -> bool {
    // The root window element emits `click`/`contextmenu` for any hit
    // (root::render mouse monitors), so those names are covered for
    // every node regardless of ancestor listeners.
    if matches!(name, "click" | "contextmenu") {
        return true;
    }
    let mut cursor = node.parent;
    while let Some(id) = cursor {
        let Some(parent) = store.node(id) else {
            break;
        };
        if matches!(parent.identity, NodeIdentity::Extension { .. })
            && parent
                .extension_props
                .get("events")
                .and_then(|v| v.as_str())
                .is_some_and(|events| events.split_whitespace().any(|e| e == name))
        {
            return true;
        }
        cursor = parent.parent;
    }
    false
}

/// Whether an extension `attrs`/`data-style` payload carries nothing but
/// metadata keys and layout-inert inline declarations — `position:
/// relative|static`, zeroed margins/padding, `box-sizing`,
/// `overflow-anchor`. Anything else keeps the wrapper: its inline style
/// may carry real layout (`width`, `display`, transforms).
fn ext_attrs_inert(raw: &str) -> bool {
    let Ok(serde_json::Value::Object(map)) = serde_json::from_str::<serde_json::Value>(raw) else {
        return false;
    };
    map.iter().all(|(key, value)| {
        if key != "style" && key != "data-style" {
            return true;
        }
        let Some(style) = value.as_str() else {
            return false;
        };
        style.split(';').all(inline_decl_inert)
    })
}

/// Whether a `data-attrs` record list (\x1e/\x1f encoded) carries
/// nothing but metadata and layout-inert inline style — same rule as
/// `ext_attrs_inert` for the standard `DataAttrs` prop.
fn data_attrs_inert(raw: &str) -> bool {
    raw.split('\x1e').all(|record| {
        let Some((key, value)) = record.split_once('\x1f') else {
            return true;
        };
        if key != "style" && key != "data-style" {
            return true;
        }
        value.split(';').all(inline_decl_inert)
    })
}

/// Whether one `name: value` inline declaration cannot change layout —
/// `position: relative|static` with no offsets, zeroed margins/padding,
/// `box-sizing`, `overflow-anchor`.
fn inline_decl_inert(decl: &str) -> bool {
    let Some((prop, value)) = decl.split_once(':') else {
        return decl.trim().is_empty();
    };
    match prop.trim() {
        "position" => matches!(value.trim(), "relative" | "static"),
        "margin" | "margin-top" | "margin-right" | "margin-bottom" | "margin-left"
        | "padding" | "padding-top" | "padding-right" | "padding-bottom" | "padding-left" => {
            let value = value.trim();
            value == "0" || value.starts_with("0px") || value.starts_with("0 ")
        }
        "box-sizing" | "overflow-anchor" => true,
        _ => false,
    }
}

/// The flex direction a node actually renders: `flex-row`/`flex-col`
/// class tokens override the kind's default (style.rs applies
/// `.flex_row()`/`.flex_col()` on top of the container base), then the
/// kind/`logseq-*` tag dispatch decides. `None` for non-container kinds.
pub(crate) fn node_flex_direction(node: &lui_core::store::Node) -> Option<bool> {
    flex_direction_of(&node.identity, &node.props, &node.extension_props)
}

/// [`node_flex_direction`] on a render-time snapshot — the callers in
/// `kinds`/`dom` hold `NodeSnapshot`s, not store nodes.
pub(crate) fn snapshot_flex_direction(node: &NodeSnapshot) -> Option<bool> {
    flex_direction_of(&node.identity, &node.props, &node.extension_props)
}

fn flex_direction_of(
    identity: &NodeIdentity,
    props: &lui_core::store::NodeProps,
    ext_props: &lui_core::store::NodeExtensionProps,
) -> Option<bool> {
    let classes = props
        .get(&Property::StyleClass)
        .and_then(|v| v.as_str())
        .or_else(|| ext_props.get("style-class").and_then(|v| v.as_str()));
    if let Some(classes) = classes {
        if classes.split_whitespace().any(|t| t == "flex-row") {
            return Some(true);
        }
        if classes.split_whitespace().any(|t| t == "flex-col") {
            return Some(false);
        }
    }
    container_direction(identity.kind()).or_else(|| crate::dom::ext_flex_direction_of(identity))
}

/// Flex direction a node renders through `kinds::container` —
/// `Some(true)` horizontal (`h_flex`), `Some(false)` vertical
/// (`v_flex`), `None` for kinds rendered by other code paths (which
/// wrapper elision never touches). Mirrors the `container` dispatch in
/// `kinds::render_node`.
fn container_direction(kind: Option<NodeKind>) -> Option<bool> {
    match kind {
        Some(
            NodeKind::Row
            | NodeKind::ButtonGroup
            | NodeKind::ToggleGroup
            | NodeKind::InputGroup
            | NodeKind::InputGroupActions
            | NodeKind::Breadcrumb
            | NodeKind::Toolbar
            | NodeKind::RadioGroup
            | NodeKind::Pagination
            | NodeKind::TableRow,
        ) => Some(true),
        Some(
            NodeKind::Column
            | NodeKind::TableCell
            | NodeKind::Box
            | NodeKind::Table
            | NodeKind::Tree
            | NodeKind::ListSection
            | NodeKind::SwipeActions
            | NodeKind::SwipeAction
            | NodeKind::Timeline,
        ) => Some(false),
        _ => None,
    }
}

/// Immutable per-render copy of one node's state. Render never holds the
/// shared borrow while building elements (child entities are created via
/// `cx.new`, which must not overlap a store borrow).
#[derive(Debug)]
pub struct NodeSnapshot {
    pub id: i64,
    pub identity: NodeIdentity,
    pub props: lui_core::store::NodeProps,
    pub extension_props: lui_core::store::NodeExtensionProps,
    pub children: Vec<i64>,
    pub parent: Option<i64>,
}

impl NodeSnapshot {
    pub fn prop(&self, property: Property) -> Option<&Value> {
        self.props.get(&property)
    }

    pub fn string_prop(&self, property: Property) -> Option<&str> {
        self.prop(property).and_then(Value::as_str)
    }

    pub fn bool_prop(&self, property: Property) -> Option<bool> {
        self.prop(property).and_then(Value::as_bool)
    }

    pub fn int_prop(&self, property: Property) -> Option<i64> {
        self.prop(property).and_then(Value::as_int)
    }

    pub fn float_prop(&self, property: Property) -> Option<f64> {
        self.prop(property).and_then(Value::as_float)
    }

    pub fn flag(&self, property: Property) -> bool {
        self.bool_prop(property) == Some(true)
    }

    /// Extension props arrive via `set-extension-prop` keyed by name
    /// (string — e.g. "style-class", "text", "attrs", "events").
    pub fn extension_prop(&self, name: &str) -> Option<&Value> {
        self.extension_props.get(name)
    }

    pub fn extension_string_prop(&self, name: &str) -> Option<&str> {
        self.extension_prop(name).and_then(Value::as_str)
    }

    pub fn enabled(&self) -> bool {
        self.bool_prop(Property::Enabled).unwrap_or(true)
    }

    /// `text` falls back to `title` — several kinds use title as the label
    /// (bottom-tab, list-section-header).
    pub fn text(&self) -> String {
        self.string_prop(Property::TextValue)
            .or_else(|| self.string_prop(Property::TitleValue))
            .unwrap_or("")
            .to_string()
    }

    pub fn is_treeitem(&self) -> bool {
        self.string_prop(Property::RoleValue) == Some("treeitem")
    }

    pub(crate) fn snapshot(store: &Store, id: i64) -> Option<NodeSnapshot> {
        Self::snapshot_with_children(store, id, true)
    }

    fn snapshot_with_children(
        store: &Store,
        id: i64,
        include_children: bool,
    ) -> Option<NodeSnapshot> {
        let node = store.node(id)?;
        Some(NodeSnapshot {
            id,
            identity: node.identity.clone(),
            props: node.props.clone(),
            extension_props: node.extension_props.clone(),
            children: if include_children {
                node.children.clone()
            } else {
                Vec::new()
            },
            parent: node.parent,
        })
    }
}

/// One option fed to a gpui-kit searchable list (`select`/`combobox`).
/// `node_id` is the source `menu-item` LUI node — confirming the option
/// fires `Press` on it, so the model's own `on_press` handler runs.
#[derive(Clone)]
pub struct LuiOption {
    pub node_id: i64,
    pub title: SharedString,
    pub disabled: bool,
}

impl gpui_kit::component::searchable_list::SearchableListItem for LuiOption {
    type Value = i64;

    fn title(&self) -> SharedString {
        self.title.clone()
    }

    fn value(&self) -> &i64 {
        &self.node_id
    }

    fn disabled(&self) -> bool {
        self.disabled
    }
}

/// Stateful gpui-component backing states kept per node. Created lazily,
/// survive re-renders, dropped with the view entity on `drop-node`.
#[derive(Default)]
pub struct ComponentStates {
    pub input: Option<Entity<InputState>>,
    pub textarea: Option<Entity<TextareaState>>,
    pub slider: Option<Entity<SliderState>>,
    pub split: Option<Entity<gpui_kit::component::resizable::ResizableState>>,
    pub split_target: std::rc::Rc<std::cell::Cell<Option<(Pixels, f32)>>>,
    pub select: Option<Entity<gpui_kit::component::select::SelectState<Vec<LuiOption>>>>,
    pub combobox: Option<Entity<gpui_kit::component::combobox::ComboboxState<Vec<LuiOption>>>>,
    pub color_picker: Option<Entity<gpui_kit::component::color_picker::ColorPickerState>>,
    pub table:
        Option<Entity<gpui_kit::component::table::TableState<crate::extension::LuiTableDelegate>>>,
    /// Last applied `gpui-table` `columns`/`rows` signature — the delegate
    /// is only rebuilt when the source strings change.
    pub table_input: std::cell::RefCell<String>,
    /// Last applied `gpui-color-picker` `value` string.
    pub color_picker_input: std::cell::RefCell<String>,
    /// Option node ids last pushed into the select/combobox delegate —
    /// `set_items` is only called when the source list changes.
    pub options_cache: std::cell::RefCell<Vec<i64>>,
    /// Wire `value` last echoed into `input` — the controlled echo only
    /// applies when the prop itself changes (re-emit or `set-value`),
    /// never against text the user typed into an uncontrolled field.
    pub input_value_echoed: std::cell::RefCell<Option<String>>,
    /// Open overlay anchored at a window point (context menu, popup menu).
    /// `Some(point)` renders the deferred layer, `None` is closed.
    pub overlay:
        std::rc::Rc<std::cell::Cell<Option<gpui_kit::gpui::Point<gpui_kit::gpui::Pixels>>>>,
    /// Trigger bounds captured on prepaint for `dropdown-menu` popup
    /// positioning — the deferred popup re-resolves against the latest
    /// frame's bounds.
    pub menu_bounds:
        std::rc::Rc<std::cell::Cell<Option<gpui_kit::gpui::Bounds<gpui_kit::gpui::Pixels>>>>,
    /// Anchored tooltip visibility flag driven by hover listeners.
    pub tooltip: std::rc::Rc<std::cell::Cell<bool>>,
    /// Submenu popup open flag for `menu-trigger` rows.
    pub menu_open: std::rc::Rc<std::cell::Cell<bool>>,
    /// The menu_trigger node id currently expanded inside this menu —
    /// sibling coordination so only one submenu stays open at a time.
    pub open_submenu: std::rc::Rc<std::cell::Cell<Option<i64>>>,
    /// `split-view` → `DockArea` sync state (extension.rs registers it).
    pub dock: Option<crate::dock::DockSync>,
    /// Per-node state bag for host-registered extension renderers: a host
    /// stores its own `Rc<RefCell<T>>` (as `Rc<dyn Any>`) here on first
    /// render and downcasts it back on subsequent renders. Keeps
    /// app-specific hosts (e.g. Logseq's `logseq-*` surfaces) out of the
    /// framework's state struct.
    pub app_state: Option<std::rc::Rc<dyn std::any::Any>>,
    /// Scroll state for scrollable container kinds — `track_scroll`
    /// registers it at render; `scroll_tracked` then marks this node as
    /// the scroll ancestor the `scroll-into-view` dom-op looks for.
    pub scroll: ScrollHandle,
    pub scroll_tracked: bool,
    pub subscriptions: Vec<Subscription>,
}

/// The view entity for one LUI node id.
pub struct LuiNodeView {
    pub id: i64,
    pub shared: Shared,
    pub states: ComponentStates,
}

impl LuiNodeView {
    pub fn new(id: i64, shared: Shared) -> Self {
        LuiNodeView {
            id,
            shared,
            states: ComponentStates::default(),
        }
    }

    pub fn snapshot(&self) -> Option<NodeSnapshot> {
        NodeSnapshot::snapshot(&self.shared.borrow().store, self.id)
    }

    /// Entity handle for a child node (creating on demand). Used by every
    /// container render to embed children while retaining component state.
    pub fn child_view(&self, child_id: i64, cx: &mut App) -> Entity<LuiNodeView> {
        LuiShared::view_for(&self.shared, child_id, cx)
    }

    /// Elements for the node's children, skipping ids the store no longer
    /// has (a drop in the same batch as a structural op).
    pub fn child_elements(
        &self,
        node: &NodeSnapshot,
        cx: &mut App,
    ) -> Vec<gpui_kit::gpui::AnyElement> {
        node.children
            .iter()
            .copied()
            .filter(|child_id| self.shared.borrow().store.node(*child_id).is_some())
            .map(|child_id| Self::element_for(&self.shared, child_id, cx))
            .collect()
    }

    /// Content-sized nodes must still measure their contents. Only nodes
    /// with both dimensions declared can use GPUI's measurement-free cache.
    pub(crate) fn element_for(shared: &Shared, id: i64, cx: &mut App) -> AnyElement {
        let node = {
            let shared = shared.borrow();
            // Containers cannot use the leaf cache. Do not duplicate their
            // children here, especially a virtual list's retained sequence.
            shared
                .store
                .node(id)
                .filter(|node| {
                    node.children.is_empty()
                        && node.float_prop(Property::WidthValue).is_some()
                        && node.float_prop(Property::HeightValue).is_some()
                })
                .and_then(|_| NodeSnapshot::snapshot(&shared.store, id))
        };
        let view = LuiShared::view_for(shared, id, cx);
        if let Some(node) = node {
            let in_virtual_list = {
                let shared = shared.borrow();
                let mut cursor = node.parent;
                let mut found = false;
                while let Some(id) = cursor {
                    if shared.virtual_lists.contains_key(&id) {
                        found = true;
                        break;
                    }
                    cursor = shared.store.node(id).and_then(|node| node.parent);
                }
                found
            };
            let cacheable = match &node.identity {
                NodeIdentity::Standard(kind) => matches!(
                    kind,
                    lui_core::NodeKind::Text
                        | lui_core::NodeKind::Heading
                        | lui_core::NodeKind::Paragraph
                        | lui_core::NodeKind::Label
                        | lui_core::NodeKind::Spacer
                        | lui_core::NodeKind::Divider
                        | lui_core::NodeKind::Icon
                        | lui_core::NodeKind::Kbd
                ),
                NodeIdentity::Extension { .. } => {
                    let states = &view.read(cx).states;
                    states.subscriptions.is_empty()
                        && states.app_state.is_none()
                        && states.input.is_none()
                        && states.table.is_none()
                        && states.dock.is_none()
                        && states.color_picker.is_none()
                }
            };
            if cacheable
                && node.children.is_empty()
                && !in_virtual_list
                && node.float_prop(Property::WidthValue).is_some()
                && node.float_prop(Property::HeightValue).is_some()
            {
                let mut frame = crate::style::all(div(), &node, cx.theme());
                return view.cached(frame.style().clone()).into_any_element();
            }
        }
        view.into_any_element()
    }

    /// Child ids for rendering, collapsing identity wrapper levels.
    ///
    /// `parent` is `Some((horizontal, multi))` when the parent renders a
    /// plain flex container: `horizontal` is its direction and `multi`
    /// is true when the parent separates children by nothing but their
    /// own boxes (no `gap` prop, no `gap-*` class token, no kind-level
    /// default gap) so a wrapper may expand several children into its
    /// slot without changing spacing.
    ///
    /// A node elides when it renders through `kinds::container` in the
    /// same direction as the parent, has at least one child, and carries
    /// only inert props: `accessibility-identifier`, or `style-class`
    /// whose tokens all resolve to no gpui style (app-vocabulary classes
    /// like `ls-*`). Event and attribute semantics are unaffected —
    /// elided nodes stay in the store, so `closest()`/carrier walks
    /// still resolve them; only their layout level disappears. Inside a
    /// same-direction flex parent such a wrapper is a layout identity —
    /// children inherit the same main-axis slots and the same cross-axis
    /// stretch. Deep wrapper chains (foldable/virtuoso scaffold mirrored
    /// from the web DOM) otherwise multiply taffy's per-level flex
    /// re-measure into exponential layout cost.
    ///
    /// `None` for contexts whose child slot is not a plain flex container
    /// (links, text flows) — no elision there since the wrapper's slot
    /// semantics are unknown.
    fn flat_child_ids(&self, children: &[i64], parent: Option<(bool, bool)>) -> Vec<i64> {
        let Some((horizontal, multi)) = parent else {
            return children
                .iter()
                .copied()
                .filter(|id| self.shared.borrow().store.node(*id).is_some())
                .collect();
        };
        let shared = self.shared.borrow();
        let mut out = Vec::with_capacity(children.len());
        let mut stack: Vec<i64> = children.iter().rev().copied().collect();
        while let Some(id) = stack.pop() {
            let Some(child) = shared.store.node(id) else {
                continue;
            };
            let elide = elidable_node(&shared.store, child, horizontal, multi);
            if elide {
                stack.extend(child.children.iter().rev().copied());
            } else {
                out.push(id);
            }
        }
        out
    }

    /// Whether the node's own flex container may host multi-child
    /// elision — no explicit `gap` prop and no `gap`/`gap-*` style-class
    /// token. Callers additionally exclude kinds whose `container`
    /// chrome adds a default gap.
    pub fn gapless(node: &NodeSnapshot) -> bool {
        node.prop(Property::Gap).is_none()
            && !node
                .string_prop(Property::StyleClass)
                .unwrap_or("")
                .split_whitespace()
                .any(|t| t == "gap" || t.starts_with("gap-"))
    }

    /// Like [`Self::child_elements`] but applies wrapper elision for a
    /// parent that renders a plain flex container.
    /// Each rendered node records its own geometry.
    pub fn child_elements_flat(
        &self,
        node: &NodeSnapshot,
        horizontal: bool,
        multi: bool,
        cx: &mut App,
    ) -> Vec<gpui_kit::gpui::AnyElement> {
        self.flat_child_ids(&node.children, Some((horizontal, multi)))
            .into_iter()
            .map(|child_id| Self::element_for(&self.shared, child_id, cx))
            .collect()
    }
}

impl Render for LuiNodeView {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        // Refresh the viewport table `style` resolves `vw`/`vh` units
        // against — cheap per-node writes, always current on resize.
        let size = window.viewport_size();
        crate::style::set_viewport_size(f32::from(size.width), f32::from(size.height));
        // Virtual lists retain the child sequence between structural patches;
        // scrolling and row updates must not copy all N child ids each frame.
        let node = {
            let shared = self.shared.borrow();
            let include_children = shared
                .virtual_lists
                .get(&self.id)
                .is_none_or(|list| list.children_dirty);
            NodeSnapshot::snapshot_with_children(&shared.store, self.id, include_children)
        };
        let Some(node) = node else {
            // Node dropped since last notify; render nothing.
            return div().into_any_element();
        };
        NodeElement {
            inner: kinds::render_node(self, &node, window, cx),
            id: self.id,
            shared: self.shared.clone(),
        }
        .into_any_element()
    }
}

/// Delegate the layout unchanged: an extra Div would alter flex sizing and
/// component geometry. Recording at this boundary works for every node kind.
struct NodeElement {
    inner: AnyElement,
    id: i64,
    shared: Shared,
}

impl IntoElement for NodeElement {
    type Element = Self;
    fn into_element(self) -> Self {
        self
    }
}

impl Element for NodeElement {
    type RequestLayoutState = ();
    type PrepaintState = ();
    fn id(&self) -> Option<ElementId> {
        None
    }
    fn source_location(&self) -> Option<&'static std::panic::Location<'static>> {
        None
    }
    fn request_layout(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&InspectorElementId>,
        window: &mut Window,
        cx: &mut App,
    ) -> (LayoutId, ()) {
        (self.inner.request_layout(window, cx), ())
    }
    fn prepaint(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&InspectorElementId>,
        bounds: Bounds<Pixels>,
        _: &mut (),
        window: &mut Window,
        cx: &mut App,
    ) {
        let own_list = {
            let mut shared = self.shared.borrow_mut();
            let own_list = shared.virtual_lists.contains_key(&self.id);
            if let Some(list) = shared.virtual_lists.get_mut(&self.id) {
                let painted = std::mem::take(&mut list.painted);
                for id in painted {
                    shared.node_bounds.remove(&id);
                }
            }
            if own_list {
                shared.painting_lists.push(self.id);
            }
            shared.node_bounds.insert(self.id, bounds);
            // Re-arm a consumed lazy-mount/virt-end watch — the node may
            // have kept its id without re-rendering, leaving the render
            // path no chance to register a fresh watch.
            crate::dom::rearm_viewport_watch(&mut shared, self.id);
            if std::env::var_os("LUI_GPUI_DUMP_BOUNDS").is_some() {
                use std::sync::{Mutex, OnceLock};
                static SEEN: OnceLock<Mutex<std::collections::HashSet<String>>> =
                    OnceLock::new();
                let class = shared
                    .store
                    .node(self.id)
                    .and_then(|n| {
                        n.props
                            .iter()
                            .find(|(p, _)| **p == lui_core::Property::StyleClass)
                            .and_then(|(_, v)| v.as_str())
                    })
                    .unwrap_or("")
                    .to_string();
                let key = format!("id={} {:?} {:?}", self.id, bounds, class);
                if SEEN
                    .get_or_init(|| Mutex::new(std::collections::HashSet::new()))
                    .lock()
                    .unwrap()
                    .insert(key.clone())
                {
                    eprintln!("bounds {key}");
                }
            }
            // An outer list owns nested row geometry too, so unmounting a
            // nested list retires all of its descendants' recorded bounds.
            let lists = shared.painting_lists.clone();
            for id in lists {
                if let Some(list) = shared.virtual_lists.get_mut(&id) {
                    list.painted.insert(self.id);
                }
            }
            own_list
        };
        let focus = {
            let shared = self.shared.borrow();
            shared
                .painting_lists
                .last()
                .and_then(|id| shared.virtual_lists.get(id))
                .and_then(|list| list.row_focus.get(&self.id))
                .cloned()
        };
        if let Some(focus) = focus {
            window.set_focus_handle(&focus, cx);
        }
        self.inner.prepaint(window, cx);
        if own_list {
            self.shared.borrow_mut().painting_lists.pop();
        }
    }
    fn paint(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&InspectorElementId>,
        _: Bounds<Pixels>,
        _: &mut (),
        _: &mut (),
        window: &mut Window,
        cx: &mut App,
    ) {
        self.inner.paint(window, cx);
    }
}
