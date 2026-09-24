import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: tabs — segmented horizontal group of button children.
Rectangle {
    id: tabs
    required property var node
    readonly property var props: node ? node.properties : ({})

    SystemPalette { id: tabsPal }

    implicitWidth: group.implicitWidth + 8
    implicitHeight: group.implicitHeight + 8
    radius: 8
    color: tabsPal.alternateBase

    RowLayout {
        id: group
        anchors.centerIn: parent
        spacing: Style.num(tabs.props, "gap", 4)

        Repeater {
            model: tabs.node ? tabs.node.children : []
            delegate: LuiNodeView {
            required property var modelData
            node: modelData }
        }
    }
}
