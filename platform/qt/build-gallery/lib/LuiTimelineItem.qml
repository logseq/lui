import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: timeline-item — marker + connector + title/description/meta;
// pressable when press-enabled.
Rectangle {
    id: item
    required property var node
    readonly property var props: node ? node.properties : ({})

    readonly property bool pressable: props["press-enabled"] === true
    readonly property bool connector: props["connector"] !== false
    readonly property color markerColor:
        Style.str(props, "variant", "") === "primary" ? "#007aff"
        : Style.str(props, "variant", "") === "destructive" ? "#dc2626"
        : "#a1a1aa"

    implicitHeight: body.implicitHeight + 16
    implicitWidth: body.implicitWidth + 16
    radius: 8
    color: props["selected"] === true ? "#f4f4f5" : "transparent"

    RowLayout {
        id: body
        anchors {
            fill: parent
            margins: 8
        }
        spacing: 10

        ColumnLayout {
            spacing: 0
            Layout.preferredWidth: 24
            Layout.alignment: Qt.AlignTop

            Item {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24

                Image {
                    anchors.centerIn: parent
                    visible: Style.str(item.props, "icon", "") !== ""
                    source: Style.iconSource(Style.str(item.props, "icon", ""))
                    width: 16
                    height: 16
                }
                Text {
                    anchors.centerIn: parent
                    visible: Style.str(item.props, "icon", "") === "" &&
                             Style.str(item.props, "indicator", "") !== ""
                    text: Style.str(item.props, "indicator", "")
                    color: item.markerColor
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                Rectangle {
                    anchors.centerIn: parent
                    visible: Style.str(item.props, "icon", "") === "" &&
                             Style.str(item.props, "indicator", "") === ""
                    width: 10
                    height: 10
                    radius: 5
                    color: item.markerColor
                }
            }

            Rectangle {
                visible: item.connector
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                width: 1
                color: "#e4e4e7"
            }
        }

        ColumnLayout {
            spacing: 2
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop

            Text {
                text: Style.str(item.props, "title", "")
                color: "#18181b"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }
            Text {
                visible: Style.str(item.props, "description", "") !== ""
                text: Style.str(item.props, "description", "")
                color: "#71717a"
                font.pixelSize: 13
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
            Text {
                visible: Style.str(item.props, "meta", "") !== ""
                text: Style.str(item.props, "meta", "")
                color: "#71717a"
                font.pixelSize: 12
                Layout.fillWidth: true
            }
        }

        Image {
            visible: item.pressable
            source: "icons/chevron-right.svg"
            Layout.preferredWidth: 18
            Layout.preferredHeight: 18
            Layout.alignment: Qt.AlignVCenter
        }
    }

    MouseArea {
        anchors.fill: parent
        visible: item.pressable && item.props["enabled"] !== false
        onClicked: item.node.press()
    }
}
