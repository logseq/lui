import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: box — bordered box container stacking children vertically.
Rectangle {
    id: box
    required property var node
    readonly property var props: node ? node.properties : ({})

    color: Style.color(props["background"], "transparent")
    border.color: Style.color(props["border-color"], "#e4e4e7")
    border.width: Style.num(props, "border-width", 1)
    radius: Style.num(props, "corner-radius", 6)

    implicitWidth: col.implicitWidth + 2 * pad
    implicitHeight: col.implicitHeight + 2 * pad

    property real pad: Math.max(Style.num(props, "padding", 0),
                                Style.num(props, "padding-vertical", 8))

    ColumnLayout {
        id: col
        anchors {
            fill: parent
            margins: box.pad
            leftMargin: Math.max(margins, Style.num(props, "padding-horizontal", 8))
            rightMargin: leftMargin
        }
        spacing: Style.num(props, "gap", 0)

        Item { Layout.fillHeight: true; visible: Style.needsLeadFiller(props) }
        Repeater {
            model: box.node ? box.node.children : []
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
