import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: panel — vertical content region presented as a raised surface.
Frame {
    id: panel
    required property var node
    readonly property var props: node ? node.properties : ({})

    padding: Style.num(props, "padding", 8)

    contentItem: ColumnLayout {
        spacing: Style.num(panel.props, "gap", 0)

        Item { Layout.fillHeight: true; visible: Style.needsLeadFiller(panel.props) }
        Repeater {
            model: panel.node ? panel.node.children : []
            delegate: LuiNodeView {
                required property var modelData
                node: modelData
                Layout.fillHeight: Style.fillMainHeight(node ? node.properties : ({})) ||
                                   Style.mainAlign(panel.props) === "space_between" ||
                                   contentFillsLayout
                Layout.fillWidth: Style.fillMainWidth(node ? node.properties : ({})) ||
                                  Style.stretchCross(panel.props) ||
                              contentFillsLayout
            }
        }
        Item { Layout.fillHeight: true; visible: Style.needsTrailFiller(panel.props) }
    }
}
