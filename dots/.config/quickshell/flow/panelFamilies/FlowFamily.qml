import QtQuick
import Quickshell
import qs
import qs.services

import qs.modules.common
import qs.modules.flow.background
import qs.modules.flow.bar
import qs.modules.flow.bluetoothConnectionPopup
import qs.modules.flow.cheatsheet
import qs.modules.flow.dock
import qs.modules.flow.lock
import qs.modules.flow.mediaControls
import qs.modules.flow.notificationPopup
import qs.modules.flow.onScreenDisplay
import qs.modules.flow.onScreenDisplay.minimalist
import qs.modules.flow.onScreenKeyboard
import qs.modules.flow.oledSaver
import qs.modules.flow.overview
import qs.modules.flow.polkit
import qs.modules.flow.regionSelector
import qs.modules.flow.screenCorners
import qs.modules.flow.screenTranslator
import qs.modules.flow.sessionScreen
import qs.modules.flow.sidebarPolicies
import qs.modules.flow.sidebarDashboard
import qs.modules.flow.overlay
import qs.modules.flow.verticalBar
import qs.modules.flow.wallpaperSelector
import qs.modules.flow.wrappedFrame
import qs.modules.flow.colorPickerPopup
import qs.modules.flow.videoEditor
import qs.modules.flow.localSendPopup
import qs.modules.flow.scratchpadOverlay
import qs.modules.flow.keyboardLayoutTransitionPopup
import qs.modules.flow.topLayer
import qs.modules.flow.tilingAssistant
import qs.modules.flow.usage
import qs.modules.flow.alarmRingingPopup
import qs.modules.flow.screenshotOverlay
import qs.modules.flow.dynamicIsland

Scope {
    property bool barExtraCondition: true
    readonly property bool usingWrappedFrame: Config.options.appearance.fakeScreenRounding === 3 && !(Config.options.bar.cornerStyle === 3 && !Config.options.bar.vertical)
    readonly property bool barBot: Config.options.bar.bottom
    readonly property bool barVert: Config.options.bar.vertical

    Component.onCompleted: Qt.callLater(() => updateBarExtraCondition())
    onUsingWrappedFrameChanged: updateBarExtraCondition()
    onBarBotChanged: updateBarExtraCondition()
    onBarVertChanged: updateBarExtraCondition()

    function updateBarExtraCondition() {
        if (!usingWrappedFrame)
            return;
        barExtraCondition = false;
        Qt.callLater(() => barExtraCondition = true);
    }

    PanelLoader {
        extraCondition: Config.options.background.enable
        component: Background {}
    }
    PanelLoader {
        extraCondition: !Config.options.bar.vertical && barExtraCondition && !GlobalStates.connectModeActive
        component: Bar {}
    }
    PanelLoader {
        component: Cheatsheet {}
    }
    PanelLoader {
        extraCondition: Config.options.appStats.overlayEnabled
        component: Usage {}
    }
    PanelLoader {
        extraCondition: Config.options.dock.enable
        component: Dock {}
    }
    PanelLoader {
        component: Lock {}
    }
    PanelLoader {
        component: MediaControls {}
    }
    PanelLoader {
        // The Scope must stay loaded so the onDeviceConnected trigger inside
        // BluetoothConnectionPopup.qml is alive; the inner LazyLoader gates the
        // actual PanelWindow on GlobalStates.bluetoothConnectionPopupOpen.
        // (df1e26966 gated this PanelLoader on the same flag, creating a
        // chicken-and-egg that prevented the popup from ever appearing.)
        extraCondition: Config.ready && !Config.options.bar.floatingNotch.enable
        component: BluetoothConnectionPopup {}
    }
    PanelLoader {
        extraCondition: Config.ready && !Config.options.bar.floatingNotch.enable
        component: KeyboardLayoutTransitionPopup {}
    }
    PanelLoader {
        extraCondition: Config.ready && !Config.options.bar.floatingNotch.enable && GlobalStates.localSendPopupOpen
        component: LocalSendPopup {}
    }
    PanelLoader {
        extraCondition: !(Config.ready
                && (Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar)
                && !Config.options.bar.floatingNotch.disableNotification)
        component: NotificationPopup {}
    }
    PanelLoader {
        extraCondition: !(Config.ready && Config.options.osd.style === "minimalist")
        component: OnScreenDisplay {}
    }
    PanelLoader {
        extraCondition: Config.ready && Config.options.osd.style === "minimalist"
        component: MinimalistOsd {}
    }
    PanelLoader {
        component: OnScreenKeyboard {}
    }
    PanelLoader {
        component: OledSaver {}
    }
    PanelLoader {
        component: Overlay {}
    }
    PanelLoader {
        component: Overview {}
    }
    // GNOME-like window scale-out during overview (OverviewWindowTransition).
    // Scope com Variants/PanelWindows próprios — instancia direto.
    // featureEnabled interno (zoomOutEnabled + windowZoomOnOverview + zoomOutStyle===0)
    // controla auto-disable. TopLayerPanel em WlrLayer.Overlay sempre fica acima
    // deste (WlrLayer.Top) — sem conflito de z-order em qualquer modo.
    OverviewWindowTransition {}
    PanelLoader {
        component: Polkit {}
    }
    PanelLoader {
        component: RegionSelector {}
    }
    PanelLoader {
        component: ScreenCorners {}
    }
    PanelLoader {
        component: ScreenTranslator {}
    }
    PanelLoader {
        component: ColorPickerPopup {}
    }
    PanelLoader {
        component: SessionScreen {}
    }
    PanelLoader {
        extraCondition: !GlobalStates.connectModeActive || GlobalStates.connectSidebarsSeparate
        component: SidebarPolicies {}
    }
    PanelLoader {
        extraCondition: !GlobalStates.connectModeActive || GlobalStates.connectSidebarsSeparate
        component: SidebarDashboard {}
    }
    PanelLoader {
        extraCondition: Config.options.bar.vertical && barExtraCondition && !GlobalStates.connectModeActive
        component: VerticalBar {}
    }
    PanelLoader {
        component: WallpaperSelector {}
    }
    PanelLoader {
        component: WrappedFrame {}
    }
    PanelLoader {
        extraCondition: GlobalStates.videoEditorPopupOpen
        component: VideoEditorPopup {}
    }
    PanelLoader {
        extraCondition: GlobalStates.videoEditorOpen
        component: VideoEditor {}
    }
    PanelLoader {
        component: ScratchpadOverlay {}
    }
    PanelLoader {
        extraCondition: AlarmService.ringingAlarmIndex !== -1 && Config.options.time.alarms.useFullscreenPopup
        component: AlarmRingingPopup {}
    }
    PanelLoader {
        extraCondition: GlobalStates.screenshotOverlayOpen
        component: ScreenshotOverlay {}
    }
    PanelLoader {
        extraCondition: Config.options.tiling.enable
        component: TilingOverlay {}
    }
    PanelLoader {
        extraCondition: Config.options.tiling.enable
        component: LayoutHint {}
    }
    PanelLoader {
        extraCondition: Config.options.tiling.enable && Config.options.tiling.overlay.stackIndicator
        component: TilingStackBadges {}
    }
    PanelLoader {
        extraCondition: GlobalStates.connectModeActive
        component: TopLayer {}
    }
    PanelLoader {
        extraCondition: Config.ready && (Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar)
        Component.onCompleted: {
            console.log("[IllogicalImpulseFamily] DynamicIsland PanelLoader - Config.ready:", Config.ready, "floatingNotch.enable:", Config.options.bar.floatingNotch.enable, "centerInBar:", Config.options.bar.floatingNotch.centerInBar);
        }
        component: DynamicIsland {}
    }
}
