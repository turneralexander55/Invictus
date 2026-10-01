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
    property bool homeThisComputer: false
    property bool failedSignIn: false    // 2.2 step 4: Not signed in yet
    property string unreachable: ""      // a home AI address that did not answer
    property string problem: ""

    readonly property bool aiOnAlready: wiz && wiz.st && wiz.st.ai === "on"
    readonly property bool ready: picked === "none"
        || (picked === "ai" && (provider === "claude"
            || (provider === "home" && (homeThisComputer || address.text.trim() !== ""))
            || (provider === "other" && key.text !== "")))

    wide: true
    step: wiz ? wiz.stepLine : ""
    heading: "How should Help work?"
    body: "Help is the button at the bottom right of the screen. You can change this later in Settings."
    nextLabel: picked === "ai" && provider === "claude" ? "Sign in to Claude" : "Continue"
    nextEnabled: ready
    backVisible: wiz && wiz.index > 0
    laterLabel: failedSignIn || unreachable !== "" ? "Later" : ""
    note: busy ? "Adding Moneta. This can take a few minutes."
        : failedSignIn ? "Not signed in yet. You can try again now, or sign in later from Help."
        : unreachable !== "" ? "Can't reach " + unreachable + ". Check the address, or ask Support."
        : problem
    noteColor: problem !== "" && !busy && !failedSignIn && unreachable === "" ? theme.pompeii : theme.parchment

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
        unreachable = ""
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
        if (provider === "home") {
            if (homeThisComputer) args.push("--this-computer")
            else args.push("--address", address.text.trim())
        }
        if (provider === "other" && otherAddress.text.trim() !== "") args.push("--address", otherAddress.text.trim())
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
            if (o.result === "provider-failed" && provider === "home" && !homeThisComputer) {
                unreachable = address.text.trim()
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
                    visible: !step.homeThisComputer
                    placeholder: "Address, like atlas.local"
                }
                SetupButton {
                    theme: step.theme
                    visible: step.provider === "home" && step.wiz && step.wiz.st && step.wiz.st.this_computer
                    implicitHeight: 44
                    size: 15
                    label: step.homeThisComputer ? "Use an address" : "Use this computer"
                    onClicked: { step.homeThisComputer = !step.homeThisComputer; step.pickAi("home") }
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
            onPick: { step.picked = "none"; step.failedSignIn = false; step.unreachable = ""; step.problem = "" }
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
                        Text {
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: "What do you need help with?"
                            font.family: step.theme.sans
                            font.pixelSize: 11
                            color: step.theme.ash
                        }
                    }
                    Item { width: 1; height: 6 }
                    Repeater {
                        model: ["Print something", "Connect to Wi-Fi", "Get a deleted file back"]
                        Text {
                            required property string modelData
                            height: 24
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 22
                            text: modelData
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
