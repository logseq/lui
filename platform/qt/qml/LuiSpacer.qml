import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: spacer — flexible empty space inside a layout.
Item {
    required property var node
    readonly property var props: node ? node.properties : ({})

    Layout.fillWidth: true
    Layout.fillHeight: true
    implicitWidth: Style.num(props, "width", 8)
    implicitHeight: Style.num(props, "height", 8)
}
