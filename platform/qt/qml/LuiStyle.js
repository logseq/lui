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

// Scoped theme lookup: a node's `theme` prop is a flat JSON string/string
// map defining a token table that covers the node and its descendants —
// the nearest scope wins before the shared palette above. Returns the raw
// token string (any CSS/QML color syntax) or undefined when unresolved.
function themeToken(node, name) {
    if (name === undefined || name === null || name === "")
        return undefined
    var key = String(name).toLowerCase()
    var cur = node
    var guard = 0
    while (cur !== null && cur !== undefined && guard++ < 512) {
        var props = cur.properties
        var raw = props ? props["theme"] : undefined
        if (typeof raw === "string" && raw.length > 0) {
            try {
                var dict = JSON.parse(raw)
                for (var k in dict) {
                    if (k.toLowerCase() === key && typeof dict[k] === "string")
                        return dict[k]
                }
            } catch (e) { }
        }
        cur = cur.parent
    }
    return undefined
}

// Like color() but resolves `name` against `node`'s theme scopes first.
function nodeColor(node, name, fallback) {
    var token = themeToken(node, name)
    if (token !== undefined) return token
    return color(name, fallback)
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
    return a === "center" || a === "end"
}

function needsTrailFiller(props) {
    // Qt Quick Layouts distribute slack proportionally across cells when
    // nothing fills, so a start-aligned row still needs a trailing stretch
    // item to keep its children packed to the left.
    var a = mainAlign(props)
    return a === "center" || a === "start"
}

// A lead/trail filler only packs non-filling children toward the main
// axis. Qt divides leftover space equally across every filling cell, so
// once a real child fills, the filler must drop out or it steals half the
// slack. Returns true when any delegate fills the main axis.
function anyFillMain(repeater, horizontal) {
    for (let i = 0; i < repeater.count; ++i) {
        const d = repeater.itemAt(i)
        if (d && (horizontal ? d.layoutFillWidth : d.layoutFillHeight) === true)
            return true
    }
    return false
}

function stretchCross(props) {
    return !has(props, "cross") || props["cross"] === "stretch"
}

function crossAlignmentEnum(props, horizontal) {
    // .pragma library has no Qt object — use the raw alignment flag
    // values (Qt.AlignHCenter=4, AlignVCenter=128, AlignTop=32,
    // AlignBottom=64, AlignLeft=1, AlignRight=2).
    // `horizontal` = the container is a row: its cross axis is vertical.
    switch (str(props, "cross", "stretch")) {
    case "start": return horizontal ? 32 : 1
    case "center": return horizontal ? 128 : 4
    case "end": return horizontal ? 64 : 2
    default: return horizontal ? 32 : 1
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
