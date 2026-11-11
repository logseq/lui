//! Time segments and editing belong to public NSH TimeField; LUI owns source text.
use crate::{render::Event, store::Node, ui};
use chrono::{NaiveTime, Timelike};
use nsh_base::{HourCycle, TimeField, TimeFieldEvent, TimeFieldProps, TimeOfDay, TimePrecision};
use nsh_core::{
    element::ComponentElement,
    prelude::*,
};
use std::{cell::Cell, rc::Rc, sync::Arc};

type Emit = Rc<dyn Fn(Event)>;

fn value(text: &str) -> Result<(TimeOfDay, TimePrecision), String> {
    for (precision, format) in [
        (TimePrecision::Minute, "%H:%M"),
        (TimePrecision::Second, "%H:%M:%S"),
    ] {
        if let Ok(time) = NaiveTime::parse_from_str(text, format)
            && time.nanosecond() == 0
            && time.format(format).to_string() == text
        {
            return Ok((TimeOfDay(time), precision));
        }
    }
    Err("NSH time input requires nonempty 24-hour HH:MM or HH:MM:SS text".into())
}

fn text(time: TimeOfDay, precision: TimePrecision) -> String {
    time.0.format(precision.format(HourCycle::H23)).to_string()
}

pub(super) fn validate(node: &Node) -> Result<(), String> {
    value(node.string("text"))?;
    for flag in ["read-only", "autofocus", "navigate-enabled"] {
        if node.boolean(flag, false) {
            return Err(format!(
                "NSH TimeField does not expose {flag}; remove it from the time input"
            ));
        }
    }
    if !node.string("placeholder").is_empty() {
        return Err("NSH TimeField does not expose a placeholder".into());
    }
    Ok(())
}

pub(crate) fn element(
    node: Signal<Arc<Node>>,
    reference: ElementRef,
    emit: Emit,
    theme: ui::Theme,
) -> ComponentElement<TimeField> {
    // A single scalar projection prevents parsing again on unrelated style updates.
    let source_text = computed(move || node.get().string("text").to_owned());
    let source =
        computed(move || value(&source_text.get()).expect("atomically validated 24-hour time"));
    let focused = signal(false);
    let skip_blur = Rc::new(Cell::new(false));
    let entering_skip = skip_blur.clone();
    reference.on_focus_in(move || {
        entering_skip.set(false);
        focused.set(true);
    });
    let leaving = focused;
    let blur_skip = skip_blur.clone();
    let blur_emit = emit.clone();
    reference.on_focus_out(move || {
        let was_focused = leaving.get_untracked();
        leaving.set(false);
        let suppressed = blur_skip.replace(false);
        if !was_focused || suppressed {
            return;
        }
        let Some(node) = node.try_get() else { return };
        if node.boolean("enabled", true) && node.boolean("submit-on-blur", false) {
            blur_emit(Event::Submit(node.id));
        }
    });
    let submit = emit.clone();
    let active = computed(move || focused.get() && node.get().boolean("enabled", true));
    effect(move || {
        if !active.get() {
            return;
        }
        let submit = submit.clone();
        let skip_blur = skip_blur.clone();
        on_key_with(
            "enter",
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                repeat: false,
                for_focus: true,
                ..Default::default()
            },
            move |_| {
                let Some(node) = node.try_get() else { return };
                if !node.boolean("enabled", true) {
                    return;
                }
                // Match a single-line Input: submit first, then native blur once.
                skip_blur.set(true);
                dismiss_keyboard();
                submit(Event::Submit(node.id));
            },
        );
    });
    let change = emit;
    nsh_base::TimeField::element(TimeFieldProps {
        value: Prop::bind(move || Some(source.get().0)),
        precision: Prop::bind(move || source.get().1),
        disabled: Prop::bind(move || !node.get().boolean("enabled", true)),
        accessibility_label: Prop::bind(move || {
            let node = node.get();
            let label = node.string("accessibility-label");
            Some(
                if label.is_empty() {
                    node.string("label")
                } else {
                    label
                }
                .to_owned()
                .into(),
            )
        }),
        segment_class: Some(
            "rounded-sm px-0.5 focus:bg-accent focus:text-accent-foreground".into(),
        )
        .into(),
        segment_style: Prop::bind(move || {
            let mut style = view().focus(|style| {
                style
                    .bg(ui::color(theme, "accent"))
                    .text_color(ui::color(theme, "accent-foreground"))
            });
            style.style().clone().into()
        }),
        ..Default::default()
    })
    .min_h_8()
    .px_2()
    .py_1()
    .items_center()
    .rounded(move || ui::radius(theme))
    .border_1()
    .border_color(move || ui::color(theme, "input"))
    .bg(move || ui::color(theme, "background"))
    .text_color(move || ui::color(theme, "foreground"))
    .focus_within(|style| style.border_color(move || ui::color(theme, "ring")))
    .disabled_style(|style| style.opacity(0.5))
    .on_event(move |event: &TimeFieldEvent| {
        let TimeFieldEvent::Change(time) = event;
        let Some(current) = node.try_get() else {
            return;
        };
        if current.boolean("enabled", true) {
            change(Event::Text(
                current.id,
                text(*time, source.get_untracked().1),
            ));
        }
    })
}

#[cfg(test)]
mod tests;
