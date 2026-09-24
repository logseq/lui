import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: accordion — expandable section; selected = expanded, toggled
// via the toggle event.
ColumnLayout {
    id: accordion
    required property var node
    readonly property var props: node ? node.properties : ({})

    spacing: 0
    readonly property bool expanded: props["selected"] === true

    ItemDelegate {
        id: header
        Layout.fillWidth: true
        enabled: accordion.props["enabled"] !== false
        implicitHeight: 36

        contentItem: RowLayout {
            spacing: 8
            Text {
                text: Style.str(accordion.props, "text", "")
                color: header.enabled ? header.palette.text : header.palette.placeholderText
                font.pixelSize: 14
                font.weight: Font.Medium
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Image {
                source: "icons/chevron-down.svg"
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
                rotation: accordion.expanded ? 0 : -90
            }
        }
        onClicked: accordion.node.toggle(!accordion.expanded)
    }

    ColumnLayout {
        visible: accordion.expanded
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 4

        Repeater {
            model: accordion.node ? accordion.node.children : []
            delegate: LuiNodeView {
            required property var modelData
            node: modelData }
        }
    }
}
