// A choice card on "How should Help work?" (no-ai.md 2.1): a picture of
// what Help will look like, the title, one line, and room for the choices
// inside it. Picked: a parchment border and a marble tick.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: cc
    property Theme theme
    property bool picked: false
    property string title: ""
    property string line: ""
    property alias picture: pic.data
    default property alias content: inner.data
    signal pick()

    radius: 14
    color: theme.stone
    clip: true
    implicitHeight: col.implicitHeight

    MouseArea {
        anchors.fill: parent
        onClicked: cc.pick()
        cursorShape: Qt.PointingHandCursor
    }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 0
        Rectangle {
            id: pic
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            topLeftRadius: cc.radius
            topRightRadius: cc.radius
            color: cc.theme.night
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: cc.theme.line
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: 20
            Layout.topMargin: 18
            spacing: 0
            Text {
                text: cc.title
                font.family: cc.theme.sans
                font.pixelSize: 20
                font.weight: Font.Medium
                color: cc.theme.marble
            }
            Text {
                text: cc.line
                font.family: cc.theme.sans
                font.pixelSize: 15
                lineHeight: 1.25
                color: cc.theme.parchment
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.topMargin: 8
            }
            ColumnLayout {
                id: inner
                Layout.fillWidth: true
                spacing: 0
            }
        }
    }

    // the border, over the picture
    Rectangle {
        anchors.fill: parent
        radius: cc.radius
        color: "transparent"
        border.width: cc.picked ? 2 : 1
        border.color: cc.picked ? cc.theme.parchment : cc.theme.line
    }

    // the tick, top right
    Rectangle {
        x: parent.width - 40
        y: 14
        width: 26
        height: 26
        radius: 13
        color: cc.picked ? cc.theme.marble : "transparent"
        border.width: cc.picked ? 0 : 2
        border.color: cc.theme.ash
        Canvas {
            anchors.fill: parent
            visible: cc.picked
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = cc.theme.night
                ctx.lineWidth = 2.4
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.beginPath()
                ctx.moveTo(7.5, 13.5)
                ctx.lineTo(11, 17)
                ctx.lineTo(18.5, 9)
                ctx.stroke()
            }
        }
    }
}
