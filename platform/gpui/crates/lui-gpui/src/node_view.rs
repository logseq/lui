//! One `Entity<LuiNodeView>` per LUI node — the minimal re-render unit.

use gpui_kit::component::input::{InputState, TextareaState};
use gpui_kit::component::slider::SliderState;
use gpui_kit::gpui::{div, App, Context, Entity, IntoElement, Render, Subscription, Window};
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

    fn snapshot(store: &Store, id: i64) -> Option<NodeSnapshot> {
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

/// Stateful gpui-component backing states kept per node. Created lazily,
/// survive re-renders, dropped with the view entity on `drop-node`.
#[derive(Default)]
pub struct ComponentStates {
    pub input: Option<Entity<InputState>>,
    pub textarea: Option<Entity<TextareaState>>,
    pub slider: Option<Entity<SliderState>>,
    /// Open overlay anchored at a window point (context menu, popup menu).
    /// `Some(point)` renders the deferred layer, `None` is closed.
    pub overlay:
        std::rc::Rc<std::cell::Cell<Option<gpui_kit::gpui::Point<gpui_kit::gpui::Pixels>>>>,
    /// Anchored tooltip visibility flag driven by hover listeners.
    pub tooltip: std::rc::Rc<std::cell::Cell<bool>>,
    /// Submenu popup open flag for `menu-trigger` rows.
    pub menu_open: std::rc::Rc<std::cell::Cell<bool>>,
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
