//! Menu-item presentation; NSH's MenuItem owns activation, focus and checks.
use super::{Theme, color, controls, icon, part, radius};
use nsh_core::{
    element::{ComponentElement, Style, StyleRefinement},
    prelude::*,
};
use std::rc::Rc;

pub(crate) struct Appearance {
    pub variant: Prop<SharedString>,
    pub preserve_foreground: Prop<bool>,
    pub size: Prop<SharedString>,
    pub selection_placement: Prop<SharedString>,
    pub icon: Prop<SharedString>,
    pub text: Prop<SharedString>,
    pub shortcut: Prop<SharedString>,
    pub content_style: Rc<dyn Fn() -> Style>,
}

pub(crate) fn element(
    props: nsh_base::MenuItemProps,
    theme: Theme,
    appearance: Appearance,
    children: AnyElement,
) -> ComponentElement<nsh_base::MenuItem> {
    let Appearance {
        variant,
        preserve_foreground,
        size,
        selection_placement,
        icon: glyph,
        text: label,
        shortcut,
        content_style,
    } = appearance;
    let checked = props.checked;
    let indicator = props.indicator_style;
    let element = controls::choice(
        nsh_base::MenuItem::element(nsh_base::MenuItemProps {
            indicator_style: Prop::bind(move || {
                // Keep the same typed keys in both states: the native part binds
                // them from its initial style, including an initially absent check.
                let style = StyleRefinement::default()
                    .size(controls::command_icon_extent(size.get().as_ref()))
                    .flex_shrink_0()
                    .opacity(0.0)
                    .checked(|style| style.opacity(1.0));
                let style = if checked.get().is_some() {
                    style.flex()
                } else {
                    style.hidden()
                };
                part(style).then(&indicator.get())
            }),
            ..props
        }),
        theme,
    )
    .rounded(move || radius(theme))
    .style_with(move |_| {
        let mut style = controls::command_size(size.get().as_ref());
        style = match selection_placement.get().as_ref() {
            "leading" => style.flex_row(),
            "top" => style.flex_col(),
            _ => style.flex_row_reverse(),
        };
        let variant = variant.get();
        let style = match variant.as_ref() {
            "primary" => style
                .bg(color(theme, "primary"))
                .text_color(color(theme, "primary-foreground")),
            "secondary" => style
                .bg(color(theme, "secondary"))
                .text_color(color(theme, "secondary-foreground")),
            "outline" => style
                .border_1()
                .border_color(color(theme, "border"))
                .text_color(color(theme, "foreground")),
            "destructive" => style.text_color(color(theme, "destructive")),
            _ => style.text_color(color(theme, "foreground")),
        };
        let destructive = variant == "destructive";
        let authored_foreground = preserve_foreground.get();
        let mut style = style
            .hover(|style| {
                let style = style.bg(color(
                    theme,
                    if destructive { "destructive" } else { "accent" },
                )
                .opacity(if destructive { 0.1 } else { 1.0 }));
                if authored_foreground {
                    style
                } else {
                    style.text_color(color(
                        theme,
                        if destructive {
                            "destructive"
                        } else {
                            "accent-foreground"
                        },
                    ))
                }
            })
            .checked(|style| {
                let style = style.bg(color(theme, "accent"));
                // A default native state color must not beat an authored base
                // foreground solely because checked/hover is more specific.
                if authored_foreground {
                    style
                } else {
                    style.text_color(color(
                        theme,
                        if destructive {
                            "destructive"
                        } else {
                            "accent-foreground"
                        },
                    ))
                }
            });
        style.style().clone()
    });
    element
        .fill(
            "indicator",
            icon("check", move || {
                controls::command_icon_extent(size.get().as_ref())
            }),
        )
        .child(
            view()
                .flex_row()
                .items_center()
                .flex_auto()
                .min_w_0()
                .gap_2()
                .state_inline_style(move || content_style())
                .child(
                    icon(
                        move || glyph.get(),
                        move || controls::command_icon_extent(size.get().as_ref()),
                    )
                    .style_with(move |style| {
                        if glyph.get().is_empty() {
                            style.hidden()
                        } else {
                            style
                        }
                    }),
                )
                .child(
                    text(move || label.get())
                        .flex_auto()
                        .min_w_0()
                        .style_with(move |style| {
                            if label.get().is_empty() {
                                style.hidden()
                            } else {
                                style
                            }
                        }),
                )
                .child(children)
                .child(
                    text(move || shortcut.get())
                        .ml(auto())
                        .text_xs()
                        .flex_shrink_0()
                        .text_color(move || {
                            color(
                                theme,
                                if variant.get() == "destructive" {
                                    "destructive"
                                } else {
                                    "muted-foreground"
                                },
                            )
                        })
                        .style_with(move |style| {
                            if shortcut.get().is_empty() {
                                style.hidden()
                            } else {
                                style
                            }
                        }),
                ),
        )
}

#[cfg(test)]
#[path = "menu_item_tests.rs"]
mod tests;
