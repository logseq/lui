import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: list-item — pressable row with optional icon/text/subtitle.
ItemDelegate {
    id: item
    required property var node
    readonly property var props: node ? node.properties : ({})

    enabled: props["enabled"] !== false
    highlighted: props["selected"] === true
    readonly property bool isTreeItem: props["role"] === "treeitem"
    readonly property bool isTreeDir:
        isTreeItem &&
        String(props["icon"] || "").indexOf("folder") === 0
    padding: 6
    leftPadding: padding +
        (isTreeItem ? Math.max(0, Number(props["tree-level"] || 0) - 1) * 16 : 0)
    implicitHeight: Math.max(30, contentItem.implicitHeight + 12)

    contentItem: RowLayout {
        spacing: 10
        Image {
            visible: item.isTreeItem
            opacity: item.isTreeDir ? 1 : 0
            source: "icons/chevron-right.svg"
            rotation: item.props["expanded"] === true ? 90 : 0
            Layout.preferredWidth: 12
            Layout.preferredHeight: 12
        }
        Image {
            visible: Style.str(item.props, "icon", "") !== ""
            source: Style.iconSource(Style.str(item.props, "icon", ""))
            Layout.preferredWidth: 18
            Layout.preferredHeight: 18
            fillMode: Image.PreserveAspectFit
        }
        ColumnLayout {
            spacing: 1
            Layout.fillWidth: true
            Text {
                text: Style.str(item.props, "text", "")
                color: !item.enabled ? item.palette.placeholderText
                       : item.highlighted ? item.palette.highlightedText
                       : item.palette.text
                font.pixelSize: 14
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Text {
                visible: Style.str(item.props, "subtitle", "") !== ""
                text: Style.str(item.props, "subtitle", "")
                color: item.highlighted ? item.palette.highlightedText
                                        : item.palette.placeholderText
                font.pixelSize: 12
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }
    }


    background: Rectangle {
        color: item.down ? item.palette.mid
               : item.highlighted ? item.palette.highlight
               : item.hovered ? item.palette.midlight
               : "transparent"
    }

    onClicked: {
        // treeitem rows select/expand via the change cascade, not press.
        if (props["role"] === "treeitem") node.change()
        else node.press()
    }
    onPressAndHold: if (props["long-press-enabled"] === true) node.longPress()
    onDoubleClicked: if (props["double-press-enabled"] === true) node.doublePress()
}
