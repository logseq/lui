import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: row — horizontal layout honoring gap, main-alignment, and
// cross-alignment.
RowLayout {
    id: row
    required property var node
    readonly property var props: node ? node.properties : ({})

    spacing: Style.num(props, "gap", 0)

    readonly property bool _anyFillW: Style.anyFillMain(rowRep, true)

    Item { Layout.fillWidth: true; visible: Style.needsLeadFiller(props) && !_anyFillW }
    Repeater {
        id: rowRep
        model: node ? node.children : []
        delegate: LuiNodeView {
            required property var modelData
            node: modelData
            Layout.fillWidth: Style.fillMainWidth(node ? node.properties : ({})) ||
                              Style.mainAlign(row.props) === "space_between" ||
                               contentFillsLayout
            Layout.fillHeight: Style.fillMainHeight(node ? node.properties : ({})) ||
                               Style.stretchCross(row.props) ||
                              contentFillsLayout
            Layout.alignment: Style.crossAlignmentEnum(row.props, true)
        }
    }
    Item { Layout.fillWidth: true; visible: Style.needsTrailFiller(props) && !_anyFillW }
}
