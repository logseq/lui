// Generic retained-node renderer: loads the component for node.kind (or the
// registered QML source for extension nodes) and applies the common chrome —
// sizing, background/border, padding, context menus, and the appear event.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "LuiStyle.js" as Style

Item {
    id: view
    required property var node

    // Set by LuiStack for overlay children (dropdown-menu, tooltip) so the
    // popup anchors to the preceding sibling.
    property Item overlayAnchor: null

    readonly property var props: node && node.properties ? node.properties : ({})

    function prop(name, fallback) {
        var v = props[name]
        return v !== undefined && v !== null ? v : fallback
    }

    function componentFor(kind) {
        var pascal = String(kind).split("-").map(function(part) {
            return part.length === 0 ? "" : part[0].toUpperCase() + part.slice(1)
        }).join("")
        return "Lui" + pascal + ".qml"
    }

    readonly property var contextMenuNode: {
        var kids = node ? node.children : []
        for (var i = 0; i < kids.length; ++i)
            if (kids[i] && kids[i].kind === "context-menu") return kids[i]
        return null
    }

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    property real _w: Number(prop("width", 0))
    property real _h: Number(prop("height", 0))
    width: _w > 0 ? _w : implicitWidth
    height: _h > 0 ? _h : implicitHeight

    Layout.fillWidth: Number(prop("grow", 0)) > 0 ||
                      prop("container-relative-frame", "") === "horizontal" ||
                      prop("container-relative-frame", "") === "both"
    Layout.fillHeight: Number(prop("grow", 0)) > 0 ||
                       prop("container-relative-frame", "") === "vertical" ||
                       prop("container-relative-frame", "") === "both"
    Layout.minimumWidth: Number(prop("min-width", 0))
    Layout.minimumHeight: Number(prop("min-height", 0))
    Layout.maximumWidth: Number(prop("max-width", 0)) > 0
                         ? Number(prop("max-width", 0)) : Infinity
    Layout.maximumHeight: Number(prop("max-height", 0)) > 0
                          ? Number(prop("max-height", 0)) : Infinity

    objectName: prop("accessibility-identifier", "") !== ""
                ? "lui-" + prop("accessibility-identifier", "")
                : (node ? "lui-node-" + node.nodeId : "lui-node")

    Accessible.role: Accessible.ClientArea
    Accessible.name: prop("accessibility-label", "")

    Rectangle {
        id: backdrop
        anchors.fill: parent
        visible: color !== "transparent" || border.width > 0
        color: Style.color(view.prop("background", ""), "transparent")
        border.color: Style.color(view.prop("border-color", ""), "transparent")
        border.width: Number(view.prop("border-width", 0))
        radius: Number(view.prop("corner-radius", 0))
    }

    Loader {
        id: content
        anchors {
            fill: parent
            margins: Number(view.prop("padding", 0))
            leftMargin: Math.max(margins, Number(view.prop("padding-horizontal", 0)))
            rightMargin: leftMargin
            topMargin: Math.max(margins, Number(view.prop("padding-vertical", 0)))
            bottomMargin: topMargin
        }
        source: view.node
                ? (view.node.extension
                   ? view.node.componentSource
                   : view.componentFor(view.node.kind))
                : ""
        onLoaded: {
            item.node = Qt.binding(function() { return view.node })
            if ("anchorItem" in item)
                item.anchorItem = Qt.binding(function() { return view.overlayAnchor })
        }
    }

    // Context menus open on right-click or long-press on their host.
    MouseArea {
        anchors.fill: parent
        z: 10
        acceptedButtons: Qt.RightButton
        enabled: view.contextMenuNode !== null
        onClicked: function(mouse) {
            ctxMenu.popup(view, mouse.x, mouse.y)
        }
        onPressAndHold: function(mouse) {
            ctxMenu.popup(view, mouse.x, mouse.y)
        }
    }

    Menu {
        id: ctxMenu
        Instantiator {
            model: view.contextMenuNode ? view.contextMenuNode.children : []
            delegate: Loader {
                required property var modelData
                property var childNode: modelData
                sourceComponent: childNode && childNode.kind === "divider"
                                 ? sepComponent : itemComponent
                onLoaded: item.childNode = childNode
            }
            onObjectAdded: function(index, object) {
                ctxMenu.insertItem(index, object.item)
            }
            onObjectRemoved: function(index, object) {
                ctxMenu.removeItem(object.item)
            }
        }
    }

    Component {
        id: sepComponent
        MenuSeparator {
            property var childNode
        }
    }
    Component {
        id: itemComponent
        MenuItem {
            property var childNode
            text: childNode ? String(childNode.properties["text"] || "") : ""
            enabled: !childNode || childNode.properties["enabled"] !== false
            onTriggered: if (childNode) childNode.press()
        }
    }

    Component.onCompleted: {
        if (view.node && !view.node.extension &&
                view.node.properties["appear-enabled"] === true) {
            view.node.appear()
        }
    }
}
