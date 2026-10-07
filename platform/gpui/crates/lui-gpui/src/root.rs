//! Window-level root view: mounts the LUI root node's entity.

use std::cell::OnceCell;

use gpui_kit::component::theme::ActiveTheme;
use gpui_kit::component::v_flex;
use gpui_kit::gpui::{
    canvas, div, px, Context, DispatchPhase, FocusHandle, InteractiveElement, IntoElement,
    KeyDownEvent, MouseButton, MouseDownEvent, MouseUpEvent, ParentElement, Render,
    StatefulInteractiveElement, Styled, Subscription, Window,
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
                let mouse_shared = self.shared.clone();
                v_flex()
                    .id("lui-root-scroll")
                    .size_full()
                    .overflow_y_scroll()
                    .bg(cx.theme().background)
                    .text_color(cx.theme().foreground)
                    .font_family(cx.theme().font_family.clone())
                    .track_focus(&focus)
                    .on_key_down(move |ev: &KeyDownEvent, window, cx| {
                        if ev.is_held {
                            return;
                        }
                        // A focused text input (block editor, cmdk field)
                        // already receives text through its registered
                        // input handler — forwarding the same key as a
                        // document keydown would double-insert it, and
                        // native targets can't carry a `.ed-input` target
                        // for the document handler to recognize. Named
                        // keys are different: gpui reports Enter/Tab/
                        // Escape as control-char key_chars, the input
                        // never treats them as text, and document
                        // listeners (palette Enter/arrows, editor Esc)
                        // expect them — only printable key_chars are
                        // suppressed.
                        let text_char = ev
                            .keystroke
                            .key_char
                            .as_deref()
                            .is_some_and(|s| s.chars().all(|c| !c.is_control()));
                        if text_char
                            && !ev.keystroke.modifiers.platform
                            && !ev.keystroke.modifiers.control
                            && window.focused(cx).is_some()
                            && !focus.is_focused(window)
                        {
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
                    // Web parity: document `mousedown`/`click` listeners see
                    // every pointer press, whatever it lands on — dom.rs only
                    // wires element handlers for nodes that declared `click`,
                    // so forward both phases from a window-level observer
                    // (the same mechanism the editor conduit uses; element
                    // `.on_mouse_*` listeners never reach this root through
                    // gpui's hit dispatch). OCaml's 60ms coalescing drops the
                    // duplicate when a wired `click` also fires.
                    .child(
                        canvas(
                            |_, _, _| {},
                            move |_bounds, _, window, _cx| {
                                let down_shared = mouse_shared.clone();
                                window.on_mouse_event(
                                    move |event: &MouseDownEvent, phase, _window, cx| {
                                        if phase != DispatchPhase::Capture
                                            || event.button != MouseButton::Left
                                        {
                                            return;
                                        }
                                        let Some(hit) = crate::dom::deepest_hit(
                                            &down_shared,
                                            event.position,
                                        ) else {
                                            return;
                                        };
                                        let Some((carrier, ident)) =
                                            crate::dom::logseq_carrier(
                                                &down_shared,
                                                Some(hit),
                                            )
                                        else {
                                            return;
                                        };
                                        let position = event.position;
                                        crate::dom::dom_event_via(
                                            &down_shared,
                                            carrier,
                                            &ident,
                                            hit,
                                            "mousedown",
                                            serde_json::json!({
                                                "clientX": f64::from(position.x),
                                                "clientY": f64::from(position.y),
                                            }),
                                            cx,
                                        );
                                    },
                                );
                                let up_shared = mouse_shared.clone();
                                window.on_mouse_event(
                                    move |event: &MouseUpEvent, phase, _window, cx| {
                                        if phase != DispatchPhase::Capture
                                            || event.button != MouseButton::Left
                                        {
                                            return;
                                        }
                                        let Some(hit) = crate::dom::deepest_hit(
                                            &up_shared,
                                            event.position,
                                        ) else {
                                            return;
                                        };
                                        let Some((carrier, ident)) =
                                            crate::dom::logseq_carrier(
                                                &up_shared,
                                                Some(hit),
                                            )
                                        else {
                                            return;
                                        };
                                        let position = event.position;
                                        crate::dom::dom_event_via(
                                            &up_shared,
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
                                );
                            },
                        )
                        .absolute()
                        .size(px(1.)),
                    )
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
