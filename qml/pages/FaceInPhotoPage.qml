import QtQuick 2.6
import Sailfish.Silica 1.0

// Shows the full photo with one face highlighted (everything else dimmed),
// so the user can see who is being identified in context.
Page {
    id: page

    property string photoPath
    // Normalized (0-1) face bounding box, relative to the oriented image
    property real bboxX
    property real bboxY
    property real bboxWidth
    property real bboxHeight

    allowedOrientations: Orientation.All

    Image {
        id: photo
        anchors.fill: parent
        source: photoPath ? "file://" + photoPath : ""
        fillMode: Image.PreserveAspectFit
        // Bboxes are normalized to the EXIF-oriented image, so the display
        // must be oriented the same way or frames land off the face
        autoTransform: true
        asynchronous: true

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: photo.status === Image.Loading
        }

        Item {
            anchors.fill: parent
            visible: photo.status === Image.Ready

            // Painted area of the photo inside the Image item
            property real imgX: (photo.width - photo.paintedWidth) / 2
            property real imgY: (photo.height - photo.paintedHeight) / 2

            // Face frame in item coordinates (bbox is normalized, so it
            // scales with the painted size directly)
            property real frameX: imgX + bboxX * photo.paintedWidth
            property real frameY: imgY + bboxY * photo.paintedHeight
            property real frameW: bboxWidth * photo.paintedWidth
            property real frameH: bboxHeight * photo.paintedHeight

            id: overlay

            // Dim everything around the face
            Rectangle {  // above
                x: overlay.imgX
                y: overlay.imgY
                width: photo.paintedWidth
                height: overlay.frameY - overlay.imgY
                color: "black"
                opacity: 0.55
            }
            Rectangle {  // below
                x: overlay.imgX
                y: overlay.frameY + overlay.frameH
                width: photo.paintedWidth
                height: overlay.imgY + photo.paintedHeight - (overlay.frameY + overlay.frameH)
                color: "black"
                opacity: 0.55
            }
            Rectangle {  // left
                x: overlay.imgX
                y: overlay.frameY
                width: overlay.frameX - overlay.imgX
                height: overlay.frameH
                color: "black"
                opacity: 0.55
            }
            Rectangle {  // right
                x: overlay.frameX + overlay.frameW
                y: overlay.frameY
                width: overlay.imgX + photo.paintedWidth - (overlay.frameX + overlay.frameW)
                height: overlay.frameH
                color: "black"
                opacity: 0.55
            }

            // Face frame
            Rectangle {
                x: overlay.frameX
                y: overlay.frameY
                width: overlay.frameW
                height: overlay.frameH
                color: "transparent"
                border.color: Theme.highlightColor
                border.width: 3
            }
        }
    }

    // Tap anywhere to go back
    MouseArea {
        anchors.fill: parent
        onClicked: pageStack.pop()
    }

    Label {
        anchors {
            bottom: parent.bottom
            bottomMargin: Theme.paddingLarge
            horizontalCenter: parent.horizontalCenter
        }
        text: qsTr("Tap to go back")
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.secondaryColor
    }
}
