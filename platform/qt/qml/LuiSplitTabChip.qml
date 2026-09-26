// One tab chip inside a split-pane's tab strip. Draggable (reorder within
// the strip, move to another pane, or drop on a pane edge to split) and
// itself a drop target for insertion before/after its index.
import QtQuick
import QtQuick.Controls

Item {
    id: chip
    required property var tabNode
    required property int index
    required property var paneItem
    required property bool selected

    readonly property string tabId: String(tabNode.prop("tab-id", ""))
    readonly property string title:
        String(tabNode.prop("title", tabId))
    readonly property bool dirty: tabNode.prop("dirty", false) === true
    readonly property bool closable:
        tabNode.prop("closable", true) !== false

    // Payload read by drop targets (drag.source.splitPayload).
    readonly property var splitPayload: ({ "tab": tabId, "pane": paneItem.paneId })

    width: chipRow.width
    height: 30
    opacity: dragArea.active ? 0.6 : 1.0

    Drag.active: dragArea.active
    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.MoveAction
    Drag.keys: ["lui-split-tab"]
    Drag.source: chip
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: height / 2

    Row {
        id: chipRow
        height: chip.height
        spacing: 4
        leftPadding: 10
        rightPadding: 10

        Rectangle {
            visible: chip.dirty
            width: 5; height: 5; radius: 2.5
            color: "#888888"
            anchors.verticalCenter: parent.verticalCenter
        }

        Label {
            text: chip.title
            font.pixelSize: 12
            color: chip.selected ? "#dddddd" : "#999999"
            elide: Text.ElideRight
            maximumLineCount: 1
            anchors.verticalCenter: parent.verticalCenter
        }

        Label {
            visible: chip.closable
            text: "×"
            font.pixelSize: 13
            color: "#999999"
            anchors.verticalCenter: parent.verticalCenter
            MouseArea {
                anchors.fill: parent
                onClicked: chip.paneItem.node.emitExtensionEvent(
                    "tab-closed", {"tab": chip.tabId})
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: chip.selected ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
    }

    // Leading insertion indicator for drops on this chip.
    Rectangle {
        width: 2
        height: 18
        visible: paneItem.tabDropIndex === chip.index
        color: "#4488ff"
        anchors.verticalCenter: parent.verticalCenter
    }

    TapHandler {
        onTapped: {
            chip.paneItem.node.emitExtensionEvent(
                "tab-selected", {"tab": chip.tabId})
            chip.paneItem.node.emitExtensionEvent("pane-focused", {})
        }
    }

    DragHandler {
        id: dragArea
        target: null  // drag via the Drag attached props; we don't move the chip
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        // Default take-over lets the drag win once the pointer passes the
        // drag threshold, releasing TapHandler for plain clicks.
    }

    DropArea {
        anchors.fill: parent
        keys: ["lui-split-tab"]
        onPositionChanged: function(drag) {
            // Left/right halves pick before/after this index.
            paneItem.tabDropIndex =
                drag.x < width / 2 ? chip.index : chip.index + 1
            paneItem.dropZone = ""
        }
        onExited:
            if (paneItem.tabDropIndex === chip.index ||
                paneItem.tabDropIndex === chip.index + 1)
                paneItem.tabDropIndex = -1
        onDropped: function(drop) {
            var target = paneItem.tabDropIndex
            paneItem.tabDropIndex = -1
            var payload = drop.source && drop.source.splitPayload
                          ? drop.source.splitPayload : null
            if (!payload) { drop.accepted = false; return }
            paneItem.node.emitExtensionEvent("tab-moved", {
                "tab": payload.tab,
                "index": target < 0 ? chip.index : target,
                "from-pane": payload.pane
            })
            drop.accept(Qt.MoveAction)
        }
    }
}
