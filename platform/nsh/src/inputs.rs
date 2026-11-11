//! Canonical input policies over the retained public native Input.
use crate::{render::Event, store::Node};
use nsh_core::{SubmitBehavior, prelude::*};
use std::{rc::Rc, sync::Arc};

pub(crate) fn validate(node: &Node) -> Result<(), String> {
    if matches!(
        node.kind.as_str(),
        "input" | "text-field" | "secure-field" | "search-field" | "textarea"
    ) {
        for property in ["navigate-enabled", "submit-on-blur"] {
            if node.boolean(property, false) {
                return Err(format!(
                    "NSH text-control {property}=true is not implemented yet; native Input owns editing and submission"
                ));
            }
        }
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
    input.on_submit(move |_: &str| {
        let node = node.get_untracked();
        if node.boolean("enabled", true) {
            emit(Event::Submit(node.id));
        }
    })
}
