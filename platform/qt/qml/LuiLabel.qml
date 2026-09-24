import QtQuick
import "LuiStyle.js" as Style

// Wire kind: label — small secondary text.
Text {
    id: label
    required property var node
    readonly property var props: node ? node.properties : ({})

    text: Style.str(props, "text", "")
    color: Style.color(props["foreground"], "#52525b")
    font.pixelSize: 12
    wrapMode: Text.WordWrap
}
