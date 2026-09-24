import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: step — one marker inside a stepper; state derives from the
// parent's "active" index.
RowLayout {
    id: step
    required property var node
    readonly property var props: node ? node.properties : ({})

    spacing: 6
    readonly property int index: {
        if (!node || !node.parent) return 0
        var siblings = node.parent.children
        for (var i = 0; i < siblings.length; ++i)
            if (siblings[i] === node) return i
        return 0
    }
    readonly property int count:
        node && node.parent ? node.parent.children.length : 1
    readonly property int active:
        node && node.parent
        ? Style.num(node.parent.properties, "active", 0) : 0
    readonly property string state:
        index < active ? "completed" : index === active ? "active" : "pending"

    Rectangle {
        width: 24
        height: 24
        radius: 12
        color: step.state === "pending" ? "transparent" : "#007aff"
        border.color: step.state === "pending" ? "#a1a1aa" : "#007aff"
        border.width: 1

        Image {
            visible: step.state === "completed"
            anchors.centerIn: parent
            source: "icons/check.svg"
            width: 14
            height: 14
        }
        Text {
            visible: step.state !== "completed"
            anchors.centerIn: parent
            text: String(step.index + 1)
            color: step.state === "active" ? "#ffffff" : "#71717a"
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
    }

    Text {
        text: Style.str(step.props, "text", "")
        color: step.state === "pending" ? "#71717a" : "#18181b"
        font.pixelSize: 14
        font.weight: step.state === "active" ? Font.DemiBold : Font.Normal
    }

    Rectangle {
        visible: step.index + 1 < step.count
        Layout.preferredWidth: 24
        Layout.preferredHeight: 1
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        color: "#e4e4e7"
    }
}
