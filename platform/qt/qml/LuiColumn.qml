import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: column — vertical layout honoring gap, main-alignment, and
// cross-alignment.
ColumnLayout {
    required property var node
    readonly property var props: node ? node.properties : ({})

    spacing: Style.num(props, "gap", 0)

    readonly property bool _anyFillH: Style.anyFillMain(colRep, false)

    Item { Layout.fillHeight: true; visible: Style.needsLeadFiller(props) && !_anyFillH }
    Repeater {
        id: colRep
        model: node ? node.children : []
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
    Item { Layout.fillHeight: true; visible: Style.needsTrailFiller(props) && !_anyFillH }
}
