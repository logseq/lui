import QtQuick
import "LuiStyle.js" as Style

// Wire kind: label — small secondary text.
Text {
    id: label
    required property var node
    readonly property var props: node ? node.properties : ({})

    SystemPalette { id: labelPal }
    text: Style.str(props, "text", "")
    color: Style.nodeColor(node, props["foreground"], labelPal.placeholderText)
    font.pixelSize: 12
    wrapMode: Text.WordWrap
}
