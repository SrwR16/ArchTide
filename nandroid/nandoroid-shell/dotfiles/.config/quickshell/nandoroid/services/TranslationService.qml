pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../core"
import "../core/functions" as Functions

/**
 * TranslationService.qml
 * Ported logic from ii: handles text translation using 'translate-shell' (trans).
 *
 * Uses an engine fallback system: the request is attempted with each engine
 * in order until one succeeds. If Google is rate limited (trans exits 0 but
 * returns nothing), the next engine (e.g. Bing) is tried automatically.
 */
Singleton {
    id: root

    property string translatedText: ""
    property string detectedLanguage: ""
    property bool isTranslating: translateProc.running
    property var availableLanguages: ["auto", "en", "id", "ja", "zh", "ko", "fr", "de", "es", "it", "ru", "pt"]
    property var languageNamesMap: ({})
    
    // Track current active query to prevent race conditions on clear
    property string currentQuery: ""

    // --- Engine fallback ---
    // Ordered by preference; on failure/rate limit the next engine is tried.
    // Bing is the only dependable free fallback; yandex/apertium are broken
    // or too limited to be worth the added latency.
    readonly property var engines: ["google", "bing"]
    readonly property var engineDisplayNames: ({ "google": "Google", "bing": "Bing" })
    // Engine that last succeeded; tried first on subsequent requests ("sticky")
    property string preferredEngine: "google"
    // Engine that produced the latest successful result ("" if none)
    property string lastEngine: ""

    // Request status feedback for UI: "idle" | "ok" | "failed"
    property string status: "idle"

    // Internal: params of the in-flight request
    property string pendingSource: ""
    property string pendingTarget: ""
    property int requestId: 0

    function engineOrder() {
        const preferred = root.engines.includes(root.preferredEngine) ? root.preferredEngine : root.engines[0];
        return [preferred, ...root.engines.filter(e => e !== preferred)];
    }

    /**
     * Builds a bash script that loops over the engines in order.
     * Protocol on stdout:
     *   Line 1: "__OK__:<engine>" or "__FAIL__"
     *   Line 2 (only when source is auto): detected language code
     *   Remaining lines: the translation itself
     */
    function buildCommand(text, source, target) {
        const esc = Functions.StringUtils.shellSingleQuoteEscape;
        const qText = `'${esc(text)}'`;
        const qSource = `'${esc(source)}'`;
        const qTarget = `'${esc(target)}'`;
        const order = root.engineOrder();

        let lines = [];
        if (source === "auto") {
            lines.push(`DET_CODE=''`);
        }
        for (let i = 0; i < order.length; i++) {
            const eng = `'${esc(order[i])}'`;
            if (source === "auto") {
                lines.push(`if [ -z "$DET_CODE" ]; then DET_CODE=$(trans -e ${eng} -identify -no-ansi -- ${qText} 2>/dev/null | awk '/Code/{print $2; exit}'); fi`);
            }
            lines.push(`RES=$(trans -brief -e ${eng} -s ${qSource} -t ${qTarget} -- ${qText} 2>/dev/null)`);
            lines.push(`RC=$?`);
            // trans exits 0 even when rate limited, so also require a non-empty result
            lines.push(`if [ $RC -eq 0 ] && [ -n "$RES" ]; then printf '__OK__:${order[i]}\\n'; if [ -n "$DET_CODE" ]; then printf '%s\\n' "$DET_CODE"; fi; printf '%s\\n' "$RES"; exit 0; fi`);
        }
        lines.push(`printf '__FAIL__\\n'`);
        lines.push(`exit 1`);

        return ["bash", "-c", lines.join("\n")];
    }

    function translate(text, source, target) {
        const cleanText = (text || "").trim();
        root.currentQuery = cleanText;
        if (cleanText.length === 0) {
            if (translateProc.running) translateProc.running = false;
            root.translatedText = "";
            root.detectedLanguage = "";
            root.lastEngine = "";
            root.status = "idle";
            return;
        }
        
        if (translateProc.running) translateProc.running = false;

        const s = source || "auto";
        const t = target || "en";

        root.requestId++;
        translateProc.requestId = root.requestId;
        root.pendingSource = s;
        root.pendingTarget = t;
        root.detectedLanguage = "";
        root.status = "idle";

        translateProc.command = buildCommand(cleanText, s, t);
        translateProc.buffer = "";
        translateProc.succeeded = false;
        translateProc.headerDone = false;
        translateProc.expectCode = false;
        
        translateProc.running = true;
    }

    Process {
        id: translateProc
        command: []
        running: false
        property string buffer: ""
        property int requestId: -1
        property bool succeeded: false
        property bool headerDone: false
        property bool expectCode: false
        stdout: SplitParser {
            onRead: (line) => {
                const textLine = line.toString();
                if (!translateProc.headerDone) {
                    translateProc.headerDone = true;
                    if (textLine.startsWith("__OK__:")) {
                        translateProc.succeeded = true;
                        root.lastEngine = textLine.substring("__OK__:".length);
                        translateProc.expectCode = (root.pendingSource === "auto");
                    }
                    return;
                }
                if (translateProc.expectCode) {
                    translateProc.expectCode = false;
                    root.detectedLanguage = textLine.trim();
                    return;
                }
                if (translateProc.buffer === "") {
                    translateProc.buffer = textLine;
                } else {
                    translateProc.buffer += "\n" + textLine;
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim().length > 0) {
                    console.error("[TranslationService] stderr:", this.text.trim());
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            // Ignore stale exits from cancelled/older requests
            if (translateProc.requestId !== root.requestId || root.currentQuery.length === 0) return;

            if (translateProc.succeeded && exitCode === 0) {
                root.translatedText = translateProc.buffer.trim();
                if (root.lastEngine !== "") root.preferredEngine = root.lastEngine;
                root.status = "ok";
            } else {
                console.error("[TranslationService] All engines failed (rate limit or unavailable). Exit code:", exitCode);
                root.translatedText = "";
                root.status = "failed";
            }
        }
    }

    // Dynamic fetch to expand the list and get English names
    Process {
        id: getLangsProc
        command: ["trans", "-list-all", "-no-ansi", "-no-bidi"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const output = this.text.trim();
                if (output.length > 0) {
                    let lines = output.split('\n');
                    let codes = [];
                    let map = {};
                    
                    const regex = /^([a-z]{2,3}(?:-[A-Za-z]+)?)\s+(.+?)\s{2,}(.+)$/i;
                    
                    for (let i = 0; i < lines.length; i++) {
                        let match = lines[i].match(regex);
                        if (match && match[1] && match[2]) {
                            let code = match[1];
                            let name = match[2].trim();
                            if (code !== "auto") {
                                codes.push(code);
                                map[code] = name;
                            }
                        }
                    }
                    
                    codes.sort();
                    if (codes.length > 5) {
                        root.languageNamesMap = map;
                        root.availableLanguages = ["auto", ...codes];
                    }
                }
            }
        }
    }
}
