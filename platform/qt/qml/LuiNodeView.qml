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

    // The frame chrome reserves space around the loaded component, so the
    // implicit size must include it — otherwise a padded node claims a slot
    // smaller than its content and children overflow into neighbours.
    implicitWidth: content.implicitWidth + _padH * 2
    implicitHeight: content.implicitHeight + _padV * 2

    // Extension components opt into filling their layout slot by declaring
    // `property bool fillsLayout: true` on their root item — grow/frame can
    // never reach extension nodes (their properties map is the schema).
    readonly property bool contentFillsLayout:
        node !== null && node.extension &&
        content.item !== null && content.item.fillsLayout === true

    // Mirrors of the attached Layout fill flags — Layout.* cannot be read
    // through an object reference (item.Layout is undefined outside the
    // item), so parent containers inspect these instead.
    readonly property bool layoutFillWidth: Layout.fillWidth
    readonly property bool layoutFillHeight: Layout.fillHeight

    property real _w: Number(prop("width", 0))
    property real _h: Number(prop("height", 0))

    // Inside a Layout with fill flags the parent assigns the size — an
    // eager width/height binding would re-assert the implicit size (0 for
    // extension surfaces) and silently defeat the fill.
    Binding on width {
        when: view._w > 0 || !view.Layout.fillWidth
        value: view._w > 0 ? view._w : view.implicitWidth
    }
    Binding on height {
        when: view._h > 0 || !view.Layout.fillHeight
        value: view._h > 0 ? view._h : view.implicitHeight
    }

    Layout.preferredWidth: view._w > 0 ? view._w : view.implicitWidth
    Layout.preferredHeight: view._h > 0 ? view._h : view.implicitHeight
    Layout.fillWidth: Number(prop("grow", 0)) > 0 ||
                      prop("container-relative-frame", "") === "horizontal" ||
                      prop("container-relative-frame", "") === "both" ||
                      view.contentFillsLayout
    Layout.fillHeight: Number(prop("grow", 0)) > 0 ||
                       prop("container-relative-frame", "") === "vertical" ||
                       prop("container-relative-frame", "") === "both" ||
                       view.contentFillsLayout
    Layout.minimumWidth: Number(prop("min-width", 0))
    Layout.minimumHeight: Number(prop("min-height", 0))
    Layout.maximumWidth: Number(prop("max-width", 0)) > 0
                         ? Number(prop("max-width", 0)) : Infinity
    Layout.maximumHeight: Number(prop("max-height", 0)) > 0
                          ? Number(prop("max-height", 0)) : Infinity

    objectName: prop("accessibility-identifier", "") !== ""
                ? "lui-" + prop("accessibility-identifier", "")
                : (node ? "lui-node-" + node.nodeId : "lui-node")

    Accessible.role: Accessible.Client
    Accessible.name: prop("accessibility-label", "")

    Rectangle {
        id: backdrop
        anchors.fill: parent
        visible: color !== "transparent" || border.width > 0
        color: Style.nodeColor(view.node, view.prop("background", ""), "transparent")
        border.color: Style.nodeColor(view.node, view.prop("border-color", ""), "transparent")
        border.width: Number(view.prop("border-width", 0))
        radius: Number(view.prop("corner-radius", 0))
    }

    readonly property real _padAll: Number(prop("padding", 0))
    readonly property real _padH: Math.max(_padAll,
        Number(prop("padding-horizontal", 0)))
    readonly property real _padV: Math.max(_padAll,
        Number(prop("padding-vertical", 0)))

    Loader {
        id: content
        anchors {
            fill: parent
            leftMargin: view._padH
            rightMargin: view._padH
            topMargin: view._padV
            bottomMargin: view._padV
        }
        readonly property string componentUrl: view.node
            ? (view.node.extension
               ? String(view.node.componentSource)
               : view.componentFor(view.node.kind))
            : ""
        onComponentUrlChanged: reload()
        // setSource() always destroys and recreates the item; var-typed node
        // bindings refire onNodeChanged for the same object, so reloading
        // unconditionally would tear down the subtree (and input focus) on
        // every patch. Skip when the loaded item already serves this node.
        function reload() {
            if (!view.node || componentUrl === "") {
                if (source != "") setSource("")
                return
            }
            if (status === Loader.Ready && source == componentUrl &&
                item && item.node === view.node)
                return
            setSource(componentUrl, {"node": view.node})
        }
        onLoaded: {
            if ("anchorItem" in item)
                item.anchorItem = Qt.binding(function() { return view.overlayAnchor })
        }
    }

    // The same component URL can serve a different node object when a
    // delegate is reused; re-inject the node in that case.
    Connections {
        target: view
        function onNodeChanged() { content.reload() }
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
