import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: toolbar — horizontal (or vertical) strip of children.
Loader {
    id: toolbar
    required property var node
    readonly property var props: node ? node.properties : ({})

    sourceComponent: Style.str(props, "orientation", "horizontal") === "vertical"
                     ? verticalStrip : horizontalStrip

    Component {
        id: horizontalStrip
        RowLayout {
            property var node: toolbar.node
            spacing: Style.num(toolbar.props, "gap", 4)
            Repeater {
                model: toolbar.node ? toolbar.node.children : []
                delegate: LuiNodeView {
            required property var modelData
            node: modelData }
            }
        }
    }

    Component {
        id: verticalStrip
        ColumnLayout {
            property var node: toolbar.node
            spacing: Style.num(toolbar.props, "gap", 4)
            Repeater {
                model: toolbar.node ? toolbar.node.children : []
                delegate: LuiNodeView {
            required property var modelData
            node: modelData }
            }
        }
    }
}
