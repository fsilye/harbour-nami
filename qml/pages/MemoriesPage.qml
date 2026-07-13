import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page

    property var faceManager: facePipeline

    allowedOrientations: Orientation.All

    // Memories model
    ListModel {
        id: memoriesModel
    }

    Component.onCompleted: {
        if (faceManager && faceManager.initialized) {
            windowDays = parseInt(faceManager.getSetting("memories_window_days", "20"))
        }
        detectMemories()
    }

    // Days to look around today's date: exact-day matching almost never
    // fires, a window makes memories actually show up (user-tunable)
    property int windowDays: 20

    // Circular distance in days between a photo's month/day and today's,
    // ignoring the year (so Dec 30 is 3 days from Jan 2)
    function dayDistance(photoDate, today) {
        var a = new Date(2001, photoDate.getMonth(), photoDate.getDate())
        var b = new Date(2001, today.getMonth(), today.getDate())
        var d = Math.abs(Math.round((a.getTime() - b.getTime()) / 86400000))
        return Math.min(d, 365 - d)
    }

    // Detect memories: photos from around this date in previous years
    function detectMemories() {
        if (!faceManager || !faceManager.initialized) return

        memoriesModel.clear()

        var today = new Date()
        var currentYear = today.getFullYear()

        var people = faceManager.getAllPeople()
        var byYear = {}  // year -> { photos, people, bestDistance }

        for (var i = 0; i < people.length; i++) {
            var person = people[i]
            var photos = faceManager.getPersonPhotos(person.person_id)

            for (var j = 0; j < photos.length; j++) {
                var photo = photos[j]
                if (!photo.timestamp) continue

                var photoDate = new Date(photo.timestamp * 1000)
                var photoYear = photoDate.getFullYear()
                if (photoYear >= currentYear) continue

                var distance = dayDistance(photoDate, today)
                if (distance > windowDays) continue

                if (!byYear[photoYear]) {
                    byYear[photoYear] = {
                        year: photoYear,
                        photos: [],
                        seen: {},
                        people: {},
                        bestDistance: distance,
                        repDate: photoDate
                    }
                }

                var group = byYear[photoYear]
                if (!group.seen[photo.file_path]) {
                    group.seen[photo.file_path] = true
                    group.photos.push(photo)
                    group.people[person.person_id] = person.name
                    if (distance < group.bestDistance) {
                        group.bestDistance = distance
                        group.repDate = photoDate
                    }
                }
            }
        }

        // Plain JS objects (ListModel.get() references break after clear())
        var memoriesList = []
        for (var year in byYear) {
            var memory = byYear[year]
            var peopleNames = []
            for (var personId in memory.people) {
                peopleNames.push(memory.people[personId])
            }

            memoriesList.push({
                year: memory.year,
                yearsAgo: currentYear - memory.year,
                dateString: Qt.formatDate(memory.repDate, "d MMMM yyyy"),
                distanceDays: memory.bestDistance,
                photoCount: memory.photos.length,
                peopleCount: peopleNames.length,
                peopleNames: peopleNames.join(", "),
                coverPhoto: memory.photos[0].file_path
            })
        }

        // Closest to today first, then most recent year
        memoriesList.sort(function(a, b) {
            if (a.distanceDays !== b.distanceDays) {
                return a.distanceDays - b.distanceDays
            }
            return a.yearsAgo - b.yearsAgo
        })

        for (var n = 0; n < memoriesList.length; n++) {
            memoriesModel.append(memoriesList[n])
        }
    }

    SilicaListView {
        id: listView
        anchors.fill: parent

        model: memoriesModel

        header: Column {
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("Memories")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Photos from around this time in previous years")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                wrapMode: Text.WordWrap
            }

            Item {
                width: parent.width
                height: Theme.paddingMedium
            }
        }

        delegate: BackgroundItem {
            id: memoryItem
            width: ListView.view.width
            height: Theme.itemSizeExtraLarge + Theme.paddingLarge

            Row {
                anchors {
                    fill: parent
                    leftMargin: Theme.horizontalPageMargin
                    rightMargin: Theme.horizontalPageMargin
                }
                spacing: Theme.paddingMedium

                // Cover photo with overlay
                Item {
                    width: Theme.itemSizeExtraLarge
                    height: Theme.itemSizeExtraLarge
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        anchors.fill: parent
                        source: model.coverPhoto ? "file://" + model.coverPhoto : ""
                        fillMode: Image.PreserveAspectCrop
                        autoTransform: true
                        clip: true
                        asynchronous: true

                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.color: Theme.rgba(Theme.highlightColor, 0.3)
                            border.width: 2
                            radius: Theme.paddingSmall
                        }

                        BusyIndicator {
                            anchors.centerIn: parent
                            running: parent.status === Image.Loading
                            size: BusyIndicatorSize.Small
                        }
                    }

                    // Years ago badge
                    Rectangle {
                        anchors {
                            bottom: parent.bottom
                            right: parent.right
                            margins: Theme.paddingSmall
                        }
                        width: yearsLabel.width + Theme.paddingMedium
                        height: yearsLabel.height + Theme.paddingSmall
                        radius: Theme.paddingSmall / 2
                        color: Theme.rgba(Theme.highlightBackgroundColor, 0.9)

                        Label {
                            id: yearsLabel
                            anchors.centerIn: parent
                            text: model.yearsAgo + (model.yearsAgo === 1 ? qsTr(" year ago") : qsTr(" years ago"))
                            font.pixelSize: Theme.fontSizeExtraSmall
                            font.bold: true
                            color: Theme.highlightColor
                        }
                    }
                }

                // Memory info
                Column {
                    width: parent.width - Theme.itemSizeExtraLarge - Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.paddingSmall

                    Label {
                        text: model.dateString
                        color: memoryItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: true
                        truncationMode: TruncationMode.Fade
                        width: parent.width
                    }

                    Label {
                        text: model.photoCount + " " + (model.photoCount === 1 ? qsTr("photo") : qsTr("photos"))
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeSmall
                        truncationMode: TruncationMode.Fade
                        width: parent.width
                    }

                    Label {
                        text: model.peopleNames
                        color: Theme.secondaryHighlightColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                        truncationMode: TruncationMode.Fade
                        width: parent.width
                        visible: model.peopleCount > 0
                    }
                }
            }

            onClicked: {
                pageStack.push(Qt.resolvedUrl("MemoryDetailPage.qml"), {
                    year: model.year,
                    windowDays: windowDays,
                    title: model.dateString
                })
            }
        }

        ViewPlaceholder {
            enabled: listView.count === 0
            text: qsTr("No memories")
            hintText: qsTr("No photos found from this day in previous years")
        }

        VerticalScrollDecorator {}
    }
}
