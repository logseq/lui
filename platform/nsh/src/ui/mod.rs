//! Shared desktop presentation. Explicit LUI node styles override these defaults.
pub(crate) mod checkbox;
pub(crate) mod context_menu;
pub(crate) mod controls;
mod icons;
pub(crate) mod menu_item;
pub(crate) use checkbox::{element as checkbox, event as checkbox_event};

use crate::style::ThemeView;
use nsh_core::{
    element::{ComponentElement, Input, StyleRefinement},
    prelude::*,
};
use std::sync::Arc;

pub fn button(props: nsh_base::ButtonProps, theme: Theme) -> ComponentElement<nsh_base::Button> {
    nsh_base::Button::element(props)
        .px_3()
        .py_2()
        .rounded(move || radius(theme))
        .bg(move || color(theme, "secondary"))
        .text_color(move || color(theme, "secondary-foreground"))
        .hover(|s| s.bg(move || color(theme, "accent")))
        .active(|s| s.opacity(0.7))
        .focus_visible(|s| s.border_1().border_color(move || color(theme, "ring")))
        .disabled_style(|s| s.opacity(0.5))
}

/// Decorative icons inherit the surrounding command's semantic foreground.
pub(crate) fn icon(
    name: impl IntoReactive<SharedString>,
    extent: impl IntoReactive<Points>,
) -> nsh_core::element::Svg {
    let name = name.into_reactive();
    let registry = use_context::<crate::application_icons::IconRegistry>();
    let source = computed(move || {
        let name = name.get();
        registry
            .as_ref()
            .and_then(|registry| registry.source(&name))
            .unwrap_or_else(|| icons::source(name.strip_prefix("app:").unwrap_or(&name)))
    });
    let extent = extent.into_reactive();
    let height = extent.clone();
    svg(move || source.get())
        .w(move || extent.get())
        .h(move || height.get())
        .flex_shrink_0()
        .accessibility_elements_hidden(true)
}

/// Menu supplies activation and keyboard navigation to this public trigger
/// slot. A second Button controller would put focus below that slot.
pub(crate) fn menu_trigger(theme: Theme) -> View {
    view()
        .role(AccessibilityRole::Button)
        .px_3()
        .py_2()
        .rounded(move || radius(theme))
        .bg(move || color(theme, "secondary"))
        .text_color(move || color(theme, "secondary-foreground"))
        .hover(|s| s.bg(move || color(theme, "accent")))
        .active(|s| s.opacity(0.7))
        .focus_visible(|s| {
            s.outline(px(2.0))
                .outline_color(move || color(theme, "ring"))
        })
        .disabled_style(|s| s.opacity(0.5))
}

pub fn input(theme: Theme) -> Input {
    nsh_base::input()
        .min_h_8()
        .px_2()
        .py_1()
        .rounded(move || radius(theme))
        .border_1()
        .border_color(move || color(theme, "input"))
        .bg(move || color(theme, "background"))
        .text_color(move || color(theme, "foreground"))
        .focus(|s| s.border_color(move || color(theme, "ring")))
        .disabled_style(|s| s.opacity(0.5))
}

pub(crate) type Theme = Signal<Arc<ThemeView>>;

pub(crate) fn color(theme: Theme, role: &str) -> AdaptiveColor {
    theme
        .get()
        .color(role)
        .expect("atomically validated scoped theme color")
}
pub(crate) fn radius(theme: Theme) -> Points {
    theme
        .get()
        .radius()
        .expect("atomically validated scoped theme radius")
}
pub(crate) fn part(style: StyleRefinement) -> nsh_core::element::Style {
    style.into()
}
