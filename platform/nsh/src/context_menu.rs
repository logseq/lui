//! Attached context menus reuse NSH's native controller and retained trigger.
use crate::{controls::ChildIdentity, style::ContextMenuStyles, ui};
use nsh_core::prelude::*;
use std::rc::Rc;

pub(crate) struct Attachment {
    pub primary: bool,
    pub source: Signal<Option<ChildIdentity>>,
    pub theme: ui::context_menu::Theme,
    pub disabled: Rc<dyn Fn() -> bool>,
    pub render: Rc<dyn Fn(ChildIdentity) -> AnyElement>,
    pub closed: Rc<dyn Fn(ChildIdentity)>,
    pub styles: Memo<ContextMenuStyles>,
    pub key: SharedString,
}

pub(crate) fn wrap(trigger: AnyElement, attachment: Attachment) -> AnyElement {
    let Attachment {
        primary,
        source,
        theme,
        disabled,
        render,
        closed,
        styles,
        key,
    } = attachment;
    macro_rules! attach {
        ($element:expr) => {
            $element
                // The public slot forwards refs and events to the existing
                // trigger. Native Menu/ContextMenu owns opening and focus.
                .fill("trigger", trigger)
                .child(dynamic(move || {
                    source.get().map(|identity| render(identity))
                }))
                .on_event(move |event: &nsh_base::MenuEvent| {
                    if matches!(event, nsh_base::MenuEvent::OpenChange(false, _))
                        && let Some(identity) = source.get_untracked()
                    {
                        closed(identity);
                    }
                })
                .state_inline_style(move || styles.get().outer)
                .key(key)
                .into_element()
        };
    }
    if primary {
        attach!(ui::context_menu::primary(
            nsh_base::MenuProps {
                // An explicit disabled attachment temporarily closes the native
                // controller; otherwise Menu retains its own uncontrolled state.
                open: Prop::bind(move || disabled().then_some(false)),
                ..Default::default()
            },
            theme,
        ))
    } else {
        attach!(ui::context_menu::styled(
            nsh_base::ContextMenuProps {
                disabled: Prop::bind(move || disabled()),
                ..Default::default()
            },
            theme,
        ))
    }
}
