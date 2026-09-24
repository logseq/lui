import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: row — horizontal layout honoring gap, main-alignment, and
// cross-alignment.
RowLayout {
    required property var node
    readonly property var props: node ? node.properties : ({})

    spacing: Style.num(props, "gap", 0)

    Item { Layout.fillWidth: true; visible: Style.needsLeadFiller(props) }
    Repeater {
        model: node ? node.children : []
        delegate: LuiNodeView {
            required property var modelData
            node: modelData
            Layout.fillWidth: Style.fillMainWidth(node ? node.properties : ({})) ||
                              Style.mainAlign(props) === "space_between"
            Layout.fillHeight: Style.fillMainHeight(node ? node.properties : ({})) ||
                               Style.stretchCross(props)
        }
    }
    Item { Layout.fillWidth: true; visible: Style.needsTrailFiller(props) }
}
