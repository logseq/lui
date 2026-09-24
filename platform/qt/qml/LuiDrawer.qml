import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: drawer — main content plus a side panel; selected = presented,
// toggled via the toggle event.
Item {
    id: host
    required property var node
    readonly property var props: node ? node.properties : ({})

    readonly property bool presented: props["selected"] === true
    readonly property var mainChild: node && node.children.length > 0
                                     ? node.children[0] : null
    readonly property var panelChild: node && node.children.length > 1
                                      ? node.children[1] : null

    Loader {
        anchors.fill: parent
        active: host.mainChild !== null
        sourceComponent: mainContent
    }

    Component {
        id: mainContent
        LuiNodeView { node: host.mainChild }
    }

    Drawer {
        id: drawer
        edge: Qt.LeftEdge
        modal: true
        interactive: true
        width: Style.num(host.props, "width", 320)
        height: host.height
        position: host.presented ? 1 : 0
        visible: position > 0
        onVisibleChanged: {
            if (!visible && host.presented && host.node)
                host.node.toggle(false)
        }

        contentItem: Loader {
            active: host.panelChild !== null
            sourceComponent: panelContent
        }


    }

    Component {
        id: panelContent
        LuiNodeView {
            node: host.panelChild
            anchors.fill: parent
        }
    }
}
