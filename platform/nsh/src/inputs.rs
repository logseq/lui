//! Canonical input policies over the retained public native Input.
use crate::{render::Event, store::Node};
use nsh_core::{SubmitBehavior, prelude::*};
use std::{cell::Cell, rc::Rc, sync::Arc};

pub(crate) fn validate(node: &Node) -> Result<(), String> {
    if matches!(
        node.kind.as_str(),
        "input" | "text-field" | "secure-field" | "search-field" | "textarea"
    ) && node.boolean("navigate-enabled", false)
    {
        return Err("NSH text-control navigate-enabled=true is not implemented yet; native Input owns editing and submission".into());
    }
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
pub(crate) fn attach(input: Input, node: Signal<Arc<Node>>, emit: Rc<dyn Fn(Event)>) -> Input {
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
    if !node.get_untracked().props.contains_key("submit-on-blur") {
        // Preserve the ordinary Input path: no focus/composition observers or
        // policy state are allocated unless this option was authored at mount.
        return input.on_submit(move |_: &str| {
            let node = node.get_untracked();
            if node.boolean("enabled", true) {
                emit(Event::Submit(node.id));
            }
        });
    }
    let state = Rc::new(Cell::new(BlurState::default()));
    let focused = state.clone();
    let composition = state.clone();
    let blurred = state.clone();
    let blur_emit = emit.clone();
    input
        .on_focus(move || focused.set(BlurState::default()))
        .on_composition_change(move |event: &Composition| {
            let mut current = composition.get();
            current.composing = event.composing;
            composition.set(current);
        })
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
        })
        .on_submit(move |_: &str| {
            let mut current = state.get();
            if current.composing {
                return;
            }
            let Some(node) = node.try_get() else { return };
            // Native single-line BlurAndSubmit sends SubmitEditing before Blur.
            // A textarea's Submit keeps focus, so its later blur is a separate
            // request even if the text has not changed in between.
            current.suppress_native_blur = node.kind != "textarea";
            state.set(current);
            if node.boolean("enabled", true) {
                emit(Event::Submit(node.id));
            }
        })
}

#[derive(Clone, Copy, Default)]
struct BlurState {
    suppress_native_blur: bool,
    composing: bool,
}

#[cfg(test)]
mod blur_tests;
