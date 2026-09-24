import QtQuick
import "LuiStyle.js" as Style

// Wire kind: paragraph — wrapped body text.
Text {
    id: para
    required property var node
    readonly property var props: node ? node.properties : ({})

    text: Style.str(props, "text", "")
    color: Style.color(props["foreground"], "#3f3f46")
    font.pixelSize: 14
    lineHeight: 1.4
    wrapMode: Text.WordWrap
}
