import QtQuick
import QtQuick.Controls
import QtQml
import "LuiStyle.js" as Style

// Wire kind: tooltip — with an anchor (inside a stack) it configures the
// stock ToolTip on the anchor so the platform shows it on hover/focus;
// without an anchor it renders inline as a static status label.
Item {
    id: tip
    required property var node
    property Item anchorItem: null
    readonly property var props: node ? node.properties : ({})

    function arm() {
        var a = tip.anchorItem
        if (!a || !a.ToolTip) return
        a.ToolTip.text = Style.str(tip.props, "text", "")
        var delay = Number(tip.props["tooltip-delay"] || 0)
        if (delay > 0) a.ToolTip.delay = delay
        a.ToolTip.visible = Qt.binding(function() {
            return (a.hovered === true) || (a.activeFocus === true)
        })
    }
    onAnchorItemChanged: arm()
    Component.onCompleted: arm()

    // Anchored tips are pure overlays (zero slot); unanchored tips render
    // inline as a label, so they must claim space instead of drawing over
    // neighbouring siblings.
    implicitWidth: tip.anchorItem ? 0 : bubble.implicitWidth
    implicitHeight: tip.anchorItem ? 0 : bubble.implicitHeight

    Rectangle {
        id: bubble
        visible: !tip.anchorItem
        implicitWidth: label.implicitWidth + 16
        implicitHeight: label.implicitHeight + 10
        radius: 6
        color: tip.palette.toolTipBase

        Text {
            id: label
            anchors.centerIn: parent
            text: Style.str(tip.props, "text", "")
            color: tip.palette.toolTipText
            font.pixelSize: 12
        }
    }
}
