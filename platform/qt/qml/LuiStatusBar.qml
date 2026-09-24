import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: status-bar — bottom bar showing text.
Rectangle {
    id: bar
    required property var node
    readonly property var props: node ? node.properties : ({})

    color: Style.color(props["background"], "#f4f4f5")
    border.color: Style.color(props["border-color"], "#e4e4e7")
    border.width: Style.num(props, "border-width", 0)
    implicitHeight: 26
    implicitWidth: 160

    Text {
        anchors {
            fill: parent
            leftMargin: 10
            rightMargin: 10
        }
        text: Style.str(bar.props, "text", "")
        color: Style.color(bar.props["foreground"], "#52525b")
        font.pixelSize: 12
        horizontalAlignment: Style.textAlignEnum(bar.props)
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
}
