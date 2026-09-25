import QtQuick
import "LuiStyle.js" as Style

// Wire kind: icon — named SVG glyph.
Image {
    required property var node
    readonly property var props: node ? node.properties : ({})

    source: Style.iconSource(Style.str(props, "name", ""))
    readonly property int iconSize: {
        var pt = Style.num(props, "point-size", 0)
        if (pt > 0) return pt
        switch (Style.str(props, "size", "default")) {
        case "sm": return 14
        case "lg": return 24
        case "icon": return 18
        default: return 18
        }
    }
    // Image.implicitWidth/Height are read-only; sourceSize makes the
    // implicit size iconSize x iconSize.
    sourceSize.width: iconSize
    sourceSize.height: iconSize
    fillMode: Image.PreserveAspectFit
}
