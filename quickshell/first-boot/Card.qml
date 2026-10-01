// One setup card (simple-mode.md 3.1, the first-start mockups): basalt,
// radius 20, 640 px (880 wide), the mark, `Welcome · Step N of M`, the
// heading, one or two lines of body, the step's own content, then Back on
// the left and the one gold button on the right.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: card
    property Theme theme
    property bool wide: false
    property bool showMark: true
    property string step: ""
    property string heading: ""
    property string body: ""
    property string note: ""            // one line under the content (no-ai.md 2.2 step 4)
    property color noteColor: theme.parchment
    property string backLabel: "Back"
    property bool backVisible: true
    property string laterLabel: ""      // a second text button beside the gold one
    property string nextLabel: "Continue"
    property bool nextEnabled: true
    property bool busy: false
    default property alias content: slot.data
    signal back()
    signal later()
    signal next()

    width: wide ? 880 : 640
    implicitHeight: col.implicitHeight + 72
    radius: 20
    color: Qt.rgba(theme.basalt.r, theme.basalt.g, theme.basalt.b, 0.97)
    border.width: 1
    border.color: theme.line

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top }
        anchors.leftMargin: 48
        anchors.rightMargin: 48
        anchors.topMargin: 40
        spacing: 0

        Mark {
            visible: card.showMark
            color: card.theme.marble
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
        }
        Text {
            visible: card.step !== ""
            text: card.step
            font.family: card.theme.sans
            font.pixelSize: 13
            font.letterSpacing: 0.26
            color: card.theme.ash
            Layout.topMargin: card.showMark ? 22 : 0
        }
        Text {
            text: card.heading
            font.family: card.theme.sans
            font.pixelSize: 28
            font.weight: Font.Medium
            color: card.theme.marble
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Layout.topMargin: 6
        }
        Text {
            visible: card.body !== ""
            text: card.body
            font.family: card.theme.sans
            font.pixelSize: 17
            lineHeight: 1.3
            color: card.theme.parchment
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Layout.topMargin: 12
        }
        Item {
            id: slot
            Layout.fillWidth: true
            Layout.topMargin: children.length > 0 ? 24 : 0
            implicitHeight: childrenRect.height
        }
        Text {
            visible: card.note !== ""
            text: card.note
            font.family: card.theme.sans
            font.pixelSize: 15
            color: card.noteColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Layout.topMargin: 16
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 32
            Layout.bottomMargin: 32
            spacing: 8
            SetupButton {
                theme: card.theme
                text: true
                label: card.backLabel
                visible: card.backVisible
                enabled_: !card.busy
                onClicked: card.back()
            }
            Item { Layout.fillWidth: true }
            SetupButton {
                theme: card.theme
                text: true
                label: card.laterLabel
                visible: card.laterLabel !== ""
                enabled_: !card.busy
                onClicked: card.later()
            }
            SetupButton {
                id: nextButton
                theme: card.theme
                gold: true
                label: card.nextLabel
                enabled_: card.nextEnabled && !card.busy
                onClicked: card.next()
            }
        }
    }
}
