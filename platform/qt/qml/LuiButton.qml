import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: button — press action, optional icon + variant styling.
Button {
    id: button
    required property var node
    readonly property var props: node ? node.properties : ({})

    readonly property string variant: Style.str(props, "variant", "default")
    readonly property string size: Style.str(props, "size", "default")
    readonly property string iconName: Style.str(props, "icon", "")
    readonly property string placement:
        Style.str(props, "icon-placement", "leading")

    text: Style.str(props, "text", "")
    enabled: props["enabled"] !== false
    Component.onCompleted: if (props["autofocus"] === true) forceActiveFocus()

    padding: Style.controlPadding(size)

    contentItem: GridLayout {
        rows: button.placement === "top" ? 2 : 1
        columns: button.placement === "top" ? 1 : 2
        rowSpacing: 2
        columnSpacing: 6

        Image {
            visible: button.iconName !== ""
            source: Style.iconSource(button.iconName)
            Layout.preferredWidth: 14
            Layout.preferredHeight: 14
            fillMode: Image.PreserveAspectFit
            Layout.alignment: Qt.AlignCenter
            Layout.column: button.placement === "trailing" ? 1 : 0
            Layout.row: 0
        }
        Text {
            text: button.text
            color: button.palette.buttonText
            font.pixelSize: Style.fontSize(button.size)
            horizontalAlignment: Style.textAlignEnum(button.props)
            elide: Text.ElideRight
            Layout.column: button.placement === "top" ? 0
                          : button.placement === "trailing" ? 0 : 1
            Layout.row: button.placement === "top" ? 1 : 0
        }
    }

    background: Rectangle {
        implicitWidth: 80
        implicitHeight: button.size === "icon" ? 28
                        : button.size === "sm" ? 28
                        : button.size === "lg" ? 40 : 34
        radius: 6
        color: {
            if (!button.enabled) return "#e4e4e7"
            switch (button.variant) {
            case "primary": return button.down ? "#0060c9" : "#007aff"
            case "secondary": return button.down ? "#e4e4e7" : "#f4f4f5"
            case "outline": return button.down ? "#f4f4f5" : "transparent"
            case "ghost": return button.down ? "#f4f4f5" : "transparent"
            case "destructive": return button.down ? "#b91c1c" : "#ef4444"
            default: return button.down ? "#0060c9" : "#007aff"
            }
        }
        border.color: button.variant === "outline" ? "#d4d4d8" : "transparent"
        border.width: button.variant === "outline" ? 1 : 0
    }

    palette.buttonText: {
        if (!button.enabled) return "#a1a1aa"
        switch (button.variant) {
        case "primary":
        case "destructive": return "#ffffff"
        default: return "#18181b"
        }
    }

    onClicked: node.press()
    onPressAndHold: if (props["long-press-enabled"] === true) node.longPress()
}
