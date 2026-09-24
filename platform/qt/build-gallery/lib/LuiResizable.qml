import QtQuick
import "LuiStyle.js" as Style

// Wire kind: resizable — a surface whose children stack to fill it.
Item {
    required property var node
    readonly property var props: node ? node.properties : ({})

    implicitWidth: Style.num(props, "width", 200)
    implicitHeight: Style.num(props, "height", 120)

    Repeater {
        model: node ? node.children : []
        delegate: LuiNodeView {
            required property var modelData
            node: modelData
            anchors.fill: parent
        }
    }
}
