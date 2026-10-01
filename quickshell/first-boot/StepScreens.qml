// Atrium screen 2, "Which screen is in front of you?" (simple-mode.md 3.2,
// mockup simple-firstboot-2-screens.html). Shown on every screen at once,
// each with its own number; the screen whose `This one` is clicked becomes
// the main one. Nobody answers in 60 s: the laptop's screen or the largest.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: step
    property var wiz
    property Theme theme
    property string screenName: ""
    property bool busy: false

    readonly property var ordered: wiz && wiz.st
        ? wiz.st.monitors.slice().sort((a, b) => a.x - b.x || a.y - b.y) : []
    readonly property int number: ordered.findIndex(m => m.name === screenName) + 1

    width: 520
    implicitHeight: col.implicitHeight + 80
    radius: 20
    color: theme ? Qt.rgba(theme.basalt.r, theme.basalt.g, theme.basalt.b, 0.97) : "transparent"
    border.width: 1
    border.color: theme ? theme.line : "transparent"

    function choose(name) {
        if (busy) return
        busy = true
        wiz.call(name === "" ? ["monitors-write", "auto"] : ["monitors-write", name], "", (code, o) => {
            busy = false
            if (o.ok) {
                wiz.mainScreen = o.main
                wiz.monitorsWritten = true
            }
            wiz.next()
        })
    }

    Timer {
        // one timer is enough: only the main screen's copy runs it
        interval: 60000
        running: step.wiz !== undefined && step.wiz !== null && step.screenName === step.wiz.mainScreen
        onTriggered: step.choose("")
    }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 32 }
        spacing: 0
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: step.wiz ? step.wiz.stepLine : ""
            font.family: step.theme ? step.theme.sans : ""
            font.pixelSize: 14
            color: step.theme ? step.theme.ash : "grey"
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 10
            text: "Which screen is in front of you?"
            font.family: step.theme ? step.theme.sans : ""
            font.pixelSize: 26
            font.weight: Font.Medium
            color: step.theme ? step.theme.marble : "white"
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 400
            Layout.topMargin: 8
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "Click the button on that screen. Your taskbar and new windows will go there."
            font.family: step.theme ? step.theme.sans : ""
            font.pixelSize: 16
            color: step.theme ? step.theme.parchment : "grey"
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 12
            text: step.number > 0 ? String(step.number) : ""
            font.family: step.theme ? step.theme.sans : ""
            font.pixelSize: 150
            font.weight: Font.Light
            color: step.theme ? step.theme.marble : "white"
        }
        SetupButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 8
            Layout.preferredWidth: 140
            Layout.preferredHeight: 56
            theme: step.theme
            gold: true
            label: "This one"
            enabled_: !step.busy
            onClicked: step.choose(step.screenName)
        }
    }
}
