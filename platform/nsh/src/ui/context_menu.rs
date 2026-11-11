//! Context-menu parts share the existing scoped popup tokens.
use crate::style::ThemeView;
use nsh_core::{
    element::{ComponentElement, Style, StyleRefinement},
    prelude::*,
};
use std::{rc::Rc, sync::Arc};

pub(crate) type Theme = Rc<dyn Fn() -> Arc<ThemeView>>;

pub(crate) fn styled(
    props: nsh_base::ContextMenuProps,
    theme: Theme,
) -> ComponentElement<nsh_base::ContextMenu> {
    nsh_base::ContextMenu::element(nsh_base::ContextMenuProps {
        popup_class: Some("p-1 gap-1 border rounded-(--radius)".into()).into(),
        popup_style: popup_style(theme),
        ..props
    })
}

/// Buttons use the primary menu behavior already expected by LUI applications.
pub(crate) fn primary(
    props: nsh_base::MenuProps,
    theme: Theme,
) -> ComponentElement<nsh_base::Menu> {
    nsh_base::Menu::element(nsh_base::MenuProps {
        popup_class: Some("p-1 gap-1 border rounded-(--radius)".into()).into(),
        popup_style: popup_style(theme),
        ..props
    })
}

fn popup_style(theme: Theme) -> Prop<Style> {
    Prop::bind(move || {
        let theme = theme();
        super::part(
            StyleRefinement::default()
                .bg(theme
                    .color("popover")
                    .expect("validated context-menu theme"))
                .text_color(
                    theme
                        .color("popover-foreground")
                        .expect("validated context-menu theme"),
                )
                .border_color(theme.color("border").expect("validated context-menu theme"))
                .rounded(theme.radius().expect("validated context-menu radius")),
        )
    })
}
