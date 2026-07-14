import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page

    property int personId
    property string personName

    property var faceManager: facePipeline

    allowedOrientations: Orientation.All

    // Photos model
    ListModel {
        id: photosModel
    }

    // Statistics
    property int totalPhotos: 0
    property string firstPhotoDate: ""
    property string lastPhotoDate: ""

    function refreshPhotos() {
        if (!faceManager || !faceManager.initialized) return

        photosModel.clear()
        var photos = faceManager.getPersonPhotos(personId)

        totalPhotos = photos.length

        // Calculate date range
        if (photos.length > 0) {
            var firstTimestamp = null
            var lastTimestamp = null

            for (var i = 0; i < photos.length; i++) {
                photosModel.append(photos[i])

                // Assuming photos have a timestamp or date field
                // For now, we'll use file modification time if available
                if (photos[i].timestamp) {
                    var ts = photos[i].timestamp
                    if (firstTimestamp === null || ts < firstTimestamp) {
                        firstTimestamp = ts
                    }
                    if (lastTimestamp === null || ts > lastTimestamp) {
                        lastTimestamp = ts
                    }
                }
            }

            // Format dates (basic formatting for now)
            if (firstTimestamp) {
                var firstDate = new Date(firstTimestamp * 1000)
                firstPhotoDate = Qt.formatDate(firstDate, "MMM yyyy")
                var lastDate = new Date(lastTimestamp * 1000)
                lastPhotoDate = Qt.formatDate(lastDate, "MMM yyyy")
            }
        } else {
            firstPhotoDate = ""
            lastPhotoDate = ""
        }
    }

    Component.onCompleted: {
        refreshPhotos()
    }

    SilicaGridView {
        id: gridView
        anchors.fill: parent

        cellWidth: width / 3
        cellHeight: cellWidth

        model: photosModel

        PullDownMenu {
            MenuItem {
                text: qsTr("Share All Photos")
                enabled: totalPhotos > 0
                onClicked: {
                    // Collect all photo paths
                    var photoPaths = []
                    for (var i = 0; i < photosModel.count; i++) {
                        var photo = photosModel.get(i)
                        if (photo.file_path) {
                            photoPaths.push(photo.file_path)
                        }
                    }

                    // Open Sailfish OS share dialog
                    if (photoPaths.length > 0) {
                        pageStack.push("Sailfish.TransferEngine.SharePage", {
                            content: photoPaths,
                            mimeType: "image/jpeg",
                            serviceFilter: ["sharing", "e-mail"]
                        })
                    }
                }
            }
        }

        header: Column {
            width: parent.width
            spacing: 0

            PageHeader {
                title: personName || qsTr("Unknown")
            }

            // Statistics card
            Item {
                width: parent.width
                height: statsCard.height + Theme.paddingLarge
                visible: totalPhotos > 0

                Rectangle {
                    id: statsCard
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    height: statsColumn.height + 2 * Theme.paddingMedium
                    x: Theme.horizontalPageMargin
                    radius: Theme.paddingSmall
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)

                    Column {
                        id: statsColumn
                        width: parent.width - 2 * Theme.paddingMedium
                        anchors.centerIn: parent
                        spacing: Theme.paddingMedium

                        // Photo count
                        Row {
                            width: parent.width
                            spacing: Theme.paddingSmall

                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                source: "image://theme/icon-m-image"
                                width: Theme.iconSizeSmall
                                height: Theme.iconSizeSmall
                            }

                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: totalPhotos + " " + (totalPhotos === 1 ? qsTr("photo") : qsTr("photos"))
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.highlightColor
                            }
                        }

                        // Date range
                        Row {
                            width: parent.width
                            spacing: Theme.paddingSmall
                            visible: firstPhotoDate !== "" && lastPhotoDate !== ""

                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                source: "image://theme/icon-m-date"
                                width: Theme.iconSizeSmall
                                height: Theme.iconSizeSmall
                            }

                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    if (firstPhotoDate === lastPhotoDate) {
                                        return firstPhotoDate
                                    } else {
                                        return firstPhotoDate + " - " + lastPhotoDate
                                    }
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.secondaryHighlightColor
                            }
                        }
                    }
                }
            }

            SectionHeader {
                text: qsTr("Photos")
                visible: totalPhotos > 0
            }
        }

        delegate: BackgroundItem {
            width: gridView.cellWidth
            height: gridView.cellHeight

            Image {
                id: photoImage
                anchors.fill: parent
                anchors.margins: Theme.paddingSmall / 2
                source: model.file_path ? "file://" + model.file_path : ""
                fillMode: Image.PreserveAspectCrop
                autoTransform: true
                rotation: model.rotation || 0
                clip: true
                asynchronous: true

                // Error state
                Rectangle {
                    anchors.fill: parent
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                    visible: parent.status === Image.Error

                    Image {
                        anchors.centerIn: parent
                        source: "image://theme/icon-m-image"
                        opacity: 0.3
                    }
                }

                BusyIndicator {
                    anchors.centerIn: parent
                    size: BusyIndicatorSize.Small
                    running: parent.status === Image.Loading
                }
            }

            onClicked: {
                // TODO: Open full image viewer
                console.log("Open photo:", model.file_path)
            }
        }

        ViewPlaceholder {
            enabled: gridView.count === 0
            text: qsTr("No photos")
            hintText: qsTr("This person has no associated photos yet")
        }

        VerticalScrollDecorator {}
    }
}
