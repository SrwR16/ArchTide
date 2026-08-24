import "../../../../core"
import "../../../../services"
import "../../../../widgets"
import "../../../../core/functions" as Functions
import "."
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

/**
 * Functional Network Settings page.
 * Provides WiFi scanning, listing, and connection management.
 */
Item {
    id: root

    property string currentView: "main" // "main", "saved", or "wired"

    onVisibleChanged: {
        if (visible) Network.update()
        else root.currentView = "main"
    }
    
    // Reset scroll when changing views
    onCurrentViewChanged: {
        mainFlicking.contentY = 0
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 0
        spacing: 24 * Appearance.effectiveScale

        // ── Header ──
        ColumnLayout {
            spacing: 4 * Appearance.effectiveScale
            Layout.fillWidth: true
            Layout.rightMargin: 24 * Appearance.effectiveScale
            
            RowLayout {
                Layout.fillWidth: true
                spacing: 12 * Appearance.effectiveScale

                // Back Button (only in sub-pages)
                RippleButton {
                    visible: root.currentView !== "main"
                    implicitWidth: 40 * Appearance.effectiveScale
                    implicitHeight: 40 * Appearance.effectiveScale
                    buttonRadius: 20 * Appearance.effectiveScale
                    colBackground: Appearance.colors.colLayer1
                    onClicked: root.currentView = "main"
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "arrow_back"
                        iconSize: 24 * Appearance.effectiveScale
                        color: Appearance.colors.colOnLayer1
                    }
                }

                StyledText {
                    text: {
                        if (root.currentView === "main") return I18nService.tr("Network & Internet")
                        if (root.currentView === "saved") return I18nService.tr("Saved Networks")
                        if (root.currentView === "wired") return I18nService.tr("Wired Network")
                        return I18nService.tr("Network")
                    }
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    Layout.fillWidth: true
                }
                
                RowLayout {
                    visible: root.currentView === "main"
                    spacing: 12 * Appearance.effectiveScale
                    
                    // Refresh Button
                    RippleButton {
                        implicitWidth: 40 * Appearance.effectiveScale
                        implicitHeight: 40 * Appearance.effectiveScale
                        buttonRadius: 20 * Appearance.effectiveScale
                        colBackground: Appearance.colors.colLayer1
                        onClicked: Network.wifiScanning ? Network.cancelRescanWifi() : Network.rescanWifi()
                        
                        contentItem: MaterialSymbol {
                            id: refreshIconNetwork
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: Network.wifiScanning ? "close" : "refresh"
                            iconSize: 20 * Appearance.effectiveScale
                            color: Appearance.colors.colOnLayer1
                        }
                    }

                    // Add Network Button
                    RippleButton {
                        implicitWidth: 40 * Appearance.effectiveScale
                        implicitHeight: 40 * Appearance.effectiveScale
                        buttonRadius: 20 * Appearance.effectiveScale
                        colBackground: Appearance.colors.colLayer1
                        onClicked: GlobalStates.addNetworkDialogOpen = true
                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "add"
                            iconSize: 20 * Appearance.effectiveScale
                            color: Appearance.colors.colOnLayer1
                        }
                    }

                    // Global WiFi Toggle
                    AndroidToggle {
                        checked: Network.wifiEnabled
                        onToggled: Network.toggleWifi()
                    }
                }
            }
            StyledText {
                text: {
                    if (root.currentView === "main") return I18nService.tr("Manage your WiFi networks, Ethernet, and connectivity.")
                    if (root.currentView === "saved") return I18nService.tr("Manage and forget your saved WiFi networks.")
                    if (root.currentView === "wired") return I18nService.tr("Manage your wired ethernet connections.")
                    return ""
                }
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colSubtext
            }
        }

        // ── Scrollable Content Area ──
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Flickable {
                id: mainFlicking
                anchors.fill: parent
                contentHeight: contentCol.implicitHeight
                clip: true
                interactive: true

                ScrollBar.vertical: ScrollBar {}

            ColumnLayout {
                id: contentCol
                visible: !Network.wifiScanning
                width: parent.width - (24 * Appearance.effectiveScale)
                spacing: 24 * Appearance.effectiveScale

                NetworkMainView {
                    id: mainViewCol
                    Layout.fillWidth: true
                    visible: root.currentView === "main"
                }
                NetworkSavedView {
                    id: savedViewCol
                    Layout.fillWidth: true
                    visible: root.currentView === "saved"
                }
                NetworkWiredView {
                    id: wiredViewCol
                    Layout.fillWidth: true
                    visible: root.currentView === "wired"
                }
            }
        } // End Flickable

        MaterialLoadingIndicator {
            anchors.centerIn: parent
            visible: Network.wifiScanning
            implicitSize: 60 * Appearance.effectiveScale
            z: 10
        }
    } // End Item

        // ── Bottom Management Buttons (Main View) ──
        RowLayout {
            id: bottomManagementRow
            Layout.fillWidth: true
            Layout.margins: 16 * Appearance.effectiveScale
            Layout.rightMargin: 40 * Appearance.effectiveScale
            Layout.topMargin: 0
            spacing: 12 * Appearance.effectiveScale
            visible: root.currentView === "main"

            RippleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 48 * Appearance.effectiveScale
                buttonRadius: 16 * Appearance.effectiveScale
                colBackground: Appearance.colors.colLayer1
                onClicked: root.currentView = "wired"
                
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8 * Appearance.effectiveScale
                    MaterialSymbol {
                        text: "lan"
                        iconSize: 20 * Appearance.effectiveScale
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: I18nService.tr("Wired Network")
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }

            RippleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 48 * Appearance.effectiveScale
                buttonRadius: 16 * Appearance.effectiveScale
                colBackground: Appearance.colors.colLayer1
                onClicked: root.currentView = "saved"
                
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8 * Appearance.effectiveScale
                    MaterialSymbol {
                        text: "history"
                        iconSize: 20 * Appearance.effectiveScale
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: I18nService.tr("Saved Networks")
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    } // End root ColumnLayout
}
