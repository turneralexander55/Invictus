// A radio row: a title and a quiet line under it (the provider rows inside
// the AI card, and the Look step's rows).
import QtQuick
import QtQuick.Layouts

Item {
    id: row
    property Theme theme
    property bool checked: false
    property string title: ""
    property string line: ""
    signal clicked()

    Layout.fillWidth: true
    implicitHeight: lay.implicitHeight + 20
    activeFocusOnTab: true
    Keys.onSpacePressed: clicked()

    RowLayout {
        id: lay
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 12
        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            radius: 10
            color: "transparent"
            border.width: 2
            border.color: row.checked ? row.theme.marble : row.theme.ash
            Rectangle {
                anchors.centerIn: parent
                width: 10
                height: 10
                radius: 5
                color: row.theme.marble
                visible: row.checked
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3
            Text {
                Layout.fillWidth: true
                text: row.title
                font.family: row.theme.sans
                font.pixelSize: 16
                color: row.activeFocus ? row.theme.solBright : row.theme.marble
            }
            Text {
                visible: row.line !== ""
                text: row.line
                font.family: row.theme.sans
                font.pixelSize: 14
                color: row.theme.parchment
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: row.clicked()
    }
}
