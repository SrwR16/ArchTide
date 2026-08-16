pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/** Official project destinations used by Welcome cards. */
QtObject {
    readonly property string repositoryUrl: "https://github.com/SrwR16/ArchTide"
    readonly property string documentationUrl: "https://github.com/SrwR16/ArchTide/wiki"
    readonly property string discordUrl: "https://discord.gg/GtdRBXgMwq"
    readonly property bool documentationAvailable: true
}