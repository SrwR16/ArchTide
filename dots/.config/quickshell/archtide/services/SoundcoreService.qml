pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.modules.common
import qs.services

Singleton {
    id: root

    // Dictionary to store active modes by device MAC address
    property var deviceModes: ({})

    readonly property var activeDevice: {
        for (let d of BluetoothStatus.connectedDevices) {
            if (isHeadsetSupported(d)) {
                return d;
            }
        }
        return null;
    }

    property bool isConnected: activeDevice !== null
    property string targetDeviceName: activeDevice ? activeDevice.name : "None"
    property string macAddress: activeDevice ? activeDevice.address : ""

    // Backward compatibility property for unified Quick Toggle bindings
    readonly property string currentMode: {
        let dummy = deviceModes; // Force dependency tracking on the deviceModes object
        return activeDevice ? getModeForMac(activeDevice.address) : "Normal";
    }

    readonly property string soundcoreScriptPath: Quickshell.shellPath("scripts/soundcore/soundcore_anc.sh")

    function isHeadsetSupported(device) {
        if (!device) return false;
        let name = (device.name || "").toLowerCase();
        return name.includes("soundcore") || name.includes("life q30") || name.includes("q30");
    }

    function getModeForMac(mac) {
        return deviceModes[mac] || "Normal";
    }

    function updateDeviceMode(mac, mode) {
        let copy = Object.assign({}, deviceModes);
        copy[mac] = mode;
        deviceModes = copy; // Trigger QML property updates
    }

    function setMode(mac, mode) {
        // Support single argument calls like setMode(mode) by defaulting to activeDevice.address
        if (arguments.length === 1 || mode === undefined) {
            mode = mac;
            mac = activeDevice ? activeDevice.address : "";
        }

        if (!mac)
            return;

        Quickshell.execDetached([soundcoreScriptPath, "set", mac, mode]);

        // Optimistic update for immediate visual feedback
        updateDeviceMode(mac, mode);
    }

    function refreshMode(mac) {
        if (mac === undefined) {
            refreshAllConnected();
            return;
        }

        // Spawn a lightweight, isolated process to poll the specific headset
        processComponent.createObject(root, {
            "mac": mac
        });
    }

    function refreshAllConnected() {
        for (let d of BluetoothStatus.connectedDevices) {
            if (isHeadsetSupported(d)) {
                refreshMode(d.address);
            }
        }
    }

    // Isolated dynamic process component to handle concurrent polling without race conditions
    Component {
        id: processComponent
        Process {
            id: proc
            property string mac: ""

            command: [soundcoreScriptPath, "get", mac]
            running: true

            stdout: StdioCollector {
                onStreamFinished: {
                    let trimmed = text.trim();
                    if (trimmed.length > 0) {
                        root.updateDeviceMode(proc.mac, trimmed);
                    }
                    proc.destroy(); // Auto-free memory upon completion
                }
            }
        }
    }

    onIsConnectedChanged: {
        if (isConnected) {
            refreshAllConnected();
        }
    }
}
