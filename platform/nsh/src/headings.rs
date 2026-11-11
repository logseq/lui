//! Native heading semantics and theme typography for the canonical text host.
use crate::store::Node;
use nsh_core::{element::Text, prelude::*};
use std::sync::Arc;

fn level(node: &Node) -> u32 {
    node.props
        .get("heading-level")
        .and_then(serde_json::Value::as_u64)
        .map_or(2, |level| {
            u32::try_from(level).expect("canonically validated heading level")
        })
}

pub(crate) fn element(node: Signal<Arc<Node>>) -> Text {
    text(move || SharedString::from(node.get().string("text").to_owned()))
        .role(AccessibilityRole::Header)
        .accessibility_level(move || level(&node.get()))
        .style_with(move |style| match level(&node.get()) {
            1 => style.text_3xl(),
            2 => style.text_2xl(),
            3 => style.text_xl(),
            4 => style.text_lg(),
            5 => style.text_base(),
            _ => style.text_sm(),
        })
        .font_weight(FontWeight::BOLD)
}
