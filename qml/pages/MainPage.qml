import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/faceutils.js" as FaceUtils

Page {
    id: page

    allowedOrientations: Orientation.All

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

    // Layout: 0 = list, otherwise number of grid columns (2 or 4)
    property int gridColumns: 0

    // Statistics
    property int totalPeople: 0
    property int totalPhotos: 0
    property string topPerson: ""

    function reloadViewMode() {
        if (facePipeline && facePipeline.initialized) {
            var mode = facePipeline.getSetting("people_view_mode", "list")
            // "grid" is the legacy value for the 2-column grid
            gridColumns = (mode === "grid4") ? 4
                        : (mode === "grid2" || mode === "grid") ? 2
                        : 0
        }
    }

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
                    photo_count: person.photo_count,
                    contact_id: person.contact_id || ""
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

    // === Actions (shared between list and grid layouts) ===

    function openPerson(personId, name) {
        pageStack.push(Qt.resolvedUrl("PersonDetailPage.qml"), {
            personId: personId,
            personName: name
        })
    }

    function renamePerson(personId, name) {
        var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/RenamePersonDialog.qml"), {
            personId: personId,
            currentName: name
        })
        dialog.accepted.connect(function() {
            facePipeline.updatePersonName(personId, dialog.newName)
            refreshPeople()
        })
    }

    function mergePerson(personId, name) {
        var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/SelectPersonDialog.qml"), {
            peopleModel: peopleModel,
            allowCreate: false,
            excludePersonId: personId,
            titleText: qsTr("Merge %1 into...").arg(name),
            acceptLabel: qsTr("Merge")
        })
        dialog.accepted.connect(function() {
            if (dialog.selectedPersonId > 0) {
                facePipeline.mergePersons(personId, dialog.selectedPersonId)
                refreshPeople()
            }
        })
    }

    function deletePerson(personId, name) {
        Remorse.popupAction(page, qsTr("Deleting %1").arg(name), function() {
            facePipeline.deletePerson(personId)
            refreshPeople()
        })
    }

    function linkContact(personId, name) {
        var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/SelectContactDialog.qml"), {
            personName: name
        })
        dialog.accepted.connect(function() {
            facePipeline.linkPersonToContact(personId, dialog.selectedContactId)
            refreshPeople()
        })
    }

    function unlinkContact(personId) {
        facePipeline.linkPersonToContact(personId, "")
        refreshPeople()
    }

    // === Navigation (shared by both layouts) ===

    function openAbout() { pageStack.push(Qt.resolvedUrl("AboutPage.qml")) }
    function openSettings() { pageStack.push(Qt.resolvedUrl("SettingsPage.qml")) }
    function openMemories() { pageStack.push(Qt.resolvedUrl("MemoriesPage.qml")) }
    function openEvents() { pageStack.push(Qt.resolvedUrl("EventsPage.qml")) }
    function openIdentify() { pageStack.push(Qt.resolvedUrl("IdentifyFacesPage.qml")) }
    function openScan() { pageStack.push(Qt.resolvedUrl("ScanningPage.qml")) }
    function toggleSort() {
        sortMode = (sortMode === "photos") ? "name" : "photos"
        filterAndSort()
    }

    Component.onCompleted: {
        reloadViewMode()
        if (facePipeline && facePipeline.initialized) {
            refreshPeople()
        }
    }

    // Re-read the layout choice when coming back from Settings
    onStatusChanged: {
        if (status === PageStatus.Active) {
            reloadViewMode()
        }
    }

    Connections {
        target: facePipeline
        onScanCompleted: refreshPeople()
    }

    // Shared header for both layouts
    Component {
        id: peopleHeader

        Column {
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
                text: searchQuery

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
    }

    // === List layout ===
    Component {
        id: listLayout

        SilicaListView {
            id: listView
            anchors.fill: parent
            model: filteredPeopleModel
            header: peopleHeader

            PullDownMenu {
                MenuItem { text: qsTr("About"); onClicked: openAbout() }
                MenuItem { text: qsTr("Settings"); onClicked: openSettings() }
                MenuItem {
                    text: qsTr("Memories")
                    enabled: facePipeline && facePipeline.initialized
                    onClicked: openMemories()
                }
                MenuItem {
                    text: qsTr("Events")
                    enabled: facePipeline && facePipeline.initialized
                    onClicked: openEvents()
                }
                MenuItem {
                    text: qsTr("Identify Faces")
                    enabled: facePipeline && facePipeline.initialized
                    onClicked: openIdentify()
                }
                MenuItem {
                    text: qsTr("Scan Gallery")
                    enabled: facePipeline && facePipeline.initialized && !facePipeline.processing
                    onClicked: openScan()
                }
            }

            PushUpMenu {
                MenuItem {
                    text: sortMode === "photos" ? qsTr("Sort by Name") : qsTr("Sort by Photos")
                    onClicked: toggleSort()
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

                        Row {
                            width: parent.width
                            spacing: Theme.paddingSmall

                            Label {
                                text: model.name || qsTr("Unknown")
                                color: listItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                                truncationMode: TruncationMode.Fade
                                width: Math.min(implicitWidth, parent.width - (linkedIcon.visible ? linkedIcon.width + parent.spacing : 0))
                            }

                            Image {
                                id: linkedIcon
                                anchors.verticalCenter: parent.verticalCenter
                                source: "image://theme/icon-m-contact"
                                width: Theme.iconSizeExtraSmall
                                height: Theme.iconSizeExtraSmall
                                visible: facePipeline.contactsEnabled && model.contact_id && model.contact_id.length > 0
                                opacity: 0.6
                            }
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
                        onClicked: renamePerson(model.person_id, model.name)
                    }
                    MenuItem {
                        text: (model.contact_id && model.contact_id.length > 0)
                              ? qsTr("Change linked contact")
                              : qsTr("Link to contact")
                        visible: facePipeline.contactsEnabled
                        onClicked: linkContact(model.person_id, model.name)
                    }
                    MenuItem {
                        text: qsTr("Unlink contact")
                        visible: facePipeline.contactsEnabled && model.contact_id && model.contact_id.length > 0
                        onClicked: unlinkContact(model.person_id)
                    }
                    MenuItem {
                        text: qsTr("Merge into...")
                        visible: peopleModel.count > 1
                        onClicked: mergePerson(model.person_id, model.name)
                    }
                    MenuItem {
                        text: qsTr("Delete")
                        onClicked: deletePerson(model.person_id, model.name)
                    }
                }

                onClicked: openPerson(model.person_id, model.name)
            }

            ViewPlaceholder {
                enabled: listView.count === 0
                text: qsTr("No faces detected yet")
                hintText: qsTr("Pull down to scan your gallery")
            }

            VerticalScrollDecorator {}
        }
    }

    // === Grid layout ===
    Component {
        id: gridLayout

        SilicaGridView {
            id: grid
            anchors.fill: parent
            model: filteredPeopleModel
            header: peopleHeader

            property int columns: gridColumns > 0 ? gridColumns : 2
            property bool dense: columns >= 4

            cellWidth: width / columns
            cellHeight: cellWidth + (dense ? Theme.itemSizeExtraSmall : Theme.itemSizeSmall)

            PullDownMenu {
                MenuItem { text: qsTr("About"); onClicked: openAbout() }
                MenuItem { text: qsTr("Settings"); onClicked: openSettings() }
                MenuItem {
                    text: qsTr("Memories")
                    enabled: facePipeline && facePipeline.initialized
                    onClicked: openMemories()
                }
                MenuItem {
                    text: qsTr("Events")
                    enabled: facePipeline && facePipeline.initialized
                    onClicked: openEvents()
                }
                MenuItem {
                    text: qsTr("Identify Faces")
                    enabled: facePipeline && facePipeline.initialized
                    onClicked: openIdentify()
                }
                MenuItem {
                    text: qsTr("Scan Gallery")
                    enabled: facePipeline && facePipeline.initialized && !facePipeline.processing
                    onClicked: openScan()
                }
            }

            PushUpMenu {
                MenuItem {
                    text: sortMode === "photos" ? qsTr("Sort by Name") : qsTr("Sort by Photos")
                    onClicked: toggleSort()
                }
            }

            delegate: BackgroundItem {
                width: grid.cellWidth
                height: grid.cellHeight

                Column {
                    anchors.fill: parent
                    anchors.margins: grid.dense ? Theme.paddingSmall : Theme.paddingMedium
                    spacing: Theme.paddingSmall

                    Rectangle {
                        id: avatarFrame
                        width: parent.width
                        height: width
                        radius: grid.dense ? Theme.paddingSmall : Theme.paddingMedium
                        color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                        clip: true

                        Image {
                            id: gridAvatar
                            anchors.fill: parent
                            source: FaceUtils.personAvatarUrl(facePipeline, model.person_id)
                            sourceSize.width: width
                            sourceSize.height: height
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }

                        Image {
                            anchors.centerIn: parent
                            source: "image://theme/icon-m-contact"
                            visible: gridAvatar.status !== Image.Ready
                            opacity: 0.4
                        }

                        Image {
                            anchors {
                                top: parent.top
                                right: parent.right
                                margins: Theme.paddingSmall
                            }
                            source: "image://theme/icon-m-contact"
                            width: grid.dense ? Theme.iconSizeExtraSmall : Theme.iconSizeSmall
                            height: width
                            visible: facePipeline.contactsEnabled && model.contact_id && model.contact_id.length > 0
                        }
                    }

                    Label {
                        width: parent.width
                        text: model.name || qsTr("Unknown")
                        color: Theme.primaryColor
                        font.pixelSize: grid.dense ? Theme.fontSizeExtraSmall : Theme.fontSizeSmall
                        truncationMode: TruncationMode.Fade
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                onClicked: openPerson(model.person_id, model.name)
                onPressAndHold: renamePerson(model.person_id, model.name)
            }

            ViewPlaceholder {
                enabled: grid.count === 0
                text: qsTr("No faces detected yet")
                hintText: qsTr("Pull down to scan your gallery")
            }

            VerticalScrollDecorator {}
        }
    }

    // Only one layout is instantiated at a time
    Loader {
        anchors.fill: parent
        sourceComponent: gridColumns > 0 ? gridLayout : listLayout
    }
}
