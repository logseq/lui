// Generated from canonical OCaml validators. Do not edit.
use super::*;

pub(super) fn property_value_supported(property: &str, value: Scalar<'_>) -> bool {
    match (property, value) {
        ("read-only", Scalar::Bool(_)) => true,
        ("overscan", Scalar::Int(n)) => n >= 0_i64,
        ("item-extent", Scalar::Float(f)) => is_finite(f) && (f > 0.0_f64),
        ("virtual-total-count", Scalar::Int(n)) => n >= 0_i64,
        ("virtual-generation", Scalar::Int(n)) => n > 0_i64,
        ("virtual-indices", Scalar::String(indices)) => {
            virtual_indices_of_string(indices).is_some()
        }
        ("virtual-scroll-index", Scalar::Int(n)) => n >= -1_i64,
        ("text", Scalar::String(_)) => true,
        ("enabled", Scalar::Bool(_)) => true,
        ("gap", Scalar::Int(value)) => value >= 0_i64,
        ("main", Scalar::String(value)) => main_alignment_supported(value),
        ("cross", Scalar::String(value)) => cross_alignment_supported(value),
        ("grow" | "shrink", Scalar::Float(value)) => is_finite(value) && (value >= 0.0_f64),
        ("columns", Scalar::Int(value)) => value >= 0_i64,
        ("grid-column-span", Scalar::Int(value)) => value > 0_i64,
        ("padding", Scalar::Int(_)) => true,
        ("padding-horizontal", Scalar::Int(value)) => value >= 0_i64,
        (
            "padding-vertical" | "padding-top" | "padding-right" | "padding-bottom"
            | "padding-left",
            Scalar::Int(value),
        ) => value >= 0_i64,
        (
            "margin" | "margin-horizontal" | "margin-vertical" | "margin-top" | "margin-right"
            | "margin-bottom" | "margin-left",
            Scalar::Int(_),
        ) => true,
        ("background", Scalar::String(_)) => true,
        ("foreground", Scalar::String(_)) => true,
        (
            "border-color" | "indicator-border-color" | "checked-indicator-border-color",
            Scalar::String(_),
        ) => true,
        ("border-width", Scalar::Int(value)) => value >= 0_i64,
        ("corner-radius", Scalar::Int(value)) => value >= 0_i64,
        ("width", Scalar::Int(value)) => value >= 0_i64,
        ("height", Scalar::Int(value)) => value >= 0_i64,
        ("width" | "height", Scalar::String("auto")) => true,
        ("min-width", Scalar::Int(value)) => value >= 0_i64,
        ("max-width", Scalar::Int(value)) => value >= 0_i64,
        ("min-height", Scalar::Int(value)) => value >= 0_i64,
        ("max-height", Scalar::Int(value)) => value >= 0_i64,
        ("container-relative-frame", Scalar::String(value)) => {
            container_relative_frame_supported(value)
        }
        ("container-relative-frame-inset", Scalar::Int(value)) => value >= 0_i64,
        ("placeholder", Scalar::String(_)) => true,
        ("accessibility-label", Scalar::String(_)) => true,
        ("accessibility-identifier", Scalar::String(_)) => true,
        ("style-class", Scalar::String(_)) => true,
        ("heading-level", Scalar::Int(value)) => (1_i64..=6_i64).contains(&value),
        ("checked", Scalar::Bool(_)) => true,
        ("pointer-capture", Scalar::Bool(_)) => true,
        ("indeterminate", Scalar::Bool(_)) => true,
        ("toggle-detail-enabled", Scalar::Bool(_)) => true,
        ("value", Scalar::Float(value)) => is_finite(value),
        ("orientation", Scalar::String(value)) => orientation_supported(value),
        ("placement", Scalar::String(value)) => placement_supported(value),
        ("size", Scalar::String(value)) => control_size_supported(value),
        ("name", Scalar::String(value)) => icon_name_supported(value),
        ("variant", Scalar::String(value)) => button_variant_supported(value),
        ("icon", Scalar::String(value)) => icon_name_supported(value),
        ("icon-placement", Scalar::String(value))
        | ("selection-placement", Scalar::String(value)) => icon_placement_supported(value),
        ("selected", Scalar::Bool(_)) => true,
        ("autofocus", Scalar::Bool(_)) => true,
        ("submit-on-enter", Scalar::Bool(_)) | ("submit-on-blur", Scalar::Bool(_)) => true,
        ("long-press-enabled", Scalar::Bool(_)) => true,
        ("change-enabled", Scalar::Bool(_)) => true,
        ("toggle-enabled", Scalar::Bool(_)) => true,
        ("press-enabled", Scalar::Bool(_)) => true,
        ("navigate-enabled", Scalar::Bool(_)) | ("submit-enabled", Scalar::Bool(_)) => true,
        ("double-press-enabled", Scalar::Bool(_)) => true,
        ("appear-enabled", Scalar::Bool(_)) => true,
        ("focus-within-enabled", Scalar::Bool(_)) => true,
        ("pointer-enabled", Scalar::Bool(_)) => true,
        ("image", Scalar::Int(value)) => value >= 0_i64,
        ("surface", Scalar::Int(value)) => value >= 0_i64,
        ("active", Scalar::Int(value)) => value >= 0_i64,
        ("title", Scalar::String(_)) => true,
        ("description", Scalar::String(_)) => true,
        ("meta", Scalar::String(_)) => true,
        ("indicator", Scalar::String(_)) => true,
        ("connector", Scalar::Bool(_)) => true,
        ("source-x", Scalar::Float(value))
        | ("source-y", Scalar::Float(value))
        | ("source-width", Scalar::Float(value))
        | ("source-height", Scalar::Float(value)) => is_finite(value),
        ("anchor", Scalar::String(value)) => {
            (value == "above") || (value == "below") || (value == "left") || (value == "right")
        }
        ("anchor-target", Scalar::String(value)) => !ocaml_trim(value).is_empty(),
        ("anchor-rect", Scalar::String(value)) => anchor_rect_of_string(value).is_some(),
        ("anchor-alignment", Scalar::String(value)) => {
            (value == "start") || (value == "center") || (value == "end") || (value == "stretch")
        }
        ("anchor-offset", Scalar::Float(value))
        | ("anchor-alignment-offset", Scalar::Float(value)) => is_finite(value),
        ("tooltip-delay", Scalar::Int(value)) | ("duration", Scalar::Int(value)) => {
            (0_i64..=2147483647_i64).contains(&value)
        }
        ("text-alignment", Scalar::String(value)) => {
            (value == "start") || (value == "center") || (value == "end")
        }
        ("role", Scalar::String(value)) => {
            (value == "treeitem") || (value == "navigation") || (value == "navigation-heading")
        }
        ("tree-level", Scalar::Int(value)) => value > 0_i64,
        ("expanded", Scalar::Bool(_)) => true,
        ("resize-duration", Scalar::Int(value)) => value >= 0_i64,
        ("resize-easing", Scalar::String(value)) => {
            (value == "linear")
                || (value == "standard")
                || (value == "emphasized")
                || (value == "spring")
        }
        ("resize-origin", Scalar::Float(value)) => is_finite(value),
        ("first-pane-width", Scalar::Float(value)) => is_finite(value) && (value >= 0.0_f64),
        ("resize-handle-width", Scalar::Int(value)) => value >= 0_i64,
        ("resize-handle-offset", Scalar::Float(value)) => is_finite(value),
        ("theme", Scalar::String(_)) => true,
        ("theme-mode", Scalar::String(value)) => theme_mode_supported(value),
        ("key", Scalar::String(_)) => true,
        ("separator", Scalar::String(value)) => (value == "visible") || (value == "hidden"),
        ("style", Scalar::String(value)) => {
            (value == "plain") || (value == "inset") || (value == "inset-grouped")
        }
        ("scroll-target", Scalar::String(_)) => true,
        ("scroll-anchor", Scalar::String(value)) => {
            (value == "top") || (value == "center") || (value == "bottom") || (value == "nearest")
        }
        ("scroll-token", Scalar::Int(value)) => value >= 0_i64,
        ("scroll-animated", Scalar::Bool(_)) => true,
        ("track-visible-range", Scalar::Bool(_)) => true,
        ("edge", Scalar::String(value)) => {
            (value == "top") || (value == "bottom") || (value == "leading") || (value == "trailing")
        }
        ("request", Scalar::String(_) | Scalar::Int(_))
        | ("completion", Scalar::String(_) | Scalar::Int(_)) => true,
        ("types", Scalar::String(_)) => true,
        ("multiple", Scalar::Bool(_)) => true,
        ("source", Scalar::String(value)) => picker_source_supported(value),
        ("min", Scalar::Float(value)) | ("max", Scalar::Float(value)) => is_finite(value),
        ("step", Scalar::Float(value)) => is_finite(value) && (value > 0.0_f64),
        ("detents", Scalar::String(_)) => true,
        ("sizing", Scalar::String(value)) => sizing_supported(value),
        ("path", Scalar::String(_)) | ("url", Scalar::String(_)) => true,
        ("alt", Scalar::String(_)) => true,
        ("loading", Scalar::String(value)) => (value == "eager") || (value == "lazy"),
        ("referrer-policy", Scalar::String(value)) => {
            (value == "no-referrer")
                || (value == "origin")
                || (value == "strict-origin-when-cross-origin")
                || (value == "unsafe-url")
        }
        ("target", Scalar::String(value)) => (value == "_self") || (value == "_blank"),
        ("opacity" | "label-opacity", Scalar::Float(value)) => {
            is_finite(value) && (0.0_f64..=1.0_f64).contains(&value)
        }
        ("display", Scalar::String(value)) => contains(
            value,
            &[
                "contents",
                "none",
                "inline-flex",
                "block",
                "inline",
                "inline-block",
            ],
        ),
        ("tooltip", Scalar::String(_)) | ("tooltip-keys", Scalar::String(_)) => true,
        ("input-type", Scalar::String(value)) => {
            (value == "text") || (value == "color") || (value == "time")
        }
        ("accept", Scalar::String(_)) => true,
        ("directory", Scalar::Bool(_)) => true,
        ("x", Scalar::Float(value)) | ("y", Scalar::Float(value)) => is_finite(value),
        ("available-height" | "collision-padding", Scalar::Float(value)) => {
            is_finite(value) && (value >= 0.0_f64)
        }
        ("image-fit", Scalar::String(value)) => (value == "fit") || (value == "fill"),
        ("max-pixel-size", Scalar::Int(value)) => value > 0_i64,
        ("visible", Scalar::Bool(_)) => true,
        ("alignment", Scalar::String(value)) => alignment_supported(value),
        ("data-attrs", Scalar::String(payload)) => data_attrs_value_ok(payload),
        ("as", Scalar::String(tag)) => element_tag_known(tag),
        ("font-size", Scalar::String(value)) | ("line-height", Scalar::String(value)) => {
            !ocaml_trim(value).is_empty()
        }
        ("font-weight", Scalar::Int(value)) => (1_i64..=1000_i64).contains(&value),
        ("letter-spacing", Scalar::Float(value))
        | ("inset", Scalar::Float(value))
        | ("inset-top", Scalar::Float(value))
        | ("inset-right", Scalar::Float(value))
        | ("inset-bottom", Scalar::Float(value))
        | ("inset-left", Scalar::Float(value)) => is_finite(value),
        ("position", Scalar::String(value)) => contains(
            value,
            &["static", "relative", "absolute", "fixed", "sticky"],
        ),
        ("font-family", Scalar::String(value)) => !ocaml_trim(value).is_empty(),
        ("font-style", Scalar::String(value)) => contains(value, &["normal", "italic", "oblique"]),
        ("text-decoration", Scalar::String(value)) => text_decoration_supported(value),
        ("list-style", Scalar::String(value)) => contains(value, &["none", "disc", "decimal"]),
        ("flex-wrap", Scalar::String(value)) => contains(value, &["nowrap", "wrap"]),
        ("hover-foreground", Scalar::String(value))
        | ("hover-border", Scalar::String(value))
        | ("focus-within-background", Scalar::String(value))
        | ("focus-within-border", Scalar::String(value)) => !ocaml_trim(value).is_empty(),
        ("inert", Scalar::Bool(_)) => true,
        ("transition", Scalar::String(value)) => transition_supported(value),
        ("z-index", Scalar::Int(_)) => true,
        ("white-space", Scalar::String(value)) => {
            contains(value, &["normal", "nowrap", "pre-wrap", "pre-line"])
        }
        ("line-clamp", Scalar::Int(value)) => value > 0_i64,
        ("text-overflow", Scalar::String(value)) => contains(value, &["clip", "ellipsis"]),
        ("overflow", Scalar::String(value)) => contains(value, &["visible", "hidden", "auto"]),
        ("user-select", Scalar::String(value)) => contains(value, &["none", "text"]),
        ("cursor", Scalar::String(value)) => contains(value, &["default", "pointer", "text"]),
        ("shadow", Scalar::String(value))
        | ("hover-shadow", Scalar::String(value))
        | ("pressed-shadow", Scalar::String(value))
        | ("focus-shadow", Scalar::String(value))
        | ("selected-shadow", Scalar::String(value))
        | ("selected-hover-shadow", Scalar::String(value))
        | ("hover-background", Scalar::String(value))
        | ("pressed-background", Scalar::String(value))
        | ("selected-background", Scalar::String(value)) => !ocaml_trim(value).is_empty(),
        ("hover-opacity", Scalar::Float(value))
        | ("pressed-opacity", Scalar::Float(value))
        | ("disabled-opacity", Scalar::Float(value)) => (0.0_f64..=1.0_f64).contains(&value),
        ("width-viewport", Scalar::Float(value))
        | ("height-viewport", Scalar::Float(value))
        | ("min-width-viewport", Scalar::Float(value))
        | ("max-width-viewport", Scalar::Float(value))
        | ("min-height-viewport", Scalar::Float(value))
        | ("max-height-viewport", Scalar::Float(value)) => (value > 0.0_f64) && (value <= 1.0_f64),
        _ => false,
    }
}

pub(super) fn property_value_supported_for_kind(
    kind: &str,
    property: &str,
    value: Scalar<'_>,
) -> bool {
    if (property == "role") && (kind == "popover") {
        (value == Scalar::String("menu")) || (value == Scalar::String("dialog"))
    } else {
        if property == "size" {
            match value {
                Scalar::String(size) => {
                    if kind == "table-cell" {
                        control_size_supported(size) || (size == "heading") || (size == "display")
                    } else {
                        control_size_supported(size)
                    }
                }
                _ => false,
            }
        } else {
            if property == "as" {
                match value {
                    Scalar::String(tag) => element_tag_supported(kind, tag),
                    _ => false,
                }
            } else {
                property_value_supported(property, value)
            }
        }
    }
}

pub(super) fn node_properties_supported(kind: &str, properties: &Map<String, Value>) -> bool {
    presence_supported(kind, properties)
        && surface_size_supported(properties)
        && viewport_size_supported(properties)
        && (if kind == "icon" {
            match lookup("name", properties) {
                Some(name) => property_value_supported("name", name),
                None => false,
            }
        } else {
            true
        })
        && (if (kind == "button")
            || (kind == "toggle-button")
            || (kind == "toggle")
            || (kind == "radio")
        {
            {
                let text = string_property_or(properties, "text", "");
                {
                    let label = string_property_or(properties, "accessibility-label", "");
                    {
                        let icon = string_property_or(properties, "icon", "");
                        (!text.is_empty() || !label.is_empty())
                            && (if text.is_empty() && !icon.is_empty() {
                                !label.is_empty()
                            } else {
                                true
                            })
                    }
                }
            }
        } else {
            true
        })
        && (if (kind == "radio-group") || (kind == "slider") {
            string_property_nonempty(properties, "accessibility-label")
        } else {
            true
        })
        && (if (kind == "select") || (kind == "combobox") {
            {
                let text = string_property_or(properties, "text", "");
                {
                    let placeholder = string_property_or(properties, "placeholder", "");
                    !text.is_empty() || !placeholder.is_empty()
                }
            }
        } else {
            true
        })
        && (if kind == "menu-item" {
            string_property_nonempty(properties, "text")
                || string_property_nonempty(properties, "accessibility-label")
        } else {
            true
        })
        && (if kind == "accordion" {
            string_property_nonempty(properties, "text")
        } else {
            true
        })
        && (if kind == "swipe-action" {
            string_property_nonempty(properties, "text")
                || string_property_nonempty(properties, "icon")
        } else {
            true
        })
        && (if kind == "menu-trigger" {
            {
                let text = string_property_or(properties, "text", "");
                {
                    let icon = string_property_or(properties, "icon", "");
                    {
                        let label = string_property_or(properties, "accessibility-label", "");
                        (!text.is_empty() || !icon.is_empty())
                            && (if text.is_empty() {
                                !label.is_empty()
                            } else {
                                true
                            })
                    }
                }
            }
        } else {
            true
        })
        && (if (kind == "drawer") || (kind == "sheet") {
            string_property_nonempty(properties, "text")
        } else {
            true
        })
        && (if kind == "tooltip" {
            string_property_nonempty(properties, "text")
                && (if contains_property("tooltip-delay", properties) {
                    contains_property("anchor", properties)
                } else {
                    true
                })
        } else {
            true
        })
        && (if (kind == "dropdown-menu") || (kind == "tooltip") || (kind == "popover") {
            if contains_property("anchor-alignment", properties)
                || contains_property("anchor-offset", properties)
                || contains_property("anchor-alignment-offset", properties)
            {
                contains_property("anchor", properties)
            } else {
                true
            }
        } else {
            true
        })
        && (if (kind == "popover")
            && (contains_property("anchor-target", properties)
                || contains_property("anchor-rect", properties))
        {
            contains_property("anchor", properties)
                && !(contains_property("anchor-target", properties)
                    && contains_property("anchor-rect", properties))
        } else {
            true
        })
        && (if (kind == "popover") || (kind == "dropdown-menu") {
            {
                let has_x = contains_property("x", properties);
                {
                    let has_y = contains_property("y", properties);
                    (has_x == has_y) && (!(has_x) || !(contains_property("anchor", properties)))
                }
            }
        } else {
            true
        })
        && (if (kind == "avatar") || (kind == "image") {
            {
                let has_image = contains_property("image", properties);
                {
                    let has_url = string_property_nonempty(properties, "url");
                    {
                        let has_source_x = contains_property("source-x", properties);
                        {
                            let has_source_y = contains_property("source-y", properties);
                            {
                                let has_source_width =
                                    contains_property("source-width", properties);
                                {
                                    let has_source_height =
                                        contains_property("source-height", properties);
                                    {
                                        let source_count =
                                            ((if has_source_x { 1_i64 } else { 0_i64 }
                                                + if has_source_y { 1_i64 } else { 0_i64 })
                                                + if has_source_width { 1_i64 } else { 0_i64 })
                                                + if has_source_height { 1_i64 } else { 0_i64 };
                                        {
                                            let source_x =
                                                float_property(properties, "source-x", 0.0_f64);
                                            {
                                                let source_y =
                                                    float_property(properties, "source-y", 0.0_f64);
                                                {
                                                    let source_width = float_property(
                                                        properties,
                                                        "source-width",
                                                        0.0_f64,
                                                    );
                                                    {
                                                        let source_height = float_property(
                                                            properties,
                                                            "source-height",
                                                            0.0_f64,
                                                        );
                                                        (if kind == "avatar" {
                                                            string_property_nonempty(
                                                                properties, "text",
                                                            )
                                                        } else {
                                                            has_image || has_url
                                                        }) && ((source_count == 0_i64)
                                                            || (source_count == 4_i64))
                                                            && ((source_count == 0_i64)
                                                                || has_image
                                                                || has_url)
                                                            && ((source_count == 0_i64)
                                                                || ((source_x >= 0.0_f64)
                                                                    && (source_y >= 0.0_f64)
                                                                    && (source_width > 0.0_f64)
                                                                    && (source_height > 0.0_f64)))
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } else {
            true
        })
        && (if (kind == "file-image") || (kind == "file-preview") {
            string_property_nonempty(properties, "path")
        } else {
            true
        })
        && (if kind == "media-surface" {
            contains_property("surface", properties)
        } else {
            true
        })
        && (if kind == "edge-inset" {
            contains_property("edge", properties)
        } else {
            true
        })
        && (if kind == "stepper" {
            contains_property("active", properties)
        } else {
            true
        })
        && (if (kind == "step") || (kind == "timeline-item") || (kind == "bottom-tabs") {
            {
                let property = if kind == "step" {
                    "text"
                } else {
                    if kind == "timeline-item" {
                        "title"
                    } else {
                        "accessibility-label"
                    }
                };
                string_property_nonempty(properties, property)
            }
        } else {
            true
        })
        && (if kind == "bottom-tab" {
            string_property_nonempty(properties, "title")
                && true_property(properties, "press-enabled")
        } else {
            true
        })
        && (if (kind == "slider") || (kind == "progress") {
            matches!(lookup("value", properties), Some(Scalar::Float(_)))
        } else {
            true
        })
        && (if kind == "number-stepper" {
            ({
                let text = string_property_or(properties, "text", "");
                {
                    let label = string_property_or(properties, "accessibility-label", "");
                    !text.is_empty() || !label.is_empty()
                }
            }) && (match lookup("value", properties) {
                Some(Scalar::Float(value)) => is_finite(value),
                _ => false,
            }) && ({
                let minimum = float_property(properties, "min", 0.0_f64);
                {
                    let maximum = float_property(properties, "max", f64::MAX);
                    minimum <= maximum
                }
            })
        } else {
            true
        })
        && (if (kind == "tree") || (kind == "toolbar") {
            string_property_nonempty(properties, "accessibility-label")
        } else {
            true
        })
        && (if kind == "split" {
            {
                let duration = int_property(properties, "resize-duration", 0_i64);
                !(contains_property("first-pane-width", properties)
                    && contains_property("value", properties))
                    && (if contains_property("resize-easing", properties) {
                        duration > 0_i64
                    } else {
                        true
                    })
                    && (if contains_property("resize-origin", properties) {
                        duration > 0_i64
                    } else {
                        true
                    })
            }
        } else {
            true
        })
        && (if tree_row_kind(kind) {
            {
                let treeitem = treeitem_properties(properties);
                {
                    let has_tree_metadata = contains_property("tree-level", properties)
                        || contains_property("expanded", properties)
                        || contains_property("change-enabled", properties)
                        || contains_property("toggle-enabled", properties);
                    {
                        let disclosure_list_item = (kind == "list-item")
                            && !(treeitem)
                            && !(contains_property("tree-level", properties))
                            && !(contains_property("change-enabled", properties))
                            && (contains_property("expanded", properties)
                                || contains_property("toggle-enabled", properties));
                        (!(has_tree_metadata) || treeitem || disclosure_list_item)
                            && (if contains_property("expanded", properties) {
                                true_property(properties, "toggle-enabled")
                            } else {
                                true
                            })
                    }
                }
            }
        } else {
            true
        })
}

pub(super) fn is_finite(value: f64) -> bool {
    !value.is_nan() && (value != f64::INFINITY) && (value != f64::NEG_INFINITY)
}

pub(super) fn container_relative_frame_supported(value: &str) -> bool {
    (value == "horizontal")
        || (value == "vertical")
        || (value == "both")
        || (value == "min-horizontal")
        || (value == "min-vertical")
        || (value == "min-both")
}

pub(super) fn orientation_supported(value: &str) -> bool {
    (value == "horizontal") || (value == "vertical")
}

pub(super) fn placement_supported(value: &str) -> bool {
    contains(
        value,
        &[
            "automatic",
            "bottom",
            "navigation",
            "principal",
            "primary-action",
            "secondary-action",
            "status",
            "confirmation-action",
            "cancellation-action",
            "destructive-action",
            "top-bar-leading",
            "top-bar-trailing",
        ],
    )
}

pub(super) fn control_size_supported(value: &str) -> bool {
    (value == "default") || (value == "sm") || (value == "lg") || (value == "icon")
}

pub(super) fn button_variant_supported(value: &str) -> bool {
    (value == "default")
        || (value == "primary")
        || (value == "secondary")
        || (value == "outline")
        || (value == "ghost")
        || (value == "destructive")
}

pub(super) fn icon_placement_supported(value: &str) -> bool {
    (value == "leading") || (value == "trailing") || (value == "top")
}

pub(super) fn theme_mode_supported(value: &str) -> bool {
    (value == "system") || (value == "light") || (value == "dark")
}

pub(super) fn picker_source_supported(value: &str) -> bool {
    (value == "files") || (value == "photos") || (value == "camera")
}

pub(super) fn sizing_supported(value: &str) -> bool {
    (value == "form") || (value == "fitted") || (value == "page")
}

pub(super) fn main_alignment_supported(value: &str) -> bool {
    (value == "start") || (value == "center") || (value == "end") || (value == "space_between")
}

pub(super) fn cross_alignment_supported(value: &str) -> bool {
    (value == "stretch") || (value == "start") || (value == "center") || (value == "end")
}

pub(super) fn alignment_supported(value: &str) -> bool {
    (value == "top-leading")
        || (value == "top")
        || (value == "top-trailing")
        || (value == "leading")
        || (value == "center")
        || (value == "trailing")
        || (value == "bottom-leading")
        || (value == "bottom")
        || (value == "bottom-trailing")
}

pub(super) fn presence_supported(kind: &str, properties: &Map<String, Value>) -> bool {
    match kind {
        "root"
        | "grid"
        | "stack"
        | "overlay"
        | "view-that-fits"
        | "alert"
        | "bubble"
        | "text"
        | "heading"
        | "paragraph"
        | "label"
        | "text-field"
        | "secure-field"
        | "input"
        | "search-field"
        | "textarea"
        | "checkbox"
        | "switch"
        | "divider"
        | "scroll"
        | "list"
        | "virtual-list"
        | "tabs"
        | "button-group"
        | "toggle-group"
        | "spacer"
        | "spinner"
        | "context-menu"
        | "timeline"
        | "input-group"
        | "input-group-actions"
        | "breadcrumb"
        | "pagination"
        | "table"
        | "table-row"
        | "table-cell"
        | "resizable"
        | "dialog"
        | "toast"
        | "status-bar"
        | "list-section"
        | "list-section-header"
        | "list-section-footer"
        | "swipe-actions"
        | "file-picker"
        | "kbd"
        | "link" => true,
        "row" | "column" | "panel" | "card" | "box" | "list-item" => {
            if contains_property("tree-level", properties) {
                if contains_property("role", properties) {
                    if contains_property("expanded", properties) {
                        contains_property("toggle-enabled", properties)
                    } else {
                        true
                    }
                } else {
                    false
                }
            } else {
                if contains_property("change-enabled", properties) {
                    if contains_property("role", properties) {
                        if contains_property("expanded", properties) {
                            contains_property("toggle-enabled", properties)
                        } else {
                            true
                        }
                    } else {
                        false
                    }
                } else {
                    if contains_property("expanded", properties) {
                        contains_property("toggle-enabled", properties)
                    } else {
                        true
                    }
                }
            }
        }
        "edge-inset" => contains_property("edge", properties),
        "button" | "toggle-button" | "toggle" | "radio" | "menu-item" => {
            if contains_property("text", properties) {
                true
            } else {
                contains_property("accessibility-label", properties)
            }
        }
        "radio-group" | "bottom-tabs" | "tree" | "toolbar" => {
            contains_property("accessibility-label", properties)
        }
        "slider" => {
            if contains_property("accessibility-label", properties) {
                contains_property("value", properties)
            } else {
                false
            }
        }
        "number-stepper" => {
            if contains_property("text", properties) {
                contains_property("value", properties)
            } else {
                if contains_property("accessibility-label", properties) {
                    contains_property("value", properties)
                } else {
                    false
                }
            }
        }
        "progress" => contains_property("value", properties),
        "bottom-tab" => {
            if contains_property("title", properties) {
                contains_property("press-enabled", properties)
            } else {
                false
            }
        }
        "icon" => contains_property("name", properties),
        "select" | "combobox" => {
            if contains_property("text", properties) {
                true
            } else {
                contains_property("placeholder", properties)
            }
        }
        "dropdown-menu" => {
            if contains_property("anchor-alignment", properties) {
                if contains_property("anchor", properties) {
                    if contains_property("x", properties) {
                        false
                    } else {
                        !contains_property("y", properties)
                    }
                } else {
                    false
                }
            } else {
                if contains_property("anchor-offset", properties) {
                    if contains_property("anchor", properties) {
                        if contains_property("x", properties) {
                            false
                        } else {
                            !contains_property("y", properties)
                        }
                    } else {
                        false
                    }
                } else {
                    if contains_property("anchor-alignment-offset", properties) {
                        if contains_property("anchor", properties) {
                            if contains_property("x", properties) {
                                false
                            } else {
                                !contains_property("y", properties)
                            }
                        } else {
                            false
                        }
                    } else {
                        if contains_property("x", properties) {
                            if contains_property("y", properties) {
                                !contains_property("anchor", properties)
                            } else {
                                false
                            }
                        } else {
                            !contains_property("y", properties)
                        }
                    }
                }
            }
        }
        "menu-trigger" | "swipe-action" => {
            if contains_property("text", properties) {
                true
            } else {
                contains_property("icon", properties)
            }
        }
        "avatar" => {
            if contains_property("text", properties) {
                if contains_property("source-x", properties) {
                    if contains_property("source-y", properties) {
                        if contains_property("source-width", properties) {
                            if contains_property("source-height", properties) {
                                if contains_property("image", properties) {
                                    true
                                } else {
                                    contains_property("url", properties)
                                }
                            } else {
                                false
                            }
                        } else {
                            false
                        }
                    } else {
                        false
                    }
                } else {
                    if contains_property("source-y", properties) {
                        false
                    } else {
                        if contains_property("source-width", properties) {
                            false
                        } else {
                            !contains_property("source-height", properties)
                        }
                    }
                }
            } else {
                false
            }
        }
        "image" => {
            if contains_property("image", properties) {
                if contains_property("source-x", properties) {
                    if contains_property("source-y", properties) {
                        if contains_property("source-width", properties) {
                            contains_property("source-height", properties)
                        } else {
                            false
                        }
                    } else {
                        false
                    }
                } else {
                    if contains_property("source-y", properties) {
                        false
                    } else {
                        if contains_property("source-width", properties) {
                            false
                        } else {
                            !contains_property("source-height", properties)
                        }
                    }
                }
            } else {
                if contains_property("url", properties) {
                    if contains_property("source-x", properties) {
                        if contains_property("source-y", properties) {
                            if contains_property("source-width", properties) {
                                contains_property("source-height", properties)
                            } else {
                                false
                            }
                        } else {
                            false
                        }
                    } else {
                        if contains_property("source-y", properties) {
                            false
                        } else {
                            if contains_property("source-width", properties) {
                                false
                            } else {
                                !contains_property("source-height", properties)
                            }
                        }
                    }
                } else {
                    false
                }
            }
        }
        "media-surface" => contains_property("surface", properties),
        "stepper" => contains_property("active", properties),
        "step" | "accordion" | "drawer" | "sheet" => contains_property("text", properties),
        "timeline-item" => contains_property("title", properties),
        "split" => {
            if contains_property("first-pane-width", properties) {
                !contains_property("value", properties)
            } else {
                true
            }
        }
        "tooltip" => {
            if contains_property("text", properties) {
                if contains_property("tooltip-delay", properties) {
                    contains_property("anchor", properties)
                } else {
                    if contains_property("anchor-alignment", properties) {
                        contains_property("anchor", properties)
                    } else {
                        if contains_property("anchor-offset", properties) {
                            contains_property("anchor", properties)
                        } else {
                            if contains_property("anchor-alignment-offset", properties) {
                                contains_property("anchor", properties)
                            } else {
                                true
                            }
                        }
                    }
                }
            } else {
                false
            }
        }
        "file-image" | "file-preview" => contains_property("path", properties),
        "popover" => {
            if contains_property("anchor-alignment", properties) {
                if contains_property("anchor", properties) {
                    if contains_property("anchor-target", properties) {
                        if contains_property("anchor-rect", properties) {
                            false
                        } else {
                            if contains_property("x", properties) {
                                false
                            } else {
                                !contains_property("y", properties)
                            }
                        }
                    } else {
                        if contains_property("x", properties) {
                            false
                        } else {
                            !contains_property("y", properties)
                        }
                    }
                } else {
                    false
                }
            } else {
                if contains_property("anchor-offset", properties) {
                    if contains_property("anchor", properties) {
                        if contains_property("anchor-target", properties) {
                            if contains_property("anchor-rect", properties) {
                                false
                            } else {
                                if contains_property("x", properties) {
                                    false
                                } else {
                                    !contains_property("y", properties)
                                }
                            }
                        } else {
                            if contains_property("x", properties) {
                                false
                            } else {
                                !contains_property("y", properties)
                            }
                        }
                    } else {
                        false
                    }
                } else {
                    if contains_property("anchor-alignment-offset", properties) {
                        if contains_property("anchor", properties) {
                            if contains_property("anchor-target", properties) {
                                if contains_property("anchor-rect", properties) {
                                    false
                                } else {
                                    if contains_property("x", properties) {
                                        false
                                    } else {
                                        !contains_property("y", properties)
                                    }
                                }
                            } else {
                                if contains_property("x", properties) {
                                    false
                                } else {
                                    !contains_property("y", properties)
                                }
                            }
                        } else {
                            false
                        }
                    } else {
                        if contains_property("anchor-target", properties) {
                            if contains_property("anchor", properties) {
                                if contains_property("anchor-rect", properties) {
                                    false
                                } else {
                                    if contains_property("x", properties) {
                                        false
                                    } else {
                                        !contains_property("y", properties)
                                    }
                                }
                            } else {
                                false
                            }
                        } else {
                            if contains_property("anchor-rect", properties) {
                                if contains_property("anchor", properties) {
                                    if contains_property("x", properties) {
                                        false
                                    } else {
                                        !contains_property("y", properties)
                                    }
                                } else {
                                    false
                                }
                            } else {
                                if contains_property("x", properties) {
                                    if contains_property("y", properties) {
                                        !contains_property("anchor", properties)
                                    } else {
                                        false
                                    }
                                } else {
                                    !contains_property("y", properties)
                                }
                            }
                        }
                    }
                }
            }
        }
        _ => false,
    }
}
