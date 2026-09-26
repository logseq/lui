// split-branch: binary interior node. Lays out its two children along
// `orientation` ("horizontal" = side by side, "vertical" = stacked) split by
// `ratio` (0..1 share for the first child). Divider drags animate nothing;
// external ratio changes spring-animate.
import QtQuick
import QtQuick.Layouts

Item {
    id: branch
    required property var node

    property bool fillsLayout: true

    readonly property bool horizontal:
        node.prop("orientation", "horizontal") !== "vertical"
    readonly property real sourceRatio: {
        // `0` is a valid ratio — only fall back when the prop is absent.
        var value = Number(node.prop("ratio", 0.5))
        if (!isFinite(value)) value = 0.5
        return Math.min(1, Math.max(0, value))
    }

    // Local ratio: follows user drags instantly; reconciles to sourceRatio
    // when the app moves it.
    property real ratio: sourceRatio
    onSourceRatioChanged: {
        if (!divider.dragging && Math.abs(sourceRatio - ratio) > 0.000001)
            ratio = sourceRatio
    }

    readonly property real thickness: _splitViewNumber("divider-thickness", 9)
    readonly property bool animate: _splitViewBool("animation", true)

    function _splitViewProp(name, fallback) {
        var n = node
        while (n) {
            if (n.identifier === "split-view") return n.prop(name, fallback)
            n = n.parent
        }
        return fallback
    }
    function _splitViewNumber(name, fallback) {
        return Math.max(1, Number(_splitViewProp(name, fallback)))
    }
    function _splitViewBool(name, fallback) {
        return _splitViewProp(name, fallback) === true
    }

    readonly property real available: Math.max(
        (horizontal ? width : height) - thickness, 0)
    readonly property real firstLength: available * ratio

    implicitWidth: 100
    implicitHeight: 100

    Behavior on firstLength {
        enabled: branch.animate && !divider.dragging
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    // First child: leading edge to divider.
    LuiNodeView {
        node: branch.node && branch.node.children.length > 0
              ? branch.node.children[0] : null
        x: 0; y: 0
        width: branch.horizontal ? branch.firstLength : branch.width
        height: branch.horizontal ? branch.height : branch.firstLength
    }

    // Second child: divider to trailing edge.
    LuiNodeView {
        node: branch.node && branch.node.children.length > 1
              ? branch.node.children[1] : null
        x: branch.horizontal ? branch.firstLength + branch.thickness : 0
        y: branch.horizontal ? 0 : branch.firstLength + branch.thickness
        width: branch.horizontal
               ? Math.max(branch.width - branch.firstLength - branch.thickness, 0)
               : branch.width
        height: branch.horizontal
                ? branch.height
                : Math.max(branch.height - branch.firstLength - branch.thickness, 0)
    }

    // Divider: thin visible line inside a wider hit target.
    Item {
        id: divider
        property bool dragging: false
        x: branch.horizontal ? branch.firstLength : 0
        y: branch.horizontal ? 0 : branch.firstLength
        width: branch.horizontal ? branch.thickness : branch.width
        height: branch.horizontal ? branch.height : branch.thickness

        Rectangle {
            anchors.centerIn: parent
            width: branch.horizontal ? 1 : parent.width
            height: branch.horizontal ? parent.height : 1
            color: Qt.rgba(0.5, 0.5, 0.5, 0.5)
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: branch.horizontal ? Qt.SizeHorCursor
                                           : Qt.SizeVerCursor
            hoverEnabled: true
            property real startRatio: 0
            property real grab: 0
            onPressed: function(mouse) {
                divider.dragging = true
                startRatio = branch.ratio
                // Measure in the branch's frame: the divider itself moves.
                var point = mapToItem(branch, mouse.x, mouse.y)
                grab = branch.horizontal ? point.x : point.y
                mouse.accepted = true
            }
            onPositionChanged: function(mouse) {
                if (!divider.dragging || branch.available <= 0) return
                var point = mapToItem(branch, mouse.x, mouse.y)
                var delta = (branch.horizontal ? point.x : point.y) - grab
                branch.ratio = Math.min(1, Math.max(0,
                    startRatio + delta / branch.available))
            }
            onReleased: function(mouse) {
                if (!divider.dragging) return
                divider.dragging = false
                branch.node.emitExtensionEvent("ratio-changed",
                                               {"ratio": branch.ratio})
            }
        }

        // Keyboard access: arrows nudge the divider by 5%.
        Keys.onLeftPressed: if (branch.horizontal) branch.nudge(-0.05)
        Keys.onRightPressed: if (branch.horizontal) branch.nudge(0.05)
        Keys.onUpPressed: if (!branch.horizontal) branch.nudge(-0.05)
        Keys.onDownPressed: if (!branch.horizontal) branch.nudge(0.05)
        focusPolicy: Qt.TabFocus
    }

    function nudge(delta) {
        ratio = Math.min(1, Math.max(0, ratio + delta))
        node.emitExtensionEvent("ratio-changed", {"ratio": ratio})
    }
}
