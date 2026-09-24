import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: scroll — scrollable vertical stack of children.
ScrollView {
    id: view
    required property var node
    readonly property var props: node ? node.properties : ({})

    contentWidth: availableWidth
    clip: true

    ScrollBar.vertical.policy: {
        var s = Style.str(props, "scrollbars", "auto")
        if (s === "hidden" || s === "never") return ScrollBar.AlwaysOff
        if (s === "always") return ScrollBar.AlwaysOn
        return ScrollBar.AsNeeded
    }
    ScrollBar.horizontal.policy: {
        var s = Style.str(props, "scrollbars", "auto")
        if (s === "hidden" || s === "never") return ScrollBar.AlwaysOff
        if (s === "always") return ScrollBar.AlwaysOn
        return ScrollBar.AsNeeded
    }

    ColumnLayout {
        width: view.availableWidth
        spacing: Style.num(view.props, "gap", 0)

        Repeater {
            model: view.node ? view.node.children : []
            delegate: LuiNodeView {
            required property var modelData
            node: modelData }
        }
    }
}
