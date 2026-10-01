// A text field (52 px, stone, gold border while you type in it). `secret`
// hides what is typed; the text never leaves this field except on the
// command's stdin.
import QtQuick

Rectangle {
    id: field
    property Theme theme
    property string placeholder: ""
    property bool secret: false
    property alias text: input.text

    implicitHeight: 48
    radius: 10
    color: theme.stone
    border.width: 1
    border.color: input.activeFocus ? theme.sol : theme.line

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        verticalAlignment: TextInput.AlignVCenter
        font.family: field.theme.sans
        font.pixelSize: 16
        color: field.theme.marble
        selectionColor: field.theme.line
        echoMode: field.secret ? TextInput.Password : TextInput.Normal
        clip: true
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === ""
            text: field.placeholder
            font: input.font
            color: field.theme.ash
        }
    }
}
