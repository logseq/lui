//! Checkbox parts over NSH's unchanged controlled Checkbox behavior.
use super::{Theme, color, part};
use crate::{store::Node, style::ThemeView};
use nsh_core::{
    element::{ComponentElement, StyleRefinement},
    prelude::*,
};
use std::sync::Arc;

fn border(node: &Node, theme: &ThemeView, checked: bool) -> Result<AdaptiveColor, String> {
    let (property, fallback) = if checked {
        ("checked-indicator-border-color", "primary")
    } else {
        ("indicator-border-color", "border")
    };
    theme.color(
        node.props
            .get(property)
            .and_then(serde_json::Value::as_str)
            .unwrap_or(fallback),
    )
}

/// Resolve authored part colors in both transaction and environment preflight,
/// so an invalid scoped variable cannot fail after native state publication.
pub(crate) fn validate(node: &Node, theme: &ThemeView) -> Result<(), String> {
    if matches!(node.kind.as_str(), "checkbox" | "toggle") {
        border(node, theme, false)?;
        border(node, theme, true)?;
    }
    Ok(())
}

/// Project the native Checkbox owner's one proposal into each subscribed LUI
/// event. The toggle-detail mask has physical Alt in bit 3; pointer-detail
/// uses that bit for a secondary button and is a different contract.
pub(crate) fn event(
    id: u64,
    event: &nsh_base::CheckboxEvent,
) -> (&'static str, crate::render::Event) {
    use crate::render::Event;
    match event {
        nsh_base::CheckboxEvent::Change(checked) => ("toggle-enabled", Event::Toggle(id, *checked)),
        nsh_base::CheckboxEvent::ChangeDetail(detail) => (
            "toggle-detail-enabled",
            Event::ToggleDetail(
                id,
                detail.checked,
                i32::from(detail.control)
                    | (i32::from(detail.shift) << 1)
                    | (i32::from(detail.platform) << 2)
                    | (i32::from(detail.alt) << 3),
            ),
        ),
    }
}

pub(crate) fn element(
    props: nsh_base::CheckboxProps,
    theme: Theme,
    node: Signal<Arc<Node>>,
) -> ComponentElement<nsh_base::Checkbox> {
    let checked = props.checked;
    let mixed = props.indeterminate;
    nsh_base::Checkbox::element(nsh_base::CheckboxProps {
        indicator_class: Some("size-4 items-center justify-center rounded-sm border border-border checked:bg-primary checked:border-primary indeterminate:bg-primary indeterminate:border-primary".into()).into(),
        indicator_style: Prop::bind(move || {
            let node = node.get();
            let theme = theme.get();
            let unchecked = border(&node, &theme, false).expect("validated checkbox indicator color");
            let checked = border(&node, &theme, true).expect("validated checked indicator color");
            let background = theme.color("primary").expect("validated primary color");
            // These typed keys exist in every state, including initial false,
            // so native part bindings also update when props are added/removed.
            part(StyleRefinement::default()
                .border_color(unchecked)
                .checked(|s| s.bg(background).border_color(checked))
                .indeterminate(|s| s.bg(background).border_color(checked)))
        }),
        ..props
    })
        .fill("indicator", text(move || if mixed.get() { "−" } else if checked.get() { "✓" } else { "" })
            .text_xs().text_color(move || color(theme, "primary-foreground")))
        .flex_row()
        .items_center()
        .gap_2()
        .focus_visible(|s| s.border_1().border_color(move || color(theme, "ring")))
        .disabled_style(|s| s.opacity(0.5))
        // This is the same direct label child as before, without a new wrapper;
        // its opacity must not dim the indicator, mark or authored body children.
        .child(text(move || node.get().string("text").to_owned())
            .opacity(move || node.get().number("label-opacity", 1.0) as f32))
}

#[cfg(test)]
mod tests;
