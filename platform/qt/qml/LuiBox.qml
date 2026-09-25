import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: box — bordered box container stacking children vertically.
Rectangle {
    id: box
    required property var node
    readonly property var props: node ? node.properties : ({})

    SystemPalette { id: boxPal }
    color: Style.color(props["background"], "transparent")
    border.color: Style.color(props["border-color"], boxPal.mid)
    border.width: Style.num(props, "border-width", 1)
    radius: Style.num(props, "corner-radius", 6)

    implicitWidth: col.implicitWidth + 2 * padH
    implicitHeight: col.implicitHeight + 2 * padV

    property real padV: Math.max(Style.num(props, "padding", 0),
                                 Style.num(props, "padding-vertical", 8))
    property real padH: Math.max(padV,
                                 Style.num(props, "padding-horizontal", 8))

    ColumnLayout {
        id: col
        anchors {
            fill: parent
            topMargin: box.padV
            bottomMargin: box.padV
            leftMargin: box.padH
            rightMargin: box.padH
        }
        spacing: Style.num(props, "gap", 0)

        readonly property bool _anyFillH: Style.anyFillMain(boxRep, false)

        Item { Layout.fillHeight: true; visible: Style.needsLeadFiller(props) && !_anyFillH }
        Repeater {
            id: boxRep
            model: box.node ? box.node.children : []
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
}
