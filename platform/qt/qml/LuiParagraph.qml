import QtQuick
import "LuiStyle.js" as Style

// Wire kind: paragraph — wrapped body text.
Text {
    id: para
    required property var node
    readonly property var props: node ? node.properties : ({})

    SystemPalette { id: paraPal }
    text: Style.str(props, "text", "")
    color: Style.nodeColor(node, props["foreground"], paraPal.text)
    font.pixelSize: 14
    lineHeight: 1.4
    wrapMode: Text.WordWrap
}
