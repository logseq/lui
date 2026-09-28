import QtQuick
import QtQuick.Controls
import "LuiStyle.js" as Style

// Wire kind: number-stepper — bounded numeric value with -/+ buttons.
// from/step/to come from the min/step/max props; max defaults unbounded.
Row {
    id: stepper
    required property var node
    readonly property var props: node ? node.properties : ({})

    readonly property real minimum: Style.num(props, "min", 0)
    readonly property real maximum:
        props["max"] !== undefined ? Number(props["max"]) : Number.MAX_VALUE
    readonly property real stepSize: Math.max(Style.num(props, "step", 1), 0)
    readonly property real value: Style.num(props, "value", 0)
    readonly property string label: props["text"] !== undefined ? String(props["text"]) : ""

    enabled: props["enabled"] !== false
    spacing: 4

    function applyStep(delta) {
        var next = Math.min(Math.max(value + delta, minimum), maximum);
        if (next !== value && node) node.valueChanged(next);
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: stepper.label
        visible: stepper.label !== ""
    }

    Button {
        anchors.verticalCenter: parent.verticalCenter
        text: "−"
        enabled: stepper.enabled && stepper.value > stepper.minimum
        onClicked: stepper.applyStep(-stepper.stepSize)
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: stepper.value
    }

    Button {
        anchors.verticalCenter: parent.verticalCenter
        text: "+"
        enabled: stepper.enabled && stepper.value < stepper.maximum
        onClicked: stepper.applyStep(stepper.stepSize)
    }
}
