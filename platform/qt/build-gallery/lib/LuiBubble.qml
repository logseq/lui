import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: bubble — chat/message bubble tinted by variant.
Rectangle {
    id: bubble
    required property var node
    readonly property var props: node ? node.properties : ({})

    color: Style.str(props, "variant", "default") === "primary"
           ? "#007aff" : Style.color(props["background"], "#f4f4f5")
    radius: Style.num(props, "corner-radius", 16)
    border.color: Style.color(props["border-color"], "transparent")
    border.width: Style.num(props, "border-width", 0)

    implicitWidth: col.implicitWidth + 24
    implicitHeight: col.implicitHeight + 16

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 8
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: Style.num(props, "gap", 4)

        Text {
            visible: Style.str(bubble.props, "text", "") !== ""
            text: Style.str(bubble.props, "text", "")
            color: Style.str(bubble.props, "variant", "default") === "primary"
                   ? "#ffffff"
                   : Style.color(bubble.props["foreground"], "#18181b")
            font.pixelSize: 14
            horizontalAlignment: Style.textAlignEnum(bubble.props)
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Repeater {
            model: bubble.node ? bubble.node.children : []
            delegate: LuiNodeView {
            required property var modelData
            node: modelData; Layout.fillWidth: true }
        }
    }
}
