//! Extension visual host: how `create-extension` nodes render.
//!
//! Identifier namespaces (ADR 0002): extensions are app-scoped, kebab-case.
//! `gpui-*` is reserved for gpui-specific components — apps register a
//! specialized [`ExtensionRenderer`] per identifier on `LuiShared`, or fall
//! back to the generic host below (children in a labeled container).

use gpui_kit::component::theme::ActiveTheme;
use gpui_kit::component::v_flex;
use gpui_kit::gpui::{div, AnyElement, Context, IntoElement, ParentElement, Styled, Window};
use lui_core::store::NodeIdentity;
use lui_core::Property;

use crate::node_view::{LuiNodeView, NodeSnapshot};
use crate::style;

/// Renders one extension node into an element. Registered per identifier on
/// `LuiShared::extension_renderers`; takes the owning view (for child entity
/// embedding) and the node snapshot.
pub type ExtensionRenderer = for<'a, 'b, 'c> fn(
    &mut LuiNodeView,
    &NodeSnapshot,
    &mut Window,
    &mut Context<LuiNodeView>,
) -> AnyElement;

pub fn render(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let NodeIdentity::Extension { identifier, .. } = &node.identity else {
        return div().into_any_element();
    };
    let identifier = identifier.clone();

    // A registered specialized renderer wins (this is how `gpui-*`
    // components plug in).
    let renderer = view
        .shared
        .borrow()
        .extension_renderers
        .get(&identifier)
        .copied();
    if let Some(render_extension) = renderer {
        return render_extension(view, node, window, cx);
    }

    let spec = view
        .shared
        .borrow()
        .registry
        .get(&identifier)
        .map(|spec| spec.flavor);

    let children = view.child_elements(node, cx);
    match spec {
        // ADR 0003 tweaks wrap their child with platform behaviour; the
        // generic host passes the child through unchanged.
        Some(lui_core::extension::ExtensionFlavor::Tweak) if children.len() == 1 => {
            children.into_iter().next().unwrap()
        }
        _ => {
            // Generic host: visible frame so unimplemented extensions are
            // never silently blank.
            let mut element = v_flex();
            element = element
                .border_1()
                .border_color(cx.theme().warning)
                .rounded_md()
                .p_2()
                .gap_2();
            let mut element = element
                .child(
                    div()
                        .text_xs()
                        .text_color(cx.theme().warning)
                        .child(format!("[{identifier}]")),
                )
                .children(children);
            element = style::all(element, node);
            element.into_any_element()
        }
    }
}

/// Icon/prop fallback marker used by kinds that need a future visual
/// (images, pickers). Reads `text`/`path`/`url` when present.
pub fn placeholder_box(
    view: &LuiNodeView,
    node: &NodeSnapshot,
    label: &str,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    let detail = node
        .string_prop(Property::TextValue)
        .or_else(|| node.string_prop(Property::PathValue))
        .or_else(|| node.string_prop(Property::UrlValue))
        .unwrap_or_default();
    let _ = view;
    div()
        .border_1()
        .border_color(cx.theme().border)
        .rounded_md()
        .px_2()
        .py_1()
        .text_xs()
        .text_color(cx.theme().muted_foreground)
        .child(if detail.is_empty() {
            format!("[{label}]")
        } else {
            format!("[{label} {detail}]")
        })
        .into_any_element()
}
