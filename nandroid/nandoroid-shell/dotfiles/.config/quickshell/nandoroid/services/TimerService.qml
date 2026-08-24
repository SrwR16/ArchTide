pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../services"


Singleton {
    id: root

    property bool active: false
    property bool overflowing: false
    
    // Configurable, saved via settings
    property int setSeconds: 0


    property double targetTimestamp: 0
    property double remainingMs: setSeconds * 1000

    readonly property real progress: (setSeconds > 0 && !overflowing) ? Math.min(1.0, Math.max(0.0, Math.ceil(remainingMs / 1000) / setSeconds)) : 0

    readonly property bool isNegative: Math.ceil(remainingMs / 1000) < 0

    readonly property string timeString: formatTime(remainingMs)

    function formatTime(ms) {
        let s = Math.ceil(ms / 1000);
        let absS = Math.abs(s);
        const h = Math.floor(absS / 3600);
        const m = Math.floor((absS % 3600) / 60);
        const secs = absS % 60;
        
        const sign = (s < 0) ? "-" : "";
        if (h > 0) {
            return `${sign}${h}:${m.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
        } else if (m > 0) {
            return `${sign}${m}:${secs.toString().padStart(2, '0')}`;
        } else {
            return `${sign}${secs}`;
        }
    }

    function start() {
        if (setSeconds <= 0) return;
        
        if (remainingMs <= 0 && !overflowing) {
            remainingMs = setSeconds * 1000;
        }

        const now = Date.now();
        targetTimestamp = now + remainingMs;
        active = true;
    }

    function pause() {
        if (!active) return;
        active = false;
        // remainingMs is updated by the timer up to the last tick
    }

    function stop() {
        active = false;
        reset();
    }

    function reset() {
        active = false;
        overflowing = false;
        remainingMs = setSeconds * 1000;
        alarmProcess.running = false;
    }

    function setDuration(seconds) {
        setSeconds = seconds;
        reset();
    }

    function addMinute() {
        remainingMs += 60000;
        if (active) {
            targetTimestamp += 60000;
        }
        if (remainingMs > 0 && overflowing) {
            overflowing = false;
        }
    }

    Timer {
        id: timer
        interval: 100
        repeat: true
        running: root.active
        onTriggered: {
            const now = Date.now();
            root.remainingMs = root.targetTimestamp - now;
            
            if (root.remainingMs <= 0 && !root.overflowing) {
                root.overflowing = true;
                alarmProcess.running = true;
            }
        }
    }

    Process {
        id: alarmProcess
        command: ["ffplay", "-nodisp", "-autoexit", "-loop", "0", `/usr/share/sounds/${Audio.audioTheme}/stereo/alarm-clock-elapsed.oga`]
    }
}
