import QtQuick 2.6
import Sailfish.Silica 1.0

// All photos taken on a given day (opened from the Events page)
Page {
    id: page

    property string dateKey: ""   // yyyy-MM-dd
    property string title: ""

    allowedOrientations: Orientation.All

    ListModel {
        id: photosModel
    }

    function loadPhotos() {
        if (!facePipeline || !facePipeline.initialized || dateKey.length === 0) return

        photosModel.clear()

        // Collect the day's photos across every person, deduplicated
        var seen = {}
        var items = []
        var people = facePipeline.getAllPeople()
        for (var i = 0; i < people.length; i++) {
            var photos = facePipeline.getPersonPhotos(people[i].person_id)
            for (var j = 0; j < photos.length; j++) {
                var photo = photos[j]
                if (!photo.timestamp || seen[photo.file_path]) continue
                var key = Qt.formatDate(new Date(photo.timestamp * 1000), "yyyy-MM-dd")
                if (key === dateKey) {
                    seen[photo.file_path] = true
                    items.push({
                        file_path: photo.file_path,
                        timestamp: photo.timestamp
                    })
                }
            }
        }

        items.sort(function(a, b) { return a.timestamp - b.timestamp })
        for (var n = 0; n < items.length; n++) {
            photosModel.append(items[n])
        }
    }

    Component.onCompleted: {
        loadPhotos()
    }

    SilicaGridView {
        id: gridView
        anchors.fill: parent

        cellWidth: width / 3
        cellHeight: cellWidth

        model: photosModel

        header: PageHeader {
            title: page.title
            description: gridView.count + " " + (gridView.count === 1 ? qsTr("photo") : qsTr("photos"))
        }

        delegate: BackgroundItem {
            width: gridView.cellWidth
            height: gridView.cellHeight

            Image {
                anchors.fill: parent
                anchors.margins: Theme.paddingSmall / 2
                source: model.file_path ? "file://" + model.file_path : ""
                fillMode: Image.PreserveAspectCrop
                autoTransform: true
                clip: true
                asynchronous: true
                sourceSize.width: 400
                sourceSize.height: 400

                BusyIndicator {
                    anchors.centerIn: parent
                    running: parent.status === Image.Loading
                    size: BusyIndicatorSize.Small
                }
            }

            onClicked: {
                pageStack.push(Qt.resolvedUrl("PhotoViewerPage.qml"), {
                    photoPath: model.file_path
                })
            }
        }

        ViewPlaceholder {
            enabled: gridView.count === 0
            text: qsTr("No photos")
        }

        VerticalScrollDecorator {}
    }
}
