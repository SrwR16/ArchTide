import "../../../../core"
import "../../../../services"
import "../../../../widgets"
import "."
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

ColumnLayout {
    Layout.fillWidth: true
    spacing: 0
    
    SearchHandler { 
        searchString: "Overview"
        aliases: ["Workspaces", "Window Manager", "Expose"]
    }

    // ── Overview Settings Section ──
    ColumnLayout {
        id: overviewSettingsSection
        Layout.fillWidth: true
        spacing: 4 * Appearance.effectiveScale
                
                RowLayout {
                    spacing: 12 * Appearance.effectiveScale
                    Layout.bottomMargin: 8 * Appearance.effectiveScale
                    MaterialSymbol {
                        text: "grid_view"
                        iconSize: 24 * Appearance.effectiveScale
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: I18nService.tr("Overview")
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                        Layout.fillWidth: true
                    }
                }
    
                // Rows
                SegmentedWrapper {
                    Layout.fillWidth: true
                    implicitHeight: overviewRowsRow.implicitHeight + (24 * Appearance.effectiveScale)
                    orientation: Qt.Vertical
                    maxRadius: 20 * Appearance.effectiveScale
                    color: Appearance.m3colors.m3surfaceContainerHigh

                    RowLayout {
                        id: overviewRowsRow
                        anchors.fill: parent
                        anchors {
                            leftMargin: 16 * Appearance.effectiveScale
                            rightMargin: 16 * Appearance.effectiveScale
                            topMargin: 12 * Appearance.effectiveScale
                            bottomMargin: 12 * Appearance.effectiveScale
                        }
                        spacing: 16 * Appearance.effectiveScale

                        MaterialSymbol { text: "reorder"; iconSize: 24 * Appearance.effectiveScale; color: Appearance.colors.colPrimary }
                        StyledText {
                            text: I18nService.tr("Rows")
                            color: Appearance.colors.colOnLayer1
                            Layout.fillWidth: true
                        }

                        StyledStepper {
                            Layout.alignment: Qt.AlignVCenter
                            value: Config.ready && Config.options.overview ? Config.options.overview.rows : 2
                            from: 1; to: 5; stepSize: 1
                            decimals: 0
                            onValueChanged: if (Config.ready && Config.options.overview) Config.options.overview.rows = Math.round(value)
                        }
                    }
                }
    
                // Columns
                SegmentedWrapper {
                    Layout.fillWidth: true
                    implicitHeight: overviewColsRow.implicitHeight + (24 * Appearance.effectiveScale)
                    orientation: Qt.Vertical
                    maxRadius: 20 * Appearance.effectiveScale
                    color: Appearance.m3colors.m3surfaceContainerHigh

                    RowLayout {
                        id: overviewColsRow
                        anchors.fill: parent
                        anchors {
                            leftMargin: 16 * Appearance.effectiveScale
                            rightMargin: 16 * Appearance.effectiveScale
                            topMargin: 12 * Appearance.effectiveScale
                            bottomMargin: 12 * Appearance.effectiveScale
                        }
                        spacing: 16 * Appearance.effectiveScale

                        MaterialSymbol { text: "view_week"; iconSize: 24 * Appearance.effectiveScale; color: Appearance.colors.colPrimary }
                        StyledText {
                            text: I18nService.tr("Columns")
                            color: Appearance.colors.colOnLayer1
                            Layout.fillWidth: true
                        }

                        StyledStepper {
                            Layout.alignment: Qt.AlignVCenter
                            value: Config.ready && Config.options.overview ? Config.options.overview.columns : 5
                            from: 1; to: 10; stepSize: 1
                            decimals: 0
                            onValueChanged: if (Config.ready && Config.options.overview) Config.options.overview.columns = Math.round(value)
                        }
                    }
                }
    
                // Scale
                SegmentedWrapper {
                    Layout.fillWidth: true
                    implicitHeight: overviewScaleRow.implicitHeight + (24 * Appearance.effectiveScale)
                    orientation: Qt.Vertical
                    maxRadius: 20 * Appearance.effectiveScale
                    color: Appearance.m3colors.m3surfaceContainerHigh

                    RowLayout {
                        id: overviewScaleRow
                        anchors.fill: parent
                        anchors {
                            leftMargin: 16 * Appearance.effectiveScale
                            rightMargin: 16 * Appearance.effectiveScale
                            topMargin: 12 * Appearance.effectiveScale
                            bottomMargin: 12 * Appearance.effectiveScale
                        }
                        spacing: 16 * Appearance.effectiveScale

                        MaterialSymbol { text: "zoom_in"; iconSize: 24 * Appearance.effectiveScale; color: Appearance.colors.colPrimary }
                        StyledText {
                            text: I18nService.tr("Window Scale")
                            color: Appearance.colors.colOnLayer1
                            Layout.fillWidth: true
                        }

                        StyledStepper {
                            Layout.alignment: Qt.AlignVCenter
                            value: Config.ready && Config.options.overview ? Config.options.overview.scale * 100 : 15
                            from: 5; to: 50; stepSize: 1
                            decimals: 0
                            suffix: "%"
                            onValueChanged: if (Config.ready && Config.options.overview) Config.options.overview.scale = value / 100.0
                        }
                    }
                }
    
                // Workspace Spacing
                SegmentedWrapper {
                    Layout.fillWidth: true
                    implicitHeight: overviewSpacingRow.implicitHeight + (24 * Appearance.effectiveScale)
                    orientation: Qt.Vertical
                    maxRadius: 20 * Appearance.effectiveScale
                    color: Appearance.m3colors.m3surfaceContainerHigh

                    RowLayout {
                        id: overviewSpacingRow
                        anchors.fill: parent
                        anchors {
                            leftMargin: 16 * Appearance.effectiveScale
                            rightMargin: 16 * Appearance.effectiveScale
                            topMargin: 12 * Appearance.effectiveScale
                            bottomMargin: 12 * Appearance.effectiveScale
                        }
                        spacing: 16 * Appearance.effectiveScale

                        MaterialSymbol { text: "space_dashboard"; iconSize: 24 * Appearance.effectiveScale; color: Appearance.colors.colPrimary }
                        StyledText {
                            text: I18nService.tr("Workspace Spacing")
                            color: Appearance.colors.colOnLayer1
                            Layout.fillWidth: true
                        }

                        StyledStepper {
                            Layout.alignment: Qt.AlignVCenter
                            value: Config.ready && Config.options.overview ? Config.options.overview.workspaceSpacing : 10
                            from: 0; to: 50; stepSize: 1
                            decimals: 0
                            suffix: "px"
                            onValueChanged: if (Config.ready && Config.options.overview) Config.options.overview.workspaceSpacing = Math.round(value)
                        }
                    }
                }
            }
    

}
