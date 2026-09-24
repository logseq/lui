import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: stack — z-ordered overlapping children. Overlay kinds
// (dropdown-menu, tooltip) anchor to the preceding sibling.
Item {
    id: stack
    required property var node
    readonly property var props: node ? node.properties : ({})

    // Size to the largest non-overlay child's intrinsic size. childrenRect
    // must not be used here: delegate width/height bind to stack.width/
    // height, so childrenRect would feed implicit size back through the
    // delegates' actual sizes and spin a layout loop.
    implicitWidth: rep.maxChildImplicitWidth
    implicitHeight: rep.maxChildImplicitHeight

    Repeater {
        id: rep
        readonly property real maxChildImplicitWidth: _maxChildImplicit(true)
        readonly property real maxChildImplicitHeight: _maxChildImplicit(false)
        function _maxChildImplicit(horizontal) {
            var m = 0
            for (var i = 0; i < count; ++i) {
                var c = itemAt(i)
                if (!c || c._overlay) continue
                var v = horizontal ? c.implicitWidth : c.implicitHeight
                if (v > m) m = v
            }
            return m
        }

        model: stack.node ? stack.node.children : []
        delegate: LuiNodeView {
            required property var modelData
            node: modelData
            // Overlay kinds (dropdown-menu, context-menu, tooltip) present
            // through their own Popup/ToolTip — they stay visible so the
            // overlay component can show, but take no in-stack space.
            readonly property bool _overlay: {
                var k = node ? node.kind : ""
                return k === "dropdown-menu" || k === "context-menu" ||
                       k === "tooltip"
            }
            width: _overlay ? 0 : stack.width
            height: _overlay ? 0 : stack.height
        }
        onItemAdded: function(index, item) {
            item.overlayAnchor = index > 0 ? rep.itemAt(index - 1) : stack
        }
    }
}
