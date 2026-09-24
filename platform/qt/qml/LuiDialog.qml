import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: dialog — modal surface; the node's presence means presented,
// closing emits dismiss.
Item {
    id: host
    required property var node
    readonly property var props: node ? node.properties : ({})

    implicitWidth: 0
    implicitHeight: 0

    Dialog {
        id: dialog
        modal: true
        focus: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(
            Style.num(host.props, "width", 0) > 0
                ? Style.num(host.props, "width", 0) : 400,
            Overlay.overlay ? Overlay.overlay.width - 48 : 400)
        padding: 20
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onClosed: if (host.node) host.node.dismiss()

        header: Text {
            visible: Style.str(host.props, "text", "") !== ""
            text: Style.str(host.props, "text", "")
            color: dialog.palette.text
            font.pixelSize: 16
            font.weight: Font.DemiBold
            padding: 4
            bottomPadding: 8
        }

        contentItem: ColumnLayout {
            spacing: 8
            Repeater {
                model: host.node ? host.node.children : []
                delegate: LuiNodeView {
            required property var modelData
            node: modelData }
            }
        }


    }

    Component.onCompleted: dialog.open()
}
