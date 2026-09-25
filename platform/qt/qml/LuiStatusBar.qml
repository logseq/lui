import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: status-bar — bottom bar showing text.
Rectangle {
    id: bar
    required property var node
    readonly property var props: node ? node.properties : ({})

    SystemPalette { id: barPal }
    color: Style.nodeColor(node, props["background"], barPal.window)
    border.color: Style.nodeColor(node, props["border-color"], barPal.mid)
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
        color: Style.nodeColor(bar.node, bar.props["foreground"], barPal.text)
        font.pixelSize: 12
        horizontalAlignment: Style.textAlignEnum(bar.props)
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
}
