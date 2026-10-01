// The setup screens' buttons (simple-mode.md 3.1): `gold` is the one next
// step (52 px), plain is the stone button, `text` is the quiet one (Back,
// Skip, Later). A disabled gold button loses the gold: gold means "here".
import QtQuick

Rectangle {
    id: button
    property Theme theme
    property string label: ""
    property bool gold: false
    property bool text: false
    property bool enabled_: true
    property int size: 16
    signal clicked()

    implicitHeight: 52
    implicitWidth: caption.implicitWidth + 56
    radius: 10
    color: text ? "transparent" : (gold && enabled_ ? theme.sol : theme.stone)
    border.width: text || (gold && enabled_) ? 0 : 1
    border.color: theme.line
    opacity: enabled_ || gold ? 1 : 0.5
    activeFocusOnTab: enabled_

    Text {
        id: caption
        anchors.centerIn: parent
        text: button.label
        font.family: button.theme.sans
        font.pixelSize: button.size
        font.weight: button.gold ? Font.DemiBold : Font.Medium
        color: button.gold && button.enabled_ ? button.theme.night
             : button.text ? button.theme.parchment
             : button.enabled_ ? button.theme.marble : button.theme.ash
    }

    Rectangle {
        // keyboard focus ring: gold marks where you are
        anchors.fill: parent
        anchors.margins: -3
        radius: parent.radius + 3
        color: "transparent"
        border.width: 2
        border.color: button.theme.solBright
        visible: button.activeFocus
    }

    MouseArea {
        anchors.fill: parent
        enabled: button.enabled_
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
    Keys.onReturnPressed: if (enabled_) clicked()
    Keys.onSpacePressed: if (enabled_) clicked()
}
