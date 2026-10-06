//! One `Entity<LuiNodeView>` per LUI node — the minimal re-render unit.

use gpui_kit::component::input::{InputState, TextareaState};
use gpui_kit::component::slider::SliderState;
use gpui_kit::gpui::{
    div, App, Bounds, Context, Entity, IntoElement, Pixels, Render, ScrollHandle, SharedString,
    Subscription, Window,
};
use lui_core::store::{NodeIdentity, Store};
use lui_core::wire::Value;
use lui_core::Property;

use crate::backend::{LuiShared, Shared};
use crate::kinds;

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
        let node = store.node(id)?;
        Some(NodeSnapshot {
            id,
            identity: node.identity.clone(),
            props: node.props.clone(),
            extension_props: node.extension_props.clone(),
            children: node.children.clone(),
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
    /// stores its own `Rc<RefCell<T>>` here on first render and downcasts
    /// it back on subsequent renders. Keeps app-specific hosts (e.g.
    /// Logseq's `logseq-*` surfaces) out of the framework's state struct.
    pub app_state: Option<std::rc::Rc<std::cell::RefCell<dyn std::any::Any>>>,
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
    /// container render to embed children as *entity* children — the key to
    /// per-node redraw isolation.
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
            .map(|child_id| self.child_view(child_id, cx).into_any_element())
            .collect()
    }

    /// `on_children_prepainted` listener recording each rendered child's
    /// window-space bounds into `shared.node_bounds`. Attach it to a
    /// container's outer `Div`; the prepainted order matches
    /// [`Self::child_elements`] (both filter out dropped children).
    pub fn bounds_recorder(
        &self,
        node: &NodeSnapshot,
    ) -> impl Fn(Vec<Bounds<Pixels>>, &mut Window, &mut App) + 'static {
        let shared = self.shared.clone();
        let child_ids: Vec<i64> = node
            .children
            .iter()
            .copied()
            .filter(|child_id| shared.borrow().store.node(*child_id).is_some())
            .collect();
        move |bounds, _window, _cx| {
            let mut shared = shared.borrow_mut();
            for (id, bounds) in child_ids.iter().zip(bounds) {
                shared.node_bounds.insert(*id, bounds);
            }
        }
    }
}

impl Render for LuiNodeView {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let Some(node) = self.snapshot() else {
            // Node dropped since last notify; render nothing.
            return div().into_any_element();
        };
        kinds::render_node(self, &node, window, cx)
    }
}
