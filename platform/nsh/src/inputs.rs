//! Canonical input policies over the retained public native Input.
use crate::{render::Event, store::Node};
use nsh_core::{SubmitBehavior, prelude::*};
use std::{cell::Cell, rc::Rc, sync::Arc};

pub(crate) fn validate(node: &Node) -> Result<(), String> {
    if node.kind == "input" && matches!(node.string("input-type"), "color" | "time") {
        return Err(format!(
            "NSH input-type={} is not implemented yet; use input-type=text for a text editor",
            node.string("input-type")
        ));
    }
    Ok(())
}

/// Keeps native Input's editing, composition, focus and submission behavior.
/// A textarea's explicit Enter policy changes only its native configuration.
pub(crate) fn attach(
    input: Input,
    node: Signal<Arc<Node>>,
    reference: ElementRef,
    emit: Rc<dyn Fn(Event)>,
) -> Input {
    let input = if node.get_untracked().kind == "textarea" {
        input.submit_behavior(move || {
            if node.get().boolean("submit-on-enter", false) {
                SubmitBehavior::Submit
            } else {
                SubmitBehavior::Newline
            }
        })
    } else {
        input
    };
    let initial = node.get_untracked();
    let authored_blur = initial.props.contains_key("submit-on-blur");
    let authored_navigation = initial.props.contains_key("navigate-enabled");
    if !authored_blur && !authored_navigation {
        // Ordinary Inputs allocate no additional policy state or observers.
        return input.on_submit(move |_: &str| {
            let node = node.get_untracked();
            if node.boolean("enabled", true) {
                emit(Event::Submit(node.id));
            }
        });
    }
    let blur = authored_blur.then(|| Rc::new(Cell::new(BlurState::default())));
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
    if let Some(blur) = &blur {
        let focused = blur.clone();
        let blurred = blur.clone();
        let blur_emit = emit.clone();
        input = input
            .on_focus(move || focused.set(BlurState::default()))
            .on_blur(move || {
                let before = blurred.replace(BlurState::default());
                let Some(node) = node.try_get() else { return };
                if node.boolean("enabled", true)
                    && node.boolean("submit-on-blur", false)
                    && !before.composing
                    && !before.suppress_native_blur
                {
                    blur_emit(Event::Submit(node.id));
                }
            });
    }
    input.on_submit(move |_: &str| {
        if composing.is_some_and(|composing| composing.try_get().unwrap_or(true))
            || blur.as_ref().is_some_and(|blur| blur.get().composing)
        {
            return;
        }
        let Some(node) = node.try_get() else { return };
        if let Some(blur) = &blur {
            let mut current = blur.get();
            // Single-line BlurAndSubmit emits SubmitEditing before Blur.
            // A textarea's later Blur remains a separate request.
            current.suppress_native_blur = node.kind != "textarea";
            blur.set(current);
        }
        if node.boolean("enabled", true) {
            emit(Event::Submit(node.id));
        }
    })
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

#[derive(Clone, Copy, Default)]
struct BlurState {
    suppress_native_blur: bool,
    composing: bool,
}

#[cfg(test)]
mod blur_tests;
#[cfg(test)]
mod navigation_tests;
