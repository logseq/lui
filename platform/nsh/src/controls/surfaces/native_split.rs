//! Split delegates sizing, native capture and adjustable actions to NSH panels.
//! Source sizes are native wanted sizes; completed native resizes notify LUI.
use super::{Emit, Presentation, emit_flag, enabled, label};
use crate::{render::Event, store::Node, ui};
use nsh_core::{element::StyleRefinement, prelude::*};
use std::sync::Arc;

pub(super) fn validate(node: &Node) -> Result<(), String> {
    if node.children.len() != 2 {
        return Err("NSH split requires exactly two pane children".into());
    }
    if node.props.contains_key("value") {
        return Err("NSH split uses native absolute panel sizes; replace value with first-pane-width or omit sizing for equal native panels".into());
    }
    if node.boolean("pointer-enabled", false) {
        return Err("NSH split exposes native resize completion; place pointer enter/leave handlers on a surrounding LUI container".into());
    }
    if node.number("first-pane-width", 0.0) > f32::MAX as f64 {
        return Err("NSH split first-pane-width exceeds the native point range".into());
    }
    if node.props.contains_key("resize-handle-width") {
        return Err(
            "NSH split uses its native 9-point handle band; remove resize-handle-width".into(),
        );
    }
    if node.number("resize-handle-offset", 0.0) != 0.0 {
        return Err(
            "NSH split uses its native centered handle; remove resize-handle-offset".into(),
        );
    }
    if node.number("resize-duration", 0.0) != 0.0
        || node.props.contains_key("resize-easing")
        || node.props.contains_key("resize-origin")
    {
        return Err("NSH split uses native panel resizing without legacy resize-duration/easing/origin options".into());
    }
    Ok(())
}

pub(super) fn element(
    node: Signal<Arc<Node>>,
    emit: Emit,
    presentation: Presentation,
) -> AnyElement {
    let source = presentation
        .children
        .as_ref()
        .expect("split child renderer")
        .clone();
    let theme = presentation.theme;
    let id = node.get_untracked().id;
    let props = nsh_base::ResizablePanelGroupProps {
        disabled: Prop::bind(move || !enabled(node)),
        handle_accessibility_label: Prop::bind(move || {
            let name = label(node);
            Some(if name.is_empty() {
                "Split divider".into()
            } else {
                format!("{name} divider").into()
            })
        }),
        handle_style: Prop::bind(move || {
            ui::part(
                StyleRefinement::default()
                    .bg(ui::color(theme, "border"))
                    .group_hover(|style| style.bg(ui::color(theme, "primary")))
                    .group_active(|style| style.bg(ui::color(theme, "primary"))),
            )
        }),
        ..Default::default()
    };
    presentation.component(nsh_base::ResizablePanelGroup::element(props).child(each(
        source.identities,
        |identity| *identity,
        move |identity, index| {
            let identity = identity.get_untracked();
            let child = (source.lookup)(identity);
            let notify = emit.clone();
            nsh_base::ResizablePanel::element(nsh_base::ResizablePanelProps {
                size: Prop::bind(move || {
                    if index.get() != 0 {
                        return None;
                    }
                    node.get()
                        .props
                        .get("first-pane-width")
                        .and_then(serde_json::Value::as_f64)
                        .map(|width| px(width as f32))
                }),
                min_size: Prop::bind(move || {
                    child.map_or(nsh_base::PANEL_MIN_SIZE, |child| {
                        px(child
                            .get()
                            .number("min-width", nsh_base::PANEL_MIN_SIZE.0 as f64)
                            as f32)
                    })
                }),
                max_size: Prop::bind(move || {
                    child.and_then(|child| {
                        child
                            .get()
                            .props
                            .get("max-width")
                            .and_then(serde_json::Value::as_f64)
                            .map(|width| px(width as f32))
                    })
                }),
                ..Default::default()
            })
            .on_event(move |event: &nsh_base::ResizablePanelEvent| {
                let nsh_base::ResizablePanelEvent::Resize(size) = event;
                if index.get_untracked() == 0 {
                    emit_flag(
                        node,
                        "change-enabled",
                        &notify,
                        Event::Value(id, size.0 as f64),
                    );
                }
            })
            .test_id(&format!("lui-{id}-split-pane-{}", identity.0))
            .child((source.render)(identity))
        },
    )))
}

#[cfg(test)]
mod tests;
