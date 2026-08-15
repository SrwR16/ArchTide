import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.waffle.looks

SequentialAnimation {
    id: root

    required property var target

    property bool left: false

    PropertyAction {
        target: root.target
        property: "ListView.delayRemove"
        value: true
    }
    ParallelAnimation {
        NumberAnimation {
            target: root.target
            property: "x"
            to: root.left ? -root.target.width : root.target.width
            duration: 250
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Looks.transition.easing.bezierCurve.easeIn
        }
        NumberAnimation {
            target: root.target.draggedItem
            property: "opacity"
            to: 0.0
            duration: 250
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Looks.transition.easing.bezierCurve.easeIn
        }
    }
    PropertyAction {
        target: root.target
        property: "ListView.delayRemove"
        value: false
    }
}
