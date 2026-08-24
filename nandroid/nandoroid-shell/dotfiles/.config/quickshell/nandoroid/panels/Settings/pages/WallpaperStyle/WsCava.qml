import "../../../../core"
import "../../../../services"
import "../../../../widgets"
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: 0

    SearchHandler { 
        searchString: "Visualizer"
        aliases: ["Cava", "Audio", "Desktop Cava", "Lockscreen Cava"]
    }

    // ── Visualizer Section ──
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4 * Appearance.effectiveScale

        // Section Header
        RowLayout {
            spacing: 12 * Appearance.effectiveScale
            Layout.bottomMargin: 8 * Appearance.effectiveScale

            MaterialSymbol {
                text: "equalizer"
                iconSize: 24 * Appearance.effectiveScale
                color: Appearance.colors.colPrimary
            }
            StyledText {
                text: I18nService.tr("Audio Visualizer")
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
                Layout.fillWidth: true
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4 * Appearance.effectiveScale

            // --- Desktop Visualizer Toggle ---
            SegmentedWrapper {
                id: desktopCavaCard
                Layout.fillWidth: true
                implicitHeight: desktopCavaRow.implicitHeight + (24 * Appearance.effectiveScale)
                orientation: Qt.Vertical
                maxRadius: 20 * Appearance.effectiveScale
                color: Appearance.m3colors.m3surfaceContainerHigh

                RippleButton {
                    anchors.fill: parent
                    colBackground: Appearance.m3colors.m3surfaceContainerHigh
                    colBackgroundHover: Appearance.m3colors.m3surfaceContainerHigh
                    buttonRadius: 0
                    topLeftRadius: desktopCavaCard.rTopLeft
                    topRightRadius: desktopCavaCard.rTopRight
                    bottomLeftRadius: desktopCavaCard.rBottomLeft
                    bottomRightRadius: desktopCavaCard.rBottomRight
                    onClicked: if(Config.ready) Config.options.appearance.background.showCava = !Config.options.appearance.background.showCava
                }

                RowLayout {
                    id: desktopCavaRow
                    anchors.fill: parent
                    anchors {
                        leftMargin: 16 * Appearance.effectiveScale
                        rightMargin: 16 * Appearance.effectiveScale
                        topMargin: 12 * Appearance.effectiveScale
                        bottomMargin: 12 * Appearance.effectiveScale
                    }
                    spacing: 16 * Appearance.effectiveScale
                    MaterialSymbol { text: "desktop_windows"; iconSize: 24 * Appearance.effectiveScale; color: Appearance.colors.colPrimary }
                    StyledText { text: I18nService.tr("Show on desktop"); Layout.fillWidth: true; color: Appearance.colors.colOnLayer1 }
                    AndroidToggle {
                        checked: Config.ready && Config.options.appearance.background.showCava
                        onToggled: if(Config.ready) Config.options.appearance.background.showCava = !checked
                    }
                }
            }

            // --- Desktop Opacity Slider ---
            SegmentedWrapper {
                Layout.fillWidth: true
                visible: Config.ready && Config.options.appearance.background.showCava
                implicitHeight: desktopOpacityRow.implicitHeight + (24 * Appearance.effectiveScale)
                orientation: Qt.Vertical
                maxRadius: 20 * Appearance.effectiveScale
                color: Appearance.m3colors.m3surfaceContainerHigh
                RowLayout {
                    id: desktopOpacityRow
                    anchors.fill: parent
                    anchors {
                        leftMargin: 16 * Appearance.effectiveScale
                        rightMargin: 16 * Appearance.effectiveScale
                        topMargin: 12 * Appearance.effectiveScale
                        bottomMargin: 12 * Appearance.effectiveScale
                    }
                    spacing: 16 * Appearance.effectiveScale

                    MaterialSymbol { text: "opacity"; iconSize: 24 * Appearance.effectiveScale; color: Appearance.colors.colPrimary }
                    StyledText { text: I18nService.tr("Desktop opacity"); Layout.fillWidth: true; color: Appearance.colors.colOnLayer1 }
                    StyledStepper {
                        Layout.alignment: Qt.AlignVCenter
                        from: 0.05; to: 0.5; stepSize: 0.01
                        displayFactor: 100
                        decimals: 0
                        suffix: "%"
                        value: Config.options.appearance.background.cavaOpacity
                        onValueChanged: Config.options.appearance.background.cavaOpacity = value
                    }
                }
            }

            // --- Lockscreen Visualizer Toggle ---
            SegmentedWrapper {
                id: lockCavaCard
                Layout.fillWidth: true
                implicitHeight: lockCavaRow.implicitHeight + (24 * Appearance.effectiveScale)
                orientation: Qt.Vertical
                maxRadius: 20 * Appearance.effectiveScale
                color: Appearance.m3colors.m3surfaceContainerHigh

                RippleButton {
                    anchors.fill: parent
                    colBackground: Appearance.m3colors.m3surfaceContainerHigh
                    colBackgroundHover: Appearance.m3colors.m3surfaceContainerHigh
                    buttonRadius: 0
                    topLeftRadius: lockCavaCard.rTopLeft
                    topRightRadius: lockCavaCard.rTopRight
                    bottomLeftRadius: lockCavaCard.rBottomLeft
                    bottomRightRadius: lockCavaCard.rBottomRight
                    onClicked: if(Config.ready) Config.options.lock.showCava = !Config.options.lock.showCava
                }

                RowLayout {
                    id: lockCavaRow
                    anchors.fill: parent
                    anchors {
                        leftMargin: 16 * Appearance.effectiveScale
                        rightMargin: 16 * Appearance.effectiveScale
                        topMargin: 12 * Appearance.effectiveScale
                        bottomMargin: 12 * Appearance.effectiveScale
                    }
                    spacing: 16 * Appearance.effectiveScale
                    MaterialSymbol { text: "lock"; iconSize: 24 * Appearance.effectiveScale; color: Appearance.colors.colPrimary }
                    StyledText { text: I18nService.tr("Show on lock screen"); Layout.fillWidth: true; color: Appearance.colors.colOnLayer1 }
                    AndroidToggle {
                        checked: Config.ready && Config.options.lock.showCava
                        onToggled: if(Config.ready) Config.options.lock.showCava = !checked
                    }
                }
            }

            // --- Lockscreen Opacity Slider ---
            SegmentedWrapper {
                Layout.fillWidth: true
                visible: Config.ready && Config.options.lock.showCava
                implicitHeight: lockOpacityRow.implicitHeight + (24 * Appearance.effectiveScale)
                orientation: Qt.Vertical
                maxRadius: 20 * Appearance.effectiveScale
                color: Appearance.m3colors.m3surfaceContainerHigh
                RowLayout {
                    id: lockOpacityRow
                    anchors.fill: parent
                    anchors {
                        leftMargin: 16 * Appearance.effectiveScale
                        rightMargin: 16 * Appearance.effectiveScale
                        topMargin: 12 * Appearance.effectiveScale
                        bottomMargin: 12 * Appearance.effectiveScale
                    }
                    spacing: 16 * Appearance.effectiveScale

                    MaterialSymbol { text: "opacity"; iconSize: 24 * Appearance.effectiveScale; color: Appearance.colors.colPrimary }
                    StyledText { text: I18nService.tr("Lock screen opacity"); Layout.fillWidth: true; color: Appearance.colors.colOnLayer1 }
                    StyledStepper {
                        Layout.alignment: Qt.AlignVCenter
                        from: 0.05; to: 0.5; stepSize: 0.01
                        displayFactor: 100
                        decimals: 0
                        suffix: "%"
                        value: Config.options.lock.cavaOpacity
                        onValueChanged: Config.options.lock.cavaOpacity = value
                    }
                }
            }
        }
    }
}
