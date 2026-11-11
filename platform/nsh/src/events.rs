//! Native host event bindings and the existing canonical pointer payload.
use crate::{contract, render::Event, store::Node};
use nsh_core::{
    ContextMenuEvent, MouseButton, PressEvent, TouchPhase,
    element::{Element, Interactive, after_answer},
    geometry::{Point, Points},
    keymap::Modifiers,
    prelude::*,
};
use std::{cell::Cell, rc::Rc, sync::Arc};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum PointerKind {
    PressDetail,
    Down,
    Up,
    Move,
    Cancel,
    ContextMenu,
}
impl PointerKind {
    pub(crate) fn name(self) -> &'static str {
        match self {
            Self::PressDetail => "press-detail",
            Self::Down => "pointer-down",
            Self::Up => "pointer-up",
            Self::Move => "pointer-move",
            Self::Cancel => "pointer-cancel",
            Self::ContextMenu => "context-menu-press",
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct PointerDetail {
    pub x: f64,
    pub y: f64,
    pub modifiers: i32,
    pub button: i32,
    pub target_class: String,
}

/// Layout-owned visibility, inherited through existing reactive owners. The
/// lifetime guard makes pending callbacks safe after a keyed row is disposed.
#[derive(Clone)]
pub(crate) struct VisibilityScope(Rc<dyn Fn() -> bool>);
impl VisibilityScope {
    fn visible(&self) -> bool {
        (self.0)()
    }
}

pub(crate) fn scope_visibility(visible: impl Fn() -> bool + 'static) {
    let parent = use_context::<VisibilityScope>();
    let active = Rc::new(Cell::new(true));
    let cleanup_active = active.clone();
    cleanup(move || cleanup_active.set(false));
    let shown = computed(move || parent.as_ref().is_none_or(VisibilityScope::visible) && visible());
    provide_context(VisibilityScope(Rc::new(move || {
        active.get() && shown.get()
    })));
}

#[derive(Clone, Copy, Default)]
pub(crate) struct Capabilities(u8);
impl Capabilities {
    pub(crate) fn authored(node: &Node) -> Self {
        let mut value = 0;
        for (bit, flag) in [
            "press-enabled",
            "pointer-enabled",
            "long-press-enabled",
            "double-press-enabled",
        ]
        .iter()
        .enumerate()
        {
            if node.boolean(flag, false) {
                value |= 1 << bit;
            }
        }
        if node.props.contains_key("submit-on-blur") {
            value |= 1 << 4;
        }
        if matches!(
            node.kind.as_str(),
            "input" | "text-field" | "secure-field" | "search-field" | "textarea" | "combobox"
        ) && node.props.contains_key("navigate-enabled")
        {
            value |= 1 << 5;
        }
        Self(value)
    }
    /// A false later value requires no observer. Remembering actual installed
    /// capacity separately prevents absent -> false -> true from bypassing it.
    pub(crate) fn required(node: &Node) -> Self {
        let mut required = Self::authored(node);
        if !node.boolean("submit-on-blur", false) {
            required.0 &= !(1 << 4);
        }
        if !node.boolean("navigate-enabled", false) {
            required.0 &= !(1 << 5);
        }
        required
    }
    pub(crate) fn contains(self, other: Self) -> bool {
        self.0 & other.0 == other.0
    }
}

pub(crate) fn modifiers(keys: Modifiers, secondary: bool) -> i32 {
    i32::from(keys.ctrl)
        | (i32::from(keys.shift) << 1)
        | (i32::from(keys.cmd) << 2)
        | (i32::from(secondary) << 3)
}
fn detail(position: Point<Points>, keys: Modifiers, button: Option<MouseButton>) -> PointerDetail {
    PointerDetail {
        x: f64::from(position.x.0),
        y: f64::from(position.y.0),
        modifiers: modifiers(keys, button == Some(MouseButton::Right)),
        button: match button {
            None | Some(MouseButton::Left) => 0,
            Some(MouseButton::Middle) => 1,
            Some(MouseButton::Right) => 2,
            Some(MouseButton::Back) => 3,
            Some(MouseButton::Forward) => 4,
        },
        // This is a native surface, so there is no DOM target class.
        target_class: String::new(),
    }
}

#[derive(Clone)]
pub(crate) struct NativeEvents {
    node: Signal<Arc<Node>>,
    notify: Rc<dyn Fn(Event)>,
    installed: Rc<Cell<Option<Capabilities>>>,
    current: Rc<dyn Fn() -> bool>,
    visibility: Option<VisibilityScope>,
    press_snapshot: Rc<Cell<Option<PressEvent>>>,
}
impl NativeEvents {
    pub(crate) fn new(
        node: Signal<Arc<Node>>,
        notify: Rc<dyn Fn(Event)>,
        installed: Rc<Cell<Option<Capabilities>>>,
        current: Rc<dyn Fn() -> bool>,
        visibility: Option<VisibilityScope>,
    ) -> Self {
        Self {
            node,
            notify,
            installed,
            current,
            visibility,
            press_snapshot: Rc::new(Cell::new(None)),
        }
    }
    /// A native Menu owns trigger activation. Its unit event consumes the
    /// native payload observed on that same host, without activating it twice.
    pub(crate) fn semantic(&self, event: Event) {
        if !(self.current)() {
            return;
        }
        if let Event::Press(id) = event {
            let press = self.press_snapshot.take();
            let mask = press.map_or(0, |press| modifiers(press.modifiers, false));
            (self.notify)(if mask == 0 {
                Event::Press(id)
            } else {
                Event::NativePress(id, mask)
            });
            if let Some(press) = press {
                self.pointer(
                    PointerKind::PressDetail,
                    detail(press.page_position, press.modifiers, None),
                );
            }
        } else {
            (self.notify)(event);
        }
    }
    fn accepts(&self, flag: &str, event: &str) -> bool {
        if !(self.current)() {
            return false;
        }
        let node = self.node.get_untracked();
        (matches!(event, "appear" | "focus-within-changed") || node.boolean("enabled", true))
            && node.boolean(flag, false)
            && contract::event_supported(&node.kind, event)
    }
    fn pointer(&self, kind: PointerKind, detail: PointerDetail) {
        if self.accepts("pointer-enabled", kind.name()) {
            (self.notify)(Event::Pointer {
                node: self.node.get_untracked().id,
                kind,
                detail,
            });
        }
    }
    pub(crate) fn appear(&self, reference: ElementRef) {
        if !self.node.get_untracked().boolean("appear-enabled", false) {
            return;
        }
        if self.visibility.is_none() {
            let events = self.clone();
            after_answer(move || {
                if (events.current)()
                    && reference.node().is_some()
                    && events.accepts("appear-enabled", "appear")
                {
                    (events.notify)(Event::Appear(events.node.get_untracked().id));
                }
            });
            return;
        }
        let events = self.clone();
        let was_visible = Rc::new(Cell::new(false));
        let revision = Rc::new(Cell::new(0_u64));
        effect(move || {
            let visible = events
                .visibility
                .as_ref()
                .is_none_or(VisibilityScope::visible);
            if was_visible.replace(visible) == visible {
                return;
            }
            let next = revision
                .get()
                .checked_add(1)
                .expect("appearance transition counter exhausted");
            revision.set(next);
            if !visible {
                return;
            }
            let events = events.clone();
            let revision = revision.clone();
            after_answer(move || {
                if revision.get() == next
                    && (events.current)()
                    && reference.node().is_some()
                    && events
                        .visibility
                        .as_ref()
                        .is_none_or(VisibilityScope::visible)
                    && events.accepts("appear-enabled", "appear")
                {
                    (events.notify)(Event::Appear(events.node.get_untracked().id));
                }
            });
        });
    }
    pub(crate) fn focus(&self, reference: ElementRef) {
        if !contract::event_supported(&self.node.get_untracked().kind, "focus-within-changed") {
            return;
        }
        let entered = self.clone();
        reference.on_focus_in(move || {
            if entered.accepts("focus-within-enabled", "focus-within-changed") {
                (entered.notify)(Event::Focus(entered.node.get_untracked().id));
            }
        });
        let left = self.clone();
        reference.on_focus_out(move || {
            if left.accepts("focus-within-enabled", "focus-within-changed") {
                (left.notify)(Event::Blur(left.node.get_untracked().id));
            }
        });
    }
    pub(crate) fn attach<E: Element + Interactive>(&self, mut element: E) -> E {
        let node = self.node.get_untracked();
        self.installed.set(Some(Capabilities::authored(&node)));
        let supports = |event| contract::event_supported(&node.kind, event);
        let picker_owned = matches!(node.kind.as_str(), "select" | "combobox" | "menu-trigger");
        if (node.boolean("press-enabled", false) && supports("press"))
            || (node.boolean("pointer-enabled", false) && supports("press-detail"))
            || (node.boolean("double-press-enabled", false) && supports("double-press"))
        {
            let events = self.clone();
            element = element.on_press(move |event: &PressEvent| {
                if !(events.current)() {
                    return;
                }
                let id = events.node.get_untracked().id;
                if picker_owned {
                    if !events.accepts("press-enabled", "press") {
                        events.press_snapshot.set(None);
                        events.pointer(
                            PointerKind::PressDetail,
                            detail(event.page_position, event.modifiers, None),
                        );
                        return;
                    }
                    events.press_snapshot.set(Some(*event));
                    let pending = events.press_snapshot.clone();
                    after_answer(move || pending.set(None));
                    return;
                }
                if events.accepts("press-enabled", "press") {
                    let mask = modifiers(event.modifiers, false);
                    (events.notify)(if mask == 0 {
                        Event::Press(id)
                    } else {
                        Event::NativePress(id, mask)
                    });
                }
                events.pointer(
                    PointerKind::PressDetail,
                    detail(event.page_position, event.modifiers, None),
                );
                if event.clicks == 2 && events.accepts("double-press-enabled", "double-press") {
                    (events.notify)(Event::DoublePress(id));
                }
            });
        }
        if node.boolean("long-press-enabled", false) && supports("long-press") {
            let events = self.clone();
            element = element.on_long_press(move |_: &PressEvent| {
                if events.accepts("long-press-enabled", "long-press") {
                    (events.notify)(Event::LongPress(events.node.get_untracked().id));
                }
            });
        }
        if node.boolean("pointer-enabled", false) {
            if supports("pointer-enter") {
                let events = self.clone();
                element = element.on_mouse_enter(move |_: &nsh_core::MouseEvent| {
                    if events.accepts("pointer-enabled", "pointer-enter") {
                        (events.notify)(Event::PointerEnter(events.node.get_untracked().id));
                    }
                });
            }
            if supports("pointer-leave") {
                let events = self.clone();
                element = element.on_mouse_leave(move |_: &nsh_core::MouseEvent| {
                    if events.accepts("pointer-enabled", "pointer-leave") {
                        (events.notify)(Event::PointerLeave(events.node.get_untracked().id));
                    }
                });
            }
            if supports("pointer-down") {
                let events = self.clone();
                element = element.on_press_down(move |event: &PressEvent| {
                    events.pointer(
                        PointerKind::Down,
                        detail(event.page_position, event.modifiers, None),
                    )
                });
            }
            if supports("pointer-up") {
                let events = self.clone();
                element = element.on_press_up(move |event: &PressEvent| {
                    events.pointer(
                        PointerKind::Up,
                        detail(event.page_position, event.modifiers, None),
                    )
                });
            }
            if supports("context-menu-press") {
                let events = self.clone();
                element = element.on_context_menu(move |event: &ContextMenuEvent| {
                    let button = (event.pointer_type == Some(nsh_core::PointerType::Mouse))
                        .then_some(MouseButton::Right);
                    events.pointer(
                        PointerKind::ContextMenu,
                        detail(event.page_position, event.modifiers, button),
                    );
                });
            }
            if supports("pointer-move") {
                let events = self.clone();
                element = element.on_mouse_move(move |event: &nsh_core::MouseEvent| {
                    events.pointer(
                        PointerKind::Move,
                        detail(event.page_position, event.modifiers, event.pressed_button),
                    )
                });
            }
            if supports("pointer-move") || supports("pointer-cancel") {
                let events = self.clone();
                element = element.on_touch(move |event: &nsh_core::TouchEvent| {
                    let kind = match event.phase {
                        TouchPhase::Move => PointerKind::Move,
                        TouchPhase::Cancel => PointerKind::Cancel,
                        _ => return,
                    };
                    for point in event.points.iter().filter(|point| point.changed) {
                        if event.phase == TouchPhase::Cancel
                            || point.pointer_type != nsh_core::PointerType::Mouse
                        {
                            events.pointer(kind, detail(point.page, Modifiers::default(), None));
                        }
                    }
                });
            }
        }
        element
    }
}

#[cfg(test)]
#[path = "events_tests.rs"]
mod tests;
