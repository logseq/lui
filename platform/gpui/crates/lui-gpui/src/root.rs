//! Window-level root view: mounts the LUI root node's entity.

use std::cell::OnceCell;

use gpui_kit::component::theme::ActiveTheme;
use gpui_kit::component::v_flex;
use gpui_kit::gpui::{
    div, Context, FocusHandle, InteractiveElement, IntoElement, KeyDownEvent, ParentElement, Render,
    StatefulInteractiveElement, Styled, Window,
};

use crate::backend::{LuiShared, Shared};

/// The view hosted inside `gpui_component::Root`. Renders the root node
/// entity (itself redraw-isolated) or an empty screen while no root is
/// attached yet.
///
/// Owns a window-level FocusHandle so key events always have a dispatch
/// path: when nothing else is focused (browse mode) the root holds focus,
/// and its `on_key_down` forwards every keystroke to OCaml as a `keydown`
/// dom-event, matching the web document keydown that global shortcuts and
/// command dispatch listen on.
pub struct LuiRootView {
    pub shared: Shared,
    focus: OnceCell<FocusHandle>,
}

impl LuiRootView {
    pub fn new(shared: Shared) -> Self {
        LuiRootView {
            shared,
            focus: OnceCell::new(),
        }
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
        let focus = self.focus.get_or_init(|| cx.focus_handle()).clone();
        // Nothing focused → fall back to the root handle so key events
        // keep dispatching outside of editor surfaces.
        if window.focused(cx).is_none() {
            focus.focus(window, cx);
        }
        let keydown_shared = self.shared.clone();
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
                    .track_focus(&focus)
                    .on_key_down(move |ev: &KeyDownEvent, _window, cx| {
                        if ev.is_held {
                            return;
                        }
                        // dom-events must target an extension node — OCaml
                        // drops extension events on standard nodes. Any
                        // extension node works: emit_event fans out to the
                        // document (window) listeners regardless.
                        let node_id = {
                            let store = &keydown_shared.borrow().store;
                            let mut stack = store.root.into_iter().collect::<Vec<_>>();
                            let mut found = None;
                            while let Some(id) = stack.pop() {
                                if let Some(node) = store.node(id) {
                                    if matches!(
                                        node.identity,
                                        lui_core::store::NodeIdentity::Extension { .. }
                                    ) {
                                        found = Some(id);
                                        break;
                                    }
                                    stack.extend(node.children.iter().copied());
                                }
                            }
                            match found {
                                Some(id) => id,
                                None => return,
                            }
                        };
                        let ks = &ev.keystroke;
                        let mods = ks.modifiers;
                        // gpui reports named keys lowercase; DOM listeners
                        // match KeyboardEvent.key spellings.
                        let key = match ks.key.as_str() {
                            "escape" => "Escape",
                            "enter" => "Enter",
                            "tab" => "Tab",
                            "backspace" => "Backspace",
                            "delete" => "Delete",
                            "arrowup" => "ArrowUp",
                            "arrowdown" => "ArrowDown",
                            "arrowleft" => "ArrowLeft",
                            "arrowright" => "ArrowRight",
                            "home" => "Home",
                            "end" => "End",
                            "pageup" => "PageUp",
                            "pagedown" => "PageDown",
                            "space" => " ",
                            other => other,
                        };
                        crate::dom::dom_event(
                            &keydown_shared,
                            node_id,
                            "",
                            "keydown",
                            serde_json::json!({
                                "key": key,
                                "keyChar": ks.key_char,
                                "metaKey": mods.platform,
                                "ctrlKey": mods.control,
                                "shiftKey": mods.shift,
                                "altKey": mods.alt,
                            }),
                            cx,
                        );
                    })
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
