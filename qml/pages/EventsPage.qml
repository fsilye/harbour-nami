import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page

    property var faceManager: facePipeline

    allowedOrientations: Orientation.All

    // Events model (grouped photos by date)
    ListModel {
        id: eventsModel
    }

    Component.onCompleted: {
        detectEvents()
    }

    // Simple event detection: group photos by date
    function detectEvents() {
        if (!faceManager || !faceManager.initialized) return

        eventsModel.clear()

        // Get all people
        var people = faceManager.getAllPeople()
        var dateMap = {}  // Map of date -> { people: Set, photos: Array }

        // Collect all photos grouped by date
        for (var i = 0; i < people.length; i++) {
            var person = people[i]
            var photos = faceManager.getPersonPhotos(person.person_id)

            for (var j = 0; j < photos.length; j++) {
                var photo = photos[j]
                if (!photo.timestamp) continue

                // Get date only (no time)
                var date = new Date(photo.timestamp * 1000)
                var dateKey = Qt.formatDate(date, "yyyy-MM-dd")

                if (!dateMap[dateKey]) {
                    dateMap[dateKey] = {
                        date: date,
                        people: {},
                        photos: []
                    }
                }

                // Track unique people for this date
                dateMap[dateKey].people[person.person_id] = person.name

                // Add photo if not already present
                var photoExists = false
                for (var k = 0; k < dateMap[dateKey].photos.length; k++) {
                    if (dateMap[dateKey].photos[k].file_path === photo.file_path) {
                        photoExists = true
                        break
                    }
                }
                if (!photoExists) {
                    dateMap[dateKey].photos.push(photo)
                }
            }
        }

        // Convert to plain JS objects first: ListModel.get() returns live
        // references that are invalidated by clear(), so sorting via the
        // model produced rows with empty fields ("0 photos" events)
        var events = []
        for (var dateKey in dateMap) {
            var event = dateMap[dateKey]
            if (event.photos.length >= 2) {
                var peopleNames = []
                for (var personId in event.people) {
                    peopleNames.push(event.people[personId])
                }

                events.push({
                    dateKey: dateKey,
                    time: event.date.getTime(),
                    dateString: Qt.formatDate(event.date, "ddd d MMM yyyy"),
                    photoCount: event.photos.length,
                    peopleCount: peopleNames.length,
                    peopleNames: peopleNames.join(", "),
                    coverPhoto: event.photos[0].file_path
                })
            }
        }

        // Sort by date (most recent first)
        events.sort(function(a, b) {
            return b.time - a.time
        })

        for (var n = 0; n < events.length; n++) {
            eventsModel.append(events[n])
        }
    }

    SilicaListView {
        id: listView
        anchors.fill: parent

        model: eventsModel

        header: Column {
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("Events")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Photos automatically grouped by date")
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
            id: eventItem
            width: ListView.view.width
            height: Theme.itemSizeExtraLarge + Theme.paddingMedium

            Row {
                anchors {
                    fill: parent
                    leftMargin: Theme.horizontalPageMargin
                    rightMargin: Theme.horizontalPageMargin
                }
                spacing: Theme.paddingMedium

                // Cover photo
                Image {
                    width: Theme.itemSizeExtraLarge
                    height: Theme.itemSizeExtraLarge
                    anchors.verticalCenter: parent.verticalCenter
                    source: model.coverPhoto ? "file://" + model.coverPhoto : ""
                    fillMode: Image.PreserveAspectCrop
                    autoTransform: true
                    clip: true
                    asynchronous: true

                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        border.color: Theme.rgba(Theme.highlightColor, 0.2)
                        border.width: 1
                        radius: Theme.paddingSmall
                    }

                    BusyIndicator {
                        anchors.centerIn: parent
                        running: parent.status === Image.Loading
                        size: BusyIndicatorSize.Small
                    }
                }

                // Event info
                Column {
                    width: parent.width - Theme.itemSizeExtraLarge - Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.paddingSmall

                    Label {
                        text: model.dateString
                        color: eventItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                        font.pixelSize: Theme.fontSizeMedium
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
                pageStack.push(Qt.resolvedUrl("DayPhotosPage.qml"), {
                    dateKey: model.dateKey,
                    title: model.dateString
                })
            }
        }

        ViewPlaceholder {
            enabled: listView.count === 0
            text: qsTr("No events detected")
            hintText: qsTr("Events are created when you have multiple photos from the same day")
        }

        VerticalScrollDecorator {}
    }
}
