import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions

QuickToggleModel {
    name: Translation.tr("ANC Mode")

    readonly property var activeService: {
        if (SoundcoreService.isConnected) return SoundcoreService;
        if (BudsService.isConnected) return BudsService;
        return null;
    }

    // Consider toggled on when not Normal (i.e. NoiseCanceling or Transparency)
    toggled: activeService ? activeService.currentMode !== "Normal" : false

    icon: {
        let mode = activeService ? activeService.currentMode : "Normal";
        if (mode === "Normal")
            return "hearing";
        if (mode === "Transparency")
            return "visibility";
        if (mode === "NoiseCanceling")
            return "noise_control_off";
        return "hearing";
    }

    statusText: {
        let mode = activeService ? activeService.currentMode : "Normal";
        if (mode === "Normal")
            return Translation.tr("Normal");
        if (mode === "Transparency")
            return Translation.tr("Transparency");
        if (mode === "NoiseCanceling")
            return Translation.tr("ANC");
        return Translation.tr("Normal");
    }

    mainAction: () => {
        if (!activeService) return;
        let mode = activeService.currentMode;
        let nextMode = "Normal";
        if (mode === "Normal")
            nextMode = "Transparency";
        else if (mode === "Transparency")
            nextMode = "NoiseCanceling";
        else if (mode === "NoiseCanceling")
            nextMode = "Normal";

        activeService.setMode(nextMode);
    }

    tooltipText: Translation.tr("Cycle ANC Mode")
}
