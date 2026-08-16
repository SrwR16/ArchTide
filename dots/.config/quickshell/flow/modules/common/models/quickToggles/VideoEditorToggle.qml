import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Video Editor")
    hasStatusText: false
    toggled: false
    icon: "movie_edit"

    mainAction: () => {
        GlobalStates.sidebarRightOpen = false;
        delayedActionTimer.start();
    }
    
    Timer {
        id: delayedActionTimer
        interval: 300
        repeat: false
        onTriggered: {
            GlobalStates.videoEditorPath = "";
            GlobalStates.videoEditorOpen = true;
        }
    }

    tooltipText: Translation.tr("Video Editor")
}
