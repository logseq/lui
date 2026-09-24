import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: grid — column-count grid layout.
GridLayout {
    required property var node
    readonly property var props: node ? node.properties : ({})

    columns: Math.max(1, Style.num(props, "columns", 1))
    rowSpacing: Style.num(props, "gap", 0)
    columnSpacing: rowSpacing

    Repeater {
        model: node ? node.children : []
        delegate: LuiNodeView {
            required property var modelData
            node: modelData
            Layout.fillWidth: true
            Layout.fillHeight: Style.fillMainHeight(node ? node.properties : ({})) ||
                                   contentFillsLayout
        }
    }
}
