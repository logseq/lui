//! Window-level root view: mounts the LUI root node's entity.

use std::cell::OnceCell;

use gpui_kit::component::theme::ActiveTheme;
use gpui_kit::component::v_flex;
use gpui_kit::gpui::{
    div, Context, FocusHandle, InteractiveElement, IntoElement, KeyDownEvent, MouseButton,
    MouseUpEvent, ParentElement, Render, StatefulInteractiveElement, Styled,
    Subscription, Window,
};

use crate::backend::{LuiShared, Shared};


/// The view hosted inside `gpui_component::Root`. Renders the root node
/// entity or an empty screen while no root is
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
    /// Window appearance subscription (kept alive for the view's life):
    /// OS light/dark switches re-apply the registered gpui-component theme.
    appearance: OnceCell<Subscription>,
}

impl LuiRootView {
    pub fn new(shared: Shared) -> Self {
        LuiRootView {
            shared,
            focus: OnceCell::new(),
            appearance: OnceCell::new(),
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
        // Follow OS appearance changes: re-apply the registered theme so
        // colors, scrollbar and resize-handle styles all track light/dark.
        self.appearance.get_or_init(|| {
            cx.observe_window_appearance(window, |_, window, cx| {
                crate::theme::sync_window_appearance(window, cx);
            })
        });
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
                let click_shared = self.shared.clone();
                v_flex()
                    .id("lui-root-scroll")
                    .size_full()
                    .overflow_y_scroll()
                    .bg(cx.theme().background)
                    .text_color(cx.theme().foreground)
                    .font_family(cx.theme().font_family.clone())
                    .track_focus(&focus)
                    .on_mouse_up(
                        MouseButton::Left,
                        move |event: &MouseUpEvent, _window, cx| {
                            // Web parity: a click targets the deepest hit
                            // element, and document listeners see it even
                            // when it lands on a plain element — dom.rs
                            // only wires `click` on nodes that declared it.
                            // Emit the hit through an extension carrier;
                            // OCaml's 60ms coalescing drops the wired
                            // duplicate when one also fires.
                            let Some(hit) = crate::dom::deepest_hit(&click_shared, event.position)
                            else {
                                return;
                            };
                            let Some((carrier, ident)) =
                                crate::dom::logseq_carrier(&click_shared, Some(hit))
                            else {
                                return;
                            };
                            let position = event.position;
                            crate::dom::dom_event_via(
                                &click_shared,
                                carrier,
                                &ident,
                                hit,
                                "click",
                                serde_json::json!({
                                    "clientX": f64::from(position.x),
                                    "clientY": f64::from(position.y),
                                }),
                                cx,
                            );
                        },
                    )
                    .on_key_down(move |ev: &KeyDownEvent, window, cx| {
                        if ev.is_held {
                            return;
                        }
                        // A focused text input (block editor, cmdk field)
                        // already receives text through its registered
                        // input handler — forwarding the same key as a
                        // document keydown would double-insert it, and
                        // native targets can't carry a `.ed-input` target
                        // for the document handler to recognize.
                        if ev.keystroke.key_char.is_some()
                            && !ev.keystroke.modifiers.platform
                            && !ev.keystroke.modifiers.control
                            && window.focused(cx).is_some()
                            && !focus.is_focused(window)
                        {
                            return;
                        }
                        let Some((node_id, identifier)) =
                            crate::dom::logseq_carrier(&keydown_shared, None)
                        else {
                            return;
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
                            "up" | "arrowup" => "ArrowUp",
                            "down" | "arrowdown" => "ArrowDown",
                            "left" | "arrowleft" => "ArrowLeft",
                            "right" | "arrowright" => "ArrowRight",
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
                            &identifier,
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
