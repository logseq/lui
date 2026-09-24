import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: toast — transient notification card; auto-dismisses after
// "duration" ms (0 = manual).
Item {
    id: toast
    required property var node
    readonly property var props: node ? node.properties : ({})

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight

    Frame {
        id: card
        implicitWidth: row.implicitWidth + 32
        implicitHeight: row.implicitHeight + 32

        contentItem: RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 12
            Repeater {
                model: toast.node ? toast.node.children : []
                delegate: LuiNodeView {
            required property var modelData
            node: modelData }
            }
        }
    }

    Timer {
        interval: Style.num(toast.props, "duration", 0)
        running: interval > 0
        onTriggered: if (toast.node) toast.node.dismiss()
    }
}
