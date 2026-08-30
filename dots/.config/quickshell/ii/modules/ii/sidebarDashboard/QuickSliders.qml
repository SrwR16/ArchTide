import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.UPower

Rectangle {
    id: root

    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    property bool editMode: false

    implicitWidth: contentItem.implicitWidth + root.horizontalPadding * 2
    implicitHeight: contentItem.implicitHeight + root.verticalPadding * 2
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    property real verticalPadding: 4
    property real horizontalPadding: 12

    // Layout / sizing
    readonly property int columns: Config.options.sidebar.quickSliders.columns
    property real spacing: 8
    property real padding: 6
    readonly property real baseCellWidth: {
        const availableWidth = root.width - (root.padding * 2) - (root.spacing * (root.columns))
        return availableWidth / root.columns
    }
    readonly property real baseCellHeight: 56

    // Slider definitions (fixed order, index 0-3 mirrors config keys)
    readonly property list<var> sliders: [
        {
            index: 0,
            icon: "brightness_6",
            getVal: () => root.brightnessMonitor.brightness,
            setVal: (v) => root.brightnessMonitor.setBrightness(v)
        },
        {
            index: 1,
            icon: "volume_up",
            getVal: () => Audio.sink.audio.volume,
            setVal: (v) => { Audio.sink.audio.volume = v }
        },
        {
            index: 2,
            icon: "mic",
            getVal: () => Audio.source.audio.volume,
            setVal: (v) => { Audio.source.audio.volume = v }
        },
        {
            index: 3,
            icon: "light_mode",
            secondaryIcon: "wb_twilight",
            getVal: () => Hyprsunset.gamma === 100 ? 0.3 + root.brightnessMonitor?.brightness * 0.7 : (Hyprsunset.gamma - Hyprsunset.gammaLowerLimit) / (100 - Hyprsunset.gammaLowerLimit) * 0.3,
            setVal: (v) => {
                if (v >= 0.3) {
                    root.brightnessMonitor.setBrightness((v - 0.3) / 0.7);
                    if (Hyprsunset.gamma !== 100) {
                        Hyprsunset.setGamma(100);
                    }
                } else {
                    if (root.brightnessMonitor.brightness !== 0) {
                        root.brightnessMonitor.setBrightness(0);
                    }
                    Hyprsunset.setGamma((v / 0.3 * (100 - Hyprsunset.gammaLowerLimit) + Hyprsunset.gammaLowerLimit));
                }
            }
        }
    ]

    function sliderList(enabledOnly) {
        const out = [];
        for (const s of root.sliders) {
            if (enabledOnly && !root.sliderShown(s.index)) continue;
            out.push(s);
        }
        return out;
    }

    readonly property list<var> sliderRows: sliderRowsForList(root.editMode ? root.sliderList(false) : root.sliderList(true))

    function sliderRowsForList(list) {
        const rows = [];
        let row = [];
        let totalSize = 0;
        for (const s of list) {
            const size = root.sliderSize(s.index);
            if (totalSize + size > root.columns) {
                rows.push(row);
                row = [];
                totalSize = 0;
            }
            row.push(s);
            totalSize += size;
        }
        if (row.length > 0) {
            rows.push(row);
        }
        return rows;
    }

    // Edit-mode helpers (access config by fixed slider index)
    function sliderShown(index) {
        const qs = Config.options.sidebar.quickSliders;
        if (index === 0) return qs.showBrightness;
        if (index === 1) return qs.showVolume;
        if (index === 2) return qs.showMic;
        return qs.showGamma;
    }
    function setSliderShown(index, shown) {
        const qs = Config.options.sidebar.quickSliders;
        if (index === 0) qs.showBrightness = shown;
        else if (index === 1) qs.showVolume = shown;
        else if (index === 2) qs.showMic = shown;
        else qs.showGamma = shown;
    }
    function sliderSize(index) {
        const qs = Config.options.sidebar.quickSliders;
        if (index === 0) return qs.brightnessSize;
        if (index === 1) return qs.volumeSize;
        if (index === 2) return qs.micSize;
        return qs.gammaSize;
    }
    function setSliderSize(index, size) {
        const qs = Config.options.sidebar.quickSliders;
        if (index === 0) qs.brightnessSize = size;
        else if (index === 1) qs.volumeSize = size;
        else if (index === 2) qs.micSize = size;
        else qs.gammaSize = size;
    }
    function toggleSliderEnabled(index) {
        root.setSliderShown(index, !root.sliderShown(index));
    }
    function toggleSliderSize(index) {
        root.setSliderSize(index, 3 - root.sliderSize(index));
    }

    Column {
        id: contentItem
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.spacing

        Repeater {
            id: rowsRepeater
            model: ScriptModel {
                values: Array(root.sliderRows.length)
            }
            delegate: RowLayout {
                id: sliderRow
                required property int index
                spacing: root.spacing
                property var rowData: root.sliderRows[index]

                Repeater {
                    model: sliderRow.rowData
                    delegate: QuickSliderTile {
                        sliderIndex: modelData.index
                        editMode: root.editMode
                    }
                }
            }
        }
    }

    component QuickSliderTile: Rectangle {
        id: tile
        required property int sliderIndex
        required property bool editMode
        required property var modelData

        readonly property real mySize: root.sliderSize(tile.sliderIndex)
        width: root.baseCellWidth * tile.mySize + root.spacing * (tile.mySize - 1)
        height: root.baseCellHeight
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2

        Behavior on width {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        QuickSlider {
            anchors {
                left: parent.left
                right: parent.right
                leftMargin: 8
                rightMargin: 8
                verticalCenter: parent.verticalCenter
            }
            sliderData: modelData
            materialSymbol: modelData.icon
            secondaryMaterialSymbol: modelData?.secondaryIcon ?? ""
        }

        MouseArea { // Blocking MouseArea for edit interactions
            visible: tile.editMode
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons

            onReleased: (event) => {
                if (event.button === Qt.LeftButton)
                    root.toggleSliderEnabled(tile.sliderIndex);
            }
            onPressed: (event) => {
                if (event.button === Qt.RightButton) root.toggleSliderSize(tile.sliderIndex);
            }
            onPressAndHold: root.toggleSliderSize(tile.sliderIndex)
        }
    }

    component QuickSlider: StyledSlider {
        id: quickSlider
        required property string materialSymbol
        property string secondaryMaterialSymbol
        property var sliderData
        configuration: StyledSlider.Configuration.M
        stopIndicatorValues: []
        dividerValues: secondaryMaterialSymbol.length > 0 ? [secondaryIcon.iconLocation] : []
        value: sliderData ? sliderData.getVal() : 0
        onMoved: sliderData && sliderData.setVal(value)

        MaterialSymbol {
            id: icon
            property bool nearFull: quickSlider.value >= 0.82
            anchors {
                verticalCenter: quickSlider.verticalCenter
                right: nearFull ? quickSlider.handle.right : quickSlider.right
                rightMargin: nearFull ? 14 : 8
            }
            iconSize: 20
            color: nearFull ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            text: quickSlider.materialSymbol

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on anchors.rightMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        MaterialSymbol {
            id: secondaryIcon
            visible: secondaryMaterialSymbol.length > 0
            property real iconLocation: 0.3
            property bool nearIcon: iconLocation - quickSlider.value <= 0.1 && iconLocation - quickSlider.value > (quickSlider.handleWidth + 8 - 14) / quickSlider.effectiveDraggingWidth
            anchors {
                verticalCenter: quickSlider.verticalCenter
                right: nearIcon ? quickSlider.handle.right : quickSlider.right
                rightMargin: nearIcon ? 14 : (1 - iconLocation) * quickSlider.effectiveDraggingWidth + quickSlider.rightPadding + 8
            }
            iconSize: 20
            color: quickSlider.value >= iconLocation - 0.1 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            text: secondaryMaterialSymbol

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }
}
