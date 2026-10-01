pragma ComponentBehavior: Bound
// Tessera step 2, look (design.md 2.3; docs/look.md): the theme (Dusk, the
// Roman one, by default), motion (Showcase by default in Tessera) and
// whether apps are light or dark. Next applies all three through
// invictus-theme, invictus-motion and gsettings.
import QtQuick
import QtQuick.Layouts

Card {
    id: step
    property var wiz
    property string screenName: ""
    property string theme_: ""
    property string motion: "showcase"
    property string apps: "dark"

    readonly property var themes: wiz && wiz.st ? wiz.st.themes : []

    wide: true
    step: wiz ? wiz.stepLine : ""
    heading: "Choose a look"
    body: "You can change all of this later in Settings > Look."
    backVisible: wiz && wiz.index > 0
    onBack: wiz.back()
    Component.onCompleted: {
        if (!wiz || !wiz.st) return
        const cur = themes.find(t => t.current) || themes.find(t => t.id === "dusk") || themes[0]
        theme_ = cur ? cur.id : "dusk"
        motion = wiz.st.motion || "showcase"
        apps = wiz.st.apps || "dark"
    }
    onNext: {
        busy = true
        wiz.call(["look", theme_, motion, apps], "", (code, o) => {
            busy = false
            wiz.reload()
            if (o.ok) wiz.next()
            else note = "Part of that didn't apply. You can change it later in Settings > Look."
        })
    }

    component Segments: Row {
        id: seg
        property var options: []        // [[value, label]]
        property string value: ""
        signal picked(string v)
        spacing: 8
        Repeater {
            model: seg.options
            SetupButton {
                required property var modelData
                theme: step.theme
                implicitHeight: 44
                size: 15
                label: modelData[1]
                border.width: seg.value === modelData[0] ? 2 : 1
                border.color: seg.value === modelData[0] ? step.theme.parchment : step.theme.line
                onClicked: seg.picked(modelData[0])
            }
        }
    }

    GridLayout {
        width: parent.width
        columns: 2
        columnSpacing: 32
        rowSpacing: 16

        Text { text: "Theme"; font.family: step.theme.sans; font.pixelSize: 15; color: step.theme.parchment; Layout.alignment: Qt.AlignTop; Layout.topMargin: 10 }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Repeater {
                model: step.themes
                Radio {
                    required property var modelData
                    theme: step.theme
                    checked: step.theme_ === modelData.id
                    title: modelData.name
                    onClicked: step.theme_ = modelData.id
                }
            }
        }

        Text { text: "Motion"; font.family: step.theme.sans; font.pixelSize: 15; color: step.theme.parchment; Layout.alignment: Qt.AlignVCenter }
        Segments {
            options: [["showcase", "Showcase"], ["calm", "Calm"], ["off", "Off"]]
            value: step.motion
            onPicked: v => step.motion = v
        }

        Text { text: "Apps"; font.family: step.theme.sans; font.pixelSize: 15; color: step.theme.parchment; Layout.alignment: Qt.AlignVCenter }
        Segments {
            options: [["dark", "Dark"], ["light", "Light"]]
            value: step.apps
            onPicked: v => step.apps = v
        }
    }
}
