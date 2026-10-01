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
                implicitHeight: 228
                radius: 14
                color: step.theme.stone
                border.color: step.theme.line
                clip: true
                Rectangle {
                    id: pic
                    width: parent.width
                    height: 120
                    color: step.theme.night
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
                            Rectangle {
                                // the Help button's icon: a lapis ring with a ?
                                visible: thing.modelData[0] === "help"
                                width: 22
                                height: 22
                                radius: 11
                                color: "transparent"
                                border.width: 2
                                border.color: step.theme.lapis
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    anchors.centerIn: parent
                                    text: "?"
                                    font.family: step.theme.sans
                                    font.pixelSize: 14
                                    font.weight: Font.Bold
                                    color: step.theme.lapis
                                }
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
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 44
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
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Repeater {
                                model: ["–", "□", "×"]
                                Rectangle {
                                    required property string modelData
                                    required property int index
                                    width: 36
                                    height: 36
                                    radius: 18
                                    color: step.theme.stone
                                    border.width: index === 2 ? 2 : 0
                                    border.color: step.theme.marble
                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.modelData
                                        font.pixelSize: 16
                                        color: step.theme.marble
                                    }
                                }
                            }
                        }
                    }
                }
                Column {
                    anchors { top: pic.bottom; left: parent.left; right: parent.right; margins: 18 }
                    spacing: 6
                    Text {
                        width: parent.width
                        text: thing.modelData[1]
                        font.family: step.theme.sans
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        color: step.theme.marble
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        width: parent.width
                        text: thing.modelData[2]
                        font.family: step.theme.sans
                        font.pixelSize: 15
                        color: step.theme.parchment
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
