import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    // State
    property int currentPhoto: 0
    property int totalPhotos: 0
    property int facesDetected: 0
    property bool scanning: true

    Component.onCompleted: {
        // Start scanning every whitelisted folder (defaults to Pictures)
        var raw = facePipeline.getSetting("scan_folders", "")
        var folders = raw.length > 0
            ? raw.split("\n").filter(function (f) { return f.length > 0 })
            : [facePipeline.getSetting("gallery_path", defaultGalleryPath)]
        facePipeline.scanGalleries(folders, true)
    }

    Connections {
        target: facePipeline

        onScanProgress: {
            currentPhoto = current
            totalPhotos = total
        }

        onPhotoProcessed: {
            if (result.success) {
                facesDetected += result.facesDetected
            }
        }

        onScanCompleted: {
            scanning = false
            facesDetected = facesDetected
            // Navigate to results page
            pageStack.replace(Qt.resolvedUrl("ScanResultsPage.qml"), {
                photosProcessed: photosProcessed,
                facesDetected: facesDetected
            })
        }

        onScanFailed: {
            // Cancelled or errored: leave the scanning page
            scanning = false
            pageStack.pop()
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge * 2

            // Spacer
            Item {
                width: parent.width
                height: Theme.paddingLarge * 4
            }

            // Animated circle progress
            Item {
                width: parent.width
                height: Theme.itemSizeHuge * 2

                // Outer glow circle
                Rectangle {
                    anchors.centerIn: parent
                    width: Theme.itemSizeHuge * 1.8
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.color: Theme.highlightColor
                    border.width: 2
                    opacity: 0.3

                    SequentialAnimation on opacity {
                        running: scanning
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.8; duration: 1000; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 0.3; duration: 1000; easing.type: Easing.InOutQuad }
                    }

                    SequentialAnimation on scale {
                        running: scanning
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.1; duration: 1000; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.0; duration: 1000; easing.type: Easing.InOutQuad }
                    }
                }

                // Main circle
                Rectangle {
                    id: mainCircle
                    anchors.centerIn: parent
                    width: Theme.itemSizeHuge * 1.5
                    height: width
                    radius: width / 2
                    color: Theme.rgba(Theme.highlightColor, 0.1)
                    border.color: Theme.highlightColor
                    border.width: 3

                    // Progress arc (simulated with rotation)
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - 20
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.color: Theme.highlightColor
                        border.width: 8
                        opacity: 0.6

                        rotation: totalPhotos > 0 ? (currentPhoto / totalPhotos) * 360 : 0

                        Behavior on rotation {
                            NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                        }
                    }

                    // Center content
                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.paddingSmall

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: totalPhotos > 0 ? currentPhoto : "0"
                            font.pixelSize: Theme.fontSizeHuge * 1.5
                            font.bold: true
                            color: Theme.highlightColor
                        }

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: totalPhotos > 0 ? "/ " + totalPhotos : "..."
                            font.pixelSize: Theme.fontSizeLarge
                            color: Theme.secondaryColor
                        }
                    }
                }
            }

            // Title
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: scanning ? qsTr("Scanning Gallery") : qsTr("Scan Complete")
                font.pixelSize: Theme.fontSizeExtraLarge
                font.bold: true
                color: Theme.highlightColor
            }

            // Subtitle
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - Theme.horizontalPageMargin * 4
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: scanning ?
                      (totalPhotos > 0 ? qsTr("%1 files processed out of %2 files").arg(currentPhoto).arg(totalPhotos) : qsTr("Preparing...")) :
                      qsTr("Found %n face(s)", "", facesDetected)
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.secondaryColor
            }

            // Stats
            Item {
                width: parent.width
                height: Theme.paddingLarge
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingLarge * 3

                Column {
                    spacing: Theme.paddingSmall

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: currentPhoto
                        font.pixelSize: Theme.fontSizeHuge
                        font.bold: true
                        color: Theme.highlightColor
                    }

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("Photos")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryColor
                    }
                }

                Rectangle {
                    width: 1
                    height: Theme.itemSizeSmall
                    color: Theme.secondaryColor
                    opacity: 0.3
                }

                Column {
                    spacing: Theme.paddingSmall

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: facesDetected
                        font.pixelSize: Theme.fontSizeHuge
                        font.bold: true
                        color: Theme.highlightColor
                    }

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("Faces")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryColor
                    }
                }
            }

            // Progress percentage
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: totalPhotos > 0 ? Math.round((currentPhoto / totalPhotos) * 100) + "%" : "0%"
                font.pixelSize: Theme.fontSizeExtraLarge
                font.bold: true
                color: Theme.highlightColor
                opacity: 0.8
                visible: scanning
            }

            // Cancel button (if needed)
            Item {
                width: parent.width
                height: Theme.paddingLarge * 2
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: scanning ? qsTr("Cancel") : qsTr("Done")

                onClicked: {
                    if (scanning) {
                        facePipeline.cancel()
                    } else {
                        pageStack.pop()
                    }
                }
            }
        }
    }
}
