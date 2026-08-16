pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.waffle.looks

// TODO: Swipe to dismiss
MouseArea {
    id: root

    required property var notificationGroup
    readonly property var notifications: notificationGroup?.notifications ?? []
    property bool expanded: false
    property var draggedItem: contentLayout

    implicitWidth: contentLayout.implicitWidth
    implicitHeight: contentLayout.implicitHeight

    function dismissAll(left = undefined) {
        if (left === undefined) {
            const pos = Config?.options.notifications.position ?? "top_right";
            if (pos.endsWith("left")) left = true;
            else if (pos.endsWith("right")) left = false;
            else left = contentLayout.x < 0;
        }
        removeAnimation.left = left;

        root.notifications.forEach(notif => {
            Qt.callLater(() => {
                Notifications.discardNotification(notif.notificationId);
            });
        });
        contentLayout.opacity = contentLayout.opacity; // Break binding
        removeAnimation.start();
    }

    WNotificationDismissAnim {
        id: removeAnimation
        target: root
    }

    property real dragDismissThreshold: 100
    drag {
        axis: Drag.XAxis
        target: contentLayout
        minimumX: (Config?.options.notifications.position ?? "top_right").endsWith("left") ? 0 : -Infinity
        maximumX: (Config?.options.notifications.position ?? "top_right").endsWith("right") ? 0 : Infinity
        onActiveChanged: {
            if (drag.active)
                return;
            
            const threshold = root.dragDismissThreshold;
            const value = contentLayout.x;
            
            if (Math.abs(value) > threshold) {
                root.dismissAll(value < 0);
            } else {
                contentLayout.x = 0;
            }
        }
    }

    ColumnLayout {
        id: contentLayout
        spacing: 4
        width: root.width

        opacity: {
            if (!root.drag.active) return 1.0;
            var u = root.width > 0 ? Math.min(1.0, Math.abs(contentLayout.x) / root.width) : 0.0;
            return (1.0 - u * u * u) * (1.0 - u * u * u);
        }
        Behavior on opacity {
            enabled: !root.drag.active
            NumberAnimation {
                duration: 250
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Looks.transition.easing.bezierCurve.easeIn
            }
        }

        Behavior on x {
            animation: Looks.transition.enter.createObject(this)
        }

        GroupHeader {
            id: notifHeader
            Layout.fillWidth: true
            Layout.margins: 11
        }

        WListView {
            Layout.leftMargin: -Math.min(35, contentLayout.x)
            Layout.rightMargin: -Layout.leftMargin
            Layout.fillWidth: true
            implicitWidth: notifHeader.implicitWidth
            implicitHeight: contentHeight
            interactive: false
            spacing: 4
            model: ScriptModel {
                values: root.expanded ? root.notifications.slice().reverse() : root.notifications.slice(-1)
                objectProp: "notificationId"
            }
            delegate: WSingleNotification {
                id: singleNotif
                required property int index
                required property var modelData

                width: ListView.view.width
                notification: modelData

                groupExpandControlMessage: {
                    if (root.notifications.length <= 1)
                        return "";
                    if (!root.expanded)
                        return Translation.tr("+%1 notifications").arg(root.notifications.length - 1);
                    if (index === root.notifications.length - 1)
                        return Translation.tr("See fewer");
                    return "";
                }
                onGroupExpandToggle: {
                    root.expanded = !root.expanded;
                }
            }
        }
    }

    component GroupHeader: MouseArea {
        id: headerMouseArea
        hoverEnabled: true
        acceptedButtons: Qt.NoButton

        implicitWidth: appHeader.implicitWidth
        implicitHeight: appHeader.implicitHeight

        RowLayout {
            id: appHeader
            anchors.fill: parent
            spacing: 7

            WNotificationAppIcon {
                Layout.alignment: Qt.AlignVCenter
                icon: root.notificationGroup?.appIcon ?? ""
            }

            WText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignLeft
                elide: Text.ElideRight
                text: root.notificationGroup?.appName ?? ""
            }

            // NotificationHeaderButton { // TODO: More notification functionality needed so we can have this button
            //     visible: headerMouseArea.containsMouse
            //     Layout.leftMargin: 25
            //     Layout.rightMargin: 25
            //     icon.name: "more-horizontal"
            // }

            NotificationHeaderButton {
                visible: headerMouseArea.containsMouse
                Layout.rightMargin: 3
                icon.name: "dismiss"
                onClicked: {
                    root.dismissAll();
                }
            }
        }
    }
}
