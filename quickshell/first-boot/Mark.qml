// The Invictus mark (docs/look.md "The mark"): nine rays, the disc, the
// horizon, one colour. Drawn from the same 64-unit geometry as the SVG.
import QtQuick

Canvas {
    id: mark
    property color color: "#ECE6DA"
    implicitWidth: 44
    implicitHeight: 44
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()

    readonly property var rays: [
        [48.74, 40.95, 57.61, 42.51], [48.42, 33.60, 57.11, 31.27], [45.02, 27.07, 51.92, 21.29],
        [39.18, 22.59, 42.99, 14.44], [32.00, 21.00, 32.00, 12.00], [24.82, 22.59, 21.01, 14.44],
        [18.98, 27.07, 12.08, 21.29], [15.58, 33.60, 6.89, 31.27], [15.26, 40.95, 6.39, 42.51]
    ]

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const k = width / 64
        ctx.scale(k, k)
        ctx.strokeStyle = mark.color
        ctx.fillStyle = mark.color
        ctx.lineCap = "round"
        ctx.lineWidth = 3.5
        for (const r of rays) {
            ctx.beginPath()
            ctx.moveTo(r[0], r[1])
            ctx.lineTo(r[2], r[3])
            ctx.stroke()
        }
        ctx.beginPath()
        ctx.arc(32, 38, 12, 0, 2 * Math.PI)
        ctx.fill()
        ctx.beginPath()
        ctx.moveTo(6, 56)
        ctx.lineTo(58, 56)
        ctx.stroke()
    }
}
