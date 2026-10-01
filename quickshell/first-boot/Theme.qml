// The colour tokens (docs/look.md) for the first-start screens. Values come
// from ~/.config/invictus/current/qml-tokens.json, which invictus-theme
// writes from theme/templates/qml-tokens.json; Dusk is the fallback before a
// theme has been applied.
import QtQuick

QtObject {
    property var tokens: ({})

    function tok(name, fallback) {
        return tokens && tokens[name] ? tokens[name] : fallback
    }

    readonly property color night: tok("night", "#14120F")
    readonly property color basalt: tok("basalt", "#1C1A16")
    readonly property color stone: tok("stone", "#27241F")
    readonly property color line: tok("line", "#3A352D")
    readonly property color marble: tok("marble", "#ECE6DA")
    readonly property color parchment: tok("parchment", "#BDB4A3")
    readonly property color ash: tok("ash", "#968E7F")
    readonly property color sol: tok("sol", "#E0A64B")
    readonly property color solBright: tok("sol_bright", "#F0C274")
    readonly property color pompeii: tok("pompeii", "#D9725A")
    readonly property color laurel: tok("laurel", "#94AD7B")
    readonly property color lapis: tok("lapis", "#7C9FD4")
    readonly property string wallpaper: tokens && tokens.wallpaper ? "file://" + tokens.wallpaper : ""

    readonly property string sans: "IBM Plex Sans"
    readonly property string serifCaps: "Cormorant SC"
}
