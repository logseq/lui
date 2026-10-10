//! Scalar and structural validation at the retained wire boundary.
use crate::protocol_rules;
use crate::store::{BackendError, Node, Store};
use crate::wire::Value;
use crate::wire_schema::{NodeKind as K, Property as P};

fn error(message: &str) -> BackendError {
    BackendError(message.into())
}

fn slug(value: &str) -> bool {
    !value.is_empty()
        && value.split('-').all(|part| {
            !part.is_empty()
                && part
                    .bytes()
                    .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
        })
}

fn attrs(value: &str) -> bool {
    value.is_empty()
        || value.split('\u{1e}').all(|record| {
            let mut parts = record.split('\u{1f}');
            let name = parts.next().unwrap_or("");
            parts.next().is_some()
                && parts.next().is_none()
                && (matches!(name, "role" | "tabindex" | "draggable" | "style")
                    || name.strip_prefix("data-").is_some_and(|v| !v.is_empty())
                    || name.strip_prefix("aria-").is_some_and(|v| !v.is_empty()))
        })
}

pub(crate) fn property(kind: K, property: P, value: Option<&Value>) -> Result<(), BackendError> {
    if !protocol_rules::property_supported(kind, property) {
        return Err(error("property is not supported by this kind"));
    }
    let Some(value) = value else {
        return Ok(());
    };
    let valid = match value {
        Value::Str(value) => match property {
            P::IconName | P::InlineIconName => {
                protocol_rules::string_supported(property, value)
                    || value.strip_prefix("app:").is_some_and(slug)
            }
            P::DataAttrs => attrs(value),
            P::PickerRequest | P::PickerCompletion => true,
            P::RoleValue if kind == K::Popover => value == "menu",
            P::SizeValue if kind == K::TableCell => {
                matches!(value.as_str(), "heading" | "display")
                    || protocol_rules::string_supported(property, value)
            }
            P::As => match kind {
                K::Text => [
                    "span", "em", "strong", "b", "i", "u", "s", "del", "mark", "small", "code",
                    "kbd", "sub", "sup", "pre",
                ]
                .contains(&value.as_str()),
                K::Heading => ["h1", "h2", "h3", "h4", "h5", "h6"].contains(&value.as_str()),
                K::Paragraph => ["p", "span", "div", "pre"].contains(&value.as_str()),
                K::Label => ["label", "span", "div"].contains(&value.as_str()),
                _ => false,
            },
            _ => protocol_rules::string_supported(property, value),
        },
        Value::Bool(_) => matches!(
            property,
            P::Enabled
                | P::Checked
                | P::Selected
                | P::Autofocus
                | P::SubmitOnEnter
                | P::LongPressEnabled
                | P::ChangeEnabled
                | P::ToggleEnabled
                | P::PressEnabled
                | P::SubmitEnabled
                | P::DoublePressEnabled
                | P::AppearEnabled
                | P::PointerEnabled
                | P::Connector
                | P::Expanded
                | P::ScrollAnimated
                | P::TrackVisibleRange
                | P::PickerMultiple
                | P::PickerDirectory
                | P::Visible
        ),
        Value::Int(number) => match property {
            // margins may be negative — collapsing adjacent space is legitimate
            P::PaddingValue
            | P::PickerRequest
            | P::PickerCompletion
            | P::ZIndex
            | P::MarginValue
            | P::MarginHorizontal
            | P::MarginVertical
            | P::MarginTop
            | P::MarginRight
            | P::MarginBottom
            | P::MarginLeft => true,
            P::HeadingLevel => (1..=6).contains(number),
            P::FontWeight => (1..=1000).contains(number),
            P::TooltipDelay | P::DurationValue => (0..=i32::MAX as i64).contains(number),
            P::TreeLevel | P::MaxPixelSize => *number > 0,
            P::Gap
            | P::GridColumns
            | P::PaddingHorizontal
            | P::PaddingVertical
            | P::BorderWidth
            | P::CornerRadius
            | P::WidthValue
            | P::HeightValue
            | P::MinWidth
            | P::MaxWidth
            | P::MinHeight
            | P::MaxHeight
            | P::ContainerRelativeFrameInset
            | P::ImageIdValue
            | P::SurfaceIdValue
            | P::ActiveIndex
            | P::ResizeDuration
            | P::ScrollToken => *number >= 0,
            // JSON numbers lose the OCaml int/float distinction; accept exact
            // integral spellings for numeric floating-point properties.
            _ => float_property(property, *number as f64),
        },
        Value::Float(number) => float_property(property, *number),
    };
    if valid {
        Ok(())
    } else {
        Err(error("invalid property scalar value"))
    }
}

fn float_property(property: P, number: f64) -> bool {
    number.is_finite()
        && match property {
            P::GrowValue | P::AvailableHeight => number >= 0.0,
            P::StepValue => number > 0.0,
            P::Opacity | P::HoverOpacity | P::PressedOpacity | P::DisabledOpacity => {
                (0.0..=1.0).contains(&number)
            }
            P::WidthViewport
            | P::HeightViewport
            | P::MinWidthViewport
            | P::MaxWidthViewport
            | P::MinHeightViewport
            | P::MaxHeightViewport => number > 0.0 && number <= 1.0,
            P::LetterSpacing
            | P::Inset
            | P::InsetTop
            | P::InsetRight
            | P::InsetBottom
            | P::InsetLeft => true,
            P::ProgressValue
            | P::SourceX
            | P::SourceY
            | P::SourceWidth
            | P::SourceHeight
            | P::AnchorOffset
            | P::ResizeOrigin
            | P::MinValue
            | P::MaxValue
            | P::PopupX
            | P::PopupY => true,
            _ => false,
        }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn typed_visual_numbers_follow_the_ocaml_contract() {
        for weight in [1, 400, 500, 700, 1000] {
            property(K::Text, P::FontWeight, Some(&Value::Int(weight))).unwrap();
        }
        for weight in [0, 1001] {
            assert!(property(K::Text, P::FontWeight, Some(&Value::Int(weight))).is_err());
        }
        assert!(property(K::Text, P::FontWeight, Some(&Value::Float(500.5))).is_err());
        for p in [
            P::LetterSpacing,
            P::Inset,
            P::InsetTop,
            P::InsetRight,
            P::InsetBottom,
            P::InsetLeft,
        ] {
            for n in [-2.5, 0.0, 4.5] {
                property(K::Text, p, Some(&Value::Float(n))).unwrap();
            }
            property(K::Text, p, Some(&Value::Int(0))).unwrap();
            assert!(property(K::Text, p, Some(&Value::Float(f64::INFINITY))).is_err());
        }
        property(K::Text, P::ZIndex, Some(&Value::Int(-1))).unwrap();
        assert!(property(K::Text, P::ZIndex, Some(&Value::Float(1.5))).is_err());
        for p in [P::HoverOpacity, P::PressedOpacity, P::DisabledOpacity] {
            for n in [0.0, 0.5, 1.0] {
                property(K::Text, p, Some(&Value::Float(n))).unwrap();
            }
            property(K::Text, p, Some(&Value::Int(1))).unwrap();
            for n in [-0.1, 1.1, f64::NAN] {
                assert!(property(K::Text, p, Some(&Value::Float(n))).is_err());
            }
        }
        for p in [
            P::WidthViewport,
            P::HeightViewport,
            P::MinWidthViewport,
            P::MaxWidthViewport,
            P::MinHeightViewport,
            P::MaxHeightViewport,
        ] {
            for n in [0.5, 1.0] {
                property(K::Text, p, Some(&Value::Float(n))).unwrap();
            }
            property(K::Text, p, Some(&Value::Int(1))).unwrap();
            for n in [0.0, -0.1, 1.1, f64::INFINITY] {
                assert!(property(K::Text, p, Some(&Value::Float(n))).is_err());
            }
        }
    }
}

fn ancestor(store: &Store, node: &Node, kind: K) -> bool {
    let mut parent = node.parent;
    while let Some(id) = parent {
        let Some(current) = store.node(id) else {
            return false;
        };
        if current.identity.kind() == Some(kind) {
            return true;
        }
        parent = current.parent;
    }
    false
}

pub(crate) fn node(store: &Store, node: &Node) -> Result<(), BackendError> {
    let Some(kind) = node.identity.kind() else {
        return Ok(());
    };
    let nonempty = |prop| node.string_prop(prop).is_some_and(|s| !s.is_empty());
    let present = |prop| node.props.contains_key(&prop);
    let fail = |valid, message| if valid { Ok(()) } else { Err(error(message)) };
    for (minimum, maximum) in [(P::MinWidth, P::MaxWidth), (P::MinHeight, P::MaxHeight)] {
        if let (Some(min), Some(max)) = (node.int_prop(minimum), node.int_prop(maximum)) {
            fail(min <= max, "minimum surface size exceeds maximum")?;
        }
    }
    match kind {
        K::Icon => fail(present(P::IconName), "icon requires a name")?,
        K::Button | K::ToggleButton | K::Toggle | K::Radio => fail(
            nonempty(P::TextValue) || nonempty(P::AccessibilityLabel),
            "control requires text or an accessibility label",
        )?,
        K::Select | K::Combobox => fail(
            nonempty(P::TextValue) || nonempty(P::PlaceholderValue),
            "selector requires text or placeholder",
        )?,
        K::Dialog => fail(
            nonempty(P::TextValue) || !node.children.is_empty(),
            "dialog requires text or content children",
        )?,
        K::MenuItem
        | K::Accordion
        | K::Drawer
        | K::Sheet
        | K::Tooltip
        | K::Avatar
        | K::Step => fail(nonempty(P::TextValue), "node requires nonempty text")?,
        K::SwipeAction => fail(
            nonempty(P::TextValue) || nonempty(P::InlineIconName),
            "swipe action requires text or icon",
        )?,
        K::MenuTrigger => fail(
            (nonempty(P::TextValue) || nonempty(P::InlineIconName))
                && (nonempty(P::TextValue) || nonempty(P::AccessibilityLabel)),
            "menu trigger requires content and a label",
        )?,
        K::FileImage | K::FilePreview => fail(nonempty(P::PathValue), "file node requires a path")?,
        K::MediaSurface => fail(
            present(P::SurfaceIdValue),
            "media surface requires a surface",
        )?,
        K::EdgeInset => fail(present(P::EdgeValue), "edge inset requires an edge")?,
        K::Stepper => fail(present(P::ActiveIndex), "stepper requires an active index")?,
        K::TimelineItem => fail(nonempty(P::TitleValue), "timeline item requires a title")?,
        K::BottomTab => fail(
            nonempty(P::TitleValue) && node.flag(P::PressEnabled),
            "bottom tab requires a title and press support",
        )?,
        _ => (),
    }
    if matches!(
        kind,
        K::RadioGroup | K::Slider | K::Tree | K::Toolbar | K::BottomTabs
    ) {
        fail(
            nonempty(P::AccessibilityLabel),
            "node requires an accessibility label",
        )?;
    }
    if matches!(kind, K::Slider | K::Progress | K::NumberStepper) {
        fail(
            node.float_prop(P::ProgressValue).is_some(),
            "numeric control requires a value",
        )?;
    }
    if kind == K::NumberStepper {
        fail(
            nonempty(P::TextValue) || nonempty(P::AccessibilityLabel),
            "stepper requires text or label",
        )?;
        fail(
            node.float_prop(P::MinValue).unwrap_or(0.)
                <= node.float_prop(P::MaxValue).unwrap_or(f64::MAX),
            "stepper bounds are inverted",
        )?;
    }
    if matches!(kind, K::DropdownMenu | K::Tooltip | K::Popover) {
        fail(
            !(present(P::AnchorAlignmentValue)
                || present(P::AnchorOffset)
                || kind == K::Tooltip && present(P::TooltipDelay))
                || present(P::AnchorValue),
            "anchor settings require an anchor",
        )?;
    }
    if matches!(kind, K::Popover | K::DropdownMenu) {
        fail(
            present(P::PopupX) == present(P::PopupY)
                && !(present(P::PopupX) && present(P::AnchorValue)),
            "invalid popover positioning",
        )?;
    }
    if matches!(kind, K::Avatar | K::Image) {
        let count = [P::SourceX, P::SourceY, P::SourceWidth, P::SourceHeight]
            .iter()
            .filter(|&&p| present(p))
            .count();
        let source = present(P::ImageIdValue) || nonempty(P::UrlValue);
        fail(kind != K::Image || source, "image requires an image or URL")?;
        fail(
            count == 0
                || count == 4
                    && source
                    && node.float_prop(P::SourceX).unwrap_or(-1.) >= 0.
                    && node.float_prop(P::SourceY).unwrap_or(-1.) >= 0.
                    && node.float_prop(P::SourceWidth).unwrap_or(0.) > 0.
                    && node.float_prop(P::SourceHeight).unwrap_or(0.) > 0.,
            "invalid image crop",
        )?;
    }
    if kind == K::Root {
        fail(
            node.parent.is_none() && node.children.len() == 1,
            "root requires exactly one child and no parent",
        )?;
    }
    if matches!(kind, K::Split | K::Drawer) {
        fail(
            node.children.len() == 2,
            "split or drawer requires exactly two children",
        )?;
    }
    if kind == K::Split {
        fail(
            !(present(P::ResizeEasing) || present(P::ResizeOrigin))
                || node.int_prop(P::ResizeDuration).unwrap_or(0) > 0,
            "resize settings require a duration",
        )?;
    }
    if kind == K::Radio {
        fail(
            ancestor(store, node, K::RadioGroup),
            "radio requires a radio-group ancestor",
        )?;
    }
    if node.is_treeitem() {
        fail(
            ancestor(store, node, K::Tree),
            "treeitem requires a tree ancestor",
        )?;
    }
    if matches!(
        kind,
        K::Row | K::Column | K::Panel | K::Card | K::Box | K::ListItem
    ) {
        let metadata = present(P::TreeLevel)
            || present(P::Expanded)
            || present(P::ChangeEnabled)
            || present(P::ToggleEnabled);
        let disclosure = kind == K::ListItem
            && !node.is_treeitem()
            && !present(P::TreeLevel)
            && !present(P::ChangeEnabled)
            && (present(P::Expanded) || present(P::ToggleEnabled));
        fail(
            !metadata || node.is_treeitem() || disclosure,
            "tree metadata requires treeitem role",
        )?;
        fail(
            !present(P::Expanded) || node.flag(P::ToggleEnabled),
            "expansion requires toggle support",
        )?;
    }
    if kind == K::ListItem && !node.is_treeitem() {
        let content = node.children.iter().any(|&id| {
            store.node(id).is_some_and(|child| {
                !matches!(
                    child.identity.kind(),
                    Some(K::SwipeActions | K::ContextMenu)
                ) && !(present(P::Expanded) && child.identity.kind() == Some(K::ListItem))
            })
        });
        fail(
            nonempty(P::TextValue) || content,
            "list item requires text or content children",
        )?;
    }
    if kind == K::InputGroup {
        let kinds = node
            .children
            .iter()
            .filter_map(|&id| store.node(id).and_then(|n| n.identity.kind()))
            .collect::<Vec<_>>();
        fail(
            kinds == [K::Textarea] || kinds == [K::Textarea, K::InputGroupActions],
            "input group requires textarea then optional actions",
        )?;
    }
    if kind == K::InputGroupActions {
        fail(
            node.parent
                .and_then(|id| store.node(id))
                .and_then(|n| n.identity.kind())
                == Some(K::InputGroup),
            "actions require an input group parent",
        )?;
    }
    context_menu(store, node)?;
    Ok(())
}

fn context_menu(store: &Store, node: &Node) -> Result<(), BackendError> {
    let kind = node.identity.kind();
    let menu_count = node
        .children
        .iter()
        .filter(|&&id| {
            store
                .node(id)
                .is_some_and(|child| child.identity.kind() == Some(K::ContextMenu))
        })
        .count();
    if menu_count > 1 {
        return Err(error("host accepts at most one context-menu"));
    }
    if menu_count > 0
        && !(kind.is_some_and(protocol_rules::context_menu_host)
            || [
                P::PressEnabled,
                P::DoublePressEnabled,
                P::ToggleEnabled,
                P::LongPressEnabled,
            ]
            .iter()
            .any(|&prop| node.flag(prop)))
    {
        return Err(error("context-menu host must be interactive"));
    }
    if kind != Some(K::ContextMenu) {
        return Ok(());
    }
    if node.parent.is_none() {
        return Err(error("context-menu requires a direct host"));
    }
    for &id in &node.children {
        let child = store
            .node(id)
            .ok_or_else(|| error("unknown context-menu child"))?;
        if child.identity.kind() == Some(K::MenuItem) {
            let nested = |kind| {
                child.children.iter().any(|&id| {
                    store
                        .node(id)
                        .is_some_and(|node| node.identity.kind() == Some(kind))
                })
            };
            if nested(K::ContextMenu) {
                return Err(error("context-menu submenu must use dropdown-menu"));
            }
            if !child.flag(P::PressEnabled) && !nested(K::DropdownMenu) {
                return Err(error("context-menu menu-item requires press support"));
            }
        }
        if child.identity.kind() == Some(K::Divider)
            && !child.props.is_empty()
            && !(child.props.len() == 2
                && child.string_prop(P::OrientationValue) == Some("horizontal")
                && child.string_prop(P::StyleClass) == Some("lui-separator"))
        {
            return Err(error("context-menu separator accepts no attributes"));
        }
    }
    Ok(())
}
