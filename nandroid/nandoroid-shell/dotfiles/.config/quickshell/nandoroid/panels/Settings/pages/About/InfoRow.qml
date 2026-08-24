import "../../../../core"
import "../../../../widgets"
import QtQuick
import QtQuick.Layouts

SegmentedWrapper {
    id: infoRowRoot
    property string label
    property string value
    Layout.fillWidth: true
    implicitHeight: infoRow.implicitHeight + (24 * Appearance.effectiveScale)
    orientation: Qt.Vertical
    maxRadius: 20 * Appearance.effectiveScale
    color: Appearance.m3colors.m3surfaceContainerHigh

    RowLayout {
        id: infoRow
        anchors.fill: parent
        anchors {
            leftMargin: 16 * Appearance.effectiveScale
            rightMargin: 16 * Appearance.effectiveScale
            topMargin: 12 * Appearance.effectiveScale
            bottomMargin: 12 * Appearance.effectiveScale
        }
        spacing: 16 * Appearance.effectiveScale

        StyledText {
            text: label
            color: Appearance.colors.colOnLayer1
            Layout.fillWidth: true
        }
        StyledText {
            text: value
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            Layout.alignment: Qt.AlignRight
            elide: Text.ElideRight
        }
    }
}
