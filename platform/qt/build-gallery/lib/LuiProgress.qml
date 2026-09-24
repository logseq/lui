import QtQuick
import QtQuick.Controls
import "LuiStyle.js" as Style

// Wire kind: progress — 0..1 progress bar.
ProgressBar {
    id: bar
    required property var node
    readonly property var props: node ? node.properties : ({})

    from: 0
    to: 1
    value: Style.num(props, "value", 0)
    implicitWidth: 160
}
