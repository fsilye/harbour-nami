import QtQuick 2.6
import Sailfish.Silica 1.0

// A memory's photos scattered like polaroids thrown on a table
Page {
    id: page

    property int year: 0
    property int windowDays: 20
    property string title: ""

    allowedOrientations: Orientation.All

    ListModel {
        id: photosModel
    }

    // Deterministic pseudo-random in [0,1) so the scatter looks organic but
    // stays stable across relayouts
    function jitter(i, salt) {
        var x = Math.sin(i * 127.1 + salt * 311.7) * 43758.5453
        return x - Math.floor(x)
    }

    function dayDistance(photoDate, today) {
        var a = new Date(2001, photoDate.getMonth(), photoDate.getDate())
        var b = new Date(2001, today.getMonth(), today.getDate())
        var d = Math.abs(Math.round((a.getTime() - b.getTime()) / 86400000))
        return Math.min(d, 365 - d)
    }

    function loadPhotos() {
        if (!facePipeline || !facePipeline.initialized || year === 0) return

        photosModel.clear()

        var today = new Date()
        var seen = {}
        var items = []
        var people = facePipeline.getAllPeople()
        for (var i = 0; i < people.length; i++) {
            var photos = facePipeline.getPersonPhotos(people[i].person_id)
            for (var j = 0; j < photos.length; j++) {
                var photo = photos[j]
                if (!photo.timestamp || seen[photo.file_path]) continue
                var photoDate = new Date(photo.timestamp * 1000)
                if (photoDate.getFullYear() !== year) continue
                if (dayDistance(photoDate, today) > windowDays) continue
                seen[photo.file_path] = true
                items.push({
                    file_path: photo.file_path,
                    timestamp: photo.timestamp,
                    caption: Qt.formatDate(photoDate, "d MMM yyyy")
                })
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

    SilicaFlickable {
        id: flickable
        anchors.fill: parent
        contentHeight: header.height + table.height + Theme.paddingLarge * 2

        PageHeader {
            id: header
            title: page.title
            description: photosModel.count + " " + (photosModel.count === 1 ? qsTr("photo") : qsTr("photos"))
        }

        // The "table" the polaroids land on
        Item {
            id: table
            anchors.top: header.bottom
            width: parent.width
            // Two loose columns; each row eats ~55% of a polaroid height so
            // they overlap a little like a real pile
            property real polaroidWidth: width * 0.46
            property real polaroidHeight: polaroidWidth * 1.2
            property real rowStep: polaroidHeight * 0.72
            height: photosModel.count > 0
                    ? Math.ceil(photosModel.count / 2) * rowStep + polaroidHeight * 0.5
                    : 0

            Repeater {
                model: photosModel

                // One polaroid: white frame, photo, handwritten-style caption
                delegate: Item {
                    id: polaroid

                    property real jx: jitter(index, 1)
                    property real jy: jitter(index, 2)
                    property real jr: jitter(index, 3)

                    width: table.polaroidWidth
                    height: table.polaroidHeight
                    x: Theme.horizontalPageMargin
                       + (index % 2) * (table.width - table.polaroidWidth - 2 * Theme.horizontalPageMargin)
                       * (0.9 + 0.1 * jx)
                       + (index % 2 === 0 ? jx * table.width * 0.06 : -jx * table.width * 0.06)
                    y: Math.floor(index / 2) * table.rowStep + jy * table.rowStep * 0.25
                    rotation: (jr - 0.5) * 16
                    z: index

                    // Thrown-on-the-table entrance
                    opacity: 0
                    scale: 1.35
                    Component.onCompleted: dropAnimation.start()

                    SequentialAnimation {
                        id: dropAnimation
                        PauseAnimation { duration: 120 * index }
                        ParallelAnimation {
                            NumberAnimation {
                                target: polaroid; property: "opacity"
                                to: 1; duration: 260; easing.type: Easing.OutQuad
                            }
                            NumberAnimation {
                                target: polaroid; property: "scale"
                                to: 1; duration: 320; easing.type: Easing.OutBack
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: "white"
                        radius: 2

                        // Cheap drop shadow
                        Rectangle {
                            anchors.fill: parent
                            anchors.topMargin: 3
                            anchors.leftMargin: 3
                            z: -1
                            color: Theme.rgba("black", 0.35)
                            radius: 2
                        }

                        Image {
                            id: polaroidPhoto
                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                                margins: parent.width * 0.05
                            }
                            height: parent.height - parent.width * 0.24
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

                        Label {
                            anchors {
                                top: polaroidPhoto.bottom
                                left: parent.left
                                right: parent.right
                                bottom: parent.bottom
                            }
                            text: model.caption
                            color: "#444444"
                            font.italic: true
                            font.pixelSize: Theme.fontSizeExtraSmall
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            pageStack.push(Qt.resolvedUrl("PhotoViewerPage.qml"), {
                                photoPath: model.file_path
                            })
                        }
                    }
                }
            }
        }

        ViewPlaceholder {
            enabled: photosModel.count === 0
            text: qsTr("No photos")
        }

        VerticalScrollDecorator {}
    }
}
