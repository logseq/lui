//! Window-level root view: mounts the LUI root node's entity.

use std::cell::OnceCell;

use gpui_kit::component::theme::ActiveTheme;
use gpui_kit::component::v_flex;
use gpui_kit::gpui::{
    canvas, div, px, App, Context, DispatchPhase, FocusHandle, InteractiveElement, IntoElement,
    MouseButton, MouseDownEvent, MouseUpEvent, ParentElement, Render,
    StatefulInteractiveElement, Styled, Subscription, Window,
};

use crate::backend::{LuiShared, Shared};

/// The view hosted inside `gpui_component::Root`. Renders the root node
/// entity or an empty screen while no root is
/// attached yet.
///
/// Owns a window-level FocusHandle so key events always have a dispatch
/// path: when nothing else is focused (browse mode) the root holds focus,
/// and a global keystroke observer forwards every keystroke to OCaml as a
/// `keydown` dom-event, matching the web document keydown that global
/// shortcuts and command dispatch listen on.
pub struct LuiRootView {
    pub shared: Shared,
    focus: OnceCell<FocusHandle>,
    /// Window appearance subscription (kept alive for the view's life):
    /// OS light/dark switches re-apply the registered gpui-component theme.
    appearance: OnceCell<Subscription>,
    /// Global keystroke observer (kept alive for the view's life):
    /// document `keydown` must fire for every keystroke, including ones
    /// a focused input consumes — the element-level `on_key_down` only
    /// sees keys in its own focus path.
    keystroke: OnceCell<Subscription>,
}

impl LuiRootView {
    pub fn new(shared: Shared) -> Self {
        LuiRootView {
            shared,
            focus: OnceCell::new(),
            appearance: OnceCell::new(),
            keystroke: OnceCell::new(),
        }
    }
}

/// Emit a document `keydown` dom event for one keystroke.
///
/// DOM parity: a document keydown targets the focused element
/// (document.activeElement). When a registered focusable holds focus
/// the event's target is that node, letting OCaml route editing vs.
/// browse-mode dispatch (`.ed-input` targets stay with the conduit,
/// everything else reaches the global keymap). With no focus — browse
/// mode — any extension node works: `emit_event` fans out to the
/// document listeners regardless.
fn emit_dom_keydown(
    shared: &Shared,
    ks: &gpui_kit::gpui::Keystroke,
    window: &mut Window,
    cx: &mut App,
) {
    // The carrier must be a `logseq-*` dom extension node — `dom-event`
    // is a logseq-dom convention; other extensions declare no `dom-event`
    // schema and OCaml rejects the payload as invalid. Clicks use the
    // same carrier walk (`dom::logseq_carrier`).
    let found = shared.borrow_mut().focused_node(window);
    let Some((node_id, identifier)) = crate::dom::logseq_carrier(shared, found) else {
        return;
    };
    let mods = ks.modifiers;
    // gpui reports named keys lowercase; DOM listeners match
    // KeyboardEvent.key spellings.
    let key = match ks.key.as_str() {
        "escape" => "Escape",
        "enter" | "return" => "Enter",
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
        shared,
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
        match root_id {
            Some(id) => {
                let view = LuiShared::view_for(&self.shared, id, cx);
                // The LUI root node is typically a plain column; other
                // backends get their outer scrolling from the host surface,
                // so the window root supplies it here.
                let mouse_shared = self.shared.clone();
                let keystroke_focus = focus.clone();
                self.keystroke.get_or_init(|| {
                    let keydown_shared = self.shared.clone();
                    cx.observe_keystrokes(move |_this, ev, window, cx| {
                        // A focused text input (block editor, cmdk field)
                        // already receives text through its registered
                        // input handler — forwarding the same key as a
                        // document keydown would double-insert it. Named
                        // keys are different: gpui reports Enter/Tab/
                        // Escape as control-char key_chars, the input
                        // never treats them as text, and document
                        // listeners (palette Enter/arrows, editor Esc)
                        // expect them — only printable key_chars are
                        // suppressed while a non-root element is focused.
                        let text_char = ev
                            .keystroke
                            .key_char
                            .as_deref()
                            .is_some_and(|s| s.chars().all(|c| !c.is_control()));
                        if text_char
                            && !ev.keystroke.modifiers.platform
                            && !ev.keystroke.modifiers.control
                            && window.focused(cx).is_some()
                            && !keystroke_focus.is_focused(window)
                        {
                            return;
                        }
                        // Host-side Escape dismisses the topmost open
                        // overlay — the web backend's `modal_key_handler`
                        // equivalent. The keydown still reaches document
                        // listeners below (web fires it too).
                        if ev.keystroke.key == "escape" {
                            crate::backend::dismiss_topmost_overlay(&keydown_shared, cx);
                        }
                        emit_dom_keydown(&keydown_shared, &ev.keystroke, window, cx);
                    })
                });
                v_flex()
                    .id("lui-root-scroll")
                    .size_full()
                    .overflow_y_scroll()
                    .bg(cx.theme().background)
                    .text_color(cx.theme().foreground)
                    .font_family(cx.theme().font_family.clone())
                    .track_focus(&focus)
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
                                            || !matches!(
                                                event.button,
                                                MouseButton::Left | MouseButton::Right
                                            )
                                        {
                                            return;
                                        }
                                        // No painted node under the point
                                        // still means a document click —
                                        // target the root so OCaml's
                                        // outside-editor blur/commit
                                        // handlers see it.
                                        let Some(hit) =
                                            crate::dom::deepest_hit(&down_shared, event.position)
                                                .or_else(|| {
                                                    down_shared.borrow().store.root
                                                })
                                        else {
                                            return;
                                        };
                                        let Some((carrier, ident)) =
                                            crate::dom::logseq_carrier(&down_shared, Some(hit))
                                        else {
                                            return;
                                        };
                                        let position = event.position;
                                        crate::dom::dom_event_via(
                                            &down_shared,
                                            carrier,
                                            &ident,
                                            hit,
                                            if event.button == MouseButton::Right {
                                                "contextmenu"
                                            } else {
                                                "mousedown"
                                            },
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
                                        let Some(hit) =
                                            crate::dom::deepest_hit(&up_shared, event.position)
                                                .or_else(|| up_shared.borrow().store.root)
                                        else {
                                            return;
                                        };
                                        let Some((carrier, ident)) =
                                            crate::dom::logseq_carrier(&up_shared, Some(hit))
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
