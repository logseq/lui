import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: stepper — horizontal row of step children; "active" marks the
// current step index.
RowLayout {
    required property var node
    readonly property var props: node ? node.properties : ({})

    spacing: Style.num(props, "gap", 0)

    Repeater {
        model: node ? node.children : []
        delegate: LuiNodeView {
            required property var modelData
            node: modelData }
    }

    Item { Layout.fillWidth: true }
}
