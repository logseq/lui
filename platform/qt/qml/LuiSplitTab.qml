// split-tab: data carrier for a pane's tab. The pane renders the selected
// tab through a LuiNodeView on this node, which lands here — stack the
// standard children so a bare split-tab still shows its content.
import QtQuick

Item {
    id: tab
    required property var node

    property bool fillsLayout: true

    implicitWidth: childrenRepeater.count > 0 ? 100 : 0
    implicitHeight: childrenRepeater.count > 0 ? 100 : 0

    Repeater {
        id: childrenRepeater
        model: tab.node ? tab.node.children : []
        delegate: LuiNodeView {
            anchors.fill: tab
            node: modelData
        }
    }
}
