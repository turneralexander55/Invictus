pragma ComponentBehavior: Bound
// The last step. Atrium: screen 4, "Three things to know" (simple-mode.md
// 3.2, mockup simple-firstboot-4-ready.html). Tessera: step 7's short tour
// (design.md 2.3), in the same card. `Start using Invictus` takes the
// "First boot done" safety copy through invictus-sys and closes.
import QtQuick
import QtQuick.Layouts

Card {
    id: step
    property var wiz
    property string screenName: ""

    readonly property bool atrium: wiz && wiz.st && wiz.st.flavor === "atrium"
    readonly property bool ai: wiz && (wiz.choice === "ai" || (wiz.choice === "" && wiz.st && wiz.st.ai === "on"))

    // [picture, title, line]; picture: "start", "close", "help", or a key label
    readonly property var things: atrium ? [
        ["start", "Start opens your apps", "Bottom left. Everything you need is in there."],
        ["close", "× closes a window", "Top right of every window. – puts it aside."],
        ["help", "Help is always here", ai ? "Ask a question by talking or typing."
                                           : "Guides for everyday things, and a way to ask Support."]
    ] : [
        ai ? ["Super + A", "Super + A opens Moneta", "Ask, or say what to change. It asks before it does anything."]
           : ["Super + Enter", "Super + Enter opens a terminal", "Super + Space opens the app launcher."],
        ["Super + /", "Super + / lists every shortcut", "Grouped, and searchable."],
        ["Snapshots", "Undo lives in the boot menu", "Pick Snapshots when the computer starts to go back to before a change."]
    ]

    wide: true
    step: wiz ? wiz.stepLine : ""
    heading: atrium ? "Three things to know" : "Before you start"
    nextLabel: "Start using Invictus"
    backVisible: false
    busy: wiz ? wiz.finishing : false
    onNext: wiz.finish()

    RowLayout {
        width: parent.width
        spacing: 16
        Repeater {
            model: step.things
            Rectangle {
                id: thing
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignTop
                // as tall as its words: a two-line title must not push the
                // line out of the card (the row takes the tallest of three)
                implicitHeight: pic.height + words.implicitHeight + 34
                radius: 14
                color: step.theme.stone
                Rectangle {
                    id: pic
                    width: parent.width
                    height: 120
                    topLeftRadius: thing.radius
                    topRightRadius: thing.radius
                    color: step.theme.night
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: step.theme.line
                    }
                    // Atrium: the real control, drawn small. Tessera: the keys.
                    Rectangle {
                        anchors.centerIn: parent
                        visible: thing.modelData[0] !== "close"
                        width: control.implicitWidth + 48
                        height: 54
                        radius: 10
                        color: step.theme.stone
                        Row {
                            id: control
                            anchors.centerIn: parent
                            spacing: 10
                            Mark {
                                visible: thing.modelData[0] === "start"
                                width: 24
                                height: 24
                                color: step.theme.marble
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Icon {
                                // the Help button's icon, in lapis
                                visible: thing.modelData[0] === "help"
                                width: 26
                                height: 26
                                color: step.theme.lapis
                                paths: ["M21 12a9 9 0 1 1-18 0a9 9 0 1 1 18 0",
                                        "M9.3 9.3a2.8 2.8 0 0 1 5.4 1c0 1.9-2.7 2.4-2.7 4",
                                        ["M12 17.3h.01", 2.4]]
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: thing.modelData[0] === "start" ? "Start"
                                    : thing.modelData[0] === "help" ? "Help" : thing.modelData[0]
                                font.family: step.theme.sans
                                font.pixelSize: 18
                                font.weight: Font.DemiBold
                                color: step.theme.marble
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                    // a window's title bar, drawn small (the mockup's bar)
                    Rectangle {
                        anchors.centerIn: parent
                        width: 232
                        height: 50
                        radius: 10
                        visible: thing.modelData[0] === "close"
                        color: step.theme.basalt
                        border.color: step.theme.line
                        Text {
                            x: 18
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Photos"
                            font.family: step.theme.sans
                            font.pixelSize: 16
                            font.weight: Font.Medium
                            color: step.theme.marble
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 9
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Repeater {
                                // minimise, maximise, close (ringed: the one this card is about)
                                model: [
                                    [["M5 12h14"], 2],
                                    [["M7 5.5h10a1.5 1.5 0 0 1 1.5 1.5v10a1.5 1.5 0 0 1-1.5 1.5H7a1.5 1.5 0 0 1-1.5-1.5V7A1.5 1.5 0 0 1 7 5.5z"], 1.8],
                                    [["M6 6l12 12", "M18 6 6 18"], 2]
                                ]
                                Rectangle {
                                    id: wb
                                    required property var modelData
                                    required property int index
                                    width: 32
                                    height: 32
                                    radius: 16
                                    color: step.theme.stone
                                    border.width: index === 2 ? 2 : 0
                                    border.color: step.theme.parchment
                                    Icon {
                                        anchors.centerIn: parent
                                        width: 18
                                        height: 18
                                        color: step.theme.marble
                                        paths: wb.modelData[0]
                                        stroke: wb.modelData[1]
                                    }
                                }
                            }
                        }
                    }
                }
                Column {
                    id: words
                    anchors { top: pic.bottom; left: parent.left; right: parent.right; margins: 18; topMargin: 16 }
                    spacing: 6
                    Text {
                        width: parent.width
                        text: thing.modelData[1]
                        font.family: step.theme.sans
                        font.pixelSize: 18
                        font.weight: Font.Medium
                        color: step.theme.marble
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        width: parent.width
                        text: thing.modelData[2]
                        font.family: step.theme.sans
                        font.pixelSize: 15
                        lineHeight: 1.2
                        color: step.theme.parchment
                        wrapMode: Text.WordWrap
                    }
                }
                // the border, over the picture
                Rectangle {
                    anchors.fill: parent
                    radius: thing.radius
                    color: "transparent"
                    border.color: step.theme.line
                }
            }
        }
    }
}
