import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.modules.waffle.notificationCenter

Scope {
    id: notificationPopup

    PanelWindow {
        id: root
        visible: (Notifications.popupList.length > 0) && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null

        property string position: Config.options.notifications.position ?? "top_right"
        property bool isTop: position.startsWith("top")
        property bool isBottom: position.startsWith("bottom")
        property bool isLeft: position.endsWith("left")
        property bool isRight: position.endsWith("right")

        WlrLayershell.namespace: "quickshell:notificationPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        mask: Region {
            item: listview
        }

        color: "transparent"

        WListView {
            id: listview
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 16
            anchors.bottomMargin: 16

            height: Math.min(contentItem.height + anchors.topMargin + anchors.bottomMargin, parent.height)
            width: 396
            spacing: 12

            verticalLayoutDirection: root.isBottom ? ListView.BottomToTop : ListView.TopToBottom

            states: [
                State {
                    name: "top_left"
                    when: root.position === "top_left"
                    AnchorChanges {
                        target: listview
                        anchors.left: parent.left
                        anchors.right: undefined
                        anchors.horizontalCenter: undefined
                        anchors.top: parent.top
                        anchors.bottom: undefined
                    }
                },
                State {
                    name: "top"
                    when: root.position === "top"
                    AnchorChanges {
                        target: listview
                        anchors.left: undefined
                        anchors.right: undefined
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.bottom: undefined
                    }
                },
                State {
                    name: "top_right"
                    when: root.position === "top_right"
                    AnchorChanges {
                        target: listview
                        anchors.left: undefined
                        anchors.right: parent.right
                        anchors.horizontalCenter: undefined
                        anchors.top: parent.top
                        anchors.bottom: undefined
                    }
                },
                State {
                    name: "bottom_left"
                    when: root.position === "bottom_left"
                    AnchorChanges {
                        target: listview
                        anchors.left: parent.left
                        anchors.right: undefined
                        anchors.horizontalCenter: undefined
                        anchors.top: undefined
                        anchors.bottom: parent.bottom
                    }
                },
                State {
                    name: "bottom"
                    when: root.position === "bottom"
                    AnchorChanges {
                        target: listview
                        anchors.left: undefined
                        anchors.right: undefined
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: undefined
                        anchors.bottom: parent.bottom
                    }
                },
                State {
                    name: "bottom_right"
                    when: root.position === "bottom_right"
                    AnchorChanges {
                        target: listview
                        anchors.left: undefined
                        anchors.right: parent.right
                        anchors.horizontalCenter: undefined
                        anchors.top: undefined
                        anchors.bottom: parent.bottom
                    }
                }
            ]

            model: ScriptModel {
                values: Notifications.popupList
            }
            delegate: WSingleNotification {
                required property var modelData
                notification: modelData
                width: ListView.view.width - ListView.view.leftMargin - ListView.view.rightMargin
            }
        }
    }
}
