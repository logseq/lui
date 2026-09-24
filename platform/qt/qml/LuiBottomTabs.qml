import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: bottom-tabs — content plus a bottom navigation bar of
// bottom-tab children; the selected child fills the body.
ColumnLayout {
    id: tabs
    required property var node
    readonly property var props: node ? node.properties : ({})

    SystemPalette { id: tabsPal }
    spacing: 0
    readonly property var pages: node ? node.children : []
    readonly property int selectedIndex: {
        var kids = pages
        for (var i = 0; i < kids.length; ++i) {
            if (kids[i] && kids[i].properties["selected"] === true) return i
        }
        return 0
    }

    StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: tabs.selectedIndex

        Repeater {
            model: tabs.pages
            delegate: LuiNodeView {
                required property var modelData
                node: modelData
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 56
        color: tabsPal.window
        border.color: tabsPal.mid
        border.width: 1

        RowLayout {
            anchors.fill: parent
            spacing: 0

            Repeater {
                model: tabs.pages
                delegate: Item {
                    required property int index
                    required property var modelData
                    readonly property var tabProps:
                        modelData && modelData.properties
                        ? modelData.properties : ({})
                    readonly property bool selected:
                        index === tabs.selectedIndex
                    readonly property bool tabEnabled:
                        tabProps["enabled"] !== false

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        Image {
                            source: Style.iconSource(
                                Style.str(parent.parent.tabProps, "icon", ""))
                            visible: source !== ""
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            Layout.alignment: Qt.AlignHCenter
                            opacity: parent.parent.selected ? 1 : 0.6
                        }
                        Text {
                            text: Style.str(parent.parent.tabProps, "title", "")
                            color: parent.parent.selected ? tabsPal.highlight : tabsPal.mid
                            font.pixelSize: 11
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: parent.tabEnabled && !parent.selected
                        onClicked: parent.modelData.press()
                    }
                }
            }
        }
    }
}
