//! Wire props -> gpui Styled translation: frame/padding/colors/text +
//! the `style-class` resolver.
//!
//! `style-class` is a backend-interpreted token string (the web backend maps
//! it to DOM className, the Apple backend interprets tokens like "capsule").
//! Here we resolve Tailwind-style atomic utilities — GPUI's Styled API is
//! Tailwind-shaped and `gpui_component::theme::color` carries the full
//! Tailwind palette — plus a semantic-class hook apps can extend.

use gpui_kit::component::theme::try_parse_color;
use gpui_kit::gpui::{px, rgba, AbsoluteLength, DefiniteLength, Hsla, Styled};
use lui_core::Property;

use crate::node_view::NodeSnapshot;

/// Parse a color token into `Hsla`: `#rgb[a]`/`#rrggbb[aa]`, `rgb[a](...)`,
/// Tailwind names (`sky-500`, `red/80`, `gray-200/50`). Palette coverage
/// follows gpui-component's `ColorName` — `slate`/`zinc`/`stone` are not in it.
pub fn color(token: &str) -> Option<Hsla> {
    let token = token.trim();
    if token.is_empty() {
        return None;
    }
    if let Ok(color) = try_parse_color(token) {
        return Some(color);
    }
    // Palette names don't compose with an `/opacity` suffix upstream
    // (`slate-200/50`); apply the Tailwind opacity scale here.
    if let Some((base, opacity)) = token.split_once('/') {
        if let Ok(opacity) = opacity.parse::<f32>() {
            let base_color = try_parse_color(base)
                .ok()
                .or_else(|| parse_hex(base))
                .or_else(|| named(base));
            if let Some(mut color) = base_color {
                color.a *= (opacity / 100.0).clamp(0.0, 1.0);
                return Some(color);
            }
        }
    }
    parse_hex(token).or_else(|| named(token))
}

fn parse_hex(token: &str) -> Option<Hsla> {
    let hex = token.strip_prefix('#')?;
    let expand = |c: u8| (c << 4) | c;
    let bytes = match hex.len() {
        3 | 4 => hex
            .bytes()
            .map(|b| u8::from_str_radix(&(b as char).to_string(), 16).map(expand))
            .collect::<Result<Vec<u8>, _>>()
            .ok()?,
        6 | 8 => (0..hex.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&hex[i..i + 2], 16))
            .collect::<Result<Vec<u8>, _>>()
            .ok()?,
        _ => return None,
    };
    let (r, g, b) = (*bytes.first()?, *bytes.get(1)?, *bytes.get(2)?);
    let a = *bytes.get(3).unwrap_or(&255);
    Some(rgba((r as u32) << 16 | (g as u32) << 8 | b as u32 | ((a as u32) << 24)).into())
}

fn named(token: &str) -> Option<Hsla> {
    // Tokens GPUI's palette parser doesn't cover — LUI emits a few
    // semantic/transparent names.
    match token {
        "transparent" => Some(rgba(0x00000000).into()),
        "black" => Some(rgba(0xff000000).into()),
        "white" => Some(rgba(0xffffffff).into()),
        _ => None,
    }
}

fn px_length(value: f64) -> DefiniteLength {
    AbsoluteLength::Pixels(px(value as f32)).into()
}

/// Apply frame props (`width`, `height`, `min-*`, `max-*`, `grow`).
pub fn frame<E: Styled>(element: E, node: &NodeSnapshot) -> E {
    let mut element = element;
    if let Some(value) = node.float_prop(Property::WidthValue) {
        element = element.w(px_length(value));
    }
    if let Some(value) = node.float_prop(Property::HeightValue) {
        element = element.h(px_length(value));
    }
    if let Some(value) = node.float_prop(Property::MinWidth) {
        element = element.min_w(px_length(value));
    }
    if let Some(value) = node.float_prop(Property::MaxWidth) {
        element = element.max_w(px_length(value));
    }
    if let Some(value) = node.float_prop(Property::MinHeight) {
        element = element.min_h(px_length(value));
    }
    if let Some(value) = node.float_prop(Property::MaxHeight) {
        element = element.max_h(px_length(value));
    }
    if let Some(value) = node.float_prop(Property::GrowValue) {
        if value > 0.0 {
            element = element.flex_grow(value as f32);
        }
    }
    element
}

/// Apply box props (`padding*`, `gap`, `main`, `cross`) on containers.
pub fn layout<E: Styled>(element: E, node: &NodeSnapshot) -> E {
    let mut element = element;
    if let Some(value) = node.float_prop(Property::Gap) {
        element = element.gap(px(value as f32));
    }
    if let Some(value) = node.float_prop(Property::PaddingValue) {
        element = element.p(px(value as f32));
    }
    if let Some(value) = node.float_prop(Property::PaddingHorizontal) {
        element = element.px(px(value as f32));
    }
    if let Some(value) = node.float_prop(Property::PaddingVertical) {
        element = element.py(px(value as f32));
    }
    if let Some(main) = node.string_prop(Property::MainAlignment) {
        element = match main {
            "center" => element.justify_center(),
            "end" => element.justify_end(),
            "space-between" | "between" => element.justify_between(),
            "space-around" | "around" => element.justify_around(),
            "space-evenly" | "evenly" => element.justify_evenly(),
            _ => element.justify_start(),
        };
    }
    if let Some(cross) = node.string_prop(Property::CrossAlignment) {
        element = match cross {
            "start" => element.items_start(),
            "end" => element.items_end(),
            "baseline" => element.items_baseline(),
            "stretch" => element,
            _ => element.items_center(),
        };
    }
    element
}

/// Apply surface props (`background`, `foreground`, `border-*`,
/// `corner-radius`) on boxes/containers.
pub fn surface<E: Styled>(element: E, node: &NodeSnapshot) -> E {
    let mut element = element;
    if let Some(token) = node.string_prop(Property::BackgroundValue).and_then(color) {
        element = element.bg(token);
    }
    if let Some(token) = node.string_prop(Property::ForegroundValue).and_then(color) {
        element = element.text_color(token);
    }
    if let Some(width) = node.float_prop(Property::BorderWidth) {
        if width > 0.0 {
            element = element.border(px(width as f32));
        }
    }
    if let Some(token) = node.string_prop(Property::BorderColorValue).and_then(color) {
        element = element.border_color(token);
    }
    if let Some(radius) = node.float_prop(Property::CornerRadius) {
        element = element.rounded(px(radius as f32));
    }
    element
}

/// Tailwind-style atomic class resolver for `style-class` tokens.
/// Covers the utility families the LUI apps emit (spacing, flex alignment,
/// colors, radius, text size/weight); unknown tokens are ignored — semantic
/// classes (e.g. `cp__*`, `ls-*`) are app vocabulary and need an app-registered
/// dictionary (see `ExtensionRegistry` docs in README).
pub fn style_class<E: Styled>(mut element: E, classes: &str) -> E {
    for token in classes.split_whitespace() {
        element = apply_utility(element, token);
    }
    element
}

/// Tailwind spacing utilities: `<prefix>-<n>` on the 4px scale.
/// Longest prefixes first so `px-4` isn't eaten by `p-`.
fn numeric_utility(token: &str) -> Option<(&'static str, f32)> {
    // Longest prefixes first so `px-4` isn't eaten by `p-` and `min-w-0`
    // isn't eaten by `w`.
    const PREFIXES: &[&str] = &[
        "leading-", "min-w-", "min-h-", "max-w-", "max-h-", "gap-x-", "gap-y-", "size-", "gap-",
        "px-", "py-", "pt-", "pb-", "pl-", "pr-", "mx-", "my-", "mt-", "mb-", "ml-", "mr-", "top-",
        "bottom-", "left-", "right-", "w-", "h-", "p-", "m-",
    ];
    for prefix in PREFIXES {
        if let Some(rest) = token.strip_prefix(prefix) {
            return rest
                .parse::<f32>()
                .ok()
                .map(|value| (prefix.trim_end_matches('-'), value * 4.0));
        }
    }
    None
}

fn apply_utility<E: Styled>(mut element: E, token: &str) -> E {
    if let Some((prefix, px_value)) = numeric_utility(token) {
        return match prefix {
            "p" => element.p(px(px_value)),
            "pt" => element.pt(px(px_value)),
            "pb" => element.pb(px(px_value)),
            "pl" => element.pl(px(px_value)),
            "pr" => element.pr(px(px_value)),
            "px" => element.px(px(px_value)),
            "py" => element.py(px(px_value)),
            "m" => element.m(px(px_value)),
            "mt" => element.mt(px(px_value)),
            "mb" => element.mb(px(px_value)),
            "ml" => element.ml(px(px_value)),
            "mr" => element.mr(px(px_value)),
            "mx" => element.mx(px(px_value)),
            "my" => element.my(px(px_value)),
            "gap" => element.gap(px(px_value)),
            "gap-x" => element.gap_x(px(px_value)),
            "gap-y" => element.gap_y(px(px_value)),
            "w" => element.w(px(px_value)),
            "h" => element.h(px(px_value)),
            "size" => element.size(px(px_value)),
            "min-w" => element.min_w(px(px_value)),
            "min-h" => element.min_h(px(px_value)),
            "max-w" => element.max_w(px(px_value)),
            "max-h" => element.max_h(px(px_value)),
            "top" => element.top(px(px_value)),
            "bottom" => element.bottom(px(px_value)),
            "left" => element.left(px(px_value)),
            "right" => element.right(px(px_value)),
            "leading" => element.line_height(px(px_value)),
            _ => element,
        };
    }
    match token {
        "flex" | "flexbox" => element.flex(),
        "flex-row" => element.flex_row(),
        "flex-col" => element.flex_col(),
        "flex-wrap" | "wrap" => element.flex_wrap(),
        "flex-nowrap" | "nowrap" => element.flex_nowrap(),
        "flex-1" | "grow" | "grow-1" => element.flex_1(),
        "grow-0" => element.flex_grow(0.),
        "shrink" => element.flex_shrink(1.),
        "shrink-0" => element.flex_shrink(0.),
        "min-w-0" => element.min_w(px(0.)),
        "min-h-0" => element.min_h(px(0.)),
        "min-w-full" => element.min_w_full(),
        "min-h-full" => element.min_h_full(),
        "items-start" => element.items_start(),
        "items-center" => element.items_center(),
        "items-end" => element.items_end(),
        "items-baseline" => element.items_baseline(),
        "items-stretch" => element.items_stretch(),
        "self-start" => element.self_start(),
        "self-center" => element.self_center(),
        "self-end" => element.self_end(),
        "self-stretch" => element.self_stretch(),
        "justify-start" => element.justify_start(),
        "justify-center" => element.justify_center(),
        "justify-end" => element.justify_end(),
        "justify-between" => element.justify_between(),
        "justify-around" => element.justify_around(),
        "justify-evenly" => element.justify_evenly(),
        "w-full" => element.w_full(),
        "h-full" => element.h_full(),
        "size-full" => element.size_full(),
        "w-screen" => element.w_full(),
        "h-screen" => element.h_full(),
        "hidden" => element.invisible(),
        "visible" => element.visible(),
        "relative" => element.relative(),
        "absolute" => element.absolute(),
        "inset-0" => element
            .top(px(0.))
            .bottom(px(0.))
            .left(px(0.))
            .right(px(0.)),
        // Scroll affordances live on stateful elements (track id) — dom.rs
        // applies them; Styled only has the clipping variants.
        "overflow-hidden" => element.overflow_hidden(),
        "overflow-x-hidden" => element.overflow_x_hidden(),
        "overflow-y-hidden" => element.overflow_y_hidden(),
        "text-center" => element.text_align(gpui_kit::gpui::TextAlign::Center),
        "text-right" => element.text_align(gpui_kit::gpui::TextAlign::Right),
        "font-bold" => element.font_weight(gpui_kit::gpui::FontWeight::BOLD),
        "font-semibold" => element.font_weight(gpui_kit::gpui::FontWeight::SEMIBOLD),
        "font-medium" => element.font_weight(gpui_kit::gpui::FontWeight::MEDIUM),
        "font-mono" => element.font_family("monospace"),
        "italic" => element.italic(),
        "underline" => element.underline(),
        "line-through" => element.line_through(),
        "whitespace-nowrap" => element.whitespace_nowrap(),
        "truncate" => element.text_ellipsis(),
        "cursor-pointer" => element.cursor_pointer(),
        "cursor-default" => element.cursor_default(),
        "border" => element.border_1(),
        "border-0" => element.border_0(),
        "border-t" => element.border_t_1(),
        "border-b" => element.border_b_1(),
        "border-l" => element.border_l_1(),
        "border-r" => element.border_r_1(),
        "rounded" => element.rounded_md(),
        _ => {
            if let Some(rest) = token.strip_prefix("bg-") {
                if let Some(color) = color(rest) {
                    element = element.bg(color);
                }
            } else if let Some(rest) = token.strip_prefix("text-") {
                element = apply_text_utility(element, rest);
            } else if let Some(rest) = token.strip_prefix("border-") {
                if let Some(color) = color(rest) {
                    element = element.border_color(color);
                }
            } else if let Some(rest) = token.strip_prefix("rounded-") {
                element = apply_radius(element, rest);
            }
            element
        }
    }
}

fn apply_text_utility<E: Styled>(element: E, rest: &str) -> E {
    use gpui_kit::gpui::Rems;
    match rest {
        "xs" => element.text_size(Rems(0.75)),
        "sm" => element.text_sm(),
        "base" => element.text_base(),
        "lg" => element.text_lg(),
        "xl" => element.text_xl(),
        "2xl" => element.text_size(Rems(1.5)),
        "3xl" => element.text_size(Rems(1.875)),
        _ => match color(rest) {
            Some(color) => element.text_color(color),
            None => element,
        },
    }
}

fn apply_radius<E: Styled>(element: E, rest: &str) -> E {
    match rest {
        "none" => element.rounded(px(0.0)),
        "sm" => element.rounded_sm(),
        "md" => element.rounded_md(),
        "lg" => element.rounded_lg(),
        "xl" => element.rounded_xl(),
        "2xl" => element.rounded(px(16.0)),
        "full" => element.rounded_full(),
        _ => element,
    }
}

/// Convenience composition used by most kinds: frame + layout + surface +
/// style-class, in wire order semantics. `style-class` lives in standard
/// props for component kinds and in extension props for extension nodes.
pub fn all<E: Styled>(element: E, node: &NodeSnapshot) -> E {
    let element = frame(element, node);
    let element = layout(element, node);
    let element = surface(element, node);
    let element = match node.float_prop(Property::Opacity) {
        Some(value) => element.opacity(value as f32),
        None => element,
    };
    match node
        .string_prop(Property::StyleClass)
        .or_else(|| node.extension_string_prop("style-class"))
    {
        Some(classes) => style_class(element, classes),
        None => element,
    }
}

#[cfg(test)]
mod tests {
    //! Snapshot-style assertions for the class -> Styled mapping table.
    //! Each test pins one mapping entry so a table edit that silently
    //! changes (or drops) a token fails loudly.

    use super::*;
    use gpui_kit::gpui::{
        div, AbsoluteLength, DefiniteLength, Fill, FontStyle, FontWeight, Length, Overflow, Rems,
        TextAlign, Visibility, WhiteSpace,
    };
    use gpui_kit::gpui::{Display, Styled};

    /// `p`-scale utility shorthand: Tailwind's 4px scale on `n`.
    fn px_len(n: f32) -> DefiniteLength {
        AbsoluteLength::Pixels(px(n * 4.0)).into()
    }

    fn abs_len(n: f32) -> Length {
        Length::Definite(px_len(n))
    }

    fn classes(token: &str) -> gpui_kit::gpui::StyleRefinement {
        let mut element = style_class(div(), token);
        element.style().clone()
    }

    #[test]
    fn color_tokens_parse_all_supported_forms() {
        for token in [
            "#fff",
            "#ff0000",
            "#ff000080",
            "#abc",
            "sky-500",
            "red/80",
            "gray-200/50",
            "transparent",
            "black",
            "white",
        ] {
            assert!(color(token).is_some(), "color({token:?})");
        }
        for token in [
            "",
            "   ",
            "not-a-color",
            "#",
            "#ff",
            "rgb(",
            // gpui-component's palette table lacks slate/zinc/stone.
            "slate-200",
            "slate-200/50",
        ] {
            assert!(color(token).is_none(), "color({token:?}) must be None");
        }
    }

    #[test]
    fn hex_color_expands_short_and_alpha_forms() {
        let hsla = color("#fff").unwrap();
        assert_eq!(hsla, color("#ffffff").unwrap());
        let alpha = color("#ff000080").unwrap();
        assert!(alpha.a < 0.51 && alpha.a > 0.49, "alpha ~= 0.5: {alpha:?}");
    }

    #[test]
    fn spacing_utilities_map_to_the_4px_scale() {
        for (token, expected) in [
            ("p-4", px_len(4.0)),
            ("p-0", px_len(0.0)),
            ("p-10", px_len(10.0)),
        ] {
            let s = classes(token);
            for edge in [
                s.padding.top,
                s.padding.right,
                s.padding.bottom,
                s.padding.left,
            ] {
                assert_eq!(edge, Some(expected), "{token}");
            }
        }
        let s = classes("px-2");
        assert_eq!(s.padding.left, Some(px_len(2.0)));
        assert_eq!(s.padding.right, Some(px_len(2.0)));
        assert_eq!(s.padding.top, None);
        let s = classes("py-3");
        assert_eq!(s.padding.top, Some(px_len(3.0)));
        assert_eq!(s.padding.bottom, Some(px_len(3.0)));
        let s = classes("pt-1 pb-2 pl-3 pr-4");
        assert_eq!(s.padding.top, Some(px_len(1.0)));
        assert_eq!(s.padding.bottom, Some(px_len(2.0)));
        assert_eq!(s.padding.left, Some(px_len(3.0)));
        assert_eq!(s.padding.right, Some(px_len(4.0)));
        // margins
        let s = classes("m-2 mt-3 mb-1 mx-4");
        assert_eq!(s.margin.top, Some(abs_len(3.0)));
        assert_eq!(s.margin.bottom, Some(abs_len(1.0)));
        assert_eq!(s.margin.left, Some(abs_len(4.0)));
        assert_eq!(s.margin.right, Some(abs_len(4.0)));
        // gaps
        let s = classes("gap-2");
        assert_eq!(s.gap.width, Some(px_len(2.0)));
        assert_eq!(s.gap.height, Some(px_len(2.0)));
        let s = classes("gap-x-4 gap-y-1");
        assert_eq!(s.gap.width, Some(px_len(4.0)));
        assert_eq!(s.gap.height, Some(px_len(1.0)));
        // line height
        assert_eq!(classes("leading-6").text.line_height, Some(px_len(6.0)));
        // insets
        let s = classes("top-2 bottom-4 left-1 right-3");
        assert_eq!(s.inset.top, Some(abs_len(2.0)));
        assert_eq!(s.inset.bottom, Some(abs_len(4.0)));
        assert_eq!(s.inset.left, Some(abs_len(1.0)));
        assert_eq!(s.inset.right, Some(abs_len(3.0)));
    }

    #[test]
    fn longest_prefix_wins_over_shorter_ones() {
        // `px-4` must not be eaten by `p-`; `min-w-0` not by `w-`.
        let s = classes("px-4");
        assert_eq!(s.padding.top, None, "px- must not set top padding");
        assert_eq!(s.padding.left, Some(px_len(4.0)));
        let s = classes("min-w-0");
        assert_eq!(s.min_size.width, Some(abs_len(0.0)));
        let s = classes("min-h-2");
        assert_eq!(s.min_size.height, Some(abs_len(2.0)));
        let s = classes("max-w-8 max-h-6");
        assert_eq!(s.max_size.width, Some(abs_len(8.0)));
        assert_eq!(s.max_size.height, Some(abs_len(6.0)));
        // `size-N` sets both axes.
        let s = classes("size-5");
        assert_eq!(s.size.width, Some(abs_len(5.0)));
        assert_eq!(s.size.height, Some(abs_len(5.0)));
    }

    #[test]
    fn flex_and_alignment_tokens() {
        assert_eq!(classes("flex").display, Some(Display::Flex));
        for (token, want) in [
            ("flex-row", gpui_kit::gpui::FlexDirection::Row),
            ("flex-col", gpui_kit::gpui::FlexDirection::Column),
        ] {
            assert_eq!(classes(token).flex_direction, Some(want), "{token}");
        }
        assert_eq!(
            classes("flex-wrap").flex_wrap,
            Some(gpui_kit::gpui::FlexWrap::Wrap)
        );
        assert_eq!(
            classes("flex-nowrap").flex_wrap,
            Some(gpui_kit::gpui::FlexWrap::NoWrap)
        );
        assert_eq!(classes("flex-1").flex_grow, Some(1.0));
        assert_eq!(classes("grow-0").flex_grow, Some(0.0));
        assert_eq!(classes("shrink-0").flex_shrink, Some(0.0));
        for (token, want) in [
            ("items-start", gpui_kit::gpui::AlignItems::FlexStart),
            ("items-center", gpui_kit::gpui::AlignItems::Center),
            ("items-end", gpui_kit::gpui::AlignItems::FlexEnd),
            ("items-baseline", gpui_kit::gpui::AlignItems::Baseline),
            ("items-stretch", gpui_kit::gpui::AlignItems::Stretch),
        ] {
            assert_eq!(classes(token).align_items, Some(want), "{token}");
        }
        for (token, want) in [
            ("justify-start", gpui_kit::gpui::JustifyContent::Start),
            ("justify-center", gpui_kit::gpui::JustifyContent::Center),
            ("justify-end", gpui_kit::gpui::JustifyContent::End),
            ("justify-between", gpui_kit::gpui::JustifyContent::SpaceBetween),
            ("justify-around", gpui_kit::gpui::JustifyContent::SpaceAround),
            ("justify-evenly", gpui_kit::gpui::JustifyContent::SpaceEvenly),
        ] {
            assert_eq!(classes(token).justify_content, Some(want), "{token}");
        }
        for (token, want) in [
            ("self-start", gpui_kit::gpui::AlignSelf::Start),
            ("self-center", gpui_kit::gpui::AlignSelf::Center),
            ("self-end", gpui_kit::gpui::AlignSelf::End),
            ("self-stretch", gpui_kit::gpui::AlignSelf::Stretch),
        ] {
            assert_eq!(classes(token).align_self, Some(want), "{token}");
        }
    }

    #[test]
    fn sizing_tokens() {
        let s = classes("w-full");
        assert_eq!(
            s.size.width,
            Some(Length::Definite(DefiniteLength::Fraction(1.0)))
        );
        let s = classes("h-full");
        assert_eq!(
            s.size.height,
            Some(Length::Definite(DefiniteLength::Fraction(1.0)))
        );
        let s = classes("w-10 h-20");
        assert_eq!(s.size.width, Some(abs_len(10.0)));
        assert_eq!(s.size.height, Some(abs_len(20.0)));
    }

    #[test]
    fn visibility_position_and_overflow_tokens() {
        assert_eq!(classes("hidden").visibility, Some(Visibility::Hidden));
        assert_eq!(classes("visible").visibility, Some(Visibility::Visible));
        assert_eq!(
            classes("relative").position,
            Some(gpui_kit::gpui::Position::Relative)
        );
        assert_eq!(
            classes("absolute").position,
            Some(gpui_kit::gpui::Position::Absolute)
        );
        let s = classes("inset-0");
        for edge in [s.inset.top, s.inset.right, s.inset.bottom, s.inset.left] {
            assert_eq!(
                edge,
                Some(Length::Definite(DefiniteLength::Absolute(
                    AbsoluteLength::Pixels(px(0.0))
                )))
            );
        }
        assert_eq!(classes("overflow-hidden").overflow.x, Some(Overflow::Hidden));
        assert_eq!(classes("overflow-hidden").overflow.y, Some(Overflow::Hidden));
        assert_eq!(classes("overflow-x-hidden").overflow.x, Some(Overflow::Hidden));
        assert_eq!(classes("overflow-y-hidden").overflow.y, Some(Overflow::Hidden));
    }

    #[test]
    fn text_tokens() {
        assert_eq!(classes("text-center").text.text_align, Some(TextAlign::Center));
        assert_eq!(classes("text-right").text.text_align, Some(TextAlign::Right));
        assert_eq!(classes("font-bold").text.font_weight, Some(FontWeight::BOLD));
        assert_eq!(
            classes("font-semibold").text.font_weight,
            Some(FontWeight::SEMIBOLD)
        );
        assert_eq!(
            classes("font-medium").text.font_weight,
            Some(FontWeight::MEDIUM)
        );
        assert_eq!(
            classes("font-mono").text.font_family.as_deref(),
            Some("monospace")
        );
        assert_eq!(classes("italic").text.font_style, Some(FontStyle::Italic));
        assert!(classes("underline").text.underline.is_some());
        assert!(classes("line-through").text.strikethrough.is_some());
        assert_eq!(classes("whitespace-nowrap").text.white_space, Some(WhiteSpace::Nowrap));
        assert!(matches!(
            classes("truncate").text.text_overflow,
            Some(gpui_kit::gpui::TextOverflow::Truncate(_))
        ));
        // size scale
        assert_eq!(
            classes("text-xs").text.font_size,
            Some(AbsoluteLength::Rems(Rems(0.75)))
        );
        assert_eq!(
            classes("text-2xl").text.font_size,
            Some(AbsoluteLength::Rems(Rems(1.5)))
        );
        // colored text resolves through the palette
        let expected = color("sky-500").unwrap();
        assert_eq!(classes("text-sky-500").text.color, Some(expected));
    }

    #[test]
    fn borders_radius_and_surface_tokens() {
        let s = classes("border");
        for edge in [
            s.border_widths.top,
            s.border_widths.right,
            s.border_widths.bottom,
            s.border_widths.left,
        ] {
            assert_eq!(edge, Some(AbsoluteLength::Pixels(px(1.0))));
        }
        let s = classes("border-0");
        for edge in [
            s.border_widths.top,
            s.border_widths.right,
            s.border_widths.bottom,
            s.border_widths.left,
        ] {
            assert_eq!(edge, Some(AbsoluteLength::Pixels(px(0.0))));
        }
        assert_eq!(
            classes("border-t").border_widths.top,
            Some(AbsoluteLength::Pixels(px(1.0)))
        );
        // radius scale — `rounded` is gpui's rounded_md (0.375rem = 6px)
        let s = classes("rounded");
        assert_eq!(
            s.corner_radii.top_left,
            Some(AbsoluteLength::Rems(Rems(0.375)))
        );
        let s = classes("rounded-none");
        assert_eq!(s.corner_radii.top_left, Some(AbsoluteLength::Pixels(px(0.0))));
        let s = classes("rounded-2xl");
        assert_eq!(s.corner_radii.top_left, Some(AbsoluteLength::Pixels(px(16.0))));
        // background + border colors flow through `color`
        let expected = color("sky-500").unwrap();
        assert_eq!(
            classes("bg-sky-500").background,
            Some(Fill::from(expected))
        );
        assert_eq!(
            classes("border-sky-500").border_color,
            Some(expected)
        );
    }

    #[test]
    fn unknown_and_semantic_tokens_are_ignored() {
        let s = classes("cp__sidebar ls-page foo-bar-42 bg-not-a-color");
        assert_eq!(s.padding.top, None);
        assert_eq!(s.background, None);
        assert_eq!(s.display, None);
    }

    #[test]
    fn surface_and_layout_read_wire_props() {
        use lui_core::store::NodeIdentity;
        use lui_core::wire::Value;
        use lui_core::wire_schema::NodeKind;
        use std::collections::BTreeMap;
        let mut props: BTreeMap<Property, Value> = BTreeMap::new();
        props.insert(Property::WidthValue, Value::Float(120.0));
        props.insert(Property::Gap, Value::Int(2));
        props.insert(Property::MainAlignment, Value::Str("center".into()));
        props.insert(
            Property::BackgroundValue,
            Value::Str("red-500".into()),
        );
        let node = NodeSnapshot {
            id: 1,
            identity: NodeIdentity::Standard(NodeKind::Column),
            props,
            extension_props: BTreeMap::new(),
            children: Vec::new(),
            parent: None,
        };
        let mut element = all(div(), &node);
        let s = element.style();
        assert_eq!(
            s.size.width,
            Some(Length::Definite(DefiniteLength::Absolute(
                AbsoluteLength::Pixels(px(120.0))
            )))
        );
        // wire `gap` is raw pixels, not the utility 4px scale
        assert_eq!(
            s.gap.width,
            Some(DefiniteLength::Absolute(AbsoluteLength::Pixels(
                px(2.0)
            )))
        );
        assert_eq!(
            s.justify_content,
            Some(gpui_kit::gpui::JustifyContent::Center)
        );
        assert_eq!(
            s.background,
            Some(Fill::from(color("red-500").unwrap()))
        );
    }
}

