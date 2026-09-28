import QtQuick

// Wire kind: view-that-fits — renders the first child that fits along
// `orientation` (default horizontal). QML has no intrinsic fit-or-fallback
// container; renders the first candidate.
Item {
    id: viewThatFits
    required property var node
    readonly property var props: node ? node.properties : ({})

    implicitWidth: rep.itemAt(0) ? rep.itemAt(0).implicitWidth : 0
    implicitHeight: rep.itemAt(0) ? rep.itemAt(0).implicitHeight : 0

    Repeater {
        id: rep
        model: {
            var children = viewThatFits.node ? viewThatFits.node.children : []
            return children.length > 0 ? [children[0]] : []
        }
        delegate: LuiNodeView {
            required property var modelData
            node: modelData
            anchors.fill: viewThatFits
        }
    }
}
