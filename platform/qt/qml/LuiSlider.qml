import QtQuick
import QtQuick.Controls
import "LuiStyle.js" as Style

// Wire kind: slider — 0..1 fractional value control.
Slider {
    id: slider
    required property var node
    readonly property var props: node ? node.properties : ({})

    from: 0
    to: 1
    value: Style.num(props, "value", 0)
    enabled: props["enabled"] !== false
    implicitWidth: 160

    onMoved: node.valueChanged(value)
}
