import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: sheet — bottom-sheet modal surface.
Item {
    id: host
    required property var node
    readonly property var props: node ? node.properties : ({})

    implicitWidth: 0
    implicitHeight: 0

    Drawer {
        id: sheet
        edge: Qt.BottomEdge
        modal: true
        interactive: true
        width: Overlay.overlay ? Overlay.overlay.width : parent.width
        height: Math.min(
            contentColumn.implicitHeight + 32,
            Overlay.overlay ? Overlay.overlay.height * 0.9 : 400)
        onClosed: if (host.node) host.node.dismiss()

        ColumnLayout {
            id: contentColumn
            width: sheet.width
            spacing: 8

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 8
                width: 36
                height: 4
                radius: 2
                color: "#d4d4d8"
            }

            Text {
                visible: Style.str(host.props, "text", "") !== ""
                text: Style.str(host.props, "text", "")
                color: "#18181b"
                font.pixelSize: 16
                font.weight: Font.DemiBold
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
            }

            Repeater {
                model: host.node ? host.node.children : []
                delegate: LuiNodeView {
            required property var modelData
                    node: modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                }
            }

            Item { implicitHeight: 16 }
        }

        background: Rectangle {
            color: "#ffffff"
            border.color: "#e4e4e7"
            border.width: 1
            radius: 12
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 12
                color: "#ffffff"
            }
        }
    }

    Component.onCompleted: sheet.open()
}
