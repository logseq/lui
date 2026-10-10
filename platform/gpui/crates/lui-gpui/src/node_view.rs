//! Per-node component state, selective render caching, and geometry tracking.

use gpui_kit::component::input::{InputState, TextareaState};
use gpui_kit::component::slider::SliderState;
use gpui_kit::component::ActiveTheme;
use gpui_kit::gpui::{
    div, AnyElement, App, Bounds, Context, Element, ElementId, Entity, GlobalElementId, Hitbox,
    HitboxBehavior, InspectorElementId, IntoElement, LayoutId, LongPressEvent, MouseButton,
    MouseDownEvent, MouseMoveEvent, MouseUpEvent, Pixels, Point, Render, ScrollHandle,
    SharedString, Styled, Subscription, TouchPhase, Window,
};
use lui_core::store::{NodeIdentity, Store};
use lui_core::wire::Value;
use lui_core::{bridge, EventKind, NodeKind, Property};

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
    // Only plain anonymous layout wrappers are identities. Semantic controls
    // have intrinsic chrome even with no props, and named nodes must measure.
    if let NodeIdentity::Standard(kind) = child.identity {
        if !matches!(kind, NodeKind::Column | NodeKind::Row | NodeKind::Box) {
            return false;
        }
    }
    if child.props.contains_key(&Property::AccessibilityIdentifier) {
        return false;
    }
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
        if key == "id" && value.as_str().is_some_and(|id| !id.is_empty()) {
            return false;
        }
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
#[derive(Debug, Clone)]
pub struct NodeSnapshot {
    pub id: i64,
    pub identity: NodeIdentity,
    pub props: lui_core::store::NodeProps,
    pub extension_props: lui_core::store::NodeExtensionProps,
    pub children: Vec<i64>,
    pub parent: Option<i64>,
    pub value_revision: u64,
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
            value_revision: node.value_revision,
        })
    }
}

/// One option fed to a gpui-kit searchable list (`select`/`combobox`).
/// `node_id` is the source `menu-item` LUI node — confirming the option
/// fires `Press` on it, so the model's own `on_press` handler runs.
#[derive(Clone, PartialEq, Eq)]
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

/// Keep the active query when model patches replace a picker's delegate.
pub struct LuiOptions {
    items: gpui_kit::component::searchable_list::SearchableVec<LuiOption>,
    query: std::rc::Rc<std::cell::RefCell<String>>,
}

impl LuiOptions {
    pub fn new(
        items: Vec<LuiOption>,
        query: std::rc::Rc<std::cell::RefCell<String>>,
        window: &mut Window,
        cx: &mut App,
    ) -> Self {
        use gpui_kit::component::searchable_list::SearchableListDelegate;
        let mut items = gpui_kit::component::searchable_list::SearchableVec::from(items);
        items.perform_search(&query.borrow(), window, cx).detach();
        Self { items, query }
    }
}

impl gpui_kit::component::searchable_list::SearchableListDelegate for LuiOptions {
    type Item = LuiOption;

    fn items_count(&self, section: usize) -> usize {
        self.items.items_count(section)
    }

    fn item(&self, ix: gpui_kit::component::IndexPath) -> Option<&LuiOption> {
        self.items.item(ix)
    }

    fn position<V>(&self, value: &V) -> Option<gpui_kit::component::IndexPath>
    where
        LuiOption: gpui_kit::component::searchable_list::SearchableListItem<Value = V>,
        V: PartialEq,
    {
        self.items.position(value)
    }

    fn on_will_change(
        &mut self,
        selection: &mut Vec<(gpui_kit::component::IndexPath, LuiOption)>,
        changes: &[gpui_kit::component::searchable_list::SearchableListChange],
    ) {
        use gpui_kit::component::searchable_list::SearchableListChange;
        let changes = changes
            .iter()
            .filter_map(|change| match change {
                SearchableListChange::Select { index } => self
                    .item(*index)
                    .is_some_and(|item| !item.disabled)
                    .then_some(SearchableListChange::Select { index: *index }),
                SearchableListChange::Deselect { index } => {
                    Some(SearchableListChange::Deselect { index: *index })
                }
            })
            .collect::<Vec<_>>();
        self.items.on_will_change(selection, &changes);
    }

    fn perform_search(
        &mut self,
        query: &str,
        window: &mut Window,
        cx: &mut App,
    ) -> gpui_kit::gpui::Task<()> {
        *self.query.borrow_mut() = query.to_string();
        self.items.perform_search(query, window, cx)
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
    pub select: Option<Entity<gpui_kit::component::select::SelectState<LuiOptions>>>,
    pub combobox: Option<Entity<gpui_kit::component::combobox::ComboboxState<LuiOptions>>>,
    pub color_picker: Option<Entity<gpui_kit::component::color_picker::ColorPickerState>>,
    pub table:
        Option<Entity<gpui_kit::component::table::TableState<crate::extension::LuiTableDelegate>>>,
    /// Last applied `gpui-table` `columns`/`rows` signature — the delegate
    /// is only rebuilt when the source strings change.
    pub table_input: std::cell::RefCell<String>,
    /// Last applied `gpui-color-picker` `value` string.
    pub color_picker_input: std::cell::RefCell<String>,
    /// Options last pushed into the select/combobox delegate —
    /// `set_items` is only called when the source list changes.
    pub options_cache: std::cell::RefCell<Vec<LuiOption>>,
    pub options_query: std::rc::Rc<std::cell::RefCell<String>>,
    /// Last explicit model value applied to the backing input state.
    pub input_value_echoed: std::cell::RefCell<Option<String>>,
    pub input_value_revision: Option<u64>,
    pub appeared: std::rc::Rc<std::cell::Cell<bool>>,
    pub pointer_hovered: std::rc::Rc<std::cell::Cell<bool>>,
    pub pending_long_press: std::rc::Rc<std::cell::Cell<(u64, Option<Point<Pixels>>)>>,
    /// Edge-triggered `autofocus`: set once the field's first render has
    /// taken focus, so re-renders don't steal focus back.
    pub autofocus_done: bool,
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
    /// Set when a submenu is closed programmatically (item activation,
    /// Escape) while the pointer still rests over its trigger — blocks
    /// the hover-open path until the pointer actually leaves the row.
    pub submenu_suppress: std::rc::Rc<std::cell::Cell<bool>>,
    /// Last painted bounds of a menu-trigger's popup. The popup can
    /// overlap the row's own rect, so the row's `on_click` consults this
    /// to ignore presses that actually landed inside the popup.
    pub popup_bounds:
        std::rc::Rc<std::cell::Cell<Option<gpui_kit::gpui::Bounds<gpui_kit::gpui::Pixels>>>>,
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

impl ComponentStates {
    /// Apply explicit model writes uniformly, including imperative set-value.
    pub(crate) fn sync_input_value(
        &mut self,
        value: String,
        revision: u64,
        window: &mut Window,
        cx: &mut App,
    ) {
        if self.input_value_revision == Some(revision) {
            return;
        }
        self.input_value_revision = Some(revision);
        *self.input_value_echoed.borrow_mut() = Some(value.clone());
        if let Some(state) = &self.input {
            if state.read(cx).value().as_ref() != value {
                state.update(cx, |state, cx| state.set_value(value.clone(), window, cx));
            }
        }
        if let Some(state) = &self.textarea {
            if state.read(cx).value().as_ref() != value {
                state.update(cx, |state, cx| state.set_value(value, window, cx));
            }
        }
    }
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
        let shared = self.shared.borrow();
        NodeSnapshot::snapshot(&shared.store, self.id)
            .or_else(|| shared.closing_nodes.get(&self.id).cloned())
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
            .filter(|child_id| {
                let shared = self.shared.borrow();
                shared.store.node(*child_id).is_some()
                    || shared.closing_nodes.contains_key(child_id)
            })
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
                        && ((node.float_prop(Property::WidthValue).is_some()
                            && node.float_prop(Property::HeightValue).is_some())
                            || matches!(node.identity, NodeIdentity::Extension { .. }))
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
            if cacheable && !in_virtual_list {
                let mut frame = crate::style::all(div(), &node, cx.theme());
                let fixed = |length| matches!(length,
                    Some(gpui_kit::gpui::Length::Definite(gpui_kit::gpui::DefiniteLength::Absolute(_))));
                // Standard dimensions and fixed extension CSS sizes both admit
                // caching. Content and parent-relative sizes must still measure.
                if fixed(frame.style().size.width) && fixed(frame.style().size.height) {
                    return view.cached(frame.style().clone()).into_any_element();
                }
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
                .or_else(|| shared.closing_nodes.get(&self.id).cloned())
        };
        let Some(node) = node else {
            // Node dropped since last notify; render nothing.
            return div().into_any_element();
        };
        NodeElement {
            inner: kinds::render_node(self, &node, window, cx),
            id: self.id,
            shared: self.shared.clone(),
            appear_enabled: node.flag(Property::AppearEnabled),
            pointer_enabled: node.enabled() && node.flag(Property::PointerEnabled),
            long_press_enabled: node.enabled() && node.flag(Property::LongPressEnabled),
            double_press_enabled: node.enabled() && node.flag(Property::DoublePressEnabled),
            appeared: self.states.appeared.clone(),
            pointer_hovered: self.states.pointer_hovered.clone(),
            pending_long_press: self.states.pending_long_press.clone(),
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
    appear_enabled: bool,
    pointer_enabled: bool,
    long_press_enabled: bool,
    double_press_enabled: bool,
    appeared: std::rc::Rc<std::cell::Cell<bool>>,
    pointer_hovered: std::rc::Rc<std::cell::Cell<bool>>,
    pending_long_press: std::rc::Rc<std::cell::Cell<(u64, Option<Point<Pixels>>)>>,
}

impl IntoElement for NodeElement {
    type Element = Self;
    fn into_element(self) -> Self {
        self
    }
}

impl Element for NodeElement {
    type RequestLayoutState = ();
    type PrepaintState = Option<Hitbox>;
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
    ) -> Option<Hitbox> {
        if self.appear_enabled && !self.appeared.replace(true) {
            let shared = self.shared.clone();
            let id = self.id;
            window.defer(cx, move |_, cx| {
                crate::backend::fire(&shared, id, EventKind::Appear, cx, || unsafe {
                    bridge::lui_ocaml_appear(id)
                });
            });
        }
        let hitbox = (self.pointer_enabled || self.long_press_enabled || self.double_press_enabled)
            .then(|| window.insert_hitbox(bounds, HitboxBehavior::Normal));
        let own_list = {
            let mut shared = self.shared.borrow_mut();
            let own_list = shared.virtual_lists.contains_key(&self.id);
            if let Some(list) = shared.virtual_lists.get_mut(&self.id) {
                let painted = std::mem::take(&mut list.painted);
                for id in painted {
                    shared.node_bounds.remove(&id);
                    shared.text_layouts.remove(&id);
                }
            }
            if own_list {
                shared.painting_lists.push(self.id);
            }
            shared.node_bounds.insert(self.id, bounds);
            // Resolve this node's effective `pointer-events` once per
            // frame: hit testing reads this map instead of re-walking
            // ancestors and re-parsing `attrs`/`style-class` JSON for
            // every candidate under the cursor.
            let hit_disabled = shared
                .store
                .node(self.id)
                .map(|node| {
                    crate::dom::pointer_decision(node)
                        .map(|enabled| !enabled)
                        .or_else(|| {
                            node.parent
                                .and_then(|parent| shared.hit_disabled.get(&parent).copied())
                        })
                        .unwrap_or(false)
                })
                .unwrap_or(false);
            shared.hit_disabled.insert(self.id, hit_disabled);
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
        // Scroll requests, visible-range reports, and image `load` —
        // deferred FFI emissions only; the bookkeeping is frame-local.
        crate::scroll::tick(&self.shared, self.id, window, cx);
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
        hitbox
    }
    fn paint(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&InspectorElementId>,
        _: Bounds<Pixels>,
        _: &mut (),
        hitbox: &mut Option<Hitbox>,
        window: &mut Window,
        cx: &mut App,
    ) {
        self.inner.paint(window, cx);
        let Some(event_hitbox) = hitbox else { return };
        let id = self.id;
        if self.pointer_enabled {
            let shared = self.shared.clone();
            let hitbox = event_hitbox.clone();
            window.on_mouse_event(move |event: &MouseDownEvent, phase, window, cx| {
                if phase.capture() && hitbox.is_hovered(window) {
                    kinds::fire_pointer_detail(
                        &shared,
                        id,
                        EventKind::PointerDown,
                        cx,
                        event.position,
                        event.button,
                        &event.modifiers,
                        |x, y, modifiers, button, class| unsafe {
                            bridge::lui_ocaml_pointer_down(id, x, y, modifiers, button, class)
                        },
                    );
                }
            });
            let shared = self.shared.clone();
            let hitbox = event_hitbox.clone();
            window.on_mouse_event(move |event: &MouseUpEvent, phase, window, cx| {
                if phase.capture() && hitbox.is_hovered(window) {
                    kinds::fire_pointer_detail(
                        &shared,
                        id,
                        EventKind::PointerUp,
                        cx,
                        event.position,
                        event.button,
                        &event.modifiers,
                        |x, y, modifiers, button, class| unsafe {
                            bridge::lui_ocaml_pointer_up(id, x, y, modifiers, button, class)
                        },
                    );
                }
            });
            let shared = self.shared.clone();
            let hitbox = event_hitbox.clone();
            let hovered = self.pointer_hovered.clone();
            window.on_mouse_event(move |_: &MouseMoveEvent, phase, window, cx| {
                if phase.capture() {
                    let next = hitbox.is_hovered(window);
                    if hovered.replace(next) != next {
                        let event = if next {
                            EventKind::PointerEnter
                        } else {
                            EventKind::PointerLeave
                        };
                        crate::backend::fire(&shared, id, event, cx, || unsafe {
                            if next {
                                bridge::lui_ocaml_pointer_enter(id)
                            } else {
                                bridge::lui_ocaml_pointer_leave(id)
                            }
                        });
                    }
                }
            });
        }
        if self.double_press_enabled {
            let shared = self.shared.clone();
            let hitbox = event_hitbox.clone();
            window.on_mouse_event(move |event: &MouseDownEvent, phase, window, cx| {
                if phase.capture()
                    && hitbox.is_hovered(window)
                    && event.button == MouseButton::Left
                    && event.click_count == 2
                {
                    crate::backend::fire(&shared, id, EventKind::DoublePress, cx, || unsafe {
                        bridge::lui_ocaml_double_press(id)
                    });
                }
            });
        }
        if self.long_press_enabled {
            let shared = std::rc::Rc::downgrade(&self.shared);
            let pending = self.pending_long_press.clone();
            let hitbox = event_hitbox.clone();
            window.on_mouse_event(move |event: &MouseDownEvent, phase, window, cx| {
                if !phase.capture()
                    || event.button != MouseButton::Left
                    || !hitbox.is_hovered(window)
                {
                    return;
                }
                let position = event.position;
                let generation = pending.get().0.wrapping_add(1);
                pending.set((generation, Some(position)));
                let pending = std::rc::Rc::downgrade(&pending);
                let shared = shared.clone();
                window
                    .spawn(cx, move |cx: &mut gpui_kit::gpui::AsyncWindowContext| {
                        let mut cx = cx.clone();
                        async move {
                            cx.background_executor()
                                .timer(std::time::Duration::from_millis(500))
                                .await;
                            _ = cx.update(|_, cx| {
                                let (Some(pending), Some(shared)) =
                                    (pending.upgrade(), shared.upgrade())
                                else {
                                    return;
                                };
                                if pending.get() != (generation, Some(position)) {
                                    return;
                                }
                                pending.set((pending.get().0, None));
                                let enabled = {
                                    let state = shared.borrow();
                                    state.root_owners > 0
                                        && state.store.node(id).is_some_and(|node| {
                                            node.enabled() && node.flag(Property::LongPressEnabled)
                                        })
                                };
                                if enabled {
                                    crate::backend::fire(
                                        &shared,
                                        id,
                                        EventKind::LongPress,
                                        cx,
                                        || unsafe { bridge::lui_ocaml_long_press(id) },
                                    );
                                }
                            });
                        }
                    })
                    .detach();
            });
            let pending = self.pending_long_press.clone();
            window.on_mouse_event(move |event: &MouseUpEvent, phase, _, _| {
                if phase.capture() && event.button == MouseButton::Left {
                    pending.set((pending.get().0, None));
                }
            });
            let pending = self.pending_long_press.clone();
            window.on_mouse_event(move |event: &MouseMoveEvent, phase, _, _| {
                if phase.capture()
                    && pending.get().1.is_some_and(|start| {
                        f32::from(event.position.x - start.x).abs() > 6.0
                            || f32::from(event.position.y - start.y).abs() > 6.0
                    })
                {
                    pending.set((pending.get().0, None));
                }
            });
            let pending = self.pending_long_press.clone();
            let shared = self.shared.clone();
            let hitbox = event_hitbox.clone();
            window.on_mouse_event(move |event: &LongPressEvent, phase, window, cx| {
                if phase.capture()
                    && event.phase == TouchPhase::Started
                    && hitbox.is_hovered(window)
                {
                    pending.set((pending.get().0, None));
                    crate::backend::fire(&shared, id, EventKind::LongPress, cx, || unsafe {
                        bridge::lui_ocaml_long_press(id)
                    });
                }
            });
        }
    }
}
