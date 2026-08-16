pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.modules.flow.overlay.crosshair
import qs.modules.flow.overlay.volumeMixer
import qs.modules.flow.overlay.floatingImage
import qs.modules.flow.overlay.fpsLimiter
import qs.modules.flow.overlay.recorder
import qs.modules.flow.overlay.resources
import qs.modules.flow.overlay.notes
import qs.modules.flow.overlay.media
import qs.modules.flow.overlay.discordVoice

DelegateChooser {
    id: root
    role: "identifier"

    DelegateChoice { roleValue: "crosshair"; Crosshair {} }
    DelegateChoice { roleValue: "floatingImage"; FloatingImage {} }
    DelegateChoice { roleValue: "fpsLimiter"; FpsLimiter {} }
    DelegateChoice { roleValue: "recorder"; Recorder {} }
    DelegateChoice { roleValue: "resources"; Resources {} }
    DelegateChoice { roleValue: "notes"; Notes {} }
    DelegateChoice { roleValue: "volumeMixer"; VolumeMixer {} }
    DelegateChoice { roleValue: "media"; MediaContent {} }
    DelegateChoice { roleValue: "discordVoice"; DiscordVoiceOverlay {} }
}
