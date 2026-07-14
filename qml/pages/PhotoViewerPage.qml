import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page

    property string photoPath: ""
    // User-applied rotation on top of EXIF auto-orientation, persisted
    property int userRotation: 0

    allowedOrientations: Orientation.All

    Component.onCompleted: {
        if (facePipeline && facePipeline.initialized && photoPath) {
            userRotation = facePipeline.photoRotation(photoPath)
        }
    }

    function rotatePhoto() {
        userRotation = (userRotation + 90) % 360
        if (facePipeline && facePipeline.initialized) {
            facePipeline.setPhotoRotation(photoPath, userRotation)
        }
    }

    SilicaFlickable {
        anchors.fill: parent

        PullDownMenu {
            MenuItem {
                text: qsTr("Close")
                onClicked: pageStack.pop()
            }
        }

        // Pinch-to-zoom support
        PinchArea {
            id: pinchArea
            anchors.fill: parent

            property real initialScale: 1.0

            onPinchStarted: {
                initialScale = photoImage.scale
            }

            onPinchUpdated: {
                var newScale = initialScale * pinch.scale
                photoImage.scale = Math.max(1.0, Math.min(newScale, 4.0))
            }

            // Photo
            Flickable {
                id: flickable
                anchors.fill: parent
                contentWidth: photoImage.width * photoImage.scale
                contentHeight: photoImage.height * photoImage.scale
                clip: true

                Image {
                    id: photoImage
                    anchors.centerIn: parent
                    source: photoPath ? "file://" + photoPath : ""
                    fillMode: Image.PreserveAspectFit
                    autoTransform: true  // honor EXIF orientation
                    asynchronous: true

                    width: page.width
                    height: page.height

                    scale: 1.0
                    rotation: page.userRotation
                    transformOrigin: Item.Center

                    Behavior on scale {
                        NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                    }

                    Behavior on rotation {
                        NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                    }

                    BusyIndicator {
                        anchors.centerIn: parent
                        running: parent.status === Image.Loading
                        size: BusyIndicatorSize.Large
                    }

                    // Error placeholder
                    Label {
                        anchors.centerIn: parent
                        visible: parent.status === Image.Error
                        text: qsTr("Failed to load image")
                        color: Theme.secondaryColor
                    }
                }

                // Double-tap to reset zoom
                MouseArea {
                    anchors.fill: parent
                    onDoubleClicked: {
                        photoImage.scale = 1.0
                        flickable.contentX = 0
                        flickable.contentY = 0
                    }
                }
            }
        }

        // Zoom controls overlay
        Item {
            anchors {
                right: parent.right
                rightMargin: Theme.horizontalPageMargin
                bottom: parent.bottom
                bottomMargin: Theme.paddingLarge * 2
            }
            width: Theme.itemSizeSmall
            height: column.height

            Column {
                id: column
                spacing: Theme.paddingMedium

                // Zoom in button
                IconButton {
                    icon.source: "image://theme/icon-m-add"
                    onClicked: {
                        photoImage.scale = Math.min(photoImage.scale * 1.5, 4.0)
                    }
                    opacity: 0.8
                }

                // Zoom out button
                IconButton {
                    icon.source: "image://theme/icon-m-remove"
                    onClicked: {
                        photoImage.scale = Math.max(photoImage.scale / 1.5, 1.0)
                    }
                    opacity: 0.8
                }

                // Rotate 90° clockwise (persisted)
                IconButton {
                    icon.source: "image://theme/icon-m-refresh"
                    onClicked: rotatePhoto()
                    opacity: 0.8
                }

                // Reset zoom button
                IconButton {
                    icon.source: "image://theme/icon-m-clear"
                    onClicked: {
                        photoImage.scale = 1.0
                        flickable.contentX = 0
                        flickable.contentY = 0
                    }
                    opacity: 0.8
                }
            }
        }
    }
}
