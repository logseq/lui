// Shared styling helpers for the Lui QML backend. Mirrors the named color
// tokens and size conventions from platform/flutter/lib/lui_flutter_backend.dart.
.pragma library

var palette = {
    "background": "#ffffff",
    "foreground": "#18181b",
    "primary": "#007aff",
    "primary-foreground": "#ffffff",
    "secondary": "#f4f4f5",
    "secondary-foreground": "#18181b",
    "glass": "#bfffffff",
    "success": "#dcfce7",
    "success-foreground": "#166534",
    "warning": "#fef9c3",
    "warning-foreground": "#854d0e",
    "error": "#fee2e2",
    "error-foreground": "#991b1b",
    "border": "#e4e4e7",
    "black": "#000000",
    "white": "#ffffff",
    "red": "#ef4444",
    "blue": "#3b82f6",
    "green": "#22c55e",
    "transparent": "transparent"
}

function color(name, fallback) {
    if (name === undefined || name === null || name === "")
        return fallback !== undefined ? fallback : "transparent"
    var found = palette[String(name).toLowerCase()]
    if (found !== undefined) return found
    var raw = String(name)
    if (raw[0] === "#" || raw.indexOf("rgb") === 0 || raw.indexOf("oklch") === 0)
        return raw
    return fallback !== undefined ? fallback : "transparent"
}

function has(props, name) {
    return props !== undefined && props !== null &&
            props[name] !== undefined && props[name] !== null
}

function str(props, name, fallback) {
    var v = has(props, name) ? props[name] : undefined
    return typeof v === "string" ? v : (fallback !== undefined ? fallback : "")
}

function num(props, name, fallback) {
    var v = has(props, name) ? props[name] : undefined
    return typeof v === "number" && isFinite(v) ? v
         : (fallback !== undefined ? fallback : 0)
}

function bool(props, name, fallback) {
    var v = has(props, name) ? props[name] : undefined
    return typeof v === "boolean" ? v : (fallback !== undefined ? fallback : false)
}

function fontSize(size) {
    switch (size) {
    case "sm": return 12
    case "lg": return 18
    case "icon": return 16
    case "heading": return 24
    case "display": return 36
    default: return 14
    }
}

function headingPixelSize(level) {
    var sizes = [32, 28, 24, 20, 18, 16]
    var index = Math.max(0, Math.min(5, level - 1))
    return sizes[index]
}

function fillMainWidth(props) {
    return num(props, "grow", 0) > 0 ||
            props["container-relative-frame"] === "horizontal" ||
            props["container-relative-frame"] === "both"
}

function fillMainHeight(props) {
    return num(props, "grow", 0) > 0 ||
            props["container-relative-frame"] === "vertical" ||
            props["container-relative-frame"] === "both"
}

function mainAlign(props) {
    return str(props, "main", "start")
}

function needsLeadFiller(props) {
    var a = mainAlign(props)
    return a === "center" || a === "end" || a === "space_between"
}

function needsTrailFiller(props) {
    var a = mainAlign(props)
    return a === "center" || a === "space_between"
}

function stretchCross(props) {
    return !has(props, "cross") || props["cross"] === "stretch"
}

function crossAlignmentEnum(props, horizontal) {
    switch (str(props, "cross", "stretch")) {
    case "start": return horizontal ? Qt.AlignTop : Qt.AlignLeft
    case "center": return Qt.AlignCenter
    case "end": return horizontal ? Qt.AlignBottom : Qt.AlignRight
    default: return horizontal ? Qt.AlignTop : Qt.AlignLeft
    }
}

function textAlignEnum(props) {
    switch (str(props, "text-alignment", "start")) {
    case "center": return 4 // Text.AlignHCenter
    case "end": return 2 // Text.AlignRight
    default: return 1 // Text.AlignLeft
    }
}

function controlPadding(size) {
    switch (size) {
    case "sm": return 6
    case "lg": return 14
    case "icon": return 6
    default: return 10
    }
}

function iconSource(name) {
    if (name === undefined || name === null || name === "") return ""
    if (String(name).indexOf("app:") === 0) return ""
    return "icons/" + name + ".svg"
}
