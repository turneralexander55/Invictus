pragma ComponentBehavior: Bound
// Step 3, "How should Help work?": the screen and flow in no-ai.md 2 (the
// single source), both flavors. Two cards, neither picked; Claude
// preselected inside the AI card; the gold button says what it does.
// After `Sign in to Claude`: the password (the polkit agent draws it, over
// this screen), then Claude's own sign-in in the browser, then the next step.
import QtQuick
import QtQuick.Layouts

Card {
    id: step
    property var wiz
    property string screenName: ""

    property string picked: ""           // "", "ai" or "none": never preselected
    property string provider: "claude"   // inside the AI card: preselected (D13)
    property bool otherOpen: false
    property bool failedSignIn: false    // 2.2 step 4: Not signed in yet
    property string addressProblem: ""   // the provider layer did not take the address or key
    property string problem: ""

    readonly property bool aiOnAlready: wiz && wiz.st && wiz.st.ai === "on"
    readonly property bool ready: picked === "none"
        || (picked === "ai" && (provider === "claude"
            || (provider === "home" && address.text.trim() !== "")
            || (provider === "other" && otherAddress.text.trim() !== "" && key.text !== "")))

    wide: true
    step: wiz ? wiz.stepLine : ""
    heading: "How should Help work?"
    body: "Help is the button at the bottom right of the screen. You can change this later in Settings."
    nextLabel: picked === "ai" && provider === "claude" ? "Sign in to Claude" : "Continue"
    nextEnabled: ready
    backVisible: wiz && wiz.index > 0
    laterLabel: failedSignIn || addressProblem !== "" ? "Later" : ""
    note: busy ? "Adding Moneta. This can take a few minutes."
        : failedSignIn ? "Not signed in yet. You can try again now, or sign in later from Help."
        : addressProblem !== "" ? addressProblem
        : problem
    noteColor: problem !== "" && !busy && !failedSignIn && addressProblem === "" ? theme.pompeii : theme.parchment

    Component.onCompleted: {
        // Only tests/firstboot/qml.sh's fake command sends render_preset, to
        // draw the picked states; the real command never does.
        const pre = wiz && wiz.st ? wiz.st.render_preset : null
        if (pre && pre.pick) picked = pre.pick
    }

    function pickAi(p) {
        picked = "ai"
        if (p) provider = p
        failedSignIn = false
        addressProblem = ""
        problem = ""
    }

    onBack: wiz.back()
    onLater: { wiz.choice = "ai"; wiz.next() }
    onNext: {
        problem = ""
        if (picked === "none") {
            busy = true
            wiz.call(["assistant", "none"], "", (code, o) => {
                busy = false
                if (code === 0 && o.result === "ok") { wiz.choice = "none"; wiz.next() }
                else problem = "That didn't work. Try again, or ask Support."
            })
            return
        }
        if (provider === "claude" && aiOnAlready && failedSignIn) {
            signIn()
            return
        }
        const args = ["assistant", provider]
        if (provider === "home") args.push("--address", address.text.trim())
        if (provider === "other") args.push("--address", otherAddress.text.trim())
        busy = true
        wiz.call(args, provider === "other" ? key.text : "", (code, o) => {
            busy = false
            if (provider === "other") key.text = ""
            if (code !== 0) { problem = "That didn't work. Try again, or ask Support."; return }
            if (o.result === "cancelled") return               // nothing changed, card still picked
            if (o.result === "ok" || o.result === "pending") {
                wiz.reload()
                wiz.choice = "ai"
                if (provider === "claude") {
                    if (o.result === "pending") failedSignIn = true    // no connection: sign in later
                    else signIn()
                } else {
                    wiz.next()
                }
                return
            }
            // Moneta is on; only its settings did not take
            wiz.reload()
            wiz.choice = "ai"
            if (o.result === "provider-refused") {
                addressProblem = "That address can't be used. Check it, or ask Support."
                return
            }
            if (o.result === "provider-failed") {
                addressProblem = "The key couldn't be saved. Try again, or ask Support."
                return
            }
            problem = "Moneta couldn't be added. Try again, or ask Support."
        })
    }

    function signIn() {
        busy = true
        wiz.call(["signin"], "", (code, o) => {
            busy = false
            if (o.signed_in) wiz.next()
            else failedSignIn = true
        })
    }

    RowLayout {
        width: parent.width
        spacing: 16

        // ---- An AI assistant ----
        ChoiceCard {
            theme: step.theme
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            Layout.fillHeight: true
            picked: step.picked === "ai"
            title: "An AI assistant"
            line: "Moneta answers questions, by voice or typing, and fixes things after asking you."
            onPick: step.pickAi("")
            picture: Rectangle {
                anchors.centerIn: parent
                width: 250
                height: 122
                radius: 10
                color: step.theme.basalt
                border.color: step.theme.line
                Rectangle {
                    x: parent.width - width - 12
                    y: 10
                    width: ask.implicitWidth + 18
                    height: ask.implicitHeight + 12
                    radius: 9
                    color: step.theme.stone
                    Text {
                        id: ask
                        anchors.centerIn: parent
                        text: "The printer isn't printing"
                        font.family: step.theme.sans
                        font.pixelSize: 12
                        color: step.theme.marble
                    }
                }
                Text {
                    x: 12
                    y: 52
                    width: 190
                    text: "It's out of paper. Add some and I'll send the page again."
                    font.family: step.theme.sans
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    color: step.theme.marble
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 14
                height: 1
                color: step.theme.line
            }
            Radio {
                theme: step.theme
                Layout.topMargin: 6
                checked: step.provider === "claude"
                title: "Claude (your own account)"
                line: "Anthropic's Claude. You sign in next."
                onClicked: step.pickAi("claude")
            }
            Radio {
                theme: step.theme
                checked: step.provider === "home"
                title: "A home AI system"
                line: "An AI on this computer or your home network. Nothing leaves your home."
                onClicked: step.pickAi("home")
            }
            RowLayout {
                visible: step.provider === "home"
                Layout.fillWidth: true
                Layout.leftMargin: 32
                spacing: 8
                Field {
                    id: address
                    theme: step.theme
                    Layout.fillWidth: true
                    placeholder: "Address, like atlas.local"
                }
            }
            Item {
                Layout.fillWidth: true
                Layout.topMargin: 6
                implicitHeight: 28
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (step.otherOpen ? "⌄  " : "›  ") + "Another AI"
                    font.family: step.theme.sans
                    font.pixelSize: 14
                    color: step.theme.parchment
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: step.otherOpen = !step.otherOpen
                }
            }
            Radio {
                theme: step.theme
                visible: step.otherOpen
                checked: step.provider === "other"
                title: "Another AI service"
                line: "An account you already have with another AI company. It answers; it can't do things by itself."
                onClicked: step.pickAi("other")
            }
            ColumnLayout {
                visible: step.otherOpen && step.provider === "other"
                Layout.fillWidth: true
                Layout.leftMargin: 32
                spacing: 8
                Field {
                    id: otherAddress
                    theme: step.theme
                    Layout.fillWidth: true
                    placeholder: "Address of the service"
                }
                Field {
                    id: key
                    theme: step.theme
                    Layout.fillWidth: true
                    secret: true
                    placeholder: "Key"
                }
            }
        }

        // ---- No AI ----
        ChoiceCard {
            theme: step.theme
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            Layout.fillHeight: true
            picked: step.picked === "none"
            title: "No AI"
            line: "Short how-to guides you can search, and Support when you need a person. Nothing on this computer uses AI."
            onPick: { step.picked = "none"; step.failedSignIn = false; step.addressProblem = ""; step.problem = "" }
            picture: Rectangle {
                anchors.centerIn: parent
                width: 250
                height: 122
                radius: 10
                color: step.theme.basalt
                border.color: step.theme.line
                Column {
                    x: 12
                    y: 10
                    width: parent.width - 24
                    spacing: 0
                    Rectangle {
                        width: parent.width
                        height: 24
                        radius: 6
                        color: step.theme.stone
                        Row {
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Icon {
                                width: 11
                                height: 11
                                anchors.verticalCenter: parent.verticalCenter
                                color: step.theme.ash
                                paths: ["M16.5 10.5a6 6 0 1 1-12 0a6 6 0 1 1 12 0", "m15 15 5 5"]
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "What do you need help with?"
                                font.family: step.theme.sans
                                font.pixelSize: 11
                                color: step.theme.ash
                            }
                        }
                    }
                    Item { width: 1; height: 6 }
                    // the guides, each with its icon (the mockup's printer,
                    // Wi-Fi and go-back icons), so the picture reads as a list
                    // you can click and not as a paragraph
                    Repeater {
                        model: [
                            ["Print something", ["M7 9V4h10v5", "M5.5 9h13a2 2 0 0 1 2 2v3.5a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2V11a2 2 0 0 1 2-2z", "M7 14h10v6H7z"]],
                            ["Connect to Wi-Fi", ["M2.5 9a14 14 0 0 1 19 0", "M5.5 12.3a9.5 9.5 0 0 1 13 0", "M8.6 15.5a5 5 0 0 1 6.8 0", ["M12 18.8h.01", 2.6]]],
                            ["Get a deleted file back", ["M4.5 12a7.5 7.5 0 1 0 2.2-5.3L4.5 9", "M4.5 4.5V9H9", "M12 8v4.3l3 1.7"]]
                        ]
                        Row {
                            id: guide
                            required property var modelData
                            height: 24
                            spacing: 8
                            Icon {
                                width: 14
                                height: 14
                                anchors.verticalCenter: parent.verticalCenter
                                stroke: 1.7
                                color: step.theme.parchment
                                paths: guide.modelData[1]
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: guide.modelData[0]
                                font.family: step.theme.sans
                                font.pixelSize: 12
                                color: step.theme.marble
                            }
                        }
                    }
                }
            }
        }
    }
}
