pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import "../core"
import "../core/functions"

Singleton {
    id: root

    property string query: ""
    property var clipboardHistory: []
    property var usageData: ({})
    readonly property string clipboardThumbnailDir: "/tmp/nandoroid/clipboard"

    onClipboardHistoryChanged: {
        if (!clipboardHistory || clipboardHistory.length === 0) return;
        Quickshell.execDetached(["mkdir", "-p", root.clipboardThumbnailDir]);
        clipboardHistory.forEach(entry => {
            if (entry.isImage) {
                const thumbPath = root.clipboardThumbnailDir + "/" + entry.id + ".png";
                Quickshell.execDetached(["sh", "-c", 'test -f "$2" || cliphist decode "$1" > "$2"', "sh", entry.id, thumbPath]);
            }
        });
    }

    function closeAll() {
        GlobalStates.launcherOpen = false;
        GlobalStates.spotlightOpen = false;
    }

    readonly property var quickCommands: [
        { name: "Lock Screen", subtitle: "Session Action", id: "cmd-lock", icon: "lock", isPlugin: true, emoji: "", execute: () => { Session.lock(); root.closeAll(); } },
        { name: "Reboot System", subtitle: "Session Action", id: "cmd-reboot", icon: "restart_alt", isPlugin: true, emoji: "", execute: () => { Session.reboot(); root.closeAll(); } },
        { name: "Power Off", subtitle: "Session Action", id: "cmd-poweroff", icon: "power_settings_new", isPlugin: true, emoji: "", execute: () => { Session.poweroff(); root.closeAll(); } },
        { name: "Log Out", subtitle: "Exit Hyprland", id: "cmd-logout", icon: "logout", isPlugin: true, emoji: "", execute: () => { Session.logout(); root.closeAll(); } },
        { name: "Suspend", subtitle: "Session Action", id: "cmd-suspend", icon: "bedtime", isPlugin: true, emoji: "", execute: () => { Session.suspend(); root.closeAll(); } },
        { name: "Hibernate", subtitle: "Session Action", id: "cmd-hibernate", icon: "save", isPlugin: true, emoji: "", execute: () => { Session.hibernate(); root.closeAll(); } },
        { name: "Open Dashboard", subtitle: "Shell Interface", id: "cmd-dashboard", icon: "dashboard", isPlugin: true, emoji: "", execute: () => { GlobalStates.dashboardOpen = true; root.closeAll(); } },
        { name: "Open Settings", subtitle: "Shell Interface", id: "cmd-settings", icon: "settings", isPlugin: true, emoji: "", execute: () => { GlobalStates.settingsOpen = true; root.closeAll(); } },
        { name: "System Monitor", subtitle: "Shell Interface", id: "cmd-monitor", icon: "monitoring", isPlugin: true, emoji: "", execute: () => { GlobalStates.systemMonitorOpen = true; root.closeAll(); } },
        { name: "Workspace Overview", subtitle: "Shell Interface", id: "cmd-overview", icon: "grid_view", isPlugin: true, emoji: "", execute: () => { GlobalStates.overviewOpen = true; root.closeAll(); } },
        { name: "Customize", subtitle: "Shell Interface", id: "cmd-wallpaper", icon: "palette", isPlugin: true, emoji: "", execute: () => { GlobalStates.settingsPageIndex = 4; GlobalStates.settingsOpen = true; root.closeAll(); } },
        { name: "Bluetooth Settings", subtitle: "Shell Interface", id: "cmd-bluetooth", icon: "bluetooth", isPlugin: true, emoji: "", execute: () => { GlobalStates.settingsPageIndex = 1; GlobalStates.settingsOpen = true; root.closeAll(); } },
        { name: "Network Settings", subtitle: "Shell Interface", id: "cmd-network", icon: "wifi", isPlugin: true, emoji: "", execute: () => { GlobalStates.settingsPageIndex = 0; GlobalStates.settingsOpen = true; root.closeAll(); } },
        { name: "Quick Actions", subtitle: "Tools Menu", id: "cmd-tools", icon: "construction", isPlugin: true, emoji: "", execute: () => { GlobalStates.quickActionsOpen = true; root.closeAll(); } },
        { name: "Edit Config", subtitle: "Configuration File", id: "cmd-edit-config", icon: "edit_note", isPlugin: true, emoji: "", execute: () => { Quickshell.execDetached(["xdg-open", Directories.home.replace("file://", "") + "/.config/nandoroid/config.json"]); root.closeAll(); } },
        { name: "Clear All Clipboard", subtitle: "Clipboard Action", id: "cmd-clip-wipe", icon: "delete_sweep", isPlugin: true, emoji: "", execute: () => { Quickshell.execDetached(["cliphist", "wipe"]); root.closeAll(); } },
        { name: "Clear Old Clipboard", subtitle: "Keep 100 newest", id: "cmd-clip-clear-old", icon: "mop", isPlugin: true, emoji: "", execute: () => { Quickshell.execDetached(["sh", "-c", "cliphist list | tail -n +101 | cliphist delete"]); root.closeAll(); } },
        { name: "Clear New Clipboard", subtitle: "Clear last 10 entries", id: "cmd-clip-clear-new", icon: "history", isPlugin: true, emoji: "", execute: () => { Quickshell.execDetached(["sh", "-c", "cliphist list | head -n 10 | cliphist delete"]); root.closeAll(); } },
        { name: "Restart Shell", subtitle: "Maintenance (Fast)", id: "cmd-shell-restart", icon: "refresh", isPlugin: true, emoji: "", execute: () => { Quickshell.execDetached([Directories.home.replace("file://", "") + "/.config/quickshell/nandoroid/scripts/restartshell.sh"]); root.closeAll(); } },
        { name: "Restart Shell (Fix Tray)", subtitle: "Maintenance (Deep)", id: "cmd-shell-restart-fix", icon: "build", isPlugin: true, emoji: "", execute: () => { Quickshell.execDetached([Directories.home.replace("file://", "") + "/.config/quickshell/nandoroid/scripts/restart_fix.sh"]); root.closeAll(); } }
    ]

    readonly property var quickTools: [
        { name: "Screen Snip", subtitle: "Tool", id: "tool-snip", icon: "content_cut", isPlugin: true, emoji: "", execute: () => { RegionService.screenshot(); root.closeAll(); } },
        { name: "Color Picker", subtitle: "Tool", id: "tool-picker", icon: "colorize", isPlugin: true, emoji: "", execute: () => { Quickshell.execDetached(["hyprpicker", "-a"]); root.closeAll(); } },
        { name: "OCR", subtitle: "Tool", id: "tool-ocr", icon: "text_snippet", isPlugin: true, emoji: "", execute: () => { RegionService.ocr(); root.closeAll(); } },
        { name: "QR Scanner", subtitle: "Tool", id: "tool-qr", icon: "qr_code_scanner", isPlugin: true, emoji: "", execute: () => { RegionService.qrcode(); root.closeAll(); } },
        { name: "Lens Search", subtitle: "Tool", id: "tool-lens", icon: "image_search", isPlugin: true, emoji: "", execute: () => { RegionService.search(); root.closeAll(); } },
        { name: "Screen Record", subtitle: "Tool", id: "tool-record", icon: "videocam", isPlugin: true, emoji: "", execute: () => { RegionService.record(); root.closeAll(); } },
        { name: "Record w/ Sound", subtitle: "Tool", id: "tool-record-sound", icon: "mic", isPlugin: true, emoji: "", execute: () => { RegionService.recordWithSound(); root.closeAll(); } },
        { name: "Record Fullscreen", subtitle: "Tool", id: "tool-record-full", icon: "fullscreen", isPlugin: true, emoji: "", execute: () => { RegionService.recordFullscreenWithSound(); root.closeAll(); } }
    ]

    readonly property var matugenSchemes: [
        { id: "scheme-content",     name: "Content" },
        { id: "scheme-expressive",  name: "Expressive" },
        { id: "scheme-fidelity",    name: "Fidelity" },
        { id: "scheme-fruit-salad", name: "Fruit Salad" },
        { id: "scheme-monochrome",  name: "Monochrome" },
        { id: "scheme-neutral",     name: "Neutral" },
        { id: "scheme-rainbow",     name: "Rainbow" },
        { id: "scheme-tonal-spot",  name: "Tonal Spot" }
    ]

    // Model for listing an arbitrary folder's images (used by the "<wall <dir>" path)
    FolderListModel {
        id: wallFolderModel
        showDirs: false
        showDotAndDotDot: false
        sortField: FolderListModel.Name
        sortCaseSensitive: false
        nameFilters: Wallpapers.imagePatterns
    }

    // Lazy-load limit for wallpaper browsing; grows via loadMoreWallpapers() on scroll.
    property int wallLimit: 30
    // Total candidates available in the current wall context; guards against pointless growth.
    property int _wallTotal: 0
    function loadMoreWallpapers() {
        if (root.wallLimit >= root._wallTotal) return;
        root.wallLimit += 30;
    }

    // Build candidate results for the "dwall"/"lwall" sub-commands (target: "desktop" or "lock")
    function buildWallCommandResults(arg, target) {
        const out = [];
        const folderModel = Wallpapers.folderModel;
        const apply = (fp) => {
            if (target === "lock") Wallpapers.selectForLockscreen("file://" + fp);
            else Wallpapers.select("file://" + fp);
            root.closeAll();
        };
        if (arg === "") {
            root._wallTotal = folderModel.count;
            const count = Math.min(folderModel.count, root.wallLimit);
            for (let i = 0; i < count; i++) {
                const fp = FileUtils.trimFileProtocol(folderModel.get(i, "filePath"));
                const fn = folderModel.get(i, "fileName");
                if (!fp || fp === "") continue;
                out.push({
                    name: fn,
                    subtitle: FileUtils.shortenHomePath(fp),
                    id: "wall-" + fp, icon: "wallpaper", isPlugin: true, emoji: "",
                    isImage: true, imagePath: FileUtils.trimFileProtocol(fp),
                    execute: () => apply(fp)
                });
            }
            return out;
        }

        // Direct path → resolve (~ expands to $HOME)
        if (arg.includes("/")) {
            const resolved = FileUtils.expandHomePath(arg);
            const isImageFile = Wallpapers.imagePatterns.some(p => resolved.toLowerCase().endsWith(p.slice(1)));
            if (!isImageFile) {
                // Treat as a directory: list its image files so it's clear what's inside
                const dirUrl = resolved.startsWith("file://") ? resolved : "file://" + resolved;
                if (wallFolderModel.folder !== dirUrl) wallFolderModel.folder = dirUrl;
                root._wallTotal = wallFolderModel.count;
                const dirCount = Math.min(wallFolderModel.count, root.wallLimit);
                for (let i = 0; i < dirCount; i++) {
                    const fp = FileUtils.trimFileProtocol(wallFolderModel.get(i, "filePath"));
                    const fn = wallFolderModel.get(i, "fileName");
                    if (!fp || fp === "") continue;
                    out.push({
                        name: fn,
                        subtitle: FileUtils.shortenHomePath(fp),
                        id: "wall-dir-" + fp, icon: "wallpaper", isPlugin: true, emoji: "",
                        isImage: true, imagePath: FileUtils.trimFileProtocol(fp),
                        execute: () => apply(fp)
                    });
                }
                if (wallFolderModel.count > 0) return out;
            }
            // Single file (or empty/loading folder) → apply as-is
            out.push({
                name: I18nService.tr("Apply %1").replace("%1", FileUtils.fileNameForPath(resolved)),
                subtitle: FileUtils.shortenHomePath(resolved),
                id: "wall-path-" + resolved, icon: "wallpaper", isPlugin: true, emoji: "",
                isImage: true, imagePath: FileUtils.trimFileProtocol(resolved),
                execute: () => apply(resolved)
            });
            return out;
        }

        // Fuzzy match against known wallpapers (default folder + favorites)
        const lowered = arg.toLowerCase();
        const wallHome = FileUtils.trimFileProtocol(Wallpapers.directory);
        const seen = new Set();
        const candidates = [];
        for (let i = 0; i < folderModel.count; i++) {
            const fp = FileUtils.trimFileProtocol(folderModel.get(i, "filePath"));
            const fn = folderModel.get(i, "fileName");
            if (!fp || fp === "" || seen.has(fp)) continue;
            seen.add(fp);
            if (fn && fn.toLowerCase().includes(lowered)) candidates.push({ name: fn, path: fp });
        }
        for (const fav of Wallpapers.favorites) {
            const cleanFav = FileUtils.trimFileProtocol(fav);
            const fn = FileUtils.fileNameForPath(cleanFav);
            if (cleanFav === "" || seen.has(cleanFav)) continue;
            seen.add(cleanFav);
            if (fn && fn.toLowerCase().includes(lowered)) candidates.push({ name: fn, path: cleanFav });
        }
        candidates.sort((a, b) => {
            const aStarts = a.name.toLowerCase().startsWith(lowered);
            const bStarts = b.name.toLowerCase().startsWith(lowered);
            if (aStarts && !bStarts) return -1;
            if (!aStarts && bStarts) return 1;
            return a.name.localeCompare(b.name);
        });

        root._wallTotal = candidates.length;
        const count = Math.min(candidates.length, root.wallLimit);
        for (const c of candidates.slice(0, count)) {
            out.push({
                name: c.name,
                subtitle: FileUtils.shortenHomePath(c.path),
                id: "wall-" + c.path, icon: "wallpaper", isPlugin: true, emoji: "",
                isImage: true, imagePath: FileUtils.trimFileProtocol(c.path),
                execute: () => apply(c.path)
            });
        }
        if (candidates.length === 0) {
            out.push({
                name: I18nService.tr("No matching wallpaper"),
                subtitle: I18nService.tr('No image named "%1" in %2').replace("%1", arg).replace("%2", FileUtils.shortenHomePath(wallHome)),
                id: "wall-none", icon: "search_off", isPlugin: true, emoji: "", execute: () => {}
            });
        }
        return out;
    }

    // Build candidate results for the "color ..." sub-command
    function buildColorCommandResults(arg) {
        const out = [];
        const loweredArg = arg.toLowerCase();
        let matched = root.matugenSchemes;
        if (loweredArg !== "") {
            matched = root.matugenSchemes.filter(s => s.name.toLowerCase().includes(loweredArg) || s.id.toLowerCase().includes(loweredArg));
        }
        if (matched.length === 0) {
            out.push({
                name: "No matching scheme",
                subtitle: 'Try "' + Config.options.search.settingsPrefix + 'color content" or "' + Config.options.search.settingsPrefix + 'color tonal spot"',
                id: "color-none", icon: "palette", isPlugin: true, emoji: "", execute: () => {}
            });
            return out;
        }
        for (const s of matched) {
            const isCurrent = Config.ready && Config.options.appearance.background.matugen && Config.options.appearance.background.matugenScheme === s.id;
            out.push({
                name: s.name,
                subtitle: (isCurrent ? "Current scheme · " : "") + s.id,
                id: "color-" + s.id, icon: "palette", isPlugin: true, emoji: "",
                execute: () => { Wallpapers.applyScheme(s.id); root.closeAll(); }
            });
        }
        return out;
    }

    Timer {
        id: fileSearchTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (!Config.ready || !Config.options.search) return;
            const term = root.query.trim().slice(Config.options.search.filePrefix.length).trim();
            if (term.length > 0) {
                fileSearchProc.runSearch(term);
            } else {
                fileSearchProc.results = [];
                _triggerVal++;
            }
        }
    }

    Process {
        id: fileSearchProc
        running: false
        property var results: []
        command: ["fd", "-i", "-t", "f", "--max-results", "20", "", "/home"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n").filter(l => l.length > 0);
                fileSearchProc.results = lines.map(path => {
                    const parts = path.split("/");
                    const name = parts[parts.length - 1];
                    return {
                        name: name,
                        subtitle: path,
                        id: "file-" + path,
                        icon: "insert_drive_file",
                        isPlugin: true,
                        emoji: "",
                        execute: () => { 
                            Quickshell.execDetached(["xdg-open", path]); 
                            root.closeAll(); 
                        }
                    };
                });
                _triggerVal++;
            }
        }
        function runSearch(term) {
            running = false;
            const home = FileUtils.trimFileProtocol(Directories.home.toString());
            command = ["fd", "-i", "-t", "f", "--max-results", "20", term, home];
            running = true;
        }
    }

    onQueryChanged: {
        root.wallLimit = 30;
        if (Config.ready && Config.options.search && query.trim().startsWith(Config.options.search.filePrefix)) {
            fileSearchTimer.restart();
        }
    }

    Process {
        id: cliphistProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n").filter(l => l.trim().length > 0);
                const newHistory = lines.slice(0, 50).map(line => {
                    const id = line.split("\t")[0];
                    const isImage = line.includes("[[ binary data");
                    return { id: id, raw: line, isImage: isImage };
                });
                
                if (JSON.stringify(newHistory) !== JSON.stringify(root.clipboardHistory)) {
                    root.clipboardHistory = newHistory;
                }
            }
        }
    }

    Timer {
        id: cliphistTimer
        interval: 2500
        running: GlobalStates.launcherOpen || GlobalStates.spotlightOpen
        repeat: true
        onTriggered: cliphistProc.running = true
    }

    FileView {
        id: usageFile
        path: Quickshell.shellPath("data/app_usage.json")
        watchChanges: true
        onLoaded: {
            try {
                root.usageData = JSON.parse(text());
            } catch(e) {
                root.usageData = {};
            }
            triggerUpdate();
        }
    }

    function recordExecution(appId) {
        if (!appId || !Config.options.search.enableUsageTracking) return;
        
        let currentUsage = root.usageData[appId];
        
        // Migrate old format (number) to new format (object)
        if (typeof currentUsage === "number") {
            currentUsage = { total: currentUsage, history: [] };
        } else if (!currentUsage || typeof currentUsage !== "object") {
            currentUsage = { total: 0, history: [] };
        }
        
        const now = Date.now();
        currentUsage.total += 1;
        
        if (!Array.isArray(currentUsage.history)) {
            currentUsage.history = [];
        }
        currentUsage.history.push(now);
        
        // Clean up history older than 30 days
        const thirtyDaysAgo = now - (30 * 24 * 60 * 60 * 1000);
        currentUsage.history = currentUsage.history.filter(t => t > thirtyDaysAgo);
        
        root.usageData[appId] = currentUsage;
        
        const dataStr = JSON.stringify(root.usageData);
        const path = Quickshell.shellPath("data/app_usage.json");
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" > "$2"', "sh", dataStr, path]);
        triggerUpdate();
    }

    property var allApps: []
    property string selectedCategory: "All"
    
    Timer {
        id: debounceUpdateTimer
        interval: 500
        repeat: false
        onTriggered: root.updateAppModel()
    }

    function triggerUpdate() {
        debounceUpdateTimer.restart()
    }

    readonly property var categories: {
        const cats = new Set(["All"]);
        allApps.forEach(app => {
            if (app.category && app.category !== "Application" && app.category !== "Other") {
                cats.add(app.category);
            }
        });
        const sortedCats = Array.from(cats).sort((a, b) => {
            if (a === "All") return -1;
            if (b === "All") return 1;
            return a.localeCompare(b);
        });
        if (allApps.some(app => app.category === "Other")) sortedCats.push("Other");
        return sortedCats;
    }
    
    Timer {
        id: retryTimer
        interval: 2000
        running: allApps.length < 5
        repeat: true
        onTriggered: triggerUpdate()
    }
    
    Component.onCompleted: {
        triggerUpdate()
        cliphistProc.running = true
        usageFile.reload()
        recentEmojiFile.reload()
    }

    Connections {
        target: GlobalStates
        function onLauncherOpenChanged() {
            if (GlobalStates.launcherOpen) {
                if (allApps.length === 0) triggerUpdate();
                cliphistProc.running = true;
            }
        }
        function onSpotlightOpenChanged() {
            if (GlobalStates.spotlightOpen) {
                if (allApps.length === 0) triggerUpdate();
                cliphistProc.running = true;
            }
        }
    }

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { triggerUpdate() }
    }

    // Re-sort immediately when usage tracking is toggled
    Connections {
        target: Config.options.search
        function onEnableUsageTrackingChanged() { triggerUpdate() }
    }

    function updateAppModel() {
        const apps = Array.from(DesktopEntries.applications.values);
        if (apps.length === 0) return;
        
        const uniqueApps = new Map();
        for (const app of apps) {
            if (!uniqueApps.has(app.id)) uniqueApps.set(app.id, app);
        }
        
        const mapped = Array.from(uniqueApps.values()).map(app => {
            let category = "Other";
            
            if (app.categories && Array.isArray(app.categories)) {
                const cats = app.categories;
                if (cats.includes("Game")) category = "Games";
                else if (cats.includes("Development")) category = "Development";
                else if (cats.includes("Office")) category = "Office";
                else if (cats.includes("Network") || cats.includes("WebBrowser")) category = "Internet";
                else if (cats.includes("AudioVideo") || cats.includes("Audio") || cats.includes("Video")) category = "Multimedia";
                else if (cats.includes("Settings")) category = "Settings";
                else if (cats.includes("System")) category = "System";
                else if (cats.includes("Graphics")) category = "Graphics";
                else if (cats.includes("Utility")) category = "Utility";
            }
            
            if (category === "Other") {
                const id = app.id.toLowerCase();
                const name = app.name.toLowerCase();
                if (id.includes("game") || id.includes("steam") || id.includes("retroarch")) category = "Games";
                else if (id.includes("code") || id.includes("vsc") || id.includes("studio") || id.includes("devel") || id.includes("python") || id.includes("rust")) category = "Development";
                else if (id.includes("office") || id.includes("word") || id.includes("excel") || id.includes("calc") || id.includes("pdf") || id.includes("note")) category = "Office";
                else if (id.includes("browser") || id.includes("firefox") || id.includes("chrome") || id.includes("internet") || id.includes("mail")) category = "Internet";
                else if (id.includes("player") || id.includes("vlc") || id.includes("mpv") || id.includes("music") || id.includes("video") || id.includes("audio")) category = "Multimedia";
                else if (id.includes("setting") || id.includes("config") || id.includes("control") || id.includes("tweak")) category = "Settings";
                else if (id.includes("terminal") || id.includes("system") || id.includes("monitor") || id.includes("file") || id.includes("manage")) category = "System";
                else if (id.includes("graphic") || id.includes("draw") || id.includes("paint") || id.includes("photo") || id.includes("gimp") || id.includes("inkscape")) category = "Graphics";
            }

            const usage = root.usageData[app.id];
            let smartScore = 0;
            if (typeof usage === "number") {
                smartScore = usage;
            } else if (usage && typeof usage === "object") {
                let total = usage.total || 0;
                let todayCount = 0;
                let weekCount = 0;
                const now = Date.now();
                const oneDay = 24 * 60 * 60 * 1000;
                const sevenDays = 7 * oneDay;
                
                if (Array.isArray(usage.history)) {
                    for (let i = 0; i < usage.history.length; i++) {
                        const t = usage.history[i];
                        if (now - t <= oneDay) todayCount++;
                        if (now - t <= sevenDays) weekCount++;
                    }
                }
                smartScore = (total * 1) + (weekCount * 5) + (todayCount * 10);
            }

            return {
                name: app.name,
                icon: app.icon || "application-x-executable",
                id: app.id,
                execute: () => { recordExecution(app.id); app.execute(); },
                isPlugin: false,
                subtitle: app.id,
                category: category,
                emoji: "",
                smartScore: smartScore
            };
        }).sort((a, b) => {
            if (Config.options.search.enableUsageTracking && b.smartScore !== a.smartScore) return b.smartScore - a.smartScore;
            return a.name.localeCompare(b.name);
        });
        
        allApps = mapped;
        _triggerVal++;

    }
    
    property int _triggerVal: 0

    Process {
        id: mathProc
        property string result: ""
        command: ["qalc", "-t"]
        stdout: StdioCollector {
            onStreamFinished: { mathProc.result = this.text.trim(); }
        }
        function calculate(expr) {
            running = false;
            command = ["qalc", "-t", expr];
            running = true;
        }
    }

    property var emojiList: []
    property bool emojisLoaded: false
    property string selectedEmojiCategory: ""
    property var recentEmojis: []

    readonly property var emojiCategories: {
        const byCat = {};
        const order = [];
        for (const item of root.emojiList) {
            if (!byCat[item.category]) {
                byCat[item.category] = [];
                order.push(item.category);
            }
            byCat[item.category].push(item);
        }
        const arr = [];
        for (const name of order) arr.push({ name, emojis: byCat[name] });
        return arr;
    }

    readonly property var emojiTabs: {
        const tabs = [];
        if (root.recentEmojis.length > 0) tabs.push("Recent");
        for (const cat of root.emojiCategories) tabs.push(cat.name);
        return tabs;
    }

    FileView {
        id: emojiFile
        path: Quickshell.shellPath("data/emojis.txt")
        watchChanges: true
        onLoaded: {
            const lines = text().split("\n");
            const list = [];
            for (const line of lines) {
                const parts = line.split("\t");
                if (parts.length >= 3) list.push({ emoji: parts[0], category: parts[1], name: parts[2] });
            }
            emojiList = list;
            emojisLoaded = true;
            if (!root.selectedEmojiCategory && root.emojiTabs.length > 0) {
                root.selectedEmojiCategory = root.recentEmojis.length > 0 ? "Recent" : root.emojiTabs[0];
            }
        }
    }

    FileView {
        id: recentEmojiFile
        path: Quickshell.shellPath("data/emoji_recent.json")
        watchChanges: true
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (Array.isArray(parsed)) root.recentEmojis = parsed.slice(0, 40);
            } catch(e) {
                root.recentEmojis = [];
            }
            if (!root.selectedEmojiCategory && root.emojiTabs.length > 0) {
                root.selectedEmojiCategory = root.recentEmojis.length > 0 ? "Recent" : root.emojiTabs[0];
            }
        }
    }

    readonly property bool isEmojiMode: {
        if (!Config.ready || !Config.options.search) return false;
        return root.query.trim().startsWith(Config.options.search.emojiPrefix);
    }

    readonly property string emojiQuery: root.isEmojiMode ? root.query.trim().slice(Config.options.search.emojiPrefix.length).trim().toLowerCase() : ""

    readonly property var emojiSections: {
        if (!root.isEmojiMode || root.emojiList.length === 0) return [];
        const sections = [];
        if (root.recentEmojis.length > 0) sections.push({ label: "Recent Emoji", emojis: root.recentEmojis });
        for (const cat of root.emojiCategories) sections.push({ label: cat.name, emojis: cat.emojis });
        return sections;
    }

    readonly property var emojiSearchResults: {
        if (!root.isEmojiMode || root.emojiList.length === 0 || root.emojiQuery === "") return [];
        const q = root.emojiQuery;
        const found = [];
        for (const item of root.emojiList) {
            if (item.name.toLowerCase().includes(q) || item.category.toLowerCase().includes(q)) found.push(item);
        }
        found.sort((a, b) => {
            const aStarts = a.name.toLowerCase().startsWith(q);
            const bStarts = b.name.toLowerCase().startsWith(q);
            if (aStarts && !bStarts) return -1;
            if (!aStarts && bStarts) return 1;
            return a.name.localeCompare(b.name);
        });
        return found.slice(0, 150);
    }

    function recordEmojiUse(item) {
        if (!item || !item.emoji) return;
        const recents = root.recentEmojis.filter(r => r.emoji !== item.emoji);
        recents.unshift({ emoji: item.emoji, category: item.category || "", name: item.name || "" });
        root.recentEmojis = recents.slice(0, 40);
        if (!root.selectedEmojiCategory && root.emojiTabs.length > 0) {
            root.selectedEmojiCategory = "Recent";
        }
        const dataStr = JSON.stringify(root.recentEmojis);
        const path = Quickshell.shellPath("data/emoji_recent.json");
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" > "$2"', "sh", dataStr, path]);
    }

    function useEmoji(item) {
        if (!item) return;
        Quickshell.clipboardText = item.emoji;
        root.recordEmojiUse(item);
        root.closeAll();
    }

    readonly property bool isPluginSearch: {
        const stripped = query.trim();
        if (!Config.ready || !Config.options.search) return false;
        return [
            Config.options.search.mathPrefix,
            Config.options.search.webPrefix,
            Config.options.search.emojiPrefix,
            Config.options.search.clipboardPrefix,
            Config.options.search.filePrefix,
            Config.options.search.commandPrefix,
            Config.options.search.toolsPrefix,
            Config.options.search.settingsPrefix
        ].some(p => stripped.startsWith(p));
    }

    readonly property var results: {
        const strippedQuery = query.trim();
        const isClipboard = strippedQuery.startsWith(Config.options.search.clipboardPrefix);
        if (isClipboard) clipboardHistory; 
        _triggerVal
        
        if (strippedQuery === "") {
            if (Config.ready && Config.options.search && Config.options.search.enableGrouping && selectedCategory !== "All") {
                return allApps.filter(app => app.category === selectedCategory);
            }
            return allApps;
        }

        const results = [];
        if (!Config.ready || !Config.options.search) return allApps;

        if (strippedQuery.startsWith(Config.options.search.mathPrefix)) {
            const mathExpr = strippedQuery.slice(Config.options.search.mathPrefix.length).trim();
            if (mathExpr.length > 0) {
                mathProc.calculate(mathExpr);
                results.push({
                    name: "Math Result",
                    subtitle: mathExpr + " = " + (mathProc.result || "..."),
                    id: "math-result", icon: "calculate", isPlugin: true, emoji: "",
                    execute: () => { Quickshell.clipboardText = mathProc.result; root.closeAll(); }
                });
            }
        } else if (strippedQuery.startsWith(Config.options.search.webPrefix)) {
            const webQuery = strippedQuery.slice(Config.options.search.webPrefix.length).trim();
            if (webQuery.length > 0) {
                results.push({
                    name: "Search Web", subtitle: webQuery, id: "web-search", icon: "public", isPlugin: true, emoji: "",
                    execute: () => { Qt.openUrlExternally("https://www.google.com/search?q=" + encodeURIComponent(webQuery)); root.closeAll(); }
                });
            }
        } else if (strippedQuery.startsWith(Config.options.search.emojiPrefix)) {
            const emojiQuery = strippedQuery.slice(Config.options.search.emojiPrefix.length).toLowerCase().trim();
            const emojiResults = [];
            for (const item of emojiList) {
                if (item.name.includes(emojiQuery) || emojiQuery === "") {
                    emojiResults.push({
                        name: item.name, subtitle: item.category || "Emoji", emoji: item.emoji, category: "Emoji", id: "emoji-" + item.name, icon: "face", isPlugin: true,
                        execute: () => { root.useEmoji(item); }
                    });
                }
            }
            emojiResults.sort((a, b) => {
                const aStarts = a.name.toLowerCase().startsWith(emojiQuery);
                const bStarts = b.name.toLowerCase().startsWith(emojiQuery);
                if (aStarts && !bStarts) return -1;
                if (!aStarts && bStarts) return 1;
                return a.name.localeCompare(b.name);
            });
            results.push(...emojiResults.slice(0, 50));
        } else if (strippedQuery.startsWith(Config.options.search.clipboardPrefix)) {
            const clipQuery = strippedQuery.slice(Config.options.search.clipboardPrefix.length).toLowerCase().trim();
            const clipResults = [];
            for (const entryObj of clipboardHistory) {
                const entry = entryObj.raw;
                const cleanName = entry.replace(/^\d+\t/, "").trim();
                if (cleanName.toLowerCase().includes(clipQuery) || clipQuery === "") {
                    const thumbPath = entryObj.isImage ? (root.clipboardThumbnailDir + "/" + entryObj.id + ".png") : "";
                    clipResults.push({
                        name: entryObj.isImage ? "Clipboard Image" : "Clipboard Entry",
                        subtitle: cleanName, rawValue: entry, id: "clip-" + entryObj.id, icon: entryObj.isImage ? "image" : "content_paste",
                        isPlugin: true, isImage: entryObj.isImage, imagePath: thumbPath, emoji: "",
                        execute: () => {
                            Quickshell.execDetached(["sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", entryObj.id]);
                            root.closeAll();
                        }
                    });
                }
            }
            if (clipQuery !== "") {
                clipResults.sort((a, b) => {
                    const aStarts = a.subtitle.toLowerCase().startsWith(clipQuery);
                    const bStarts = b.subtitle.toLowerCase().startsWith(clipQuery);
                    if (aStarts && !bStarts) return -1;
                    if (!aStarts && bStarts) return 1;
                    
                    // If both start with query or both don't, maintain chronological order
                    // We use the numeric ID from cliphist (higher is newer)
                    const idA = parseInt(a.id.replace("clip-", ""));
                    const idB = parseInt(b.id.replace("clip-", ""));
                    return idB - idA;
                });
            }
            results.push(...clipResults.slice(0, 50));
        } else if (strippedQuery.startsWith(Config.options.search.commandPrefix)) {
            const cmdQuery = strippedQuery.slice(Config.options.search.commandPrefix.length).toLowerCase().trim();
            const cmdResults = [];
            
            // Search both commands and tools under the command prefix
            const allCommandsAndTools = root.quickCommands.concat(root.quickTools);
            
            for (const cmd of allCommandsAndTools) {
                if (cmd.name.toLowerCase().includes(cmdQuery) || cmd.id.toLowerCase().includes(cmdQuery) || cmdQuery === "") {
                    cmdResults.push(cmd);
                }
            }
            cmdResults.sort((a, b) => {
                const aStarts = a.name.toLowerCase().startsWith(cmdQuery);
                const bStarts = b.name.toLowerCase().startsWith(cmdQuery);
                if (aStarts && !bStarts) return -1;
                if (!aStarts && bStarts) return 1;
                return a.name.localeCompare(b.name);
            });
            results.push(...cmdResults);
        } else if (strippedQuery.startsWith(Config.options.search.toolsPrefix)) {
            const toolQuery = strippedQuery.slice(Config.options.search.toolsPrefix.length).toLowerCase().trim();
            const toolResults = [];
            for (const tool of root.quickTools) {
                if (tool.name.toLowerCase().includes(toolQuery) || tool.id.toLowerCase().includes(toolQuery) || toolQuery === "") {
                    toolResults.push(tool);
                }
            }
            toolResults.sort((a, b) => {
                const aStarts = a.name.toLowerCase().startsWith(toolQuery);
                const bStarts = b.name.toLowerCase().startsWith(toolQuery);
                if (aStarts && !bStarts) return -1;
                if (!aStarts && bStarts) return 1;
                return a.name.localeCompare(b.name);
            });
            results.push(...toolResults);
        } else if (strippedQuery.startsWith(Config.options.search.settingsPrefix)) {
            const settingsQuery = strippedQuery.slice(Config.options.search.settingsPrefix.length).trim();
            const lowerSettingsQuery = settingsQuery.toLowerCase();
            if (lowerSettingsQuery === "lwall" || lowerSettingsQuery.startsWith("lwall ")) {
                results.push(...root.buildWallCommandResults(settingsQuery.slice(5).trim(), "lock"));
            } else if (lowerSettingsQuery === "dwall" || lowerSettingsQuery.startsWith("dwall ")) {
                results.push(...root.buildWallCommandResults(settingsQuery.slice(5).trim(), "desktop"));
            } else if (lowerSettingsQuery === "wall" || lowerSettingsQuery.startsWith("wall ")) {
                results.push(...root.buildWallCommandResults(settingsQuery.slice(4).trim(), "desktop"));
            } else if (lowerSettingsQuery === "color" || lowerSettingsQuery.startsWith("color ")) {
                results.push(...root.buildColorCommandResults(settingsQuery.slice("color".length).trim()));
            } else if (settingsQuery.length === 0) {
                results.push({
                    name: I18nService.tr("Set Desktop Wallpaper"), subtitle: I18nService.tr('Type "%1dwall <name or path>"').replace("%1", Config.options.search.settingsPrefix), id: "wall-hint", icon: "wallpaper", isPlugin: true, emoji: "", keepOpen: true, execute: () => { root.query = Config.options.search.settingsPrefix + "dwall "; }
                });
                results.push({
                    name: I18nService.tr("Set Lock Screen Wallpaper"), subtitle: I18nService.tr('Type "%1lwall <name or path>"').replace("%1", Config.options.search.settingsPrefix), id: "lwall-hint", icon: "lock", isPlugin: true, emoji: "", keepOpen: true, execute: () => { root.query = Config.options.search.settingsPrefix + "lwall "; }
                });
                results.push({
                    name: I18nService.tr("Set Color Scheme"), subtitle: I18nService.tr('Type "%1color <scheme>"').replace("%1", Config.options.search.settingsPrefix), id: "color-hint", icon: "palette", isPlugin: true, emoji: "", keepOpen: true, execute: () => { root.query = Config.options.search.settingsPrefix + "color "; }
                });
                const allSettings = SearchRegistry.getAllResults();
                for (const res of allSettings) {
                    results.push({
                        name: res.title + " · " + res.matchedString,
                        subtitle: res.matchedString,
                        id: "settings-all-" + res.pageIndex + "-" + res.matchedString,
                        icon: "settings",
                        isPlugin: true,
                        emoji: "",
                        execute: () => {
                            SearchRegistry.pendingJump = { pageIndex: res.pageIndex, query: res.matchedString };
                            GlobalStates.settingsOpen = true;
                            root.closeAll();
                        }
                    });
                }
            } else {
                const settingsResults = SearchRegistry.getResultsRanked(settingsQuery);
                for (const res of settingsResults) {
                    results.push({
                        name: res.title,
                        subtitle: res.matchedString,
                        id: "settings-" + res.pageIndex + "-" + res.matchedString,
                        icon: "settings",
                        isPlugin: true,
                        emoji: "",
                        execute: () => {
                            SearchRegistry.pendingJump = { pageIndex: res.pageIndex, query: res.matchedString };
                            GlobalStates.settingsOpen = true;
                            root.closeAll();
                        }
                    });
                }
                if (settingsResults.length === 0) {
                    results.push({
                        name: "No settings found", subtitle: "Try a different search term", id: "settings-none", icon: "search_off", isPlugin: true, emoji: "", execute: () => {}
                    });
                }
            }
        } else if (strippedQuery.startsWith(Config.options.search.filePrefix)) {
            const fileQuery = strippedQuery.slice(Config.options.search.filePrefix.length).toLowerCase().trim();
            const fileResults = fileSearchProc.results.slice();
            fileResults.sort((a, b) => {
                const aStarts = a.name.toLowerCase().startsWith(fileQuery);
                const bStarts = b.name.toLowerCase().startsWith(fileQuery);
                if (aStarts && !bStarts) return -1;
                if (!aStarts && bStarts) return 1;
                return a.name.localeCompare(b.name);
            });
            results.push(...fileResults);
            if (fileSearchProc.results.length === 0 && strippedQuery.length > 1) {
                 results.push({
                    name: "Searching Files...", subtitle: "Please wait", id: "file-searching", icon: "search", isPlugin: true, emoji: "", execute: () => {}
                });
            }
        }

        if (!isPluginSearch) {
            const loweredQuery = strippedQuery.toLowerCase();
            

            const filteredApps = allApps.filter(app =>
                app.name.toLowerCase().includes(loweredQuery) ||
                app.id.toLowerCase().includes(loweredQuery)
            ).sort((a, b) => {
                const nameA = a.name.toLowerCase();
                const nameB = b.name.toLowerCase();
                const aStarts = nameA.startsWith(loweredQuery);
                const bStarts = nameB.startsWith(loweredQuery);

                if (aStarts && !bStarts) return -1;
                if (!aStarts && bStarts) return 1;

                if (Config.options.search.enableUsageTracking) {
                    if (b.smartScore !== a.smartScore) return b.smartScore - a.smartScore;
                }
                
                return nameA.localeCompare(nameB);
            });
            

            results.push(...filteredApps);
        }

        return (results.length > 0 || strippedQuery === "") ? results : allApps;
    }
}
