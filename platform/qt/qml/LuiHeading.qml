import QtQuick
import "LuiStyle.js" as Style

// Wire kind: heading — bold text sized by heading-level (1-6).
Text {
    id: heading
    required property var node
    readonly property var props: node ? node.properties : ({})

    SystemPalette { id: headingPal }
    text: Style.str(props, "text", "")
    color: Style.nodeColor(node, props["foreground"], headingPal.text)
    font.pixelSize: Style.headingPixelSize(
        Math.max(1, Math.min(6, Style.num(props, "heading-level", 1))))
    font.weight: Font.DemiBold
    wrapMode: Text.WordWrap
}
