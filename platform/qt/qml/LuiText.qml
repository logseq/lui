import QtQuick
import "LuiStyle.js" as Style

// Wire kind: text — plain text; tappable when press-enabled.
Text {
    id: label
    required property var node
    readonly property var props: node ? node.properties : ({})

    SystemPalette { id: textPal }
    text: Style.str(props, "text", "")
    color: Style.nodeColor(node, props["foreground"], textPal.text)
    font.pixelSize: Style.fontSize(Style.str(props, "size", "default"))
    horizontalAlignment: Style.textAlignEnum(props)
    wrapMode: Text.WordWrap

    MouseArea {
        anchors.fill: parent
        enabled: label.props["press-enabled"] === true
        onClicked: label.node.press()
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
}
