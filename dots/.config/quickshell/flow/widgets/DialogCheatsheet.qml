import QtQuick
import QtQuick.Layouts
import "../core"
import "../widgets"

/**
 * DialogCheatsheet - A widget to display keyboard shortcuts.
 * It appears centered in its parent without a dark backdrop.
 */
Item {
    id: root
    anchors.fill: parent
    visible: false
    z: 999 // Ensure it stays on top of panel content

    property var shortcuts: [] // Array of { key: "A", action: "Do something" }
    signal closed()

    // Transparent overlay to catch clicks outside the cheatsheet
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onClicked: {
            root.visible = false;
            root.closed();
        }
        // Block scrolling from passing through
        onWheel: (event) => { event.accepted = true; }
    }

    Rectangle {
        id: bgContainer
        anchors.centerIn: parent
        width: Math.max(280 * Appearance.effectiveScale, Math.min(parent.width - 32 * Appearance.effectiveScale, contentCol.implicitWidth + 48 * Appearance.effectiveScale))
        height: Math.min(parent.height - 32 * Appearance.effectiveScale, contentCol.implicitHeight + 48 * Appearance.effectiveScale)
        color: Appearance.m3colors.m3surfaceContainerHigh
        radius: 28 * Appearance.effectiveScale
        
        // Prevent clicks on the dialog itself from closing it
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: contentCol
            anchors.fill: parent
            anchors.margins: 24 * Appearance.effectiveScale
            spacing: 0

            // Header Icon
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 16 * Appearance.effectiveScale
                text: "keyboard"
                iconSize: 24 * Appearance.effectiveScale
                color: Appearance.m3colors.m3secondary
            }

            // Headline
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 16 * Appearance.effectiveScale
                text: "Keyboard Shortcuts"
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: Appearance.m3colors.m3onSurface
            }

            // Shortcuts List
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 24 * Appearance.effectiveScale
                rowSpacing: 12 * Appearance.effectiveScale

                Repeater {
                    model: root.shortcuts

                    delegate: RowLayout {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        spacing: 16 * Appearance.effectiveScale

                        // Key Badge Row
                        RowLayout {
                            id: keyBadgeRow
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 6 * Appearance.effectiveScale

                            Repeater {
                                model: {
                                    var k = modelData.key || "";
                                    if (k.includes(" / ")) return k.split(" / ");
                                    if (k.includes(" ")) return k.split(" ");
                                    return [k];
                                }

                                delegate: Rectangle {
                                    required property string modelData
                                    
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitWidth: keyText.implicitWidth + 16 * Appearance.effectiveScale
                                    implicitHeight: keyText.implicitHeight + 8 * Appearance.effectiveScale
                                    color: Appearance.m3colors.m3surfaceContainerHighest
                                    radius: 6 * Appearance.effectiveScale
                                    border.width: 1
                                    border.color: Appearance.colors.colOutlineVariant

                                    StyledText {
                                        id: keyText
                                        anchors.centerIn: parent
                                        text: parent.modelData
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: Appearance.m3colors.m3primary
                                    }
                                }
                            }
                        }

                        // Action Text
                        StyledText {
                            id: actionText
                            Layout.fillWidth: true
                            Layout.preferredWidth: implicitWidth
                            Layout.alignment: Qt.AlignVCenter
                            text: modelData.action
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.m3colors.m3onSurfaceVariant
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }

            Item {
                Layout.fillHeight: true
                Layout.preferredHeight: 24 * Appearance.effectiveScale
            }

            // Action Button
            RippleButton {
                Layout.alignment: Qt.AlignRight
                implicitWidth: closeText.implicitWidth + 32 * Appearance.effectiveScale
                implicitHeight: 40 * Appearance.effectiveScale
                buttonRadius: 20 * Appearance.effectiveScale
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: {
                    root.visible = false;
                    root.closed();
                }
                contentItem: StyledText {
                    id: closeText
                    anchors.centerIn: parent
                    text: "Close"
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3primary
                }
            }
        }
    }

    StyledRectangularShadow {
        target: bgContainer
        z: -1
    }
}
