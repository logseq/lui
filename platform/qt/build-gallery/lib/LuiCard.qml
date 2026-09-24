import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: card — elevated surface with default border, radius, and padding.
Rectangle {
    id: card
    required property var node
    readonly property var props: node ? node.properties : ({})

    color: Style.color(props["background"], "#ffffff")
    border.color: Style.color(props["border-color"], "#e4e4e7")
    border.width: Style.num(props, "border-width", 1)
    radius: Style.num(props, "corner-radius", 10)

    implicitWidth: col.implicitWidth + 2 * padH
    implicitHeight: col.implicitHeight + 2 * padV

    property real padV: Math.max(Style.num(props, "padding", 0),
                                 Style.num(props, "padding-vertical", 12))
    property real padH: Math.max(padV,
                                 Style.num(props, "padding-horizontal", 12))

    ColumnLayout {
        id: col
        anchors {
            fill: parent
            topMargin: card.padV
            bottomMargin: card.padV
            leftMargin: card.padH
            rightMargin: card.padH
        }
        spacing: Style.num(props, "gap", 8)

        Item { Layout.fillHeight: true; visible: Style.needsLeadFiller(props) }
        Repeater {
            model: card.node ? card.node.children : []
            delegate: LuiNodeView {
                required property var modelData
                node: modelData
                Layout.fillHeight: Style.fillMainHeight(node ? node.properties : ({})) ||
                                   Style.mainAlign(props) === "space_between"
                Layout.fillWidth: Style.fillMainWidth(node ? node.properties : ({})) ||
                                  Style.stretchCross(props)
            }
        }
        Item { Layout.fillHeight: true; visible: Style.needsTrailFiller(props) }
    }
}
