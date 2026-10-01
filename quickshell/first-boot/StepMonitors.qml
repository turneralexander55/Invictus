pragma ComponentBehavior: Bound
// Tessera step 1, monitors (design.md 2.3): the screens Hyprland sees, drawn
// to scale; drag them into place, click one to make it the main screen.
// Next writes ~/.config/hypr/monitors.lua through `monitors-write` (backup,
// config check, reload). Shown only with more than one screen.
import QtQuick
import QtQuick.Layouts

Card {
    id: step
    property var wiz
    property string screenName: ""
    property string main: ""
    property var pos: ({})          // name -> [x, y] in layout pixels

    readonly property var mons: wiz && wiz.st ? wiz.st.monitors : []
    // logical size: rotated screens swap sides; the scale shrinks them
    function lw(m) { return Math.round((m.transform % 2 ? m.height : m.width) / (m.scale || 1)) }
    function lh(m) { return Math.round((m.transform % 2 ? m.width : m.height) / (m.scale || 1)) }
    // offsets that centre the starting layout in the desk (they depend on
    // the screens, not on where they are dragged, so nothing jumps)
    // the starting layout's bounding box, from where Hyprland put the screens
    readonly property var box0: {
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
        for (const m of mons) {
            x0 = Math.min(x0, m.x); y0 = Math.min(y0, m.y)
            x1 = Math.max(x1, m.x + lw(m)); y1 = Math.max(y1, m.y + lh(m))
        }
        return mons.length ? [x0, y0, x1 - x0, y1 - y0] : [0, 0, 0, 0]
    }
    readonly property real ox: Math.max(24, (desk.width - box0[2] * k) / 2) - box0[0] * k
    readonly property real oy: Math.max(24, (desk.height - box0[3] * k) / 2) - box0[1] * k
    readonly property real k: {
        let w = 0, h = 0
        for (const m of mons) { w += lw(m); h = Math.max(h, lh(m)) }
        return w > 0 ? Math.min(720 / (w * 1.4), 260 / (h * 1.6)) : 0.1
    }

    wide: true
    step: wiz ? wiz.stepLine : ""
    heading: "Arrange your screens"
    body: "Drag them to match your desk. Click the one with your bar and new windows."
    backVisible: wiz && wiz.index > 0
    onBack: wiz.back()
    Component.onCompleted: {
        if (!wiz || !wiz.st) return
        main = wiz.mainScreen
        const p = {}
        for (const m of mons) p[m.name] = [m.x, m.y]
        pos = p
    }
    onNext: {
        // normalise so the top-left screen is at 0,0
        let minx = Infinity, miny = Infinity
        for (const m of mons) { minx = Math.min(minx, pos[m.name][0]); miny = Math.min(miny, pos[m.name][1]) }
        const args = ["monitors-write", main]
        for (const m of mons) args.push(m.name + "=" + (pos[m.name][0] - minx) + "," + (pos[m.name][1] - miny))
        busy = true
        wiz.call(args, "", (code, o) => {
            busy = false
            if (o.ok) {
                wiz.mainScreen = o.main
                wiz.monitorsWritten = true
                wiz.next()
            } else {
                note = "That layout didn't work. Your old one is back."
            }
        })
    }

    Rectangle {
        id: desk
        width: parent.width
        height: 300
        radius: 12
        color: step.theme.night
        border.color: step.theme.line

        Repeater {
            model: step.mons
            Rectangle {
                id: box
                required property var modelData
                required property int index
                readonly property bool isMain: modelData.name === step.main
                width: step.lw(modelData) * step.k
                height: step.lh(modelData) * step.k
                x: step.ox + (step.pos[modelData.name] ? step.pos[modelData.name][0] : 0) * step.k
                y: step.oy + (step.pos[modelData.name] ? step.pos[modelData.name][1] : 0) * step.k
                radius: 6
                color: step.theme.stone
                // the main screen is a choice, not "you are here": parchment,
                // like a picked setup card, so Continue stays the one gold
                border.width: isMain ? 2 : 1
                border.color: isMain ? step.theme.parchment : step.theme.line
                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        // the model ("DELL U2720Q") when Hyprland knows it
                        text: box.modelData.model || box.modelData.name
                        font.family: step.theme.sans
                        font.pixelSize: 15
                        font.weight: Font.Medium
                        color: step.theme.marble
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: (box.modelData.model ? box.modelData.name + "  ·  " : "")
                            + box.modelData.width + " × " + box.modelData.height + (box.isMain ? "  ·  main" : "")
                        font.family: step.theme.sans
                        font.pixelSize: 12
                        color: step.theme.parchment
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    drag.target: box
                    cursorShape: Qt.SizeAllCursor
                    onClicked: step.main = box.modelData.name
                    onReleased: {
                        const p = Object.assign({}, step.pos)
                        p[box.modelData.name] = [Math.round((box.x - step.ox) / step.k), Math.round((box.y - step.oy) / step.k)]
                        step.pos = p
                    }
                }
            }
        }
    }
}
