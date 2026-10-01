pragma ComponentBehavior: Bound
// invictus-first-boot: the first-start screens (design.md 2.3; Atrium:
// simple-mode.md 3.2; step 3: no-ai.md 2). Opened by
// `invictus-first-boot start`, which sets INVICTUS_FIRSTBOOT_CMD to itself.
// This file only draws: every decision, file and system change is a call to
// that command (one JSON line back), so the logic is tested without a screen.
//
// One window per screen, on the Bottom layer: the browser for the Claude
// sign-in and the password prompt open above it. The card sits on the main
// screen; "Which screen is in front of you?" shows on every screen.
//
// A step is a file Step<Name>.qml; the command lists which ones to show.
// Later releases (Collegium, Windows, voice, Atrium's Wi-Fi) add their file.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    // The command every call goes to (the key goes on its stdin). Installed
    // screens (under /usr/) always call the installed command; the variable
    // is honoured only from a checkout, for the render test (Janus L1).
    readonly property bool installed: String(Quickshell.shellDir).replace(/^file:\/\//, "").startsWith("/usr/")
    readonly property string command: installed ? "/usr/bin/invictus-first-boot"
        : (Quickshell.env("INVICTUS_FIRSTBOOT_CMD") || "invictus-first-boot")
    property var st: null                 // `invictus-first-boot state`
    property int index: 0
    property string choice: ""            // after step 3: "ai" or "none"
    property string mainScreen: ""
    property bool monitorsWritten: false
    property bool finishing: false

    Theme {
        id: theme
        tokens: root.st ? root.st.tokens : ({})
    }

    // Steps still to show: the ones that need AI drop out after No AI.
    readonly property var steps: {
        if (!st) return []
        return (st.steps || []).filter(s => !(s.needs_ai && choice === "none"))
    }
    readonly property var current: steps.length ? steps[Math.min(index, steps.length - 1)] : null
    readonly property string stepLine: current ? "Welcome · Step " + (index + 1) + " of " + steps.length : ""

    // ---- calls to the command --------------------------------------------------
    Component {
        id: callComponent
        Process {
            id: proc
            property var callback
            property string input: ""
            property int code: -1
            property bool exitedSeen: false
            property bool outSeen: false
            property string outText: ""
            stdinEnabled: input !== ""
            stdout: StdioCollector {
                onStreamFinished: { proc.outText = text; proc.outSeen = true; proc.settle() }
            }
            onStarted: if (input !== "") { write(input); input = ""; stdinEnabled = false }
            onExited: (exitCode, exitStatus) => { code = exitCode; exitedSeen = true; settle() }
            function settle() {
                if (!exitedSeen || !outSeen) return
                let obj = {}
                const lines = outText.trim().split("\n")
                try { obj = JSON.parse(lines[lines.length - 1]) } catch (e) { obj = { error: "no answer" } }
                if (callback) callback(code, obj)
                destroy()
            }
        }
    }

    function call(args, input, callback) {
        const p = callComponent.createObject(root, {
            command: [root.command].concat(args), input: input || "", callback: callback
        })
        p.running = true
    }

    function reload(then) {
        call(["state"], "", (code, obj) => {
            if (code === 0) {
                // the main screen first: setting st draws the step
                if (mainScreen === "") mainScreen = obj.auto_main || ""
                st = obj
                if (obj.render_preset) {
                    // Only the render test's fake command sends this.
                    choice = obj.render_preset.choice || choice
                    const i = obj.steps.findIndex(s => s.id === obj.render_preset.step)
                    if (i >= 0) index = i
                    // a call with stdin, to prove the input is closed after it
                    const c = obj.render_preset.call
                    if (c) call(c.args, c.input, () => {})
                }
            }
            if (then) then()
        })
    }

    function next() {
        if (index < steps.length - 1) index++
    }
    function back() {
        if (index > 0) index--
    }
    function finish() {
        if (finishing) return
        finishing = true
        // One screen and no monitors step: still write monitors.lua from
        // what Hyprland sees, so the file says what this computer has.
        const done = () => call(["finish"], "", () => Qt.quit())
        if (!monitorsWritten && st && st.monitors.length > 0)
            call(["monitors-write", "auto"], "", done)
        else
            done()
    }

    Component.onCompleted: reload()

    // ---- the screens -------------------------------------------------------------
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            readonly property bool isMain: modelData.name === root.mainScreen
                || (root.mainScreen === "" && Quickshell.screens.indexOf(modelData) === 0)
            readonly property bool everyScreen: root.current !== null && root.current.id === "screens"

            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "invictus-first-boot"
            WlrLayershell.keyboardFocus: isMain ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: theme.night

            // the wallpaper, faint (the mockups' `.wall.faint`)
            Image {
                anchors.fill: parent
                source: theme.wallpaper
                fillMode: Image.PreserveAspectCrop
                opacity: 0.6
                asynchronous: true
            }

            Row {
                x: 40
                y: 34
                spacing: 12
                visible: win.isMain && !win.everyScreen
                Mark { width: 26; height: 26; color: theme.marble }
                Text {
                    text: "INVICTUS"
                    font.family: theme.serifCaps
                    font.pixelSize: 20
                    font.weight: Font.Medium
                    font.letterSpacing: 3.6
                    color: theme.marble
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Loader {
                id: stepLoader
                // a new step file, or the same one on another screen: load it
                // with its properties set before its first binding runs
                readonly property string want: root.current !== null && (win.isMain || win.everyScreen)
                    ? root.current.qml + "#" + root.index : ""
                anchors.centerIn: parent
                onWantChanged: show()
                Component.onCompleted: show()
                function show() {
                    if (want === "") { source = ""; return }
                    setSource(root.current.qml, { wiz: root, theme: theme, screenName: win.modelData.name })
                }
            }
        }
    }
}
