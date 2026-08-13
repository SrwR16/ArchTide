//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Remove two slashes below and adjust the value to change the UI scale
////@ pragma Env QT_SCALE_FACTOR=1

import "modules/common"
import "services"
import "panelFamilies"

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root
    property string openRgbApplyScript: Quickshell.shellPath("scripts/colors/openRGB/apply_openrgb.py")
    property bool openRgbStartupApplied: false

    // Stuff for every panel family
    ReloadPopup {}

    // Only what must be in place before the first paint. Everything else is
    // staged in startStagedServices(), which is anchored to Config.ready so the
    // config-gated touches below read the user's real config.json rather than
    // the JsonAdapter's QML defaults (which is what a plain Component.onCompleted
    // would still be holding while the config file loads asynchronously).
    Component.onCompleted: {
        if (Qt.application) {
            Qt.application.applicationName = "quickshell";
            Qt.application.organizationName = "Unknown Organization";
            Qt.application.organizationDomain = "unknown.organization";
        }
        MaterialThemeLoader.reapplyTheme();
    }

    // ── Staged background service startup ───────────────────────────────────
    // The desktop only appears once Config.ready (PanelFamilyLoader gates on
    // it), so the stages are measured from config-readiness, not process start.
    // Stages only instantiate the optional singletons their config flags ask
    // for: a disabled service stays uninstantiated (zero timers, zero
    // processes, zero memory) instead of merely idling internally.
    property bool _stagesStarted: false

    function startStagedServices() {
        if (root._stagesStarted)
            return;
        root._stagesStarted = true;
        stageTheme.start();
        stageAudio.start();
        stageMedia.start();
        stageOptional.start();
        stageAnalytics.start();
    }

    function loadThemeStage() {
        Hyprsunset.load();
        Wallpapers.load();
        if (Config.options?.tiling?.enable)
            TilingAssistant.enabled; // Watches for window drags; disabled stays dormant
        if (Config.options?.light?.darkMode?.automatic)
            DarkModeService.automatic; // Boot resets the automatic flag by design
    }

    function loadAudioStage() {
        SoundService.indexReady; // Scans sound themes, plays login sound if enabled
        Cliphist.refresh();
        ConflictKiller.load();
    }

    function loadMediaStage() {
        if (Config.options?.background?.mediaMode?.musicVideo?.enable)
            VideoColorSampler.active; // Samples video frames for dynamic colors
        FirstRunExperience.load();
        root.applyOpenRgbIfEnabled();
    }

    function loadOptionalStage() {
        Updates.load();
        ChangelogService.load();
    }

    function loadAnalyticsStage() {
        if (Config.options?.appStats?.enable)
            AppStats.stateDir; // Starts the usage sampler; must collect whether or not the overlay is open
        if (Config.options?.googleDrive?.enabled)
            GoogleDriveService.configured; // Keeps scheduled backups independent of Settings
        if (Config.options?.background?.widgets?.water_reminder?.enable)
            WaterReminderService.enabled; // Drives water reminder notifications
        if (Config.options?.policies?.phone !== 0) {
            KdeConnectService.available;
            PhoneContactsService.available;
            PhoneScrcpyService.available;
        }
    }

    Timer { id: stageTheme;     interval: 100;  onTriggered: root.loadThemeStage(); }
    Timer { id: stageAudio;     interval: 300;  onTriggered: root.loadAudioStage(); }
    Timer { id: stageMedia;     interval: 800;  onTriggered: root.loadMediaStage(); }
    Timer { id: stageOptional;  interval: 1500; onTriggered: root.loadOptionalStage(); }
    Timer { id: stageAnalytics; interval: 2500; onTriggered: root.loadAnalyticsStage(); }

    // Panel families
    property var families: ["ii", "waffle"]
    function cyclePanelFamily() {
        const currentIndex = families.indexOf(Config.options.panelFamily);
        const nextIndex = (currentIndex + 1) % families.length;
        Config.options.panelFamily = families[nextIndex];
    }

    function applyOpenRgbIfEnabled() {
        if (openRgbStartupApplied)
            return;
        if (!Config.ready)
            return;
        if (!(Config.options && Config.options.appearance && Config.options.appearance.openrgb && Config.options.appearance.openrgb.enable))
            return;
        if (!(Config.options && Config.options.appearance && Config.options.appearance.openrgb && Config.options.appearance.openrgb.applyOnStartup))
            return;
        openRgbStartupApplied = true;
        openRgbApplyProc.command = ["python", openRgbApplyScript];
        openRgbApplyProc.running = false;
        openRgbApplyProc.running = true;
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) {
                root.startStagedServices();
                root.applyOpenRgbIfEnabled();
            }
        }
    }

    Process {
        id: openRgbApplyProc
    }

    component PanelFamilyLoader: LazyLoader {
        required property string identifier
        property bool extraCondition: true
        active: Config.ready && Config.options.panelFamily === identifier && extraCondition
    }

    PanelFamilyLoader {
        identifier: "ii"
        component: IllogicalImpulseFamily {}
    }

    PanelFamilyLoader {
        identifier: "waffle"
        component: WaffleFamily {}
    }

    // Settings app loaded in-process once requested, then kept alive briefly
    // for fast re-opens. After the delay we drop the component to recover
    // its QML memory. Positive configured delays are capped at five seconds;
    // 0 still means keep it warm explicitly.
    readonly property int settingsUnloadCapSeconds: 5

    function settingsUnloadDelaySeconds() {
        const settingsApp = Config.options && Config.options.settingsApp;
        let configured = settingsApp && settingsApp.unloadAfterSeconds !== undefined
            ? settingsApp.unloadAfterSeconds
            : settingsUnloadCapSeconds;

        if (configured <= 0)
            return 0;
        return Math.min(configured, settingsUnloadCapSeconds);
    }

    Loader {
        id: settingsLoader
        property bool loadedOnce: false
        active: loadedOnce || GlobalStates.settingsOpen
        asynchronous: true
        source: "SettingsWindow.qml"

        // When settings closes, schedule an unload pass. If the user
        // reopens before the timer fires, the timer is reset and we
        // keep the warm component.
        Timer {
            id: settingsUnloadTimer
            interval: root.settingsUnloadDelaySeconds() * 1000
            repeat: false
            onTriggered: {
                if (GlobalStates.settingsOpen)
                    return
                // The visual Loader only owns the Settings object tree. These
                // singletons outlive it, so release their page-specific data
                // before dropping the component as well.
                SearchRegistry.clearIndex()
                ThemePreviewCache.release()
                WallpaperPreviewCache.release()
                settingsLoader.loadedOnce = false
            }
        }

        Connections {
            target: GlobalStates
            function onSettingsOpenChanged() {
                if (GlobalStates.settingsOpen) {
                    settingsUnloadTimer.stop()
                    if (!settingsLoader.loadedOnce)
                        settingsLoader.loadedOnce = true
                } else {
                    const s = root.settingsUnloadDelaySeconds()
                    if (s > 0) {
                        settingsUnloadTimer.interval = s * 1000
                        settingsUnloadTimer.restart()
                    }
                }
            }
        }
    }

    // Welcome runs in-process so it shares Config, GlobalStates and the same
    // Quickshell lifecycle as Settings. Unlike Settings, the onboarding is
    // destroyed as soon as it closes so costly page trees do not stay warm.
    Loader {
        id: welcomeLoader
        active: Config.ready && GlobalStates.welcomeOpen
        asynchronous: true
        source: "modules/welcome/WelcomeWindow.qml"
    }

    // Shortcuts
    IpcHandler {
        target: "panelFamily"

        function cycle() {
            root.cyclePanelFamily();
        }
    }

    GlobalShortcut {
        name: "panelFamilyCycle"
        description: "Cycles panel family"

        onPressed: root.cyclePanelFamily()
    }
}
