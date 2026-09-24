import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: input-group — framed composer: editor child stacked over an
// input-group-actions child.
Rectangle {
    id: group
    required property var node
    readonly property var props: node ? node.properties : ({})

    radius: 8
    color: "#ffffff"
    border.color: "#d4d4d8"
    border.width: 1
    clip: true
    implicitWidth: body.implicitWidth + 2
    implicitHeight: body.implicitHeight + 2

    ColumnLayout {
        id: body
        anchors.centerIn: parent
        width: group.width - 2
        spacing: 0

        Repeater {
            model: group.node ? group.node.children : []
            delegate: LuiNodeView {
            required property var modelData
                node: modelData
                Layout.fillWidth: true
            }
        }
    }
}
