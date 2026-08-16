pragma ComponentBehavior: Bound

import QtQuick
import qs
import Quickshell
import qs.modules.flow.background.widgets
import qs.modules.flow.background.compositor

Scope {
    id: backgroundScope

    WidgetStateManager {
        id: widgetState
    }

    readonly property alias widgetSyncVersion: widgetState.syncVersion
    readonly property alias widgetStateManager: widgetState

    Timer {
        id: secondaryWindowsTimer
        interval: 500
        repeat: false
        running: true
        onTriggered: secondaryWindowsLoader.active = true
    }

    Loader {
        id: secondaryWindowsLoader
        active: false

        sourceComponent: Item {
            Variants {
                id: widgetsVariant
                model: Quickshell.screens

                BackgroundWidgetsWindow {
                    widgetStateManager: widgetState
                }
            }

            Variants {
                id: blurOverlayVariant
                model: Quickshell.screens

                BlurOverlayWindow {}
            }
        }
    }

    Variants {
        id: root
        model: Quickshell.screens

        BackgroundRoot {
            widgetStateManager: widgetState
        }
    }
}
