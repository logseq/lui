import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: link — opens the "url" prop with the system handler
// (Qt.openUrlExternally). Renders children when present, else "text" or the
// raw url.
Item {
    id: wrapper
    required property var node
    readonly property var props: node ? node.properties : ({})

    readonly property string url: Style.str(props, "url", "")

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    RowLayout {
        id: content
        spacing: Style.num(wrapper.props, "gap", 4)

        Repeater {
            model: wrapper.node ? wrapper.node.children : []
            delegate: LuiNodeView {
                required property var modelData
                node: modelData
            }
        }

        Image {
            visible: Style.str(wrapper.props, "icon", "") !== ""
            source: Style.iconSource(Style.str(wrapper.props, "icon", ""))
            sourceSize.width: 16
            sourceSize.height: 16
        }

        Text {
            visible: (wrapper.node ? wrapper.node.children.length : 0) === 0
            text: Style.str(wrapper.props, "text", wrapper.url)
            color: Style.nodeColor(wrapper.node,
                                   wrapper.props["foreground"], "blue")
            font.underline: true
        }
    }

    TapHandler {
        enabled: wrapper.props["enabled"] !== false && wrapper.url !== ""
        onTapped: Qt.openUrlExternally(wrapper.url)
    }
}
