//! Canonical input policies over the retained public native Input.
use crate::{contract::InputTypeValue, render::Event, store::Node};

use nsh_core::{SubmitBehavior, prelude::*};
use std::{cell::Cell, rc::Rc, sync::Arc};

pub(crate) mod time;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum NativeInputKind {
    Text,
    Time,
}

fn lower_input_type(value: InputTypeValue) -> Result<NativeInputKind, String> {
    match value {
        InputTypeValue::Text => Ok(NativeInputKind::Text),
        InputTypeValue::Time => Ok(NativeInputKind::Time),
        InputTypeValue::Color => Err("NSH input-type=color is not implemented yet".into()),
    }
}

fn input_kind(node: &Node) -> Result<NativeInputKind, String> {
    let value = match node.props.get("input-type") {
        None => InputTypeValue::Text,
        Some(value) => {
            InputTypeValue::try_from(value.as_str().ok_or("NSH input-type requires a string")?)?
        }
    };
    lower_input_type(value)
}

pub(crate) fn is_time(node: &Node) -> bool {
    node.kind == "input"
        && input_kind(node).expect("atomically validated input type") == NativeInputKind::Time
}

pub(crate) fn validate(node: &Node) -> Result<(), String> {
    if node.kind == "input" && input_kind(node)? == NativeInputKind::Time {
        time::validate(node)?;
    }
    Ok(())
}

/// Literal target probes can know options without knowing the live text value.
pub(crate) fn validate_capabilities(node: &Node) -> Result<(), String> {
    if node.kind == "input" && input_kind(node)? == NativeInputKind::Time {
        time::validate_capabilities(node)?;
    }
    Ok(())
}

pub(crate) fn validate_transition(previous: &Node, node: &Node) -> Result<(), String> {
    if node.kind == "input" && input_kind(previous)? != input_kind(node)? {
        return Err("NSH changing input-type while mounted requires a new keyed node".into());
    }
    Ok(())
}

/// Native Input owns editing and composition. Canonical single-line Submit
/// reports the event while retaining focus; the application may close its field.
/// A textarea's explicit Enter policy changes only its native configuration.
pub(crate) fn attach(
    input: Input,
    node: Signal<Arc<Node>>,
    reference: ElementRef,
    emit: Rc<dyn Fn(Event)>,
) -> Input {
    attach_with_cancel(input, node, reference, emit).0
}

/// The retained input's existing cancellation policy, shared with its popup.
/// Native focus watches belong to this input's owner, not the popup's lifetime.
#[derive(Clone)]
pub(crate) struct Cancellation {
    node: Signal<Arc<Node>>,
    focused: Rc<Cell<bool>>,
    state: Rc<Cell<BlurState>>,
    emit: Rc<dyn Fn(Event)>,
}
impl Cancellation {
    pub(crate) fn cancel(&self) -> bool {
        let Some(node) = self.node.try_get() else {
            return false;
        };
        if !self.focused.get()
            || !node.boolean("enabled", true)
            || !node.boolean("dismiss-enabled", false)
        {
            return false;
        }
        // A composing/already-canceled draft still owns this key. It must not
        // fall through to dismissing the surrounding popup instead.
        request_dismiss(&node, &self.state, &*self.emit);
        true
    }
}

pub(crate) fn attach_with_cancel(
    input: Input,
    node: Signal<Arc<Node>>,
    reference: ElementRef,
    emit: Rc<dyn Fn(Event)>,
) -> (Input, Option<Cancellation>) {
    let input = if node.get_untracked().kind == "textarea" {
        input.submit_behavior(move || {
            if node.get().boolean("submit-on-enter", false) {
                SubmitBehavior::Submit
            } else {
                SubmitBehavior::Newline
            }
        })
    } else {
        input.submit_behavior(SubmitBehavior::Submit)
    };
    let initial = node.get_untracked();
    let authored_blur = initial.props.contains_key("submit-on-blur");
    let authored_navigation = initial.props.contains_key("navigate-enabled");
    let authored_dismiss = initial.props.contains_key("dismiss-enabled");
    let blur =
        (authored_blur || authored_dismiss).then(|| Rc::new(Cell::new(BlurState::default())));
    let changed_blur = blur.clone();
    let changed_emit = emit.clone();
    let input = input.on_change(move |value: &str| {
        let Some(node) = node.try_get() else { return };
        if !node.boolean("enabled", true) {
            return;
        }
        if let Some(blur) = &changed_blur {
            let mut current = blur.get();
            // A genuine native edit begins a new draft before application
            // dispatch. Controlled value patches never call this listener.
            current.suppress_native_blur = false;
            current.dismissed = false;
            blur.set(current);
        }
        changed_emit(Event::Text(node.id, value.into()));
    });
    if !authored_blur && !authored_navigation && !authored_dismiss {
        // Ordinary Inputs allocate no additional policy state or observers.
        return (
            input.on_submit(move |_: &str| {
                let node = node.get_untracked();
                if node.boolean("enabled", true) {
                    emit(Event::Submit(node.id));
                }
            }),
            None,
        );
    }
    let composing = authored_navigation.then(|| signal(false));
    if let Some(composing) = composing {
        navigation(node, reference, composing, emit.clone());
    }
    let composition_blur = blur.clone();
    let mut input = input.on_composition_change(move |event: &Composition| {
        if let Some(blur) = &composition_blur {
            let mut current = blur.get();
            current.composing = event.composing;
            blur.set(current);
        }
        if let Some(composing) = composing {
            composing.set(event.composing);
        }
    });
    let cancellation = if authored_dismiss {
        let focused = Rc::new(Cell::new(false));
        let entered = focused.clone();
        reference.on_focus_in(move || entered.set(true));
        let left = focused.clone();
        reference.on_focus_out(move || left.set(false));
        Some(Cancellation {
            node,
            focused,
            state: blur.clone().expect("authored cancellation owns blur state"),
            emit: emit.clone(),
        })
    } else {
        None
    };
    if authored_dismiss {
        let dismiss_state = blur.clone().expect("authored cancellation owns blur state");
        let dismiss_emit = emit.clone();
        input = input.on_key_press(move |key: &str| {
            if key != "Escape" {
                return;
            }
            let Some(node) = node.try_get() else { return };
            request_dismiss(&node, &dismiss_state, &*dismiss_emit);
        });
    }
    if let Some(blur) = &blur {
        let focused = blur.clone();
        let blurred = blur.clone();
        let blur_emit = emit.clone();
        input = input
            .on_focus(move || focused.set(BlurState::default()))
            .on_blur(move || {
                let before = blurred.get();
                // Blur consumes Enter deduplication, but canceled drafts stay
                // closed to late Submit until new focus or a genuine edit.
                blurred.set(BlurState {
                    dismissed: before.dismissed,
                    ..BlurState::default()
                });
                let Some(node) = node.try_get() else { return };
                if submits_on_blur(&node, before) {
                    blur_emit(Event::Submit(node.id));
                }
            });
    }
    (
        input.on_submit(move |_: &str| {
            if composing.is_some_and(|composing| composing.try_get().unwrap_or(true))
                || blur.as_ref().is_some_and(|blur| {
                    let state = blur.get();
                    state.composing || state.dismissed
                })
            {
                return;
            }
            let Some(node) = node.try_get() else { return };
            if let Some(blur) = &blur {
                let mut current = blur.get();
                // An unchanged single-line draft must not submit twice when a
                // later explicit Blur follows Enter. A real edit rearms it.
                // A textarea's later Blur remains a separate request.
                current.suppress_native_blur = node.kind != "textarea";
                blur.set(current);
            }
            if node.boolean("enabled", true) {
                emit(Event::Submit(node.id));
            }
        }),
        cancellation,
    )
}

/// Bind only the focused editor's own unmodified arrows. This is the public
/// effect-owned key lifetime used by NSH's own Combobox, not a permanent window
/// binding whose handler would consume keys intended for a different editor.
fn navigation(
    node: Signal<Arc<Node>>,
    reference: ElementRef,
    composing: Signal<bool>,
    emit: Rc<dyn Fn(Event)>,
) {
    let focused = signal(false);
    reference.on_focus_in(move || focused.set(true));
    reference.on_focus_out(move || focused.set(false));
    let active = computed(move || {
        focused.get()
            && !composing.get()
            && node.with(|node| {
                node.boolean("enabled", true) && node.boolean("navigate-enabled", false)
            })
    });
    effect(move || {
        if !active.get() {
            return;
        }
        for (key, previous) in [("up", true), ("down", false)] {
            let emit = emit.clone();
            on_key_with(
                key,
                KeyOptions {
                    when: nsh_core::keymap::When::Always,
                    repeat: true,
                    for_focus: true,
                    ..Default::default()
                },
                move |_| {
                    if active.try_get() != Some(true) {
                        return;
                    }
                    let Some(node) = node.try_get() else { return };
                    emit(if previous {
                        Event::NavigatePrevious(node.id)
                    } else {
                        Event::NavigateNext(node.id)
                    });
                },
            );
        }
    });
}

fn submits_on_blur(node: &Node, before: BlurState) -> bool {
    node.boolean("enabled", true)
        && node.boolean("submit-on-blur", false)
        && !before.composing
        && !before.suppress_native_blur
        && !before.dismissed
}

// Shared with policy tests: Headless does not synthesize native input Escape.
fn request_dismiss(node: &Node, state: &Cell<BlurState>, emit: &dyn Fn(Event)) {
    let mut current = state.get();
    if !node.boolean("enabled", true)
        || !node.boolean("dismiss-enabled", false)
        || current.composing
        || current.dismissed
    {
        return;
    }
    // Native cancellation precedes Blur. Install suppression before application
    // dispatch, which may retire this input immediately.
    current.suppress_native_blur = true;
    current.dismissed = true;
    state.set(current);
    emit(Event::Dismiss(node.id));
}

#[derive(Clone, Copy, Default)]
struct BlurState {
    suppress_native_blur: bool,
    dismissed: bool,
    composing: bool,
}

#[cfg(test)]
mod blur_tests;
#[cfg(test)]
mod navigation_tests;

#[cfg(test)]
mod dismiss_tests;
