//! Canonical LUI presentation translated through public NSH style APIs.
use crate::{contract::DisplayValue, store::Node};
use nsh_core::{
    Color, PropertyValue, StyleDecl, StyleKey, StyleValue,
    element::{AdaptiveColor, Style, StyleRefinement, Tokens},
    geometry::{Points, Size},
    prelude::*,
};
use serde_json::Value;
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};

#[derive(Clone, Debug, PartialEq)]
enum TokenValue {
    Fixed(String),
    Adaptive { light: String, dark: String },
}
impl TokenValue {
    fn at(&self, dark: bool) -> &str {
        match self {
            Self::Fixed(value) => value,
            Self::Adaptive {
                light,
                dark: dark_value,
            } => {
                if dark {
                    dark_value
                } else {
                    light
                }
            }
        }
    }
}

/// The renderer retains this value per effective theme scope. Native tokens are
/// surface defaults; LUI's JSON overlays and appearance remain subtree-local.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct ThemeView {
    base: Arc<Tokens>,
    values: Arc<BTreeMap<String, TokenValue>>,
    cyclic: Arc<[BTreeSet<String>; 2]>,
    mode: Option<bool>,
    system_dark: bool,
    pub reduced_motion: bool,
}
impl ThemeView {
    pub fn new(base: Arc<Tokens>, system_dark: bool, reduced_motion: bool) -> Self {
        Self {
            // The embedding engine can supply only its overrides (including
            // an empty set in headless roots), just as nsh_base::theme() does.
            base: Arc::new(base.over(nsh_base::Theme::default().tokens())),
            values: Arc::default(),
            cyclic: Arc::default(),
            mode: None,
            system_dark,
            reduced_motion,
        }
    }

    /// Apply the existing LUI Fixed/Adaptive wire payload, never a shadcn file.
    pub fn overlay(&self, node: &Node) -> Result<Self, String> {
        let mut next = self.clone();
        if let Some(value) = node.props.get("theme-mode") {
            next.mode = match value.as_str() {
                Some("system") => None,
                Some("light") => Some(false),
                Some("dark") => Some(true),
                _ => return Err("NSH theme-mode requires system, light or dark".into()),
            };
        }
        if let Some(encoded) = node.props.get("theme") {
            let encoded = encoded
                .as_str()
                .ok_or("NSH theme requires a JSON object string")?;
            let value: Value =
                serde_json::from_str(encoded).map_err(|error| format!("NSH theme: {error}"))?;
            let object = value
                .as_object()
                .ok_or("NSH theme requires a JSON object")?;
            let values = Arc::make_mut(&mut next.values);
            for (name, value) in object {
                if name.trim().is_empty() {
                    return Err("NSH theme token name must not be empty".into());
                }
                let fixed =
                    |value: &Value| value.as_str().filter(|s| !s.is_empty()).map(str::to_owned);
                let token = if let Some(value) = fixed(value) {
                    TokenValue::Fixed(value)
                } else if let Some(pair) = value.as_object() {
                    TokenValue::Adaptive {
                        light: pair.get("light").and_then(fixed).ok_or_else(|| {
                            format!("NSH theme token {name} requires light and dark strings")
                        })?,
                        dark: pair.get("dark").and_then(fixed).ok_or_else(|| {
                            format!("NSH theme token {name} requires light and dark strings")
                        })?,
                    }
                } else {
                    return Err(format!(
                        "NSH theme token {name} requires a string or light/dark pair"
                    ));
                };
                values.insert(name.clone(), token);
            }
            next.cyclic = Arc::new([
                cyclic_variables(&next.values, false)?,
                cyclic_variables(&next.values, true)?,
            ]);
        }
        for name in next
            .values
            .keys()
            .filter(|name| next.base.color(name).is_some())
        {
            next.color(name)?;
        }
        next.radius()?;
        Ok(next)
    }

    pub(crate) fn has_value(&self, name: &str) -> bool {
        self.values.contains_key(name)
    }
    pub(crate) fn typography(&self) -> Result<(Option<String>, Option<Points>), String> {
        let family = if self.has_value("--lx-font-stack") {
            let family = self.text("var(--lx-font-stack)")?;
            if family.trim().is_empty() {
                return Err("application theme requires a resolved font stack".into());
            }
            Some(family)
        } else {
            None
        };
        let size = if self.has_value("--lx-root-text-size") {
            let value = self.text("var(--lx-root-text-size)")?;
            let pixels = value
                .trim()
                .strip_suffix("px")
                .ok_or("application root text size requires pixels")?;
            let size = pixels
                .parse::<f32>()
                .map_err(|_| "invalid application root text size")?;
            if !size.is_finite() || size <= 0.0 {
                return Err("application root text size must be positive and finite".into());
            }
            Some(px(size))
        } else {
            None
        };
        Ok((family, size))
    }

    fn appearance(&self, dark: bool) -> bool {
        self.mode.unwrap_or(dark)
    }

    pub fn color(&self, expression: &str) -> Result<AdaptiveColor, String> {
        let light = self.color_at(expression, self.appearance(false), &mut BTreeSet::new())?;
        let dark = self.color_at(expression, self.appearance(true), &mut BTreeSet::new())?;
        Ok(AdaptiveColor::new(light, dark))
    }
    pub fn radius(&self) -> Result<Points, String> {
        if let Some(value) = self.values.get("radius") {
            let text = self.text(value.at(self.mode.unwrap_or(self.system_dark)))?;
            let text = text.trim();
            let (text, factor) = if let Some(rem) = text.strip_suffix("rem") {
                (rem, 16.0)
            } else {
                (text.strip_suffix("px").unwrap_or(text), 1.0)
            };
            let radius = text
                .parse::<f32>()
                .map_err(|_| "NSH radius requires points or rem")?
                * factor;
            if !radius.is_finite() || radius < 0.0 {
                return Err("NSH radius is outside native layout range".into());
            }
            return Ok(px(radius));
        }
        Ok(px(self.base.number("radius").unwrap_or(0.0)))
    }

    fn color_at(
        &self,
        expression: &str,
        dark: bool,
        visiting: &mut BTreeSet<String>,
    ) -> Result<Color, String> {
        self.foreground_at(expression, dark, visiting)?
            .ok_or_else(|| "NSH inherited color is valid only for foreground paint".into())
    }

    fn foreground(&self, expression: &str) -> Result<Foreground, String> {
        let light = self.foreground_at(expression, self.appearance(false), &mut BTreeSet::new())?;
        let dark = self.foreground_at(expression, self.appearance(true), &mut BTreeSet::new())?;
        Ok(match (light, dark) {
            (None, None) => Foreground::Inherit,
            (Some(light), Some(dark)) => Foreground::Color(AdaptiveColor::new(light, dark)),
            // A mixed token follows this scoped theme's actual appearance. The
            // renderer refreshes ThemeView on appearance changes, so the native
            // class and explicit color change together; no parent color is read.
            (light, dark) => match if self.appearance(self.system_dark) {
                dark
            } else {
                light
            } {
                Some(color) => Foreground::Color(color.into()),
                None => Foreground::Inherit,
            },
        })
    }

    fn foreground_at(
        &self,
        expression: &str,
        dark: bool,
        visiting: &mut BTreeSet<String>,
    ) -> Result<Option<Color>, String> {
        let expression = self.substitute(expression, dark, visiting)?;
        let name = expression.trim();
        if name.eq_ignore_ascii_case("inherit") || name.eq_ignore_ascii_case("currentcolor") {
            return Ok(None);
        }
        if let Some(value) = self.values.get(name) {
            if !visiting.insert(name.to_owned()) {
                return Err(format!("NSH cyclic color token {name}"));
            }
            let result = self.foreground_at(value.at(dark), dark, visiting);
            visiting.remove(name);
            return result;
        }
        if let Some(color) = self.base.color(name) {
            return Ok(Some(if dark { color.dark } else { color.light }.into()));
        }
        Color::parse(name)
            .map(Some)
            .ok_or_else(|| format!("NSH unresolved color {name:?}"))
    }

    fn variable(
        &self,
        name: &str,
        dark: bool,
        visiting: &mut BTreeSet<String>,
    ) -> Result<String, String> {
        let key = if self.values.contains_key(name) {
            name
        } else {
            name.strip_prefix("--").unwrap_or(name)
        };
        if self.cyclic[usize::from(dark)].contains(key) {
            return Err(format!("NSH cyclic theme variable {name}"));
        }
        if !visiting.insert(name.to_owned()) {
            return Err(format!("NSH cyclic theme variable {name}"));
        }
        let result = if let Some(value) = self.values.get(name) {
            self.substitute(value.at(dark), dark, visiting)
        } else {
            let name = name.strip_prefix("--").unwrap_or(name);
            if let Some(value) = self.values.get(name) {
                self.substitute(value.at(dark), dark, visiting)
            } else if let Some(color) = self.base.color(name) {
                Ok(if dark { color.dark } else { color.light }.to_hex())
            } else if let Some(number) = self.base.number(name) {
                Ok(number.to_string())
            } else if let Some(font) = self.base.font(name) {
                Ok(font.to_string())
            } else {
                Err(format!("NSH unresolved theme variable --{name}"))
            }
        };
        visiting.remove(name);
        result
    }

    fn substitute(
        &self,
        value: &str,
        dark: bool,
        visiting: &mut BTreeSet<String>,
    ) -> Result<String, String> {
        let mut result = String::new();
        let mut cursor = 0;
        while let Some(variable) = next_variable(value, cursor)? {
            result.push_str(&value[cursor..variable.start]);
            let replacement = self
                .variable(variable.name, dark, visiting)
                .or_else(|error| {
                    variable.fallback.map_or(Err(error), |fallback| {
                        self.substitute(fallback, dark, visiting)
                    })
                })?;
            result.push_str(&replacement);
            cursor = variable.end;
        }
        result.push_str(&value[cursor..]);
        Ok(result)
    }

    pub(crate) fn text(&self, value: &str) -> Result<String, String> {
        self.substitute(
            value,
            self.mode.unwrap_or(self.system_dark),
            &mut BTreeSet::new(),
        )
    }
}

fn cyclic_variables(
    values: &BTreeMap<String, TokenValue>,
    dark: bool,
) -> Result<BTreeSet<String>, String> {
    fn visit(
        name: &str,
        values: &BTreeMap<String, TokenValue>,
        dark: bool,
        done: &mut BTreeSet<String>,
        stack: &mut Vec<String>,
        cyclic: &mut BTreeSet<String>,
    ) -> Result<(), String> {
        if let Some(start) = stack.iter().position(|at| at == name) {
            cyclic.extend(stack[start..].iter().cloned());
            return Ok(());
        }
        if done.contains(name) {
            return Ok(());
        }
        let Some(value) = values.get(name) else {
            return Ok(());
        };
        stack.push(name.to_owned());
        let value = value.at(dark);
        let mut cursor = 0;
        // Fallback references also belong to CSS's dependency graph, even
        // when the primary reference is currently defined.
        while let Some(variable) = next_variable(value, cursor)? {
            let key = if values.contains_key(variable.name) {
                variable.name
            } else {
                variable.name.strip_prefix("--").unwrap_or(variable.name)
            };
            visit(key, values, dark, done, stack, cyclic)?;
            cursor = variable.start + 4;
        }
        stack.pop();
        done.insert(name.to_owned());
        Ok(())
    }
    let mut done = BTreeSet::new();
    let mut cyclic = BTreeSet::new();
    let mut stack = Vec::new();
    for name in values.keys() {
        visit(name, values, dark, &mut done, &mut stack, &mut cyclic)?;
    }
    Ok(cyclic)
}

struct Variable<'a> {
    start: usize,
    end: usize,
    name: &'a str,
    fallback: Option<&'a str>,
}

/// Scan CSS tokens, leaving quoted strings and comments untouched.
fn next_variable(value: &str, start: usize) -> Result<Option<Variable<'_>>, String> {
    let bytes = value.as_bytes();
    let mut index = start;
    let mut quote = 0;
    while index < bytes.len() {
        let byte = bytes[index];
        if byte == b'\\' {
            index = (index + 2).min(bytes.len());
            continue;
        }
        if quote != 0 {
            if quote == byte {
                quote = 0;
            }
            index += 1;
            continue;
        }
        if byte == b'\'' || byte == b'"' {
            quote = byte;
            index += 1;
            continue;
        }
        if bytes[index..].starts_with(b"/*") {
            let end = value[index + 2..]
                .find("*/")
                .ok_or("NSH unterminated CSS comment")?;
            index += end + 4;
            continue;
        }
        let preceded = index > 0
            && (bytes[index - 1].is_ascii_alphanumeric()
                || matches!(bytes[index - 1], b'-' | b'_')
                || bytes[index - 1] >= 128);
        if !preceded
            && bytes[index..]
                .get(..4)
                .is_some_and(|s| s.eq_ignore_ascii_case(b"var("))
        {
            let mut depth = 1;
            let mut comma = None;
            let mut inner_quote = 0;
            let mut end = index + 4;
            while end < bytes.len() {
                let byte = bytes[end];
                if byte == b'\\' {
                    end = (end + 2).min(bytes.len());
                    continue;
                }
                if inner_quote != 0 {
                    if byte == inner_quote {
                        inner_quote = 0;
                    }
                } else if byte == b'\'' || byte == b'"' {
                    inner_quote = byte;
                } else if bytes[end..].starts_with(b"/*") {
                    let comment = value[end + 2..]
                        .find("*/")
                        .ok_or("NSH unterminated CSS comment")?;
                    end += comment + 4;
                    continue;
                } else if byte == b'(' {
                    depth += 1;
                } else if byte == b')' {
                    depth -= 1;
                } else if byte == b',' && depth == 1 && comma.is_none() {
                    comma = Some(end);
                }
                if depth == 0 {
                    let name = value[index + 4..comma.unwrap_or(end)].trim();
                    if !name.starts_with("--")
                        || name.len() == 2
                        || name.contains([' ', '\t', '\r', '\n', '(', ')', ','])
                    {
                        return Err("NSH invalid CSS variable name".into());
                    }
                    return Ok(Some(Variable {
                        start: index,
                        end: end + 1,
                        name,
                        fallback: comma.map(|comma| value[comma + 1..end].trim()),
                    }));
                }
                end += 1;
            }
            return Err("NSH unterminated CSS variable".into());
        }
        index += 1;
    }
    if quote != 0 {
        return Err("NSH unterminated CSS string".into());
    }
    Ok(None)
}

fn numeric(value: &Value, property: &str) -> Result<f32, String> {
    let number = value
        .as_f64()
        .ok_or_else(|| format!("NSH {property} requires a number"))?;
    if !number.is_finite() || number.abs() > f32::MAX as f64 {
        return Err(format!("NSH {property} is outside native layout range"));
    }
    Ok(number as f32)
}

fn parsed(
    key: StyleKey,
    value: &Value,
    property: &str,
    theme: &ThemeView,
) -> Result<PropertyValue, String> {
    let number;
    let text;
    let input = if value.is_number() {
        number = numeric(value, property)?;
        StyleValue::Number(number)
    } else if let Some(value) = value.as_str() {
        text = theme.text(value)?;
        StyleValue::Str(text.trim())
    } else {
        return Err(format!("NSH {property} requires a number or string"));
    };
    key.parse_value(input)
        .map_err(|_| format!("NSH does not support {property}={value}"))
}

fn declaration(
    decls: &mut Vec<StyleDecl>,
    key: StyleKey,
    value: &Value,
    property: &str,
    theme: &ThemeView,
) -> Result<(), String> {
    decls.push(StyleDecl::Set(key, parsed(key, value, property, theme)?));
    Ok(())
}

/// Native hosts and their command content share the same layout declarations.
pub(crate) fn content_layout(node: &Node, theme: &ThemeView) -> Result<Vec<StyleDecl>, String> {
    let mut decls = Vec::with_capacity(3);
    for (name, key) in [
        ("gap", StyleKey::Gap),
        ("cross", StyleKey::AlignItems),
        ("main", StyleKey::JustifyContent),
    ] {
        if let Some(value) = node.props.get(name) {
            let alias = Value::from("space-between");
            let value = if name == "main" && value.as_str() == Some("space_between") {
                &alias
            } else {
                value
            };
            declaration(&mut decls, key, value, name, theme)?;
        }
    }
    Ok(decls)
}

/// NSH stores layer order as i32 after parsing its numeric style through f32.
pub(crate) fn z_index(node: &Node) -> Result<Option<i32>, String> {
    node.props
        .get("z-index")
        .map(|value| {
            let integer = value
                .as_i64()
                .ok_or("NSH z-index requires an exact integer")?;
            let index =
                i32::try_from(integer).map_err(|_| "NSH z-index exceeds the native i32 range")?;
            if f64::from(index as f32) != f64::from(index) {
                return Err(
                    "NSH z-index is not exactly representable by the native style parser".into(),
                );
            }
            Ok(index)
        })
        .transpose()
}

#[derive(Clone, PartialEq)]
pub(crate) struct EdgeInsetStyles {
    pub host: Style,
    pub decoration: Style,
    pub inherited: Style,
    pub insets: [Points; 4],
    pub gap: Points,
}

#[derive(Clone, PartialEq)]
pub(crate) struct ContextMenuStyles {
    pub outer: Style,
    pub trigger: Style,
}

const CONTEXT_LAYOUT: &[StyleKey] = &[
    StyleKey::Display,
    StyleKey::Position,
    StyleKey::Flex,
    StyleKey::FlexGrow,
    StyleKey::FlexShrink,
    StyleKey::FlexBasis,
    StyleKey::AlignSelf,
    StyleKey::Width,
    StyleKey::Height,
    StyleKey::MinWidth,
    StyleKey::MaxWidth,
    StyleKey::MinHeight,
    StyleKey::MaxHeight,
    StyleKey::Margin,
    StyleKey::MarginHorizontal,
    StyleKey::MarginVertical,
    StyleKey::MarginTop,
    StyleKey::MarginRight,
    StyleKey::MarginBottom,
    StyleKey::MarginLeft,
    StyleKey::Top,
    StyleKey::Right,
    StyleKey::Bottom,
    StyleKey::Left,
    StyleKey::ZIndex,
    StyleKey::GridColumn,
];

/// The native ContextMenu has one outer view. Move only parent-facing layout
/// there; its retained trigger owns padding, content layout, paint and states.
pub(crate) fn context_menu_styles(
    node: &Node,
    theme: &ThemeView,
    viewport: Size<Points>,
    defaults: &Style,
) -> Result<ContextMenuStyles, String> {
    // Style::decls intentionally excludes its typed paint/state refinement.
    // Partition the compiler's declarations before combining that refinement.
    let (decls, paint) = compile_parts(node, theme, viewport)?;
    let external = |declaration: &StyleDecl| matches!(declaration, StyleDecl::Set(key, _) | StyleDecl::Default(key, _) if CONTEXT_LAYOUT.contains(key));
    let outer = Style::from_decls(
        defaults
            .decls()
            .iter()
            .chain(&decls)
            .filter(|declaration| external(declaration))
            .cloned(),
    );
    let trigger = Style::from_decls(
        CONTEXT_LAYOUT
            .iter()
            .map(|key| StyleDecl::Set(*key, PropertyValue::Default))
            .chain(
                decls
                    .iter()
                    .filter(|declaration| {
                        node.string("position") == "static"
                            && matches!(declaration, StyleDecl::Set(StyleKey::Position, _))
                    })
                    .cloned(),
            )
            .chain(
                decls
                    .iter()
                    .filter(|declaration| !external(declaration))
                    .cloned(),
            )
            // Typed styles apply as native defaults before inline declarations.
            // Fill must be an inline declaration after the constraint resets.
            .chain([StyleDecl::Set(
                StyleKey::Flex,
                StyleKey::Flex
                    .parse_value(StyleValue::Str("auto"))
                    .expect("native flex-auto value"),
            )]),
    )
    .then(&paint);
    Ok(ContextMenuStyles { outer, trigger })
}

fn pinned_surface_property(name: &str) -> bool {
    name.starts_with("padding")
        || matches!(
            name,
            "background"
                | "foreground"
                | "border-color"
                | "border-width"
                | "corner-radius"
                | "opacity"
                | "shadow"
        )
        || ["hover-", "pressed-", "focus-", "selected-", "disabled-"]
            .iter()
            .any(|prefix| name.starts_with(prefix))
}

/// Split an edge inset's authored surface from its outer layout, reusing the
/// canonical compiler for both parts and its resolved spacing declarations.
pub(crate) fn edge_inset_styles(
    node: &Node,
    theme: &ThemeView,
    compiled: &Style,
) -> Result<EdgeInsetStyles, String> {
    let mut resolved = nsh_core::Style::default();
    for declaration in compiled.decls() {
        declaration
            .apply(&mut resolved)
            .map_err(|error| format!("NSH edge-inset layout: {error:?}"))?;
    }
    // Canonical padding, borders and gap are absolute point integers. Their
    // resolved NSH layout values therefore contain no percentages or calc().
    let padding = resolved.layout.padding;
    let border = resolved.layout.border;
    let insets = [
        px(padding.top.into_raw().value() + border.top.into_raw().value()),
        px(padding.right.into_raw().value() + border.right.into_raw().value()),
        px(padding.bottom.into_raw().value() + border.bottom.into_raw().value()),
        px(padding.left.into_raw().value() + border.left.into_raw().value()),
    ];
    let gap = px(resolved.layout.gap.height.into_raw().value());
    let host = Style::from_decls(
        compiled
            .decls()
            .iter()
            .filter(|declaration| {
                !matches!(
                    declaration,
                    StyleDecl::Set(
                        StyleKey::Padding
                            | StyleKey::PaddingHorizontal
                            | StyleKey::PaddingVertical
                            | StyleKey::PaddingTop
                            | StyleKey::PaddingRight
                            | StyleKey::PaddingBottom
                            | StyleKey::PaddingLeft
                            | StyleKey::BorderWidth
                            | StyleKey::BorderRadius
                            | StyleKey::Opacity
                            | StyleKey::Gap
                            | StyleKey::AlignItems
                            | StyleKey::JustifyContent,
                        _
                    )
                )
            })
            .cloned(),
    );
    let host = if node.props.contains_key("theme") || node.props.contains_key("theme-mode") {
        host.then(&Style::from(
            StyleRefinement::default().text_color(theme.color("foreground")?),
        ))
    } else {
        host
    };
    let mut decoration = node.clone();
    decoration.kind = "box".into();
    decoration
        .props
        .retain(|name, _| pinned_surface_property(name) && !name.starts_with("padding"));
    let decoration = compile(&decoration, theme, Size::default())?;
    let mut inherited = node.clone();
    inherited.kind = "box".into();
    inherited.props.retain(|name, _| name == "foreground");
    let inherited = compile(&inherited, theme, Size::default())?;
    Ok(EdgeInsetStyles {
        host,
        decoration,
        inherited,
        insets,
        gap,
    })
}

/// Units accepted by the native typography adapter after theme resolution.
/// Keeping translation exhaustive prevents a newly parsed unit from silently
/// falling through to an unrelated native metric.
#[derive(Clone, Copy, Debug, PartialEq)]
enum FontSize {
    Points(Points),
    RootRem(f32),
    Em(f32),
}
impl FontSize {
    fn parse(value: &str) -> Result<Self, String> {
        let value = value.trim();
        let number = |text: &str| {
            text.trim()
                .parse::<f32>()
                .ok()
                .filter(|number| number.is_finite() && *number >= 0.0)
                .ok_or_else(|| format!("NSH unsupported font-size={value:?}"))
        };
        if let Some(value) = value.strip_suffix("rem") {
            return Ok(Self::RootRem(number(value)?));
        }
        if let Some(value) = value.strip_suffix("em") {
            return Ok(Self::Em(number(value)?));
        }
        Ok(Self::Points(px(number(
            value.strip_suffix("px").unwrap_or(value),
        )?)))
    }
    fn native(self) -> Result<PropertyValue, String> {
        let points = match self {
            Self::Points(points) => points,
            Self::RootRem(value) => px(value * nsh_core::geometry::REM_SIZE.0),
            Self::Em(value) => {
                if value == 1.0 {
                    // Unset the node's own size so the native text resolver
                    // inherits its actual parent, including live changes.
                    return Ok(PropertyValue::OptPoints(None));
                }
                return Err(
                    "NSH font-size em scaling other than 1em requires an inherited parent metric"
                        .into(),
                );
            }
        };
        if !points.0.is_finite() {
            return Err("NSH font-size exceeds the native point range".into());
        }
        Ok(PropertyValue::OptPoints(Some(points)))
    }
}

/// Translate only presentation here. Canonical scalar/kind/presence validation
/// stays generated from OCaml; controls and events keep their own owners.
pub(crate) fn compile(
    node: &Node,
    theme: &ThemeView,
    viewport: Size<Points>,
) -> Result<Style, String> {
    crate::white_space::validate(node)?;
    if is_contents(node) {
        // A contents anchor has no native box. Layout and paint declarations
        // cannot create padding, margins, dimensions or a background for it.
        for property in node.props.keys() {
            if matches!(
                property.as_str(),
                "theme"
                    | "theme-mode"
                    | "foreground"
                    | "font-family"
                    | "font-size"
                    | "font-weight"
                    | "font-style"
                    | "line-height"
                    | "letter-spacing"
                    | "text-alignment"
                    | "text-decoration"
                    | "user-select"
                    | "cursor"
                    | "hover-foreground"
                    | "pressed-foreground"
                    | "focus-foreground"
                    | "focus-within-foreground"
                    | "disabled-foreground"
            ) {
                return Err(format!(
                    "NSH contents anchors do not yet project inherited {property}; apply it to a containing native element"
                ));
            }
        }
        return Ok(Style::default());
    }
    let (decls, paint) = compile_parts(node, theme, viewport)?;
    Ok(Style::from_decls(decls).then(&paint))
}

pub(crate) fn is_contents(node: &Node) -> bool {
    node.extension.is_none()
        && node
            .props
            .get("display")
            .and_then(Value::as_str)
            .and_then(|value| DisplayValue::try_from(value).ok())
            == Some(DisplayValue::Contents)
}

// No wildcard: adding a canonical display case must fail this provider's build.
fn display_value(value: &Value) -> Result<(PropertyValue, bool), String> {
    let display = DisplayValue::try_from(value.as_str().ok_or("NSH display requires a string")?)?;
    let (keyword, hidden) = match display {
        DisplayValue::None => ("none", true),
        DisplayValue::Block => ("block", false),
        DisplayValue::Contents => {
            return Err("NSH contents is a structural anchor, not a native display style".into());
        }
        DisplayValue::Inline | DisplayValue::InlineBlock | DisplayValue::InlineFlex => {
            return Err(format!(
                "NSH display={} has no native inline layout provider",
                display.as_str()
            ));
        }
    };
    StyleKey::Display
        .parse_value(StyleValue::Str(keyword))
        .map(|value| (value, hidden))
        .map_err(|error| format!("NSH display: {error:?}"))
}

fn pointer_policy(node: &Node) -> Option<nsh_core::PointerEvents> {
    use nsh_core::PointerEvents;

    if let Some(enabled) = node.props.get("pointer-enabled").and_then(Value::as_bool) {
        return Some(if enabled {
            PointerEvents::Auto
        } else {
            PointerEvents::None
        });
    }
    // An empty layout spacer must not cover an interactive sibling in a Stack.
    // Explicit pointer subscriptions above can still opt it into native hits.
    if node.kind == "spacer" {
        return Some(PointerEvents::None);
    }
    let carrier = node
        .string("data-attrs")
        .split('\x1e')
        .any(|record| record.split_once('\x1f') == Some(("data-overlay-layer", "true")));
    let presented = matches!(
        node.kind.as_str(),
        "dialog" | "sheet" | "popover" | "dropdown-menu" | "context-menu" | "toast"
    ) || (node.kind == "drawer" && !node.props.contains_key("selected"));
    (!carrier && presented).then_some(PointerEvents::Auto)
}

fn compile_parts(
    node: &Node,
    theme: &ThemeView,
    viewport: Size<Points>,
) -> Result<(Vec<StyleDecl>, Style), String> {
    z_index(node)?;
    let mut decls = Vec::with_capacity(node.props.len() + 4);
    let mut native = view();
    // Preserve the desktop cover-layer contract: false inherits through the
    // subtree, while an explicit true or a presented surface opts back in.
    if let Some(policy) = pointer_policy(node) {
        native = native.pointer_events(policy);
    }
    if node.props.contains_key("theme") || node.props.contains_key("theme-mode") {
        native = native.text_color(theme.color("foreground")?);
        if node.kind == "root" {
            native = native.bg(theme.color("background")?);
        }
    }
    match node.kind.as_str() {
        "root" => declaration(
            &mut decls,
            StyleKey::Flex,
            &Value::from(1),
            "root flex",
            theme,
        )?,
        "spacer" => {
            declaration(
                &mut decls,
                StyleKey::FlexGrow,
                &Value::from(1),
                "spacer grow",
                theme,
            )?;
            declaration(
                &mut decls,
                StyleKey::FlexShrink,
                &Value::from(1),
                "spacer shrink",
                theme,
            )?;
        }
        "row" | "toolbar" | "button-group" | "toggle-group" | "breadcrumb" => {
            let direction = if node.string("orientation") == "vertical" {
                "column"
            } else {
                "row"
            };
            declaration(
                &mut decls,
                StyleKey::FlexDirection,
                &Value::from(direction),
                "orientation",
                theme,
            )?;
        }
        _ => {}
    }

    // Apply shorthands first, then axes, then explicit edges, independently of
    // the JSON map's sort order. Canonical spacing is in points.
    for (name, key) in [
        ("padding", StyleKey::Padding),
        ("padding-horizontal", StyleKey::PaddingHorizontal),
        ("padding-vertical", StyleKey::PaddingVertical),
        ("padding-top", StyleKey::PaddingTop),
        ("padding-right", StyleKey::PaddingRight),
        ("padding-bottom", StyleKey::PaddingBottom),
        ("padding-left", StyleKey::PaddingLeft),
        ("margin", StyleKey::Margin),
        ("margin-horizontal", StyleKey::MarginHorizontal),
        ("margin-vertical", StyleKey::MarginVertical),
        ("margin-top", StyleKey::MarginTop),
        ("margin-right", StyleKey::MarginRight),
        ("margin-bottom", StyleKey::MarginBottom),
        ("margin-left", StyleKey::MarginLeft),
    ] {
        if let Some(value) = node.props.get(name) {
            declaration(&mut decls, key, value, name, theme)?;
        }
    }
    decls.extend(content_layout(node, theme)?);
    for (name, key) in [
        ("grow", StyleKey::FlexGrow),
        ("shrink", StyleKey::FlexShrink),
        ("width", StyleKey::Width),
        ("height", StyleKey::Height),
        ("min-width", StyleKey::MinWidth),
        ("max-width", StyleKey::MaxWidth),
        ("min-height", StyleKey::MinHeight),
        ("max-height", StyleKey::MaxHeight),
        ("border-width", StyleKey::BorderWidth),
        ("corner-radius", StyleKey::BorderRadius),
        ("opacity", StyleKey::Opacity),
        ("text-alignment", StyleKey::TextAlign),
        ("font-family", StyleKey::FontFamily),
        ("letter-spacing", StyleKey::LetterSpacing),
        ("text-decoration", StyleKey::TextDecorationLine),
        ("flex-wrap", StyleKey::FlexWrap),
        ("line-clamp", StyleKey::NumberOfLines),
        ("text-overflow", StyleKey::TextOverflow),
        ("user-select", StyleKey::UserSelect),
        ("overflow", StyleKey::Overflow),
        ("cursor", StyleKey::Cursor),
        ("position", StyleKey::Position),
        ("z-index", StyleKey::ZIndex),
    ] {
        if let Some(value) = node.props.get(name) {
            declaration(&mut decls, key, value, name, theme)?;
        }
    }
    if let Some(value) = node.props.get("display") {
        let (display, hidden) = display_value(value)?;
        decls.push(StyleDecl::Set(StyleKey::Display, display));
        if hidden {
            // NSH display:none removes layout frames but does not itself hide
            // the accessibility subtree. Public native visibility does both.
            // Do not emit visible for ordinary children: a hidden ancestor
            // must remain authoritative when a descendant has display:block.
            decls.push(StyleDecl::Set(
                StyleKey::Visibility,
                PropertyValue::Bool(true),
            ));
        }
    }
    if let Some(value) = node.props.get("font-weight") {
        let weight = value
            .as_u64()
            .and_then(|weight| u16::try_from(weight).ok())
            .ok_or("NSH invalid font-weight")?;
        decls.push(StyleDecl::Set(
            StyleKey::FontWeight,
            PropertyValue::FontWeight(Some(weight)),
        ));
    }
    if let Some(value) = node.props.get("font-style") {
        // NSH exposes italic rather than a distinct oblique font face. This is
        // the existing desktop LUI equivalence for both slanted styles.
        let value = if value.as_str() == Some("oblique") {
            Value::from("italic")
        } else {
            value.clone()
        };
        declaration(&mut decls, StyleKey::FontStyle, &value, "font-style", theme)?;
    }
    if let Some(value) = node.props.get("font-size") {
        let text = theme.text(value.as_str().ok_or("NSH font-size requires a string")?)?;
        decls.push(StyleDecl::Set(
            StyleKey::FontSize,
            FontSize::parse(&text)?.native()?,
        ));
    }
    if let Some(value) = node.props.get("line-height") {
        declaration(
            &mut decls,
            StyleKey::LineHeight,
            value,
            "line-height",
            theme,
        )?;
    }
    for (name, key) in [
        ("inset-top", StyleKey::Top),
        ("inset-right", StyleKey::Right),
        ("inset-bottom", StyleKey::Bottom),
        ("inset-left", StyleKey::Left),
    ] {
        if let Some(value) = node.props.get(name).or_else(|| node.props.get("inset")) {
            declaration(&mut decls, key, value, name, theme)?;
        }
    }
    for (name, key, extent) in [
        ("width-viewport", StyleKey::Width, viewport.width.0),
        ("height-viewport", StyleKey::Height, viewport.height.0),
        ("min-width-viewport", StyleKey::MinWidth, viewport.width.0),
        ("max-width-viewport", StyleKey::MaxWidth, viewport.width.0),
        (
            "min-height-viewport",
            StyleKey::MinHeight,
            viewport.height.0,
        ),
        (
            "max-height-viewport",
            StyleKey::MaxHeight,
            viewport.height.0,
        ),
    ] {
        if let Some(value) = node.props.get(name) {
            let result = numeric(value, name)? * extent;
            let value = serde_json::Number::from_f64(f64::from(result))
                .map(Value::Number)
                .ok_or_else(|| format!("NSH {name} exceeds native layout range"))?;
            declaration(&mut decls, key, &value, name, theme)?;
        }
    }
    if let Some(value) = node.props.get("container-relative-frame") {
        let axes = value
            .as_str()
            .ok_or("NSH container-relative-frame requires axes")?;
        if node.number("container-relative-frame-inset", 0.0) != 0.0 {
            return Err("NSH container-relative-frame-inset is not implemented yet".into());
        }
        let minimum = axes.starts_with("min-");
        if axes.ends_with("horizontal") || axes.ends_with("both") {
            declaration(
                &mut decls,
                if minimum {
                    StyleKey::MinWidth
                } else {
                    StyleKey::Width
                },
                &Value::from("100%"),
                "container-relative-frame",
                theme,
            )?;
        }
        if axes.ends_with("vertical") || axes.ends_with("both") {
            declaration(
                &mut decls,
                if minimum {
                    StyleKey::MinHeight
                } else {
                    StyleKey::Height
                },
                &Value::from("100%"),
                "container-relative-frame",
                theme,
            )?;
        }
    }
    if let Some(value) = node.props.get("grid-column-span") {
        declaration(
            &mut decls,
            StyleKey::GridColumn,
            &Value::from(format!(
                "span {}",
                value.as_u64().ok_or("NSH invalid grid-column-span")?
            )),
            "grid-column-span",
            theme,
        )?;
    }
    if let Some(value) = node.props.get("transition") {
        transitions(
            &mut decls,
            value.as_str().ok_or("NSH transition requires a string")?,
            theme,
        )?;
    }
    if node.boolean("inert", false) {
        return Err("NSH inert subtree semantics are not implemented yet".into());
    }

    let base = Paint::read(node, "", theme)?;
    native = base.apply(native);
    let hover = Paint::read(node, "hover-", theme)?;
    let pressed = Paint::read(node, "pressed-", theme)?;
    let focus = Paint::read(node, "focus-", theme)?;
    let within = Paint::read(node, "focus-within-", theme)?;
    let selected = Paint::read(node, "selected-", theme)?;
    let selected_hover = Paint::read(node, "selected-hover-", theme)?;
    let disabled = Paint::read(node, "disabled-", theme)?;
    native = native
        .hover(|s| hover.apply(s))
        .active(|s| pressed.apply(s))
        .focus_visible(|s| focus.apply(s))
        .focus_within(|s| within.apply(s))
        .disabled_style(|s| disabled.apply(s));
    // Selection is a LUI-owned value; do not substitute checked or pressed.
    if node.boolean("selected", false) {
        native = selected.apply(native).hover(|s| selected_hover.apply(s));
    }
    let typed = Style::from(native.style().clone());
    Ok((decls, typed))
}

pub(crate) fn uses_viewport(node: &Node) -> bool {
    [
        "width-viewport",
        "height-viewport",
        "min-width-viewport",
        "max-width-viewport",
        "min-height-viewport",
        "max-height-viewport",
    ]
    .iter()
    .any(|name| node.props.contains_key(*name))
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum Foreground {
    Inherit,
    Color(AdaptiveColor),
}

/// Native class variants clear a component's own color at the same cascade
/// rank. An inline Color(None) would incorrectly outrank authored hover colors.
pub(crate) fn foreground_classes(
    node: &Node,
    theme: &ThemeView,
) -> Result<Option<SharedString>, String> {
    let read = |property: &str| -> Result<Option<Foreground>, String> {
        node.props
            .get(property)
            .map(|value| {
                theme.foreground(
                    value
                        .as_str()
                        .ok_or("NSH foreground requires a color string")?,
                )
            })
            .transpose()
    };
    // These are the canonical foreground channels. State shadows/backgrounds
    // have different properties; do not invent extra public color channels.
    let mut classes = Vec::new();
    for (paint, class) in [
        (read("foreground")?, "text-inherit"),
        (read("hover-foreground")?, "hover:text-inherit"),
    ] {
        if matches!(paint, Some(Foreground::Inherit)) {
            classes.push(class);
        }
    }
    Ok((!classes.is_empty()).then(|| classes.join(" ").into()))
}

#[derive(Default)]
struct Paint {
    background: Option<AdaptiveColor>,
    foreground: Option<Foreground>,
    border: Option<AdaptiveColor>,
    opacity: Option<f32>,
    shadow: Option<Shadow>,
}
enum Shadow {
    None,
    Small,
    Medium,
    Large,
    Layers(Vec<nsh_core::BoxShadow>),
}
impl Paint {
    fn read(node: &Node, prefix: &str, theme: &ThemeView) -> Result<Self, String> {
        let color = |suffix| -> Result<_, String> {
            node.props
                .get(&format!("{prefix}{suffix}"))
                .map(|value| {
                    theme.color(value.as_str().ok_or("NSH paint requires a color string")?)
                })
                .transpose()
        };
        let border_name = if prefix.is_empty() {
            "border-color"
        } else {
            "border"
        };
        let opacity = node
            .props
            .get(&format!("{prefix}opacity"))
            .map(|value| numeric(value, "opacity"))
            .transpose()?;
        let shadow = node
            .props
            .get(&format!("{prefix}shadow"))
            .map(|value| -> Result<Shadow, String> {
                let value = value.as_str().ok_or("NSH shadow requires a string")?;
                Ok(match value {
                    "none" => Shadow::None,
                    "sm" => Shadow::Small,
                    "md" => Shadow::Medium,
                    "lg" => Shadow::Large,
                    _ => {
                        let text = theme.text(value)?;
                        match StyleKey::BoxShadow
                            .parse_value(StyleValue::Str(&text))
                            .map_err(|_| format!("NSH invalid shadow {value:?}"))?
                        {
                            PropertyValue::Shadows(layers) => {
                                // The native flag means an explicitly named color.
                                if layers.iter().any(|(_, has_color)| !has_color) {
                                    return Err("NSH shadow currentColor requires an inherited foreground adapter".into());
                                }
                                Shadow::Layers(layers.iter().map(|(layer, _)| *layer).collect())
                            }
                            PropertyValue::Deferred(..) => {
                                return Err("NSH shadow currentColor requires an inherited foreground adapter".into());
                            }
                            _ => return Err("NSH shadow parser returned a non-shadow value".into()),
                        }
                    }
                })
            })
            .transpose()?;
        Ok(Self {
            background: color("background")?,
            foreground: node
                .props
                .get(&format!("{prefix}foreground"))
                .map(|value| {
                    theme.foreground(
                        value
                            .as_str()
                            .ok_or("NSH foreground requires a color string")?,
                    )
                })
                .transpose()?,
            border: color(border_name)?,
            opacity,
            shadow,
        })
    }
    fn apply<S: Styled>(self, mut style: S) -> S {
        if let Some(color) = self.background {
            style = style.bg(color);
        }
        match self.foreground {
            Some(Foreground::Color(color)) => style = style.text_color(color),
            // The public host app_class binding projects the native reset,
            // preserving the same state-variant cascade as concrete paint.
            Some(Foreground::Inherit) | None => {}
        }
        if let Some(color) = self.border {
            style = style.border_color(color);
        }
        if let Some(opacity) = self.opacity {
            style = style.opacity(opacity);
        }
        if let Some(shadow) = self.shadow {
            style = match shadow {
                Shadow::None => style.shadow_none(),
                Shadow::Small => style.shadow_sm(),
                Shadow::Medium => style.shadow_md(),
                Shadow::Large => style.shadow_lg(),
                Shadow::Layers(layers) => style.shadow(layers),
            };
        }
        style
    }
}

/// NSH transitions share one timing per element. Preserve compatible parallel
/// properties; reject distinct timings rather than silently changing them.
fn transitions(decls: &mut Vec<StyleDecl>, value: &str, theme: &ThemeView) -> Result<(), String> {
    let value = theme.text(value)?;
    let mut properties = Vec::new();
    let mut timing = None;
    for segment in split_css(&value, b',') {
        let words = split_css(segment, b' ');
        let Some(property) = words.first() else {
            return Err("NSH empty transition".into());
        };
        let mut times = Vec::new();
        let mut easing = "ease";
        for word in &words[1..] {
            if word.ends_with("ms") || word.ends_with('s') {
                times.push(*word);
            } else {
                easing = word;
            }
        }
        let duration = times.first().ok_or("NSH transition requires a duration")?;
        let delay = times.get(1).copied().unwrap_or("0ms");
        let parsed = [
            StyleKey::TransitionDuration.parse_value(StyleValue::Str(duration)),
            StyleKey::TransitionDelay.parse_value(StyleValue::Str(delay)),
            StyleKey::TransitionTimingFunction.parse_value(StyleValue::Str(easing)),
        ];
        let current = parsed
            .into_iter()
            .collect::<Result<Vec<_>, _>>()
            .map_err(|_| format!("NSH unsupported transition timing in {segment:?}"))?;
        if let Some(previous) = &timing {
            if previous != &current {
                return Err(
                    "NSH parallel transitions require the same duration, delay and easing".into(),
                );
            }
        } else {
            timing = Some(current);
        }
        // These names parse in NSH but intentionally animate no property.
        if [
            "filter",
            "backdrop-filter",
            "display",
            "visibility",
            "content-visibility",
            "overlay",
            "pointer-events",
        ]
        .contains(property)
        {
            return Err(format!("NSH cannot animate transition property {property}"));
        }
        properties.push(*property);
    }
    let properties = properties.join(",");
    declaration(
        decls,
        StyleKey::TransitionProperty,
        &Value::from(properties),
        "transition",
        theme,
    )?;
    let timing = timing.ok_or("NSH empty transition")?;
    for (key, value) in [
        StyleKey::TransitionDuration,
        StyleKey::TransitionDelay,
        StyleKey::TransitionTimingFunction,
    ]
    .into_iter()
    .zip(timing)
    {
        let value = if theme.reduced_motion && key != StyleKey::TransitionTimingFunction {
            key.number_value(0.0)
                .map_err(|_| "NSH invalid reduced motion timing")?
        } else {
            value
        };
        decls.push(StyleDecl::Set(key, value));
    }
    Ok(())
}

fn split_css(value: &str, delimiter: u8) -> Vec<&str> {
    let mut parts = Vec::new();
    let mut depth = 0_u32;
    let mut start = 0;
    for (index, byte) in value.bytes().enumerate() {
        match byte {
            b'(' => depth += 1,
            b')' => depth = depth.saturating_sub(1),
            byte if depth == 0
                && (byte == delimiter || delimiter == b' ' && byte.is_ascii_whitespace()) =>
            {
                let part = value[start..index].trim();
                if !part.is_empty() {
                    parts.push(part);
                }
                start = index + 1;
            }
            _ => {}
        }
    }
    let part = value[start..].trim();
    if !part.is_empty() {
        parts.push(part);
    }
    parts
}

#[cfg(test)]
mod tests {
    use super::*;
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;
    use serde_json::json;

    fn theme() -> ThemeView {
        ThemeView::new(
            Arc::new(nsh_base::Theme::default().tokens().clone()),
            false,
            false,
        )
    }
    fn node(kind: &str, props: Value) -> Node {
        Node {
            kind: kind.into(),
            props: props.as_object().unwrap().clone(),
            ..Default::default()
        }
    }
    fn viewport() -> Size<Points> {
        Size {
            width: px(640.0),
            height: px(480.0),
        }
    }
    fn compile_props(props: Value) -> Result<Style, String> {
        compile(&node("box", props), &theme(), viewport())
    }
    fn value(style: &Style, key: StyleKey) -> &PropertyValue {
        style
            .decls()
            .iter()
            .rev()
            .find_map(|decl| match decl {
                StyleDecl::Set(found, value) if *found == key => Some(value),
                _ => None,
            })
            .unwrap()
    }

    #[test]
    fn explicit_css_shadow_layers_keep_native_base_and_hover_ranks() {
        let base = "0 1px 3px rgba(0, 0, 0, 0.1), inset 0 0 0 1px #123456";
        let hovered = "0 2px 4px #654321";
        let layers = |value: &str| {
            let PropertyValue::Shadows(layers) = StyleKey::BoxShadow
                .parse_value(StyleValue::Str(value))
                .unwrap()
            else {
                panic!("explicit colors must produce native shadow layers");
            };
            assert!(layers.iter().all(|(_, has_color)| *has_color));
            layers.iter().map(|(layer, _)| *layer).collect::<Vec<_>>()
        };
        let source = node("box", json!({"shadow":base,"hover-shadow":hovered}));
        let (_, native) = compile_parts(&source, &theme(), viewport()).unwrap();
        let mut expected = view()
            .shadow(layers(base))
            .hover(|style| style.shadow(layers(hovered)));
        assert_eq!(native, Style::from(expected.style().clone()));
    }

    #[test]
    fn inherited_css_shadows_remain_explicitly_unsupported() {
        for property in ["shadow", "hover-shadow"] {
            for value in [
                "0 1px 3px",
                "0 1px 3px currentColor",
                "0 1px 3px #123456, inset 0 0 0 1px",
            ] {
                let mut props = serde_json::Map::new();
                props.insert(property.into(), json!(value));
                let error = compile_props(Value::Object(props)).unwrap_err();
                assert!(
                    error.contains("currentColor"),
                    "{property}: {value}: {error}"
                );
            }
        }
    }

    #[test]
    fn native_font_size_units_are_explicit_and_never_guess_a_parent_metric() {
        for (text, expected) in [
            ("18", PropertyValue::OptPoints(Some(px(18.0)))),
            ("18px", PropertyValue::OptPoints(Some(px(18.0)))),
            ("1.25rem", PropertyValue::OptPoints(Some(px(20.0)))),
            ("1em", PropertyValue::OptPoints(None)),
            ("1.0em", PropertyValue::OptPoints(None)),
        ] {
            assert_eq!(
                FontSize::parse(text).unwrap().native().unwrap(),
                expected,
                "{text}"
            );
        }
        for text in [
            "2em", "0.5em", "12pt", "125%", "NaNpx", "1e100px", "-2px", "huge",
        ] {
            assert!(
                FontSize::parse(text).and_then(FontSize::native).is_err(),
                "{text}"
            );
        }
    }

    #[test]
    fn canonical_font_weights_and_text_units_are_preserved() {
        for weight in [1, 99, 500, 950, 1000] {
            let style = compile_props(
                json!({"font-weight":weight,"font-size":"1.25rem","line-height":"1.5"}),
            )
            .unwrap();
            assert_eq!(
                value(&style, StyleKey::FontWeight),
                &PropertyValue::FontWeight(Some(weight))
            );
            assert_eq!(
                value(&style, StyleKey::FontSize),
                &PropertyValue::OptPoints(Some(px(20.0)))
            );
            assert_eq!(
                value(&style, StyleKey::LineHeight),
                &StyleKey::LineHeight
                    .parse_value(StyleValue::Str("1.5"))
                    .unwrap()
            );
        }
    }

    #[test]
    fn theme_payloads_keep_aliases_adaptive_colors_and_nested_appearance() {
        let scoped = theme().overlay(&node("box", json!({"theme":r##"{"brand":{"light":"#123456","dark":"#abcdef"},"alias":"brand"}"##}))).unwrap();
        let color = scoped.color("alias").unwrap();
        assert_eq!(Color::from(color.light), Color::parse("#123456").unwrap());
        assert_eq!(Color::from(color.dark), Color::parse("#abcdef").unwrap());
        let dark = scoped
            .overlay(&node("box", json!({"theme-mode":"dark"})))
            .unwrap();
        assert_eq!(dark.color("brand").unwrap().light, color.dark);
        assert_eq!(dark.color("brand").unwrap().dark, color.dark);
        assert_ne!(theme().color("primary").unwrap(), color);
        assert!(theme().color("brand").is_err());
    }

    #[test]
    fn css_variable_tokens_preserve_fallbacks_quotes_comments_and_cycles() {
        let scoped = theme().overlay(&node("box", json!({"theme":r##"{"--base":"#123456","--a":"var(--base, var(--b))","--b":"var(--a)","--self":"var(--self, red)"}"##}))).unwrap();
        assert!(scoped.color("var(--a)").is_err());
        assert!(scoped.color("var(--b)").is_err());
        assert!(scoped.color("var(--self)").is_err());
        assert_eq!(
            scoped.color("var(--a, var(--missing, #00ff00))").unwrap(),
            AdaptiveColor::from(Color::parse("#00ff00").unwrap())
        );
        assert_eq!(
            scoped
                .text(r#"'var(--missing)' /* var(--missing) */ var(--base)"#)
                .unwrap(),
            "'var(--missing)' /* var(--missing) */ #123456"
        );
    }

    #[test]
    fn invalid_backend_values_fail_explicitly() {
        for props in [
            json!({"display":"inline"}),
            json!({"overflow":"auto"}),
            json!({"white-space":"pre-line"}),
            json!({"inert":true}),
            json!({"background":"missing-color"}),
        ] {
            assert!(compile_props(props.clone()).is_err(), "{props}");
        }
        assert!(compile_props(json!({"inert":false,"overflow":"hidden","display":"none"})).is_ok());
        assert!(
            theme()
                .overlay(&node("box", json!({"theme":"[]"})))
                .is_err()
        );
        assert!(
            theme()
                .overlay(&node(
                    "box",
                    json!({"theme":r#"{"brand":{"light":"red"}}"#})
                ))
                .is_err()
        );
    }

    #[test]
    fn parallel_transition_timing_and_reduced_motion_are_explicit() {
        let props = json!({"transition":"opacity 120ms ease-out, background-color 0.12s ease-out"});
        let normal = compile_props(props.clone()).unwrap();
        assert_eq!(
            value(&normal, StyleKey::TransitionDuration),
            &StyleKey::TransitionDuration.number_value(120.0).unwrap()
        );
        let mut reduced = theme();
        reduced.reduced_motion = true;
        let reduced = compile(&node("box", props), &reduced, viewport()).unwrap();
        assert_eq!(
            value(&reduced, StyleKey::TransitionDuration),
            &StyleKey::TransitionDuration.number_value(0.0).unwrap()
        );
        assert!(compile_props(json!({"transition":"opacity 100ms, color 200ms"})).is_err());
        assert!(compile_props(json!({"transition":"width 100ms"})).is_err());
    }

    #[component]
    fn SpacingGeometry() -> impl IntoElement {
        let outer = node(
            "row",
            json!({"width":200,"height":100,"padding":12,"padding-horizontal":20,"padding-vertical":30,"padding-top":7}),
        );
        view()
            .state_inline_style(move || compile(&outer, &theme(), viewport()).unwrap())
            .test_id("parent")
            .child(view().w(px(20.0)).h(px(10.0)).test_id("child"))
    }

    #[test]
    fn canonical_spacing_edges_win_in_measured_native_layout() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<SpacingGeometry>())).unwrap();
        app.first_render().unwrap();
        let nodes = app.screen().layout_nodes();
        let parent = nodes
            .iter()
            .find(|node| node.test_id.as_deref() == Some("parent"))
            .unwrap();
        let child = nodes
            .iter()
            .find(|node| node.test_id.as_deref() == Some("child"))
            .unwrap();
        assert!((parent.bounds.size.width.0 - 200.0).abs() < 0.01);
        assert!((child.bounds.origin.x.0 - parent.bounds.origin.x.0 - 20.0).abs() < 0.01);
        assert!((child.bounds.origin.y.0 - parent.bounds.origin.y.0 - 7.0).abs() < 0.01);
    }

    #[component]
    fn ViewportGeometry() -> impl IntoElement {
        let props = node("box", json!({"width-viewport":0.25,"height-viewport":0.5}));
        view()
            .state_inline_style(move || compile(&props, &theme(), viewport()).unwrap())
            .test_id("fraction")
    }

    #[test]
    fn viewport_fractions_have_measured_native_geometry() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<ViewportGeometry>())).unwrap();
        app.first_render().unwrap();
        let nodes = app.screen().layout_nodes();
        let target = nodes
            .iter()
            .find(|node| node.test_id.as_deref() == Some("fraction"))
            .unwrap();
        assert!((target.bounds.size.width.0 - 160.0).abs() < 0.01);
        assert!((target.bounds.size.height.0 - 240.0).abs() < 0.01);
    }

    #[test]
    fn layer_indices_require_exact_native_integer_representation() {
        for index in [
            i64::from(i32::MIN),
            -16_777_216,
            0,
            16_777_216,
            16_777_218,
            2_147_483_520,
        ] {
            assert_eq!(
                z_index(&node("box", json!({"z-index":index}))).unwrap(),
                Some(i32::try_from(index).unwrap())
            );
            compile_props(json!({"z-index":index})).unwrap();
        }
        for index in [
            i64::from(i32::MIN) - 1,
            -16_777_217,
            16_777_217,
            i64::from(i32::MAX),
            i64::from(i32::MAX) + 1,
        ] {
            assert!(
                compile_props(json!({"z-index":index}))
                    .unwrap_err()
                    .contains("z-index")
            );
        }
    }

    #[component]
    fn LayerIndexTransaction() -> impl IntoElement {
        use crate::{render::Renderer, wire::Batch};
        let renderer = Renderer::new(|_, _| {});
        let patch = |generation, ops| {
            Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
        };
        renderer
            .apply(patch(
                1,
                json!([
                    {"op":"create-node","id":1,"kind":"box"},
                    {"op":"create-node","id":2,"kind":"text"},
                    {"op":"set-prop","id":2,"property":"text","value":"Before rejected layer"},
                    {"op":"insert-child","parent":1,"child":2,"index":0}
                ]),
            ))
            .unwrap();
        renderer.set_root(1).unwrap();
        assert!(
            renderer
                .apply(patch(
                    2,
                    json!([
                        {"op":"set-prop","id":2,"property":"text","value":"Must not publish"},
                        {"op":"set-prop","id":1,"property":"z-index","value":16777217}
                    ])
                ))
                .unwrap_err()
                .contains("z-index")
        );
        renderer
            .apply(patch(
                2,
                json!([
                    {"op":"set-prop","id":1,"property":"z-index","value":16777216}
                ]),
            ))
            .unwrap();
        renderer.element()
    }

    #[test]
    fn rejected_layer_order_preserves_other_edits_and_retry_generation() {
        let mut app =
            Headless::start(EngineConfig::new(Root::of::<LayerIndexTransaction>())).unwrap();
        app.wait_for("Before rejected layer").unwrap();
        assert_eq!(app.screen().count("text:Must not publish").unwrap(), 0);
    }

    #[test]
    fn edge_inset_parts_keep_surface_properties_off_the_main_host() {
        let node = node(
            "edge-inset",
            json!({"edge":"top","width":200,"height":160,"gap":5,"padding":4,"padding-horizontal":6,"padding-top":8,"padding-right":12,"border-width":2,"background":"secondary","foreground":"destructive"}),
        );
        let theme = theme();
        let compiled = compile(&node, &theme, viewport()).unwrap();
        let parts = edge_inset_styles(&node, &theme, &compiled).unwrap();
        assert_eq!(parts.insets, [px(10.0), px(14.0), px(6.0), px(8.0)]);
        assert_eq!(parts.gap, px(5.0));
        assert_eq!(parts.host.background_color(), None);
        assert!(parts.decoration.background_color().is_some());
        let mut host = nsh_core::Style::default();
        for declaration in parts.host.decls() {
            declaration.apply(&mut host).unwrap();
        }
        assert_eq!(host.layout.padding.top.into_raw().value(), 0.0);
        assert_eq!(host.layout.border.top.into_raw().value(), 0.0);
        assert_eq!(host.layout.gap.height.into_raw().value(), 0.0);
    }
}

#[cfg(test)]
#[path = "style/inherited_foreground_tests.rs"]
mod inherited_foreground_tests;

#[cfg(test)]
#[path = "style/pointer_policy_tests.rs"]
mod pointer_policy_tests;

#[cfg(test)]
#[path = "style/hidden_display_tests.rs"]
mod hidden_display_tests;
