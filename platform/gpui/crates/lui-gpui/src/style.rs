//! Wire props -> gpui Styled translation: frame/padding/colors/text +
//! the `style-class` resolver.
//!
//! `style-class` is a backend-interpreted token string (the web backend maps
//! it to DOM className, the Apple backend interprets tokens like "capsule").
//! Here we resolve Tailwind-style atomic utilities — GPUI's Styled API is
//! Tailwind-shaped and `gpui_component::theme::color` carries the full
//! Tailwind palette — plus a semantic-class hook apps can extend.

use gpui_kit::component::theme::{try_parse_color, Theme};
use gpui_kit::gpui::{
    point, px, rgba, AbsoluteLength, BoxShadow, CursorStyle, DefiniteLength, FontWeight, Hsla,
    Length, StatefulInteractiveElement, Styled, StyleRefinement,
};
use lui_core::Property;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, RwLock};

use crate::node_view::NodeSnapshot;

/// CSS custom properties pushed by the host `style-set-property` dom-op
/// (`--ls-left-sidebar-width` and friends land on the document root).
/// Keys keep the `--` prefix; resolution is global, mirroring the CSS
/// cascade on `:root`.
static CSS_VARS: RwLock<Option<HashMap<String, String>>> = RwLock::new(None);

/// Write revision — bumped per `set_css_var`; used to dirty nodes that
/// must re-render against the new var table.
static CSS_VARS_REV: AtomicU64 = AtomicU64::new(0);

pub fn css_vars_rev() -> u64 {
    CSS_VARS_REV.load(Ordering::Relaxed)
}

/// Record a custom-property value (from `style-set-property`).
pub fn set_css_var(name: &str, value: &str) {
    CSS_VARS
        .write()
        .expect("css-var lock poisoned")
        .get_or_insert_with(HashMap::new)
        .insert(name.to_string(), value.to_string());
    CSS_VARS_REV.fetch_add(1, Ordering::Relaxed);
}

fn css_var(name: &str) -> Option<String> {
    CSS_VARS
        .read()
        .expect("css-var lock poisoned")
        .as_ref()
        .and_then(|vars| vars.get(name).cloned())
}

/// Viewport size in points — refreshed by `LuiNodeView::render` each
/// frame so `vw`/`vh`-family units resolve against the window (CSS
/// resolves them against the initial containing block, not the
/// element's parent).
static VIEWPORT: RwLock<(f32, f32)> = RwLock::new((1280.0, 800.0));

pub fn set_viewport_size(w: f32, h: f32) {
    *VIEWPORT.write().expect("viewport lock poisoned") = (w, h);
}

/// `<num>(d|s|l)?(vw|vh)` resolved against the current viewport.
fn viewport_length(token: &str) -> Option<f32> {
    let token = token.trim();
    let (w, h) = *VIEWPORT.read().expect("viewport lock poisoned");
    for (suffix, dim) in [
        ("dvw", w), ("svw", w), ("lvw", w), ("vw", w),
        ("dvh", h), ("svh", h), ("lvh", h), ("vh", h),
    ] {
        if let Some(num) = token.strip_suffix(suffix) {
            return num.parse::<f32>().ok().map(|v| v * dim / 100.0);
        }
    }
    None
}

/// App-registered semantic-class styles: `cp__*`/`ls-*`/`ui__*` tokens
/// are app vocabulary the builtin resolver ignores. The app registers
/// each class once at boot (`register_class_style`) as declarations
/// (parsed like inline style) plus utility tokens (folded back through
/// `apply_utility`, and visible to `has_class` behavior checks like
/// `overflow-y-auto`).
#[derive(Clone, Default)]
struct ClassStyle {
    declarations: Vec<(String, String)>,
    utilities: Vec<String>,
}

static CLASS_STYLES: RwLock<Option<HashMap<String, Arc<ClassStyle>>>> = RwLock::new(None);

pub fn register_class_style(name: &str, declarations: &str, utilities: &str) {
    let declarations: Vec<(String, String)> = declarations
        .split(';')
        .filter_map(|decl| {
            decl.split_once(':')
                .map(|(prop, value)| (prop.trim().to_ascii_lowercase(), value.trim().to_string()))
        })
        .collect();
    let utilities: Vec<String> = utilities
        .split_whitespace()
        .map(str::to_string)
        .collect();
    // Repeat registrations for one class merge, appending declarations:
    // sites split a class's rules across install phases (e.g. a scrim's
    // background in the theme block, its positioning in the layout
    // table) and the later registration must not clobber the earlier.
    let mut guard = CLASS_STYLES.write().expect("class-style lock poisoned");
    let entry = guard
        .get_or_insert_with(HashMap::new)
        .entry(name.to_string())
        .or_insert_with(|| Arc::new(ClassStyle::default()));
    let entry = Arc::make_mut(entry);
    entry.declarations.extend(declarations);
    entry.utilities.extend(utilities);
}

fn class_style(name: &str) -> Option<Arc<ClassStyle>> {
    CLASS_STYLES
        .read()
        .expect("class-style lock poisoned")
        .as_ref()
        .and_then(|map| map.get(name).cloned())
}

/// Whether any of the node's class tokens expands (via the registered
/// dictionary) to `token` — lets behavior checks like `has_class(node,
/// "overflow-y-auto")` see utilities carried by semantic classes.
pub fn class_has_utility(classes: &str, token: &str) -> bool {
    let styles = CLASS_STYLES.read().expect("class-style lock poisoned");
    let Some(styles) = styles.as_ref() else {
        return false;
    };
    classes
        .split_whitespace()
        .filter_map(|c| styles.get(c))
        .any(|s| s.utilities.iter().any(|u| u == token))
}

/// Explicit `pointer-events` a registered class declares — `Some(false)`
/// for `none`, `Some(true)` for `auto`. Read from its declarations or
/// utility tokens.
pub fn class_pointer_events(name: &str) -> Option<bool> {
    let registered = class_style(name)?;
    if registered
        .utilities
        .iter()
        .any(|u| u == "pointer-events-none")
    {
        return Some(false);
    }
    if registered
        .utilities
        .iter()
        .any(|u| u == "pointer-events-auto")
    {
        return Some(true);
    }
    registered
        .declarations
        .iter()
        .find(|(prop, _)| prop == "pointer-events")
        .map(|(_, value)| value != "none")
}

/// Builtin `--ls-*`/`--lx-*` CSS-variable names mapped onto the gpui theme
/// — the web app's classes.css declares these on `:root`/`dark`, here they
/// resolve through the active theme so dark mode follows the window.
fn semantic_var_color(name: &str, theme: &Theme) -> Option<Hsla> {
    // `--lx-gray-*` under the logseq accent: light binds the radix gray
    // scale; dark leaves every step (and every `-alpha` step) unset so
    // each use resolves its own `var(--ls-*)` fallback — dark bullets
    // ride --ls-block-bullet-color's teal, matching the classic theme.
    if let Some(step) = name.strip_prefix("--lx-gray-") {
        if theme.is_dark() || step.ends_with("-alpha") {
            return None;
        }
        return radix_gray(step, false, false);
    }
    Some(match name {
        "--ls-primary-background-color" | "--ls-content-background-color" => theme.background,
        "--ls-secondary-background-color"
        | "--ls-tertiary-background-color"
        | "--left-sidebar-bg-color"
        | "--right-sidebar-bg-color" => theme.secondary,
        "--ls-quaternary-background-color" | "--ls-quinary-background-color" => theme.muted,
        "--ls-primary-text-color" | "--ls-title-text-color" | "--ls-header-button-text-color" => {
            theme.foreground
        }
        "--ls-secondary-text-color" | "--ls-block-ref-text-color" => theme.muted_foreground,
        "--ls-link-text-color"
        | "--ls-link-ref-text-color"
        | "--ls-link-ref-text-hover-color"
        | "--ls-tag-text-color"
        | "--ls-external-link-color" => theme.primary,
        "--ls-active-primary-color" | "--ls-active-secondary-color" => theme.primary,
        // vars-classic.css selection tint, expressed as a translucent
        // source color: the overlay quad paints over the text on gpui,
        // so a half-alpha source composites to the opaque web value on
        // the page background while glyphs stay readable.
        "--ls-block-highlight-color" => {
            return Some(if theme.is_dark() {
                // ≈ #0a3d4b at 60% over the dark background
                rgba(0x00526999).into()
            } else {
                // #81cdfb at 50% composites to web's #c0e6fd on white
                rgba(0x81cdfb80).into()
            });
        }
        "--ls-highlight-color" | "--ls-selection-color" => theme.accent,
        "--ls-page-mark-bg-color" | "--ls-mark-highlight-color"
        | "--ls-search-highlight-color" => theme.warning,
        "--ls-border-color" => theme.border,
        // vars-classic.css: warm hairline in light, teal in dark.
        "--ls-guideline-color" => {
            return Some(if theme.is_dark() {
                rgba(0x0b4a5aff).into()
            } else {
                rgba(0x2e1b0514).into()
            });
        }
        // vars-classic.css bullet tokens — the dark values are the
        // classic teal pair; light resolves --lx-gray-08's gray.
        "--ls-block-bullet-color" => {
            return Some(if theme.is_dark() {
                rgba(0x608e91ff).into()
            } else {
                rgba(0x433f3840).into()
            });
        }
        "--ls-block-bullet-border-color" => {
            return Some(if theme.is_dark() {
                rgba(0x0f4958ff).into()
            } else {
                rgba(0xdededeff).into()
            });
        }
        "--ls-also-color-0" => theme.secondary_foreground,
        // Bare surface tokens — the LUI `background`/`foreground` vocab
        // (e.g. ~background:"secondary", "glass" on chrome.ml buttons).
        "background" => theme.background,
        "secondary" | "sidebar" => theme.secondary,
        "muted" => theme.muted,
        "muted-foreground" => theme.muted_foreground,
        "secondary-foreground" => theme.secondary_foreground,
        "foreground" => theme.foreground,
        "primary" => theme.primary,
        "accent" => theme.accent,
        "border" => theme.border,
        "warning" => theme.warning,
        "popover" | "card" | "glass" => theme.popover,
        _ => return rx_var_color(name, theme),
    })
}

/// `--rx-<color>-<step>` — the radix accent palette the web app injects
/// onto `:root` at runtime; gpui has no injector, so resolve the steps
/// the accent swatches use (-06 inactive ring, -07/-09 fill and active
/// ring) from a fixed base table matching the radix scale.
fn rx_var_color(name: &str, theme: &Theme) -> Option<Hsla> {
    let rest = name.strip_prefix("--rx-")?;
    let (rest, alpha) = match rest.strip_suffix("-alpha") {
        Some(rest) => (rest, true),
        None => (rest, false),
    };
    let (color, step) = rest.rsplit_once('-')?;
    if color == "gray" {
        return radix_gray(step, alpha, theme.is_dark());
    }
    if alpha {
        return None;
    }
    let mut base = match color {
        "none" => theme.border,
        "logseq" => theme.primary,
        _ => parse_hex(rx_base_hex(color)?)?,
    };
    if step == "06" {
        base.a *= 0.45;
    }
    Some(base)
}

/// radix `gray` scale — the light table is the `--lx-gray-*` binding of
/// the logseq accent; both modes back `--rx-gray-*` fallbacks (incl. the
/// `grayA` translucent series the kbd/bullet classes fall back to).
const GRAY_LIGHT: [&str; 12] = [
    "#fcfcfd", "#f9f9fb", "#eff0f3", "#e7e8eb", "#e0e1e6", "#d8d9e0", "#cdced6",
    "#b9bbc6", "#8b8d98", "#80838d", "#60646c", "#1c2024",
];
const GRAY_DARK: [&str; 12] = [
    "#161719", "#1c1d1f", "#232426", "#28292c", "#2e2f33", "#35373c", "#43474f",
    "#5a5f69", "#696f78", "#777b84", "#b0b4ba", "#edeef0",
];
// `grayA` — translucent series as RRGGBBAA (radix alpha steps over the
// gray-12/-12d hue; close enough for hairline fills).
const GRAYA_LIGHT: [u32; 12] = [
    0x1c202403, 0x1c202406, 0x1c202410, 0x1c202413, 0x1c20241a, 0x1c202425, 0x1c202433,
    0x1c202441, 0x1c202473, 0x1c202483, 0x1c2024a1, 0x1c2024e6,
];
const GRAYA_DARK: [u32; 12] = [
    0xedeef002, 0xedeef006, 0xedeef00c, 0xedeef012, 0xedeef019, 0xedeef01f, 0xedeef029,
    0xedeef03d, 0xedeef04e, 0xedeef066, 0xedeef0a7, 0xedeef0ef,
];

fn radix_gray(step: &str, alpha: bool, dark: bool) -> Option<Hsla> {
    let index = step.parse::<usize>().ok()?.checked_sub(1)?;
    if index >= 12 {
        return None;
    }
    if alpha {
        Some(rgba(if dark { GRAYA_DARK[index] } else { GRAYA_LIGHT[index] }).into())
    } else {
        parse_hex(if dark { GRAY_DARK[index] } else { GRAY_LIGHT[index] })
    }
}

fn rx_base_hex(color: &str) -> Option<&'static str> {
    Some(match color {
        "tomato" => "#e54d2e",
        "red" => "#e5484d",
        "crimson" => "#e93d82",
        "pink" => "#d6409f",
        "plum" => "#ab4aba",
        "purple" => "#6e56cf",
        "violet" => "#5b5bd6",
        "indigo" => "#3e63dd",
        "blue" => "#0091ff",
        "cyan" => "#00a2c7",
        "teal" => "#12a594",
        "green" => "#46a758",
        "grass" => "#62993c",
        "orange" => "#ed8b4a",
        _ => return None,
    })
}

/// `var(--name, fallback)` resolution order: host-written vars, the
/// builtin `--ls-*` semantic table (theme-aware), then the CSS fallback.
fn resolve_var_color(inner: &str, theme: Option<&Theme>) -> Option<Hsla> {
    let (name, fallback) = match inner.split_once(',') {
        Some((name, fallback)) => (name.trim(), Some(fallback.trim())),
        None => (inner.trim(), None),
    };
    if let Some(value) = css_var(name).and_then(|v| color_env(&v, theme)) {
        return Some(value);
    }
    if let Some(theme) = theme {
        if let Some(value) = semantic_var_color(name, theme) {
            return Some(value);
        }
    }
    fallback.and_then(|v| color_env(v, theme))
}

/// Parse a color token into `Hsla`: `#rgb[a]`/`#rrggbb[aa]`, `rgb[a](...)`,
/// `var(--x[, fallback])`, Tailwind names (`sky-500`, `red/80`,
/// `gray-200/50`). Palette coverage follows gpui-component's `ColorName`
/// — `slate`/`zinc`/`stone` are not in it. `var()` resolution is
/// theme-free here; `surface`/inline styles use the themed path.
pub fn color(token: &str) -> Option<Hsla> {
    color_env(token, None)
}

fn color_env(token: &str, theme: Option<&Theme>) -> Option<Hsla> {
    let token = token.trim();
    if token.is_empty() {
        return None;
    }
    if let Some(inner) = token
        .strip_prefix("var(")
        .and_then(|rest| rest.strip_suffix(')'))
    {
        return resolve_var_color(inner, theme);
    }
    if let Some(theme) = theme {
        if let Some(value) = semantic_var_color(token, theme) {
            return Some(value);
        }
    }
    if let Ok(color) = try_parse_color(token) {
        return Some(color);
    }
    // Palette names don't compose with an `/opacity` suffix upstream
    // (`slate-200/50`); apply the Tailwind opacity scale here. Any
    // resolvable base works, so `var(--ls-x)/90` and `#aabbcc/50` too.
    if let Some((base, opacity)) = token.split_once('/') {
        if let Ok(opacity) = opacity.parse::<f32>() {
            if let Some(mut color) = color_env(base, theme) {
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
    Some(
        rgba((r as u32) << 24 | (g as u32) << 16 | (b as u32) << 8 | a as u32).into(),
    )
}

fn named(token: &str) -> Option<Hsla> {
    // Tokens GPUI's palette parser doesn't cover — LUI emits a few
    // semantic/transparent names.
    match token {
        "transparent" => Some(rgba(0x00000000).into()),
        "black" => Some(rgba(0x000000ff).into()),
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

/// `<shadow-layer>[, ...]` -> `BoxShadow` list. Each layer is CSS-shaped:
/// `[inset] <x> <y> [<blur> [<spread>]] <color>` — gpui carries a real
/// `inset` flag so the highlight ring (`inset 0 0 0 1px`) translates
/// natively. Unparseable layers (e.g. `none`) drop out.
fn wire_shadows(value: &str, theme: &Theme) -> Vec<BoxShadow> {
    value
        .split(',')
        .filter_map(|layer| {
            let mut inset = false;
            let mut lengths: Vec<f32> = Vec::new();
            let mut color = None;
            for token in layer.split_whitespace() {
                if token == "inset" {
                    inset = true;
                } else if let Some(v) = resolve_px(token) {
                    lengths.push(v);
                } else if let Some(c) = color_themed(token, theme) {
                    color = Some(c);
                }
            }
            let color = color?;
            Some(BoxShadow {
                color,
                offset: point(px(*lengths.first().unwrap_or(&0.0)), px(*lengths.get(1).unwrap_or(&0.0))),
                blur_radius: px(*lengths.get(2).unwrap_or(&0.0)),
                spread_radius: px(*lengths.get(3).unwrap_or(&0.0)),
                inset,
            })
        })
        .collect()
}

/// `line-height` string -> `DefiniteLength`. Unitless numbers are font-size
/// multiples (CSS semantics) — px/rem resolve like `resolve_length`, but a
/// bare `1.5` is a `Fraction`, not 1.5px.
fn line_height_length(token: &str) -> Option<DefiniteLength> {
    let token = token.trim();
    if token.is_empty() {
        return None;
    }
    if token.ends_with("px") || token.ends_with("rem") || token.ends_with('%') {
        return resolve_length(token);
    }
    token
        .parse::<f32>()
        .ok()
        .map(DefiniteLength::Fraction)
}

/// Apply the typed appearance props on any element: typography,
/// position/insets, text overflow, shadows, cursor, viewport-relative
/// sizes, plus the static half of the state channels (`selected-*` when
/// the node's `selected` prop is set, `disabled-opacity` when disabled).
/// Pointer/focus channels live in `interactive` (they need an
/// [`InteractiveElement`]). `z-index`, `user-select` and `letter-spacing`
/// have no gpui style field — ordering is paint order, text selection is
/// not a style — so they are intentionally unhandled here.
fn appearance<E: Styled>(mut element: E, node: &NodeSnapshot, theme: &Theme) -> E {
    if let Some(value) = node.string_prop(Property::FontSize) {
        element = apply_decl(element, "font-size", value, theme);
    }
    if let Some(value) = node.int_prop(Property::FontWeight) {
        element = element.font_weight(FontWeight(value as f32));
    }
    if let Some(value) = node
        .string_prop(Property::LineHeight)
        .and_then(line_height_length)
    {
        element = element.line_height(value);
    }
    if let Some(value) = node.string_prop(Property::Position) {
        element = apply_decl(element, "position", value, theme);
    }
    if let Some(value) = node.float_prop(Property::Inset) {
        element = element
            .top(px(value as f32))
            .right(px(value as f32))
            .bottom(px(value as f32))
            .left(px(value as f32));
    }
    if let Some(value) = node.float_prop(Property::InsetTop) {
        element = element.top(px(value as f32));
    }
    if let Some(value) = node.float_prop(Property::InsetRight) {
        element = element.right(px(value as f32));
    }
    if let Some(value) = node.float_prop(Property::InsetBottom) {
        element = element.bottom(px(value as f32));
    }
    if let Some(value) = node.float_prop(Property::InsetLeft) {
        element = element.left(px(value as f32));
    }
    if let Some(value) = node.string_prop(Property::WhiteSpace) {
        element = match value {
            "nowrap" => element.whitespace_nowrap(),
            "normal" => element.whitespace_normal(),
            _ => element,
        };
    }
    if node
        .string_prop(Property::TextOverflow)
        .is_some_and(|value| value == "ellipsis")
    {
        element = element.text_ellipsis();
    }
    if let Some(value) = node.string_prop(Property::Overflow) {
        element = apply_decl(element, "overflow", value, theme);
    }
    if let Some(value) = node.string_prop(Property::Cursor) {
        element.style().mouse_cursor = match value {
            "pointer" => Some(CursorStyle::PointingHand),
            "text" => Some(CursorStyle::IBeam),
            _ => Some(CursorStyle::Arrow),
        };
    }
    if let Some(value) = node.string_prop(Property::Shadow) {
        element.style().box_shadow = wire_shadows(value, theme);
    }
    // Viewport-relative sizing: fractions of the live viewport dimensions.
    let (vw, vh) = *VIEWPORT.read().expect("viewport lock poisoned");
    if let Some(value) = node.float_prop(Property::WidthViewport) {
        element = element.w(px(value as f32 * vw));
    }
    if let Some(value) = node.float_prop(Property::HeightViewport) {
        element = element.h(px(value as f32 * vh));
    }
    if let Some(value) = node.float_prop(Property::MinWidthViewport) {
        element = element.min_w(px(value as f32 * vw));
    }
    if let Some(value) = node.float_prop(Property::MaxWidthViewport) {
        element = element.max_w(px(value as f32 * vw));
    }
    if let Some(value) = node.float_prop(Property::MinHeightViewport) {
        element = element.min_h(px(value as f32 * vh));
    }
    if let Some(value) = node.float_prop(Property::MaxHeightViewport) {
        element = element.max_h(px(value as f32 * vh));
    }
    // `selected`/`enabled` are snapshot booleans — their channels apply
    // statically here; the pointer-gated channels (`selected-hover-shadow`,
    // `hover-*`, `pressed-*`, `focus-shadow`) attach in `interactive`.
    if node.bool_prop(Property::Selected).unwrap_or(false) {
        if let Some(bg) = node
            .string_prop(Property::SelectedBackground)
            .and_then(|token| color_themed(token, theme))
        {
            element = element.bg(bg);
        }
        if let Some(value) = node.string_prop(Property::SelectedShadow) {
            element.style().box_shadow = wire_shadows(value, theme);
        }
    }
    if !node.enabled() {
        if let Some(value) = node.float_prop(Property::DisabledOpacity) {
            element = element.opacity(value as f32);
        }
    }
    element
}

/// Attach the pointer/focus state channels (`hover-*`, `pressed-*`,
/// `focus-shadow`, `selected-hover-shadow`) to a stateful element — the
/// generic containers and text kinds in `kinds.rs` build `.id(...)`
/// elements, so their state is tracked and the channels work.
pub fn interactive<E: StatefulInteractiveElement>(
    element: E,
    node: &NodeSnapshot,
    theme: &Theme,
) -> E {
    let mut element = element;
    let hover_bg = node
        .string_prop(Property::HoverBackground)
        .and_then(|token| color_themed(token, theme))
        .map(Into::into);
    let hover_opacity = node.float_prop(Property::HoverOpacity).map(|v| v as f32);
    let hover_shadow = node
        .string_prop(Property::HoverShadow)
        .map(|value| wire_shadows(value, theme));
    let selected = node.bool_prop(Property::Selected).unwrap_or(false);
    let selected_hover_shadow = node
        .string_prop(Property::SelectedHoverShadow)
        .map(|value| wire_shadows(value, theme));
    if hover_bg.is_some()
        || hover_opacity.is_some()
        || hover_shadow.is_some()
        || selected_hover_shadow.is_some()
    {
        element = element.hover(move |mut style: StyleRefinement| {
            if let Some(bg) = hover_bg {
                style.background = Some(bg);
            }
            if let Some(opacity) = hover_opacity {
                style.opacity = Some(opacity);
            }
            if let Some(shadow) = selected_hover_shadow.clone().filter(|_| selected) {
                style.box_shadow = shadow;
            } else if let Some(shadow) = hover_shadow.clone() {
                style.box_shadow = shadow;
            }
            style
        });
    }
    let pressed_bg = node
        .string_prop(Property::PressedBackground)
        .and_then(|token| color_themed(token, theme))
        .map(Into::into);
    let pressed_opacity = node.float_prop(Property::PressedOpacity).map(|v| v as f32);
    let pressed_shadow = node
        .string_prop(Property::PressedShadow)
        .map(|value| wire_shadows(value, theme));
    if pressed_bg.is_some() || pressed_opacity.is_some() || pressed_shadow.is_some() {
        element = element.active(move |mut style: StyleRefinement| {
            if let Some(bg) = pressed_bg {
                style.background = Some(bg);
            }
            if let Some(opacity) = pressed_opacity {
                style.opacity = Some(opacity);
            }
            if let Some(shadow) = pressed_shadow.clone() {
                style.box_shadow = shadow;
            }
            style
        });
    }
    let focus_shadow = node
        .string_prop(Property::FocusShadow)
        .map(|value| wire_shadows(value, theme));
    if let Some(focus_shadow) = focus_shadow {
        element = element.focus_visible(move |mut style: StyleRefinement| {
            style.box_shadow = focus_shadow.clone();
            style
        });
    }
    element
}

/// `all` plus the pointer state channels — use on stateful (`.id`-bearing)
/// elements. `all` alone is for leaves whose kind never attaches a state.
pub fn all_interactive<E>(element: E, node: &NodeSnapshot, theme: &Theme) -> E
where
    E: StatefulInteractiveElement + Styled,
{
    interactive(all(element, node, theme), node, theme)
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
            "stretch" => element.items_stretch(),
            _ => element.items_center(),
        };
    }
    element
}

/// Apply surface props (`background`, `foreground`, `border-*`,
/// `corner-radius`) on boxes/containers.
pub fn surface<E: Styled>(element: E, node: &NodeSnapshot, theme: &Theme) -> E {
    let mut element = element;
    if let Some(token) = node
        .string_prop(Property::BackgroundValue)
        .and_then(|token| color_themed(token, theme))
    {
        element = element.bg(token);
    }
    if let Some(token) = node
        .string_prop(Property::ForegroundValue)
        .and_then(|token| color_themed(token, theme))
    {
        element = element.text_color(token);
    }
    if let Some(width) = node.float_prop(Property::BorderWidth) {
        if width > 0.0 {
            element = element.border(px(width as f32));
        }
    }
    if let Some(token) = node
        .string_prop(Property::BorderColorValue)
        .and_then(|token| color_themed(token, theme))
    {
        element = element.border_color(token);
    }
    if let Some(radius) = node.float_prop(Property::CornerRadius) {
        element = element.rounded(px(radius as f32));
    }
    element
}

/// Whether `token` resolves to a concrete utility style — mirrors
/// `apply_utility` (keep in sync; the prefix families are matched
/// conservatively — an unrecognized `bg-foo` still reports active, which
/// only makes elision more conservative). Wrapper elision refuses to
/// collapse a container whose `style-class` still carries layout or
/// behavior semantics.
pub fn utility_token_active(token: &str) -> bool {
    if numeric_utility(token).is_some() {
        return true;
    }
    // A registered semantic class carries real layout — a wrapper whose
    // class dictionary entry has declarations or utilities is not inert.
    if let Some(registered) = class_style(token) {
        if !registered.declarations.is_empty() || !registered.utilities.is_empty() {
            return true;
        }
    }
    if token.starts_with("bg-")
        || token.starts_with("text-")
        || token.starts_with("border-")
        || token.starts_with("rounded-")
    {
        return true;
    }
    matches!(
        token,
        "flex" | "flexbox" | "flex-row" | "flex-col" | "flex-wrap" | "flex-nowrap" | "nowrap"
            | "flex-1" | "grow" | "grow-1" | "grow-0" | "shrink" | "shrink-0" | "min-w-0"
            | "min-h-0" | "min-w-full" | "min-h-full" | "items-start" | "items-center"
            | "items-end" | "items-baseline" | "items-stretch" | "self-start" | "self-center"
            | "self-end" | "self-stretch" | "justify-start" | "justify-center"
            | "justify-end" | "justify-between" | "justify-around" | "justify-evenly"
            | "w-full" | "h-full" | "size-full" | "w-screen" | "h-screen" | "hidden"
            | "visible" | "relative" | "absolute" | "inset-0" | "overflow-hidden"
            | "overflow-x-hidden" | "overflow-y-hidden" | "text-center" | "text-right"
            | "font-bold" | "font-semibold" | "font-medium" | "font-mono" | "monospace"
            | "italic" | "underline" | "line-through" | "whitespace-nowrap" | "truncate"
            | "headline" | "subheadline" | "caption" | "caption2" | "title" | "single-line"
            | "monospaced" | "cursor-pointer" | "cursor-default" | "border" | "border-0"
            | "border-t" | "border-b" | "border-l" | "border-r" | "rounded"
    )
}

/// Tailwind-style atomic class resolver for `style-class` tokens.
/// Covers the utility families the LUI apps emit (spacing, flex alignment,
/// colors, radius, text size/weight); unknown tokens are ignored — semantic
/// classes (e.g. `cp__*`, `ls-*`) are app vocabulary resolved through the
/// registered style dictionary (`register_class_style`).
pub fn style_class<E: Styled>(mut element: E, classes: &str, theme: &Theme) -> E {
    for token in classes.split_whitespace() {
        element = apply_utility(element, token);
        if let Some(registered) = class_style(token) {
            for (prop, value) in &registered.declarations {
                element = apply_decl(element, prop, value, theme);
            }
            for utility in &registered.utilities {
                element = apply_utility(element, utility);
            }
        }
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
        "flex-wrap" => element.flex_wrap(),
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
        // Semantic text vocabulary shared with the Apple backend's
        // style-class hook (`headline`/`subheadline`/`caption*`,
        // `single-line`, `monospaced`).
        "headline" => element.font_weight(gpui_kit::gpui::FontWeight::SEMIBOLD),
        "subheadline" => element.text_sm(),
        "caption" | "caption2" => element.text_xs(),
        "title" => element
            .text_xl()
            .font_weight(gpui_kit::gpui::FontWeight::SEMIBOLD),
        "single-line" => element.whitespace_nowrap().text_ellipsis(),
        "monospaced" => element.font_family("monospace"),
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

fn color_themed(token: &str, theme: &Theme) -> Option<Hsla> {
    color_env(token, Some(theme))
}

/// Resolve a CSS length token to `DefiniteLength`: `NNpx`, `NNrem`,
/// `NN%`, a bare number (px), or `var(--x[, fallback])`.
fn resolve_length(token: &str) -> Option<DefiniteLength> {
    let token = token.trim();
    if let Some(inner) = token
        .strip_prefix("var(")
        .and_then(|rest| rest.strip_suffix(')'))
    {
        let (name, fallback) = match inner.split_once(',') {
            Some((name, fallback)) => (name.trim(), Some(fallback.trim())),
            None => (inner.trim(), None),
        };
        return css_var(name)
            .and_then(|v| resolve_length(&v))
            .or_else(|| fallback.and_then(resolve_length));
    }
    if let Some(px_value) = token.strip_suffix("px") {
        return px_value.parse::<f64>().ok().map(px_length);
    }
    if let Some(rem_value) = token.strip_suffix("rem") {
        return rem_value
            .parse::<f32>()
            .ok()
            .map(|v| AbsoluteLength::Rems(gpui_kit::gpui::Rems(v)).into());
    }
    if let Some(percent) = token.strip_suffix('%') {
        return percent
            .parse::<f32>()
            .ok()
            .map(|v| DefiniteLength::Fraction(v / 100.0));
    }
    if let Some(value) = viewport_length(token) {
        return Some(px_length(value as f64));
    }
    token.parse::<f64>().ok().map(px_length)
}

/// `resolve_length` specialized to pixels for edge sizes (margins,
/// paddings, borders, radius) — gpui edge APIs take `Pixels`, not
/// fractions. `rem` resolves against the 16px base.
fn resolve_px(token: &str) -> Option<f32> {
    let token = token.trim();
    if let Some(inner) = token
        .strip_prefix("var(")
        .and_then(|rest| rest.strip_suffix(')'))
    {
        let (name, fallback) = match inner.split_once(',') {
            Some((name, fallback)) => (name.trim(), Some(fallback.trim())),
            None => (inner.trim(), None),
        };
        return css_var(name)
            .and_then(|v| resolve_px(&v))
            .or_else(|| fallback.and_then(resolve_px));
    }
    if let Some(px_value) = token.strip_suffix("px") {
        return px_value.parse::<f32>().ok();
    }
    if let Some(rem_value) = token.strip_suffix("rem") {
        return rem_value.parse::<f32>().ok().map(|v| v * 16.0);
    }
    if let Some(value) = viewport_length(token) {
        return Some(value);
    }
    token.parse::<f32>().ok()
}

/// One edge value allowing `auto` — margins and insets are
/// `LengthPercentageAuto` in taffy, unlike padding.
fn len_or_auto(token: &str) -> Option<Length> {
    let token = token.trim();
    if token == "auto" {
        return Some(Length::Auto);
    }
    resolve_length(token).map(Length::Definite)
}

/// Like `box_edges` but preserves `auto` edges (margin/inset only).
fn box_len_edges(value: &str) -> Option<[Length; 4]> {
    let parts: Vec<Length> = shorthand_parts(value)
        .iter()
        .filter_map(|part| len_or_auto(part))
        .collect();
    Some(match parts.len() {
        1 => [parts[0]; 4],
        2 => [parts[0], parts[1], parts[0], parts[1]],
        3 => [parts[0], parts[1], parts[2], parts[1]],
        4 => [parts[0], parts[1], parts[2], parts[3]],
        _ => return None,
    })
}

/// Declarations of the node's inline `style` attribute — carried in the
/// extension `attrs` JSON for logseq-* elements or in the `data-attrs`
/// record for plain elements.
fn inline_declarations(node: &NodeSnapshot) -> Vec<(String, String)> {
    let mut style: Option<String> = None;
    if let Some(raw) = node.extension_string_prop("attrs") {
        if let Ok(attrs) = serde_json::from_str::<serde_json::Value>(raw) {
            for key in ["style", "data-style"] {
                if let Some(value) = attrs.get(key).and_then(|v| v.as_str()) {
                    style = Some(value.to_string());
                    break;
                }
            }
        }
    }
    if style.is_none() {
        if let Some(raw) = node.string_prop(Property::DataAttrs) {
            style = raw
                .split('\x1e')
                .filter_map(|record| record.split_once('\x1f'))
                .find(|(name, _)| *name == "style" || *name == "data-style")
                .map(|(_, value)| value.to_string());
        }
    }
    style
        .map(|raw| {
            raw.split(';')
                .filter_map(|decl| {
                    decl.split_once(':').map(|(name, value)| {
                        (name.trim().to_ascii_lowercase(), value.trim().to_string())
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

/// Apply a `margin`/`padding` shorthand's edge values (1-4 parts, px only).
fn box_edges(value: &str) -> Option<[f64; 4]> {
    let parts: Vec<f64> = value
        .split_whitespace()
        .filter_map(|part| part.trim_end_matches("px").parse::<f64>().ok())
        .collect();
    Some(match parts.len() {
        1 => [parts[0]; 4],
        2 => [parts[0], parts[1], parts[0], parts[1]],
        3 => [parts[0], parts[1], parts[2], parts[1]],
        4 => [parts[0], parts[1], parts[2], parts[3]],
        _ => return None,
    })
}

/// Whitespace split that keeps `var(--a, var(--b))` whole — a CSS value
/// may carry spaces inside balanced parens.
fn shorthand_parts(value: &str) -> Vec<&str> {
    let mut parts = Vec::new();
    let mut depth = 0i32;
    let mut start = None;
    for (i, c) in value.char_indices() {
        match c {
            '(' => depth += 1,
            ')' => depth = (depth - 1).max(0),
            c if c.is_whitespace() && depth == 0 => {
                if let Some(s) = start.take() {
                    parts.push(&value[s..i]);
                }
                continue;
            }
            _ => {}
        }
        if start.is_none() {
            start = Some(i);
        }
    }
    if let Some(s) = start {
        parts.push(&value[s..]);
    }
    parts
}

/// Translate an inline-style declaration into the matching gpui styling.
/// The dom extension family uses inline style for layout-critical values
/// (sidebar width vars, code editor heights, highlights) — ignoring them
/// visibly breaks those surfaces.
fn apply_inline_style<E: Styled>(mut element: E, node: &NodeSnapshot, theme: &Theme) -> E {
    for (prop, value) in inline_declarations(node) {
        element = apply_decl(element, &prop, &value, theme);
    }
    element
}

/// Apply one `prop: value` CSS declaration — shared by inline styles and
/// registered semantic classes.
fn apply_decl<E: Styled>(mut element: E, prop: &str, value: &str, theme: &Theme) -> E {
    {
        let prop = prop;
        let value = value;
        if let Some(length) = resolve_length(value) {
            element = match prop {
                "width" => element.w(length),
                "height" => element.h(length),
                "min-width" => element.min_w(length),
                "min-height" => element.min_h(length),
                "max-width" => element.max_w(length),
                "max-height" => element.max_h(length),
                "line-height" => element.line_height(length),
                _ => element,
            };
            if matches!(
                prop,
                "width" | "height" | "min-width" | "min-height" | "max-width" | "max-height"
                    | "line-height"
            ) {
                return element;
            }
        }
        element = match prop {
            "display" => match value {
                "none" => element.invisible(),
                "flex" | "inline-flex" => element.flex().flex_row(),
                "grid" => element.grid(),
                _ => element,
            },
            "align-items" => match value {
                "center" => element.items_center(),
                "start" | "flex-start" => element.items_start(),
                "end" | "flex-end" => element.items_end(),
                "baseline" => element.items_baseline(),
                "stretch" => element.items_stretch(),
                _ => element,
            },
            "justify-content" => match value {
                "center" => element.justify_center(),
                "end" | "flex-end" => element.justify_end(),
                "start" | "flex-start" => element.justify_start(),
                "space-between" => element.justify_between(),
                "space-around" => element.justify_around(),
                "space-evenly" => element.justify_evenly(),
                _ => element,
            },
            "gap" => match resolve_px(&value) {
                Some(v) => element.gap(px(v)),
                None => element,
            },
            "column-gap" | "gap-x" => match resolve_px(&value) {
                Some(v) => element.gap_x(px(v)),
                None => element,
            },
            "row-gap" | "gap-y" => match resolve_px(&value) {
                Some(v) => element.gap_y(px(v)),
                None => element,
            },
            "flex-shrink" => match value.parse::<f32>() {
                Ok(v) => element.flex_shrink(v),
                Err(_) => element,
            },
            "flex-grow" => match value.parse::<f32>() {
                Ok(v) if v > 0. => element.flex_1(),
                _ => element,
            },
            "position" => match value {
                "absolute" => element.absolute(),
                "relative" => element.relative(),
                // Taffy has no viewport-anchored `fixed`; nearest-positioned-
                // ancestor semantics mean overlay ancestors must be
                // window-sized layers (the app registers those classes).
                "fixed" | "sticky" => element.absolute(),
                _ => element,
            },
            "inset" => match box_len_edges(value) {
                Some([t, r, b, l]) => element.top(t).right(r).bottom(b).left(l),
                None => element,
            },
            "top" => match len_or_auto(value) {
                Some(v) => element.top(v),
                None => element,
            },
            "bottom" => match len_or_auto(value) {
                Some(v) => element.bottom(v),
                None => element,
            },
            "left" => match len_or_auto(value) {
                Some(v) => element.left(v),
                None => element,
            },
            "right" => match len_or_auto(value) {
                Some(v) => element.right(v),
                None => element,
            },
            "margin" => match box_len_edges(value) {
                Some([t, r, b, l]) => element.mt(t).mr(r).mb(b).ml(l),
                None => element,
            },
            "margin-top" => match len_or_auto(value) {
                Some(v) => element.mt(v),
                None => element,
            },
            "margin-bottom" => match len_or_auto(value) {
                Some(v) => element.mb(v),
                None => element,
            },
            "margin-left" => match len_or_auto(value) {
                Some(v) => element.ml(v),
                None => element,
            },
            "margin-right" => match len_or_auto(value) {
                Some(v) => element.mr(v),
                None => element,
            },
            "padding" => match box_edges(&value) {
                Some([t, r, b, l]) => element
                    .pt(px(t as f32))
                    .pr(px(r as f32))
                    .pb(px(b as f32))
                    .pl(px(l as f32)),
                None => element,
            },
            "padding-top" => match resolve_px(&value) {
                Some(v) => element.pt(px(v)),
                None => element,
            },
            "padding-bottom" => match resolve_px(&value) {
                Some(v) => element.pb(px(v)),
                None => element,
            },
            "padding-left" => match resolve_px(&value) {
                Some(v) => element.pl(px(v)),
                None => element,
            },
            "padding-right" => match resolve_px(&value) {
                Some(v) => element.pr(px(v)),
                None => element,
            },
            "background" | "background-color" => match color_themed(&value, theme) {
                Some(color) => element.bg(color),
                None => element,
            },
            "color" => match color_themed(&value, theme) {
                Some(color) => element.text_color(color),
                None => element,
            },
            "border" => {
                // `Npx solid <color>` shorthand.
                let mut el = element;
                for part in shorthand_parts(&value) {
                    if let Some(v) = part.trim_end_matches("px").parse::<f32>().ok() {
                        el = el.border(px(v));
                    } else if let Some(c) = color_themed(part, theme) {
                        el = el.border_color(c);
                    }
                }
                el
            }
            "border-width" | "border-left" | "border-right" | "border-top"
            | "border-bottom" => {
                let mut el = element;
                for part in shorthand_parts(&value) {
                    if let Some(v) = part.trim_end_matches("px").parse::<f32>().ok() {
                        el = match prop {
                            "border-left" => el.border_l(px(v)),
                            "border-right" => el.border_r(px(v)),
                            "border-top" => el.border_t(px(v)),
                            "border-bottom" => el.border_b(px(v)),
                            _ => el.border(px(v)),
                        };
                    } else if let Some(c) = color_themed(part, theme) {
                        el = el.border_color(c);
                    }
                }
                el
            }
            "border-color" => match color_themed(&value, theme) {
                Some(color) => element.border_color(color),
                None => element,
            },
            "border-radius" => match resolve_px(&value) {
                Some(v) => element.rounded(px(v)),
                None => element,
            },
            "font-weight" => match value {
                "bold" | "700" => element.font_weight(gpui_kit::gpui::FontWeight::BOLD),
                "600" | "semibold" => element.font_weight(gpui_kit::gpui::FontWeight::SEMIBOLD),
                "500" | "medium" => element.font_weight(gpui_kit::gpui::FontWeight::MEDIUM),
                _ => element,
            },
            "font-style" if value == "italic" => element.italic(),
            "text-decoration" | "text-decoration-line" => {
                if value.contains("line-through") {
                    element.line_through()
                } else if value.contains("underline") {
                    element.underline()
                } else {
                    element
                }
            }
            "font-family" => {
                if value.contains("monospace") || value.contains("mono") {
                    element.font_family(theme.mono_font_family.clone())
                } else {
                    element
                }
            }
            "font-size" => match resolve_px(&value) {
                Some(v) => element.text_size(px(v)),
                None => element,
            },
            "opacity" => match value.parse::<f32>() {
                Ok(v) => element.opacity(v),
                Err(_) => element,
            },
            "aspect-ratio" => {
                // "16 / 9", "4/3", or a bare ratio number.
                let ratio = value
                    .split('/')
                    .filter_map(|part| part.trim().parse::<f32>().ok())
                    .collect::<Vec<_>>();
                match ratio.as_slice() {
                    [w, h] if *h != 0. => element.aspect_ratio(w / h),
                    [v] => element.aspect_ratio(*v),
                    _ => element,
                }
            }
            "flex-direction" => match value {
                "column" | "column-reverse" => element.flex_col(),
                "row" | "row-reverse" => element.flex_row(),
                _ => element,
            },
            "flex" => match value {
                "none" => element.flex_shrink(0.),
                _ => match value.parse::<f32>() {
                    Ok(v) if v > 0. => element.flex_grow(v).flex_shrink(1.),
                    _ => element,
                },
            },
            // `place-items: center` on an absolute-positioning layer — taffy
            // aligns abspos children via the parent's justify/align, which
            // is the expressible form of the web's `transform:
            // translate(-50%,-50%)` centering.
            "place-items" => match value {
                v if v.contains("center") => element.items_center().justify_center(),
                _ => element,
            },
            "justify-items" => match value {
                "center" => element.justify_center(),
                _ => element,
            },
            "overflow" => match value {
                "hidden" => element.overflow_hidden(),
                _ => element,
            },
            "overflow-x" if value == "hidden" => element.overflow_x_hidden(),
            "overflow-y" if value == "hidden" => element.overflow_y_hidden(),
            "visibility" if value == "hidden" => element.invisible(),
            "white-space" if value == "nowrap" => element.whitespace_nowrap(),
            "cursor" if value == "pointer" => element.cursor_pointer(),
            _ => element,
        };
    }
    element
}

/// Font semantics of inline HTML tags — the web emits emphasis through
/// tags (`<b>/<i>/<del>/<mark>/<code>`) and the `text` `as` prop carries
/// the same vocabulary; gpui has no UA stylesheet, so callers apply the
/// tag's style to the run.
pub(crate) fn inline_tag_style<E: Styled>(element: E, tag: &str, theme: &Theme) -> E {
    match tag {
        "b" | "strong" => element.font_weight(gpui_kit::gpui::FontWeight::BOLD),
        "i" | "em" | "dfn" | "var" => element.italic(),
        "del" | "s" => element.line_through(),
        "u" | "ins" => element.underline(),
        "mark" => element.bg(theme.warning).text_color(theme.foreground),
        "code" | "kbd" | "samp" => element
            .font_family(theme.mono_font_family.clone())
            .text_sm()
            .px_1()
            .rounded_sm()
            .bg(theme.secondary),
        "small" | "sub" | "sup" => element.text_xs(),
        // Logseq's reset styles `a { text-decoration: none }` — links are
        // colored, never underlined (all-pages/journals parity).
        "a" => element.text_color(theme.primary),
        _ => element,
    }
}

/// Convenience composition used by most kinds: frame + inline style +
/// layout + surface + style-class, in wire order semantics. `style-class`
/// lives in standard props for component kinds and in extension props for
/// extension nodes. `theme` resolves `var(--ls-*)`/semantic tokens the
/// web app declares on `:root`.
pub fn all<E: Styled>(element: E, node: &NodeSnapshot, theme: &Theme) -> E {
    // Cascade order: the semantic class is the lowest layer (like a CSS
    // rule); typed props (frame/layout/surface) and the inline `style`
    // attr all behave as inline styles on the web twin and must win over
    // it — e.g. `ui__button as-text` carries `background:transparent`
    // while `~background` is the swatch's real fill.
    let element = match node
        .string_prop(Property::StyleClass)
        .or_else(|| node.extension_string_prop("style-class"))
    {
        Some(classes) => style_class(element, classes, theme),
        None => element,
    };
    let mut element = frame(element, node);
    element = apply_inline_style(element, node, theme);
    let element = layout(element, node);
    let element = surface(element, node, theme);
    let element = appearance(element, node, theme);
    match node.float_prop(Property::Opacity) {
        Some(value) => element.opacity(value as f32),
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
        let mut element = style_class(div(), token, &Theme::default());
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
            value_revision: 0,
        };
        let mut element = all(div(), &node, &Theme::default());
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
