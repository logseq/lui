// split-pane: a leaf pane — tab strip over the selected tab's content.
// Tabs drag to reorder within the strip, move to other panes, or drop on a
// pane edge to request a split. Pane-level shortcuts emit semantic events.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: pane
    required property var node

    property bool fillsLayout: true

    readonly property string paneId: String(node.prop("pane-id", ""))
    readonly property bool paneFocused: node.prop("focused", false) === true
    readonly property var tabNodes: node.children

    function tabIdOf(tabNode) {
        return String(tabNode.prop("tab-id", ""))
    }
    function selectedId() {
        var s = node.prop("selected", "")
        if (s !== "") return String(s)
        return tabNodes.length > 0 ? tabIdOf(tabNodes[0]) : ""
    }

    // Drop-zone state: "" | "center" | "left" | "right" | "top" | "bottom".
    property string dropZone: ""
    // Index within the tab strip where a dropped tab would insert; -1 = none.
    property int tabDropIndex: -1

    focusPolicy: Qt.ClickFocus
    onActiveFocusChanged:
        if (activeFocus) node.emitExtensionEvent("pane-focused", {})

    implicitWidth: 200
    implicitHeight: 150

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- tab strip ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            color: Qt.rgba(0.5, 0.5, 0.5, 0.12)

            Flickable {
                id: strip
                anchors.fill: parent
                contentWidth: stripRow.width
                contentHeight: height
                clip: true
                flickableDirection: Flickable.HorizontalFlick

                Row {
                    id: stripRow
                    height: strip.height
                    spacing: 0

                    Repeater {
                        model: pane.tabNodes
                        delegate: LuiSplitTabChip {
                            tabNode: modelData
                            index: model.index
                            paneItem: pane
                            selected: pane.tabIdOf(modelData) === pane.selectedId()
                        }
                    }

                    // Trailing insertion indicator.
                    Rectangle {
                        width: 2
                        height: 18
                        visible: pane.tabDropIndex === pane.tabNodes.length
                        color: "#4488ff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        // ---- content: every tab stays mounted; only selected is visible ----
        Item {
            id: contentArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            Repeater {
                model: pane.tabNodes
                delegate: LuiNodeView {
                    anchors.fill: contentArea
                    node: modelData
                    visible: pane.tabIdOf(modelData) === pane.selectedId()
                }
            }

            // Edge drop-zone highlight.
            Rectangle {
                visible: pane.dropZone !== ""
                color: "#4488ff"
                opacity: pane.dropZone === "center" ? 0.10 : 0.18
                x: pane.dropZone === "left" ? 0
                    : pane.dropZone === "right" ? parent.width - _extent
                    : 0
                y: pane.dropZone === "top" ? 0
                    : pane.dropZone === "bottom" ? parent.height - _extent
                    : 0
                width: pane.dropZone === "left" || pane.dropZone === "right"
                       ? _extent : parent.width
                height: pane.dropZone === "top" || pane.dropZone === "bottom"
                        ? _extent : parent.height
                readonly property real _extent:
                    Math.max(48, Math.min(160,
                        (pane.dropZone === "left" || pane.dropZone === "right"
                         ? parent.width : parent.height) * 0.35))
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }

            // Whole-pane drop target (body = center merge, edges = split).
            DropArea {
                anchors.fill: parent
                keys: ["lui-split-tab"]

                function zoneAt(pos) {
                    var ex = Math.min(Math.max(width * 0.25, 48), 160)
                    var ey = Math.min(Math.max(height * 0.25, 48), 160)
                    if (pos.x < ex) return "left"
                    if (pos.x > width - ex) return "right"
                    if (pos.y < ey) return "top"
                    if (pos.y > height - ey) return "bottom"
                    return "center"
                }

                onPositionChanged: function(drag) {
                    pane.dropZone = zoneAt(Qt.point(drag.x, drag.y))
                }
                onExited: pane.dropZone = ""
                onDropped: function(drop) {
                    var zone = pane.dropZone
                    pane.dropZone = ""
                    var payload = drop.source && drop.source.splitPayload
                                  ? drop.source.splitPayload : null
                    if (!payload) { drop.accepted = false; return }
                    if (zone === "center") {
                        pane.node.emitExtensionEvent("tab-moved", {
                            "tab": payload.tab,
                            "index": pane.tabNodes.length,
                            "from-pane": payload.pane
                        })
                    } else if (zone !== "") {
                        pane.node.emitExtensionEvent("split-drop", {
                            "tab": payload.tab,
                            "from-pane": payload.pane,
                            "edge": zone
                        })
                    }
                    drop.accept(Qt.MoveAction)
                }
            }
        }
    }

    // Focus ring.
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 2
        border.color: "#4488ff"
        opacity: pane.paneFocused ? 0.55 : 0
        radius: 4
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    // ---- pane-level keyboard commands ----
    Keys.onPressed: function(event) {
        var mod = event.modifiers
        var cmdOpt = (mod & Qt.ControlModifier) && (mod & Qt.AltModifier)
        var cmd = (mod & Qt.ControlModifier) && !(mod & Qt.AltModifier)
        var shift = (mod & Qt.ShiftModifier)
        if (cmdOpt && !shift) {
            var dir = ""
            if (event.key === Qt.Key_Left) dir = "left"
            else if (event.key === Qt.Key_Right) dir = "right"
            else if (event.key === Qt.Key_Up) dir = "up"
            else if (event.key === Qt.Key_Down) dir = "down"
            if (dir !== "") {
                pane.node.emitExtensionEvent("navigate", {"direction": dir})
                event.accepted = true
                return
            }
            if (event.key === Qt.Key_D) {
                pane.node.emitExtensionEvent("split-requested",
                                             {"orientation": "horizontal"})
                event.accepted = true
                return
            }
        }
        if (cmdOpt && shift && event.key === Qt.Key_D) {
            pane.node.emitExtensionEvent("split-requested",
                                         {"orientation": "vertical"})
            event.accepted = true
            return
        }
        if (cmd && event.key === Qt.Key_Backslash) {
            pane.node.emitExtensionEvent("split-requested",
                {"orientation": shift ? "vertical" : "horizontal"})
            event.accepted = true
            return
        }
        if (cmd && event.key === Qt.Key_W) {
            if (shift) {
                pane.node.emitExtensionEvent("pane-closed", {})
            } else {
                var sel = selectedId()
                if (sel !== "")
                    pane.node.emitExtensionEvent("tab-closed", {"tab": sel})
            }
            event.accepted = true
            return
        }
        event.accepted = false
    }
}
