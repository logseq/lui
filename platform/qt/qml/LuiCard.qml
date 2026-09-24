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

    implicitWidth: col.implicitWidth + 2 * pad
    implicitHeight: col.implicitHeight + 2 * pad

    property real pad: Math.max(Style.num(props, "padding", 0),
                                Style.num(props, "padding-vertical", 12))

    ColumnLayout {
        id: col
        anchors {
            fill: parent
            margins: card.pad
            leftMargin: Math.max(margins, Style.num(props, "padding-horizontal", 12))
            rightMargin: leftMargin
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
