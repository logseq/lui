//! Window-level root view: mounts the LUI root node's entity.

use gpui_kit::component::theme::ActiveTheme;
use gpui_kit::component::v_flex;
use gpui_kit::gpui::{
    div, Context, InteractiveElement, IntoElement, ParentElement, Render,
    StatefulInteractiveElement, Styled, Window,
};

use crate::backend::{LuiShared, Shared};

/// The view hosted inside `gpui_component::Root`. Renders the root node
/// entity (itself redraw-isolated) or an empty screen while no root is
/// attached yet.
pub struct LuiRootView {
    pub shared: Shared,
}

impl LuiRootView {
    pub fn new(shared: Shared) -> Self {
        LuiRootView { shared }
    }
}

impl Render for LuiRootView {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let root_id = self.shared.borrow().store.root;
        // No parent records the root node's bounds — seed them from the
        // viewport so `measure-node` on the root has real data.
        let size = window.viewport_size();
        crate::domops::note_root_bounds(
            &self.shared,
            f32::from(size.width),
            f32::from(size.height),
        );
        match root_id {
            Some(id) => {
                let view = LuiShared::view_for(&self.shared, id, cx);
                // The LUI root node is typically a plain column; other
                // backends get their outer scrolling from the host surface,
                // so the window root supplies it here.
                v_flex()
                    .id("lui-root-scroll")
                    .size_full()
                    .overflow_y_scroll()
                    .bg(cx.theme().background)
                    .child(view)
                    .into_any_element()
            }
            None => div()
                .size_full()
                .bg(cx.theme().background)
                .into_any_element(),
        }
    }
}
