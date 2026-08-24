import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../widgets"
import "../../core"
import "../../core/functions" as Functions
import "../../services"

Rectangle {
    id: root
    
    // Explicitly set as spotlight
    readonly property bool isSpotlight: true
    
    color: Appearance.colors.colLayer1
    radius: Appearance.rounding.large
    
    StyledRectangularShadow {
        target: root
        radius: root.radius
        color: Functions.ColorUtils.applyAlpha(Appearance.colors.colShadow, 0.2)
        z: -1
    }
    
    readonly property var resultsProxy: LauncherSearch.results
    property int selectedIndex: 0
    property int gridColumns: 1
    property bool isKeyboardNavigation: false
    property bool jumpPending: false
    property string jumpSectionLabel: ""
    readonly property bool hasQuery: LauncherSearch.query !== ""
    
    width: 560 * Appearance.effectiveScale
    height: 480 * Appearance.effectiveScale
    implicitHeight: 480 * Appearance.effectiveScale
    
    readonly property real emojiCellSize: 54 * Appearance.effectiveScale
    readonly property real emojiGridSpacing: 2 * Appearance.effectiveScale
    readonly property real emojiGridWidth: root.width - 32 * Appearance.effectiveScale
    readonly property int emojiColumns: Math.max(4, Math.floor((root.emojiGridWidth + root.emojiGridSpacing) / (root.emojiCellSize + root.emojiGridSpacing)))
    readonly property real emojiCellW: (root.emojiGridWidth - (root.emojiColumns - 1) * root.emojiGridSpacing) / root.emojiColumns
    readonly property real emojiHeaderHeight: 30 * Appearance.effectiveScale
    
    function emojiTabIcon(category) {
        const icons = {
            "Recent": "history",
            "Smileys & Emotion": "mood",
            "People & Body": "face",
            "Animals & Nature": "pets",
            "Food & Drink": "restaurant",
            "Travel & Places": "explore",
            "Activities": "sports_soccer",
            "Objects": "lightbulb",
            "Symbols": "tag",
            "Flags": "flag"
        };
        return icons[category] || "mood";
    }
    
    function pushEmojiRows(model, flat, rowMap, emojis, cols) {
        for (let i = 0; i < emojis.length; i += cols) {
            const items = emojis.slice(i, i + cols);
            const row = { type: "emoji", items, startIndex: flat.length };
            model.push(row);
            const rowIdx = model.length - 1;
            for (let c = 0; c < items.length; c++) rowMap.push(rowIdx);
            for (const it of items) flat.push(it);
        }
    }
    
    function buildEmojiView() {
        const cols = root.emojiColumns;
        const model = [];
        const flat = [];
        const rowMap = [];
        const sections = [];
        if (LauncherSearch.emojiQuery !== "") {
            const secStart = flat.length;
            root.pushEmojiRows(model, flat, rowMap, LauncherSearch.emojiSearchResults, cols);
            if (flat.length > secStart) sections.push({ label: "", start: secStart, end: flat.length });
        } else {
            for (const section of LauncherSearch.emojiSections) {
                model.push({ type: "header", label: section.label });
                const secStart = flat.length;
                root.pushEmojiRows(model, flat, rowMap, section.emojis, cols);
                sections.push({ label: section.label, start: secStart, end: flat.length });
            }
        }
        return { model, flat, rowMap, sections };
    }
    
    function emojiNavigate(dx, dy) {
        const flat = root.emojiView.flat;
        if (!flat || flat.length === 0) return 0;
        const fromIdx = Math.min(Math.max(0, root.selectedIndex), flat.length - 1);
        if (dx !== 0) {
            return Math.min(flat.length - 1, Math.max(0, fromIdx + dx));
        }
        const sections = root.emojiView.sections;
        let secIdx = -1;
        for (let i = 0; i < sections.length; i++) {
            if (fromIdx >= sections[i].start && fromIdx < sections[i].end) { secIdx = i; break; }
        }
        if (secIdx < 0) return fromIdx;
        const sec = sections[secIdx];
        const col = (fromIdx - sec.start) % root.emojiColumns;
        const target = fromIdx + dy * root.emojiColumns;
        if (dy > 0) {
            if (target < sec.end) return target;
            const next = sections[secIdx + 1];
            if (!next) return flat.length - 1;
            return Math.min(next.end - 1, next.start + col);
        }
        if (dy < 0) {
            if (target >= sec.start) return target;
            const prev = sections[secIdx - 1];
            if (!prev) return 0;
            const lastRowLen = (prev.end - prev.start - 1) % root.emojiColumns + 1;
            const lastRowStart = prev.end - lastRowLen;
            return col < lastRowLen ? lastRowStart + col : prev.end - 1;
        }
        return fromIdx;
    }
    
    readonly property var emojiView: root.buildEmojiView()
    
    function jumpToSection(label) {
        LauncherSearch.selectedEmojiCategory = label;
        root.isKeyboardNavigation = false;
        const target = label === "Recent" ? "Recent Emoji" : label;
        const model = root.emojiView.model;
        for (let i = 0; i < model.length; i++) {
            if (model[i].type === "header" && model[i].label === target) {
                root.jumpSectionLabel = target;
                root.jumpPending = true;
                if (i + 1 < model.length && model[i + 1].type === "emoji") {
                    root.selectedIndex = model[i + 1].startIndex;
                }
                emojiListView.positionViewAtIndex(i, ListView.Beginning);
                break;
            }
        }
    }
    
    function updateActiveSection() {
        if (!LauncherSearch.isEmojiMode) return;
        if (root.isKeyboardNavigation) return;
        const model = root.emojiView.model;
        const spacing = 4 * Appearance.effectiveScale;
        const y = emojiListView.contentY;
        let acc = 0;
        let label = "";
        let activeRow = -1;
        for (let i = 0; i < model.length; i++) {
            if (model[i].type === "header") label = model[i].label;
            const h = model[i].type === "header" ? root.emojiHeaderHeight : root.emojiCellSize;
            if (acc >= y) { activeRow = i; break; }
            acc += h + spacing;
        }
        if (activeRow < 0) activeRow = model.length - 1;
        if (model[activeRow] && model[activeRow].type === "header") activeRow++;
        // While a section jump is in flight, contentY may still be in the old
        // section; don't move the selection or the tab until it settles there.
        const reachedJump = !root.jumpPending || label === root.jumpSectionLabel;
        if (!reachedJump) return;
        root.jumpPending = false;
        if (model[activeRow] && model[activeRow].type === "emoji") {
            root.selectedIndex = model[activeRow].startIndex;
        }
        const tabLabel = label === "Recent Emoji" ? "Recent" : label;
        if (tabLabel && LauncherSearch.selectedEmojiCategory !== tabLabel) {
            LauncherSearch.selectedEmojiCategory = tabLabel;
        }
    }
    
    function syncEmojiTab(index) {
        if (LauncherSearch.emojiQuery !== "") return;
        const sections = root.emojiView.sections;
        for (let i = 0; i < sections.length; i++) {
            if (index >= sections[i].start && index < sections[i].end) {
                const tabLabel = sections[i].label === "Recent Emoji" ? "Recent" : sections[i].label;
                if (tabLabel && LauncherSearch.selectedEmojiCategory !== tabLabel) {
                    LauncherSearch.selectedEmojiCategory = tabLabel;
                }
                break;
            }
        }
    }

    function executeSelected() {
        if (LauncherSearch.isEmojiMode) {
            const flat = root.emojiView.flat;
            if (flat && flat.length > 0 && selectedIndex >= 0 && selectedIndex < flat.length) {
                LauncherSearch.useEmoji(flat[selectedIndex]);
                GlobalStates.launcherOpen = false;
                GlobalStates.spotlightOpen = false;
            }
            return;
        }
        if (root.resultsProxy && root.resultsProxy.length > 0 && selectedIndex >= 0 && selectedIndex < root.resultsProxy.length) {
            const selected = root.resultsProxy[selectedIndex];
            selected.execute();
            if (!selected.keepOpen) {
                GlobalStates.launcherOpen = false;
                GlobalStates.spotlightOpen = false;
            }
        }
    }

    onSelectedIndexChanged: {
        if (!GlobalStates.spotlightOpen) return;
        if (LauncherSearch.isEmojiMode && root.isKeyboardNavigation) {
            if (root.emojiView.rowMap) {
                const rowIdx = root.emojiView.rowMap[selectedIndex];
                if (rowIdx !== undefined && rowIdx >= 0) {
                    emojiListView.positionViewAtIndex(rowIdx, ListView.Contain);
                }
            }
            root.syncEmojiTab(selectedIndex);
        }
    }

    Connections {
        target: LauncherSearch
        function onQueryChanged() {
            root.selectedIndex = 0;
            if (LauncherSearch.isEmojiMode) {
                Qt.callLater(() => {
                    if (emojiListView.model && emojiListView.model.length > 0) {
                        emojiListView.positionViewAtIndex(0, ListView.Beginning);
                    }
                });
            }
        }
    }

    // Backup grid navigation in case focus isn't on the search field
    Keys.onPressed: (event) => {
        if (!LauncherSearch.isEmojiMode) return;
        const total = root.emojiView.flat.length;
        if (total <= 0) return;
        if (event.key === Qt.Key_Up) {
            root.isKeyboardNavigation = true;
            root.selectedIndex = root.emojiNavigate(0, -1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            root.isKeyboardNavigation = true;
            root.selectedIndex = root.emojiNavigate(0, 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Left) {
            root.isKeyboardNavigation = true;
            root.selectedIndex = root.emojiNavigate(-1, 0);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            root.isKeyboardNavigation = true;
            root.selectedIndex = root.emojiNavigate(1, 0);
            event.accepted = true;
        }
    }

    // Smooth appearance animation
    Behavior on opacity {
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }
    
    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 16 * Appearance.effectiveScale
        spacing: 12 * Appearance.effectiveScale
        
        LauncherSearchField {
            id: searchField
            Layout.fillWidth: true
            launcherContent: root
        }
        
        // ── Emoji Category Tabs (icon only) ──
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 36 * Appearance.effectiveScale
            visible: LauncherSearch.isEmojiMode && LauncherSearch.emojiQuery === ""
            
            ListView {
                id: emojiTabList
                anchors.fill: parent
                orientation: ListView.Horizontal
                spacing: 8 * Appearance.effectiveScale
                model: LauncherSearch.emojiTabs
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                delegate: RippleButton {
                    width: 36 * Appearance.effectiveScale
                    height: 36 * Appearance.effectiveScale
                    buttonRadius: 18 * Appearance.effectiveScale
                    colBackground: LauncherSearch.selectedEmojiCategory === modelData ? Appearance.m3colors.m3primary : Appearance.m3colors.m3surfaceContainerHigh
                    colRipple: Appearance.m3colors.m3onPrimary
                    
                    onClicked: root.jumpToSection(modelData)
                    
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.emojiTabIcon(modelData)
                        iconSize: 20 * Appearance.effectiveScale
                        color: LauncherSearch.selectedEmojiCategory === modelData ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurfaceVariant
                    }
                }
            }
        }
        
        // ── Spotlight Content Container (Emoji List or Result List) ──
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            
            ListView {
                id: emojiListView
                anchors.fill: parent
                visible: LauncherSearch.isEmojiMode
                interactive: true
                clip: true
                spacing: 4 * Appearance.effectiveScale
                
                onContentYChanged: Qt.callLater(root.updateActiveSection)

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    hoverEnabled: false
                    onWheel: (event) => {
                        root.isKeyboardNavigation = false;
                        root.jumpPending = false;
                        event.accepted = false;
                    }
                }
                
                model: visible ? root.emojiView.model : []
                delegate: Item {
                    id: rowDelegate
                    property var rowData: modelData
                    width: emojiListView.width
                    height: rowData.type === "header" ? root.emojiHeaderHeight : root.emojiCellSize
                    
                    // ── Section header separator ──
                    StyledText {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: rowData.type === "header"
                        text: rowData.type === "header" ? rowData.label : ""
                        font.pixelSize: Math.round(12 * Appearance.effectiveScale)
                        font.weight: Font.DemiBold
                        color: Appearance.m3colors.m3primary
                        opacity: 0.9
                        elide: Text.ElideRight
                    }
                    
                    // ── Emoji row (fixed-size cells, left-aligned, fills width only on full rows) ──
                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        visible: rowData.type === "emoji"
                        spacing: root.emojiGridSpacing
                        
                        Repeater {
                            model: rowData.items
                            delegate: EmojiCell {
                                width: root.emojiCellW
                                height: root.emojiCellSize
                                emoji: modelData
                                selected: rowData.startIndex + index === root.selectedIndex
                                onHoveredChanged: {
                                    if (hovered && GlobalStates.spotlightOpen) {
                                        root.isKeyboardNavigation = false;
                                        root.jumpPending = false;
                                        root.selectedIndex = rowData.startIndex + index;
                                        root.syncEmojiTab(rowData.startIndex + index);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ListView {
                id: pluginList
                anchors.fill: parent
                visible: !LauncherSearch.isEmojiMode
                interactive: true
                clip: true
                spacing: 4 * Appearance.effectiveScale
                
                property real _savedY: -1
                function loadMoreKeepingPosition() {
                    if (pluginList.contentY > 0) pluginList._savedY = pluginList.contentY;
                    LauncherSearch.loadMoreWallpapers();
                    if (pluginList._savedY >= 0) {
                        // Restore right away (covers synchronous model reset) and again
                        // after deferred binding evaluation so no frame renders at 0.
                        pluginList.contentY = pluginList._savedY;
                        Qt.callLater(() => {
                            if (pluginList._savedY >= 0) {
                                pluginList.contentY = pluginList._savedY;
                                pluginList._savedY = -1;
                            }
                        });
                    }
                }
                
                model: visible ? root.resultsProxy : []
                delegate: LauncherListView {
                    result: modelData
                    selected: root.selectedIndex === index
                    onHoveredChanged: {
                        if (hovered) {
                            root.selectedIndex = index
                            root.isKeyboardNavigation = false
                        }
                    }
                }
                currentIndex: root.selectedIndex
                onCurrentIndexChanged: {
                    if (visible && currentIndex >= 0) {
                        positionViewAtIndex(currentIndex, ListView.Contain);
                        if (count > 0 && currentIndex >= count - 5) Qt.callLater(() => pluginList.loadMoreKeepingPosition());
                    }
                }
                onMovementEnded: {
                    if (contentHeight - contentY - height < 100) Qt.callLater(() => pluginList.loadMoreKeepingPosition());
                }
            }
        }

        // ── Vicinae Footer ──
        RowLayout {
            id: footer
            Layout.fillWidth: true
            spacing: 12 * Appearance.effectiveScale
            
            // Mode Indicator (Prefix-based)
            StyledText {
                font.pixelSize: Math.round(11 * Appearance.effectiveScale)
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
                opacity: 0.6
                text: {
                    const q = LauncherSearch.query;
                    const search = Config.ready && Config.options.search;
                    if (LauncherSearch.isEmojiMode) return I18nService.tr("Emoji Picker");
                    if (search.webPrefix && q.startsWith(search.webPrefix)) return I18nService.tr("Web Search");
                    if (search.mathPrefix && q.startsWith(search.mathPrefix)) return I18nService.tr("Calculator");
                    if (search.clipboardPrefix && q.startsWith(search.clipboardPrefix)) return I18nService.tr("Clipboard History");
                    if (search.filePrefix && q.startsWith(search.filePrefix)) return I18nService.tr("File Search");
                    if (search.commandPrefix && q.startsWith(search.commandPrefix)) return I18nService.tr("Quick Commands");
                    if (search.settingsPrefix && q.startsWith(search.settingsPrefix)) return I18nService.tr("Settings Search");
                    return q ? I18nService.tr("Spotlight Search") : I18nService.tr("Applications");
                }
            }
            
            Item { Layout.fillWidth: true }
            
            RowLayout {
                spacing: 16 * Appearance.effectiveScale
                opacity: 0.7
                
                // Navigate
                RowLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 6 * Appearance.effectiveScale
                    StyledText {
                        text: I18nService.tr("Navigate")
                        font.pixelSize: Math.round(11 * Appearance.effectiveScale)
                        color: Appearance.colors.colOnLayer1
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2 * Appearance.effectiveScale
                        Rectangle {
                            Layout.preferredWidth: 20 * Appearance.effectiveScale
                            Layout.preferredHeight: 20 * Appearance.effectiveScale
                            radius: 4 * Appearance.effectiveScale
                            color: Appearance.m3colors.m3surfaceVariant
                            StyledText { 
                                anchors.centerIn: parent; text: "↑"
                                font.pixelSize: Math.round(11 * Appearance.effectiveScale) 
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: 20 * Appearance.effectiveScale
                            Layout.preferredHeight: 20 * Appearance.effectiveScale
                            radius: 4 * Appearance.effectiveScale
                            color: Appearance.m3colors.m3surfaceVariant
                            StyledText { 
                                anchors.centerIn: parent; text: "↓"
                                font.pixelSize: Math.round(11 * Appearance.effectiveScale) 
                            }
                        }
                    }
                }

                // Open
                RowLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 6 * Appearance.effectiveScale
                    StyledText {
                        text: I18nService.tr("Open")
                        font.pixelSize: Math.round(11 * Appearance.effectiveScale)
                        color: Appearance.colors.colOnLayer1
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        Rectangle {
                            Layout.preferredWidth: 26 * Appearance.effectiveScale
                            Layout.preferredHeight: 20 * Appearance.effectiveScale
                            radius: 4 * Appearance.effectiveScale
                            color: Appearance.m3colors.m3surfaceVariant
                            StyledText { 
                                anchors.centerIn: parent
                                text: "↵"
                                font.pixelSize: Math.round(11 * Appearance.effectiveScale)
                            }
                        }
                    }
                }
            }
        }
    }
}
