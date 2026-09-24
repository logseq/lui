import QtQuick
import QtQuick.Controls
import "LuiStyle.js" as Style

// Wire kind: spinner — indeterminate activity indicator.
BusyIndicator {
    required property var node
    readonly property var props: node ? node.properties : ({})

    running: props["enabled"] !== false
    palette.dark: Style.color(props["foreground"], "#007aff")
    implicitWidth: 20
    implicitHeight: 20
}
