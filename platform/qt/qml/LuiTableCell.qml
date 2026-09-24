import QtQuick
import QtQuick.Controls
import "LuiStyle.js" as Style

// Wire kind: table-cell — text cell; pressable when press-enabled.
Item {
    id: cell
    required property var node
    readonly property var props: node ? node.properties : ({})

    implicitWidth: label.implicitWidth + 16
    implicitHeight: label.implicitHeight + 12

    Text {
        id: label
        anchors {
            fill: parent
            leftMargin: 8
            rightMargin: 8
        }
        text: Style.str(cell.props, "text", "")
        color: Style.color(cell.props["foreground"], "#18181b")
        font.pixelSize: 14
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Style.textAlignEnum(cell.props["text-alignment"])
        elide: Text.ElideRight
    }

    MouseArea {
        anchors.fill: parent
        visible: cell.props["press-enabled"] === true &&
                 cell.props["enabled"] !== false
        onClicked: cell.node.press()
    }
}
