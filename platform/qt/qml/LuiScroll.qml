import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: scroll — scrollable stack of children; orientation selects the
// scroll axis.
ScrollView {
    id: view
    required property var node
    readonly property var props: node ? node.properties : ({})

    readonly property bool horizontal:
        Style.str(props, "orientation", "vertical") === "horizontal"

    clip: true
    implicitHeight: view.horizontal
        ? Math.min(row.implicitHeight, 320)
        : Math.min(col.implicitHeight, 320)

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
        id: col
        visible: !view.horizontal
        width: view.availableWidth
        spacing: Style.num(view.props, "gap", 0)

        Repeater {
            model: view.node && !view.horizontal ? view.node.children : []
            delegate: LuiNodeView {
                required property var modelData
                node: modelData }
        }
    }

    RowLayout {
        id: row
        visible: view.horizontal
        height: view.availableHeight
        spacing: Style.num(view.props, "gap", 0)

        Repeater {
            model: view.node && view.horizontal ? view.node.children : []
            delegate: LuiNodeView {
                required property var modelData
                node: modelData }
        }
    }
}
