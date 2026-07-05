import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/faceutils.js" as FaceUtils

Page {
    id: page

    allowedOrientations: Orientation.All

    // Access global face pipeline from C++ backend
    // facePipeline is exposed via QML context in main.cpp

    // People model (source data)
    ListModel {
        id: peopleModel
    }

    // Filtered model (for search)
    ListModel {
        id: filteredPeopleModel
    }

    // Search query
    property string searchQuery: ""

    // Sort mode: "name" or "photos"
    property string sortMode: "photos"

    // Statistics
    property int totalPeople: 0
    property int totalPhotos: 0
    property string topPerson: ""

    // Refresh people list
    function refreshPeople() {
        if (!facePipeline || !facePipeline.initialized) return

        peopleModel.clear()
        var people = facePipeline.getAllPeople()

        // Calculate statistics
        totalPeople = people.length
        totalPhotos = 0
        var maxPhotos = 0
        topPerson = ""

        for (var i = 0; i < people.length; i++) {
            peopleModel.append(people[i])
            totalPhotos += people[i].photo_count

            if (people[i].photo_count > maxPhotos) {
                maxPhotos = people[i].photo_count
                topPerson = people[i].name
            }
        }

        // Apply filter and sort
        filterAndSort()
    }

    // Filter and sort people
    function filterAndSort() {
        filteredPeopleModel.clear()

        // Collect filtered items
        var items = []
        for (var i = 0; i < peopleModel.count; i++) {
            var person = peopleModel.get(i)

            // Filter by search query
            if (searchQuery === "" || person.name.toLowerCase().indexOf(searchQuery.toLowerCase()) >= 0) {
                items.push({
                    person_id: person.person_id,
                    name: person.name,
                    photo_count: person.photo_count
                })
            }
        }

        // Sort items
        if (sortMode === "name") {
            items.sort(function(a, b) {
                return a.name.toLowerCase().localeCompare(b.name.toLowerCase())
            })
        } else { // sortMode === "photos"
            items.sort(function(a, b) {
                return b.photo_count - a.photo_count
            })
        }

        // Populate filtered model
        for (var j = 0; j < items.length; j++) {
            filteredPeopleModel.append(items[j])
        }
    }

    Component.onCompleted: {
        // Wait for face pipeline to be ready
        if (facePipeline && facePipeline.initialized) {
            refreshPeople()
        }
    }

    Connections {
        target: facePipeline
        onScanCompleted: refreshPeople()
    }

    SilicaListView {
        id: listView
        anchors.fill: parent

        model: filteredPeopleModel

        PullDownMenu {
            MenuItem {
                text: qsTr("About")
                onClicked: pageStack.push(Qt.resolvedUrl("AboutPage.qml"))
            }
            MenuItem {
                text: qsTr("Settings")
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
            }
            MenuItem {
                text: qsTr("Memories")
                enabled: facePipeline && facePipeline.initialized
                onClicked: pageStack.push(Qt.resolvedUrl("MemoriesPage.qml"))
            }
            MenuItem {
                text: qsTr("Events")
                enabled: facePipeline && facePipeline.initialized
                onClicked: pageStack.push(Qt.resolvedUrl("EventsPage.qml"))
            }
            MenuItem {
                text: qsTr("Identify Faces")
                enabled: facePipeline && facePipeline.initialized
                onClicked: pageStack.push(Qt.resolvedUrl("IdentifyFacesPage.qml"))
            }
            MenuItem {
                text: qsTr("Scan Gallery")
                enabled: facePipeline && facePipeline.initialized && !facePipeline.processing
                onClicked: {
                    // Open scanning page
                    pageStack.push(Qt.resolvedUrl("ScanningPage.qml"))
                }
            }
        }

        PushUpMenu {
            MenuItem {
                text: sortMode === "photos" ? qsTr("Sort by Name") : qsTr("Sort by Photos")
                onClicked: {
                    sortMode = (sortMode === "photos") ? "name" : "photos"
                    filterAndSort()
                }
            }
        }

        header: Column {
            width: parent.width
            spacing: 0

            PageHeader {
                title: qsTr("Nami")
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Face Recognition Gallery")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
                wrapMode: Text.WordWrap
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Automatically organize your photos by faces. All processing happens on your device for complete privacy.")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }

            // Statistics card
            Item {
                width: parent.width
                height: statsCard.height
                visible: totalPeople > 0

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
                        spacing: Theme.paddingSmall

                        Row {
                            width: parent.width
                            spacing: Theme.paddingLarge

                            Column {
                                width: (parent.width - Theme.paddingLarge * 2) / 3
                                spacing: Theme.paddingSmall / 2

                                Label {
                                    text: totalPeople
                                    font.pixelSize: Theme.fontSizeHuge
                                    font.bold: true
                                    color: Theme.highlightColor
                                }

                                Label {
                                    text: totalPeople === 1 ? qsTr("person") : qsTr("people")
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    color: Theme.secondaryColor
                                }
                            }

                            Column {
                                width: (parent.width - Theme.paddingLarge * 2) / 3
                                spacing: Theme.paddingSmall / 2

                                Label {
                                    text: totalPhotos
                                    font.pixelSize: Theme.fontSizeHuge
                                    font.bold: true
                                    color: Theme.highlightColor
                                }

                                Label {
                                    text: totalPhotos === 1 ? qsTr("photo") : qsTr("photos")
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    color: Theme.secondaryColor
                                }
                            }

                            Column {
                                width: (parent.width - Theme.paddingLarge * 2) / 3
                                spacing: Theme.paddingSmall / 2

                                Label {
                                    text: topPerson || "-"
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.bold: true
                                    color: Theme.highlightColor
                                    truncationMode: TruncationMode.Fade
                                    width: parent.width
                                }

                                Label {
                                    text: qsTr("most photos")
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    color: Theme.secondaryColor
                                }
                            }
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
                visible: totalPeople > 0
            }

            // Search field
            SearchField {
                id: searchField
                width: parent.width
                placeholderText: qsTr("Search people")
                visible: totalPeople > 0

                onTextChanged: {
                    searchQuery = text
                    filterAndSort()
                }

                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            SectionHeader {
                text: qsTr("People (%1)").arg(filteredPeopleModel.count)
                visible: totalPeople > 0
            }
        }

        delegate: ListItem {
            id: listItem
            width: ListView.view.width
            contentHeight: Theme.itemSizeMedium

            Row {
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                spacing: Theme.paddingMedium

                // Face thumbnail (best face of the person, icon fallback)
                Rectangle {
                    width: Theme.itemSizeSmall
                    height: Theme.itemSizeSmall
                    radius: Theme.itemSizeSmall / 2
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)

                    Image {
                        id: avatarImage
                        anchors.fill: parent
                        source: FaceUtils.personAvatarUrl(facePipeline, model.person_id)
                        sourceSize.width: width
                        sourceSize.height: height
                        asynchronous: true
                    }

                    Image {
                        anchors.centerIn: parent
                        source: "image://theme/icon-m-contact"
                        width: Theme.iconSizeMedium
                        height: Theme.iconSizeMedium
                        visible: avatarImage.status !== Image.Ready
                    }
                }

                Column {
                    width: parent.width - Theme.itemSizeSmall - Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter

                    Label {
                        text: model.name || qsTr("Unknown")
                        color: listItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                        truncationMode: TruncationMode.Fade
                        width: parent.width
                    }

                    Label {
                        text: model.photo_count + " " + (model.photo_count === 1 ? qsTr("photo") : qsTr("photos"))
                        color: listItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                        truncationMode: TruncationMode.Fade
                        width: parent.width
                    }
                }
            }

            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Rename")
                    onClicked: {
                        var dialog = pageStack.push("Sailfish.Silica.InputDialog", {
                            acceptDestination: page,
                            acceptDestinationAction: PageStackAction.Pop,
                            title: qsTr("Rename Person"),
                            placeholderText: qsTr("Enter name"),
                            text: model.name
                        })
                        dialog.accepted.connect(function() {
                            facePipeline.updatePersonName(model.person_id, dialog.value)
                            refreshPeople()
                        })
                    }
                }
                MenuItem {
                    text: qsTr("Merge into...")
                    visible: peopleModel.count > 1
                    onClicked: {
                        var mergeSourceId = model.person_id
                        var mergeSourceName = model.name
                        var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/SelectPersonDialog.qml"), {
                            peopleModel: peopleModel,
                            allowCreate: false,
                            excludePersonId: mergeSourceId,
                            titleText: qsTr("Merge %1 into...").arg(mergeSourceName),
                            acceptLabel: qsTr("Merge")
                        })
                        dialog.accepted.connect(function() {
                            if (dialog.selectedPersonId > 0) {
                                facePipeline.mergePersons(mergeSourceId, dialog.selectedPersonId)
                                refreshPeople()
                            }
                        })
                    }
                }
                MenuItem {
                    text: qsTr("Delete")
                    onClicked: {
                        var dialog = pageStack.push("Sailfish.Silica.RemorseDialog", {
                            title: qsTr("Delete person?"),
                            text: qsTr("This will remove %1 and unlink all their photos").arg(model.name)
                        })
                        dialog.accepted.connect(function() {
                            facePipeline.deletePerson(model.person_id)
                            refreshPeople()
                        })
                    }
                }
            }

            onClicked: {
                pageStack.push(Qt.resolvedUrl("PersonDetailPage.qml"), {
                    personId: model.person_id,
                    personName: model.name
                })
            }
        }

        ViewPlaceholder {
            enabled: listView.count === 0
            text: qsTr("No faces detected yet")
            hintText: qsTr("Pull down to scan your gallery")
        }

        VerticalScrollDecorator {}
    }
}
