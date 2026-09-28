import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: sheet — bottom-sheet modal surface.
Item {
    id: host
    required property var node
    readonly property var props: node ? node.properties : ({})

    implicitWidth: 0
    implicitHeight: 0

    // detents prop: comma-separated medium|large|fraction — the sheet opens
    // at the first detent and caps at the largest (fractions of the overlay
    // height). sizing prop: form|fitted narrow the sheet to a centered
    // column; page keeps full width.
    readonly property var detentFractions: {
        var raw = props["detents"];
        if (raw === undefined || raw === null || raw === "") return null;
        var parts = String(raw).split(",");
        var out = [];
        for (var i = 0; i < parts.length; i++) {
            var token = parts[i].trim();
            var fraction = token === "medium" ? 0.5
                : token === "large" ? 1.0
                : parseFloat(token);
            if (fraction > 0 && fraction <= 1) out.push(fraction);
        }
        return out.length > 0 ? out : null;
    }
    readonly property real detentRest:
        detentFractions ? detentFractions[0] : 0.9
    readonly property bool sizingNarrow:
        Style.str(props, "sizing", "") !== "" &&
        Style.str(props, "sizing", "") !== "page"

    Drawer {
        id: sheet
        edge: Qt.BottomEdge
        modal: true
        interactive: true
        width: host.sizingNarrow && Overlay.overlay
            ? Math.min(560, Overlay.overlay.width)
            : Overlay.overlay ? Overlay.overlay.width : parent.width
        x: host.sizingNarrow && Overlay.overlay
            ? Math.round((Overlay.overlay.width - width) / 2) : 0
        height: host.detentFractions && Overlay.overlay
            ? Overlay.overlay.height * host.detentRest
            : Math.min(contentColumn.implicitHeight + 32,
                Overlay.overlay ? Overlay.overlay.height * 0.9 : 400)
        onClosed: if (host.node) host.node.dismiss()

        ColumnLayout {
            id: contentColumn
            width: sheet.width
            spacing: 8

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 8
                width: 36
                height: 4
                radius: 2
                color: sheet.palette.mid
            }

            Text {
                visible: Style.str(host.props, "text", "") !== ""
                text: Style.str(host.props, "text", "")
                color: sheet.palette.text
                font.pixelSize: 16
                font.weight: Font.DemiBold
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
            }

            Repeater {
                model: host.node ? host.node.children : []
                delegate: LuiNodeView {
            required property var modelData
                    node: modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                }
            }

            Item { implicitHeight: 16 }
        }


    }

    Component.onCompleted: sheet.open()
}
