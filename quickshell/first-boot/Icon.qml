// A line icon from SVG path data on a 24-unit grid, stroked in one colour
// (the mockups' icons: round caps and joins). `paths` is a list of path
// strings, or [path, strokeWidth] pairs when one part is heavier (a dot).
// Same approach as Mark.qml, so a theme change only repaints.
import QtQuick

Canvas {
    id: icon
    property color color: "#ECE6DA"
    property real stroke: 1.8
    property var paths: []
    implicitWidth: 16
    implicitHeight: 16
    onColorChanged: requestPaint()
    onPathsChanged: requestPaint()
    onWidthChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        ctx.scale(width / 24, height / 24)
        ctx.strokeStyle = icon.color
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        for (const p of icon.paths) {
            const d = Array.isArray(p) ? p[0] : p
            ctx.lineWidth = Array.isArray(p) ? p[1] : icon.stroke
            ctx.beginPath()
            ctx.path = d
            ctx.stroke()
        }
    }
}
