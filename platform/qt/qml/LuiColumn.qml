import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: column — vertical layout honoring gap, main-alignment, and
// cross-alignment. Tappable when press-enabled; taps on interactive
// children still reach the child (the tap layer sits below the content).
Item {
    id: col
    required property var node
    readonly property var props: node ? node.properties : ({})

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: col.props["press-enabled"] === true
        onClicked: col.node.press()
    }

    ColumnLayout {
        id: layout
        anchors.fill: parent

        spacing: Style.num(col.props, "gap", 0)

        readonly property bool _anyFillH: Style.anyFillMain(colRep, false)

        Item { Layout.fillHeight: true; visible: Style.needsLeadFiller(col.props) && !layout._anyFillH }
        Repeater {
            id: colRep
            model: col.node ? col.node.children : []
            delegate: LuiNodeView {
                required property var modelData
                node: modelData
                Layout.fillHeight: Style.fillMainHeight(node ? node.properties : ({})) ||
                                   Style.mainAlign(col.props) === "space_between" ||
                                   contentFillsLayout
                Layout.fillWidth: Style.fillMainWidth(node ? node.properties : ({})) ||
                                  Style.stretchCross(col.props) ||
                                  contentFillsLayout
                Layout.alignment: Style.crossAlignmentEnum(col.props, false)
            }
        }
        Item { Layout.fillHeight: true; visible: Style.needsTrailFiller(col.props) && !layout._anyFillH }
    }
}
