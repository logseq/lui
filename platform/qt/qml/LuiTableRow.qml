import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: table-row — horizontal row of table-cell children; cells with
// grow > 0 flex, others size to content.
Rectangle {
    id: row
    required property var node
    readonly property var props: node ? node.properties : ({})

    SystemPalette { id: rowPal }
    implicitHeight: cells.implicitHeight + (divider.visible ? 1 : 0)
    implicitWidth: cells.implicitWidth
    color: props["selected"] === true ? rowPal.alternateBase : "transparent"

    readonly property bool isLast: {
        if (!node || !node.parent) return true
        var siblings = node.parent.children
        return siblings.length > 0 && siblings[siblings.length - 1] === node
    }

    RowLayout {
        id: cells
        width: row.width
        spacing: Style.num(row.props, "gap", 0)

        Repeater {
            model: row.node ? row.node.children : []
            delegate: LuiNodeView {
            required property var modelData
                node: modelData
                Layout.fillWidth: modelData &&
                    Number(modelData.properties["grow"] || 0) > 0
            }
        }
    }

    Rectangle {
        id: divider
        visible: !row.isLast
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: rowPal.mid
    }
}
