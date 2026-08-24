import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import "../../widgets"
import "../../core"
import "../../services"

RippleButton {
    id: root
    
    property var result: modelData
    property bool selected: false
    
    // Whether this app is in the dock favorites (shares the same pinnedApps list).
    readonly property bool isFav: !!(result && !result.isPlugin) && TaskbarApps.pinVersion >= 0 && TaskbarApps.isPinned(result.id)
    
    width: parent ? parent.width : 0
    height: 48 * Appearance.effectiveScale
    
    colBackground: root.selected ? Qt.alpha(Appearance.m3colors.m3primary, 0.1) : "transparent"
    buttonRadius: Appearance.rounding.small

    // Right-click toggles favorite (pins/unpins in the shared dock list).
    altAction: (event) => {
        if (result && !result.isPlugin) TaskbarApps.togglePin(result.id)
    }
    
    onClicked: {
        if (result) {
            result.execute();
            if (!result.keepOpen) {
                GlobalStates.launcherOpen = false;
                GlobalStates.spotlightOpen = false;
            }
        }
    }
    
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12 * Appearance.effectiveScale
        anchors.rightMargin: 12 * Appearance.effectiveScale
        spacing: 12 * Appearance.effectiveScale
        
        // Icon Container
        Item {
            Layout.preferredWidth: 28 * Appearance.effectiveScale
            Layout.preferredHeight: 28 * Appearance.effectiveScale
            Layout.alignment: Qt.AlignVCenter

            MaterialShape {
                id: iconBg
                anchors.fill: parent
                shapeString: Config.ready ? Config.options.search.iconShape : "Square"
                color: (root.hovered || root.selected) ? Appearance.m3colors.m3primaryContainer : Appearance.m3colors.m3surfaceVariant
                borderWidth: 1 * Appearance.effectiveScale
                borderColor: Qt.rgba(0, 0, 0, 0.1)
                
                IconImage {
                    id: iconImg
                    source: (result && !result.isPlugin) ? Quickshell.iconPath(result.icon || "application-x-executable", "image-missing") : ""
                    visible: result && !result.isPlugin && result.emoji === ""
                    width: 18 * Appearance.effectiveScale
                    height: 18 * Appearance.effectiveScale
                    anchors.centerIn: parent
                }

                StyledText {
                    text: result.emoji || ""
                    visible: result && result.emoji !== ""
                    anchors.centerIn: parent
                    font.pixelSize: Math.round(18 * Appearance.effectiveScale)
                }
                
                MaterialSymbol {
                    text: (result && result.isPlugin) ? (result.icon || "extension") : ""
                    visible: result && result.isPlugin && result.emoji === "" && !result.isImage
                    iconSize: 18 * Appearance.effectiveScale
                    anchors.centerIn: parent
                    color: (root.hovered || root.selected) ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSurfaceVariant
                }

                ThumbnailImage {
                    anchors.fill: parent
                    sourcePath: (result && result.isImage) ? result.imagePath : ""
                    visible: !!(result && result.isImage)
                    fillMode: Image.PreserveAspectCrop
                }
            }
        }
        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.rightMargin: 8 * Appearance.effectiveScale
            spacing: 1 * Appearance.effectiveScale
            
            StyledText {
                text: (result && result.name) ? I18nService.tr(result.name) : ""
                font.pixelSize: Math.round(14 * Appearance.effectiveScale)
                font.weight: root.selected ? Font.DemiBold : Font.Medium
                color: root.selected ? Appearance.m3colors.m3primary : Appearance.m3colors.m3onSurface
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.minimumWidth: 0
            }
            
            StyledText {
                text: (result && result.subtitle) ? I18nService.tr(result.subtitle) : ""
                visible: text !== ""
                font.pixelSize: Math.round(11 * Appearance.effectiveScale)
                color: root.selected ? Appearance.m3colors.m3primary : Appearance.m3colors.m3onSurfaceVariant
                opacity: 0.7
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.minimumWidth: 0
            }
        }

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: "star"
            fill: 1
            iconSize: 14 * Appearance.effectiveScale
            color: Appearance.colors.colPrimary
            visible: root.isFav
        }
    }
}
