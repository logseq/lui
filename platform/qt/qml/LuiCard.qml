import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: card — elevated surface with default border, radius, and padding.
Frame {
    id: card
    required property var node
    readonly property var props: node ? node.properties : ({})

    topPadding: padV
    bottomPadding: padV
    leftPadding: padH
    rightPadding: padH

    property real padV: Math.max(Style.num(props, "padding", 0),
                                 Style.num(props, "padding-vertical", 12))
    property real padH: Math.max(padV,
                                 Style.num(props, "padding-horizontal", 12))

    contentItem: ColumnLayout {
        id: col
        spacing: Style.num(props, "gap", 8)

        Item { Layout.fillHeight: true; visible: Style.needsLeadFiller(props) }
        Repeater {
            model: card.node ? card.node.children : []
            delegate: LuiNodeView {
                required property var modelData
                node: modelData
                Layout.fillHeight: Style.fillMainHeight(node ? node.properties : ({})) ||
                                   Style.mainAlign(props) === "space_between" ||
                               contentFillsLayout
                Layout.fillWidth: Style.fillMainWidth(node ? node.properties : ({})) ||
                                  Style.stretchCross(props) ||
                              contentFillsLayout
            }
        }
        Item { Layout.fillHeight: true; visible: Style.needsTrailFiller(props) }
    }
}
