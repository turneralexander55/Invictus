// The colour tokens (docs/look.md) for the first-start screens. Values come
// from ~/.config/invictus/current/qml-tokens.json, which invictus-theme
// writes from theme/templates/qml-tokens.json; the default theme, Nox Aurea, is
// the fallback before a theme has been applied.
import QtQuick

QtObject {
    property var tokens: ({})

    function tok(name, fallback) {
        return tokens && tokens[name] ? tokens[name] : fallback
    }

    readonly property color night: tok("night", "#0B0A08")
    readonly property color basalt: tok("basalt", "#131210")
    readonly property color stone: tok("stone", "#1E1C18")
    readonly property color line: tok("line", "#352F26")
    readonly property color marble: tok("marble", "#EFE6D2")
    readonly property color parchment: tok("parchment", "#C2B8A3")
    readonly property color ash: tok("ash", "#9A917F")
    readonly property color sol: tok("sol", "#D9A441")
    readonly property color solBright: tok("sol_bright", "#F2D38A")
    readonly property color pompeii: tok("pompeii", "#E0775E")
    readonly property color laurel: tok("laurel", "#9BB481")
    readonly property color lapis: tok("lapis", "#84A5D8")
    readonly property string wallpaper: tokens && tokens.wallpaper ? "file://" + tokens.wallpaper : ""

    readonly property string sans: "IBM Plex Sans"
    readonly property string serifCaps: "Cormorant SC"
}
