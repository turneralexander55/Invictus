/* Invictus install slideshow: one quiet screen in Dusk while the install
   runs (Venus 3.1: no log unless you ask; Calamares shows the step and the
   progress bar under it). */
import QtQuick 2.15

Item {
    id: root
    property bool activatedInCalamares: false
    function onActivate() { activatedInCalamares = true }
    function onLeave() { activatedInCalamares = false }

    Rectangle { anchors.fill: parent; color: "#14120F" }

    Column {
        anchors.centerIn: parent
        spacing: 24
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "logo.png"
            width: 96; height: 96
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Copying Invictus to the disk"
            color: "#ECE6DA"
            font.pixelSize: 26
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Keep the computer plugged in. This takes about 15 minutes."
            color: "#968E7F"
            font.pixelSize: 17
        }
    }
}
