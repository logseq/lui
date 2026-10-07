//! Variable-height virtualization over gpui-kit's native list primitive.

use crate::node_view::{LuiNodeView, NodeSnapshot};
use crate::style;
use gpui_kit::component::ActiveTheme;
use gpui_kit::gpui::{div, px, AnyElement, App, IntoElement, ListState, Styled};
use std::collections::HashMap;

/// Retained virtualization metadata lives outside Entity leases so feedback
/// patches can invalidate measurements during a node's subscription callback.
pub(crate) struct State {
    pub state: ListState,
    pub children: std::rc::Rc<Vec<i64>>,
    pub indices: std::collections::HashMap<i64, usize>,
    pub painted: std::collections::HashSet<i64>,
    pub children_dirty: bool,
    pub row_focus: std::collections::HashMap<i64, gpui_kit::gpui::FocusHandle>,
}

/// A list that measures variable-height rows lazily. Structural changes
/// splice only the differing span and preserve the logical scroll anchor.
pub(crate) fn render(view: &mut LuiNodeView, node: &NodeSnapshot, cx: &mut App) -> AnyElement {
    use gpui_kit::gpui::{list, ListAlignment, ListState};
    let (state, children) = {
        let mut shared = view.shared.borrow_mut();
        let data = shared
            .virtual_lists
            .entry(node.id)
            .or_insert_with(|| State {
                state: ListState::new(0, ListAlignment::Top, px(64.)),
                children: std::rc::Rc::new(Vec::new()),
                indices: HashMap::new(),
                painted: Default::default(),
                children_dirty: true,
                row_focus: Default::default(),
            });
        if data.children_dirty {
            let prefix = data
                .children
                .iter()
                .zip(&node.children)
                .take_while(|(a, b)| a == b)
                .count();
            let suffix = data.children[prefix..]
                .iter()
                .rev()
                .zip(node.children[prefix..].iter().rev())
                .take_while(|(a, b)| a == b)
                .count();
            let scroll = data.state.logical_scroll_top();
            let anchor = data.children.get(scroll.item_ix).copied();
            data.state.splice_focusable(
                prefix..data.children.len() - suffix,
                node.children[prefix..node.children.len() - suffix]
                    .iter()
                    .map(|id| data.row_focus.get(id).cloned()),
            );
            data.children_dirty = false;
            data.children = std::rc::Rc::new(node.children.clone());
            data.indices = node
                .children
                .iter()
                .enumerate()
                .map(|(index, id)| (*id, index))
                .collect();
            data.row_focus.retain(|id, _| data.indices.contains_key(id));
            if let Some(index) = anchor.and_then(|id| data.indices.get(&id)).copied() {
                data.state.scroll_to(gpui_kit::gpui::ListOffset {
                    item_ix: index,
                    offset_in_item: scroll.offset_in_item,
                });
            }
        }
        (data.state.clone(), data.children.clone())
    };
    view.states.scroll_tracked = true;
    let shared = view.shared.clone();
    let list_id = node.id;
    let element = list(state, move |index, window, cx| {
        let Some(&id) = children.get(index) else {
            return div().into_any_element();
        };
        let new_focus = {
            let mut guard = shared.borrow_mut();
            let data = guard.virtual_lists.get_mut(&list_id).expect("mounted list");
            if let std::collections::hash_map::Entry::Vacant(entry) = data.row_focus.entry(id) {
                let focus = cx.focus_handle();
                entry.insert(focus.clone());
                Some(focus)
            } else {
                None
            }
        };
        if let Some(focus) = new_focus {
            let shared = shared.clone();
            // The native list borrows its state while calling render_item;
            // register the row's dispatch scope after prepaint releases it.
            window.defer(cx, move |_, cx| {
                let guard = shared.borrow();
                if let Some(data) = guard.virtual_lists.get(&list_id) {
                    if let Some(&index) = data.indices.get(&id) {
                        let scroll = data.state.logical_scroll_top();
                        data.state.splice_focusable(index..index + 1, [Some(focus)]);
                        data.state.scroll_to(scroll);
                        if let Some(view) = guard.views.get(&list_id) {
                            cx.notify(view.entity_id());
                        }
                    }
                }
            });
        }
        LuiNodeView::element_for(&shared, id, cx)
    })
    .size_full();
    style::all(element, node, cx.theme()).into_any_element()
}
