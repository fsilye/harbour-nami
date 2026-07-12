import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    property int personId: -1
    property string personName: ""
    property string contactId: ""
    property var faceManager: facePipeline

    allowedOrientations: Orientation.All

    function loadContact() {
        if (faceManager && faceManager.initialized && personId >= 0) {
            contactId = faceManager.personContactId(personId)
        }
    }

    // Photos with this person
    ListModel {
        id: photosModel
    }

    function loadPhotos() {
        if (!faceManager || !faceManager.initialized || personId < 0) return

        photosModel.clear()

        // Get all photos for this person
        var photos = faceManager.getPersonPhotos(personId)

        for (var i = 0; i < photos.length; i++) {
            photosModel.append(photos[i])
        }
    }

    Component.onCompleted: {
        loadPhotos()
        loadContact()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: qsTr("Confirm all matches")
                onClicked: {
                    var confirmed = facePipeline.confirmAllFaces(personId)
                    if (confirmed > 0) {
                        loadPhotos()
                    }
                }
            }
            MenuItem {
                text: qsTr("Rename")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/RenamePersonDialog.qml"), {
                        personId: personId,
                        currentName: personName
                    })
                    dialog.accepted.connect(function() {
                        facePipeline.updatePersonName(personId, dialog.newName)
                        personName = dialog.newName
                    })
                }
            }
            MenuItem {
                text: contactId.length > 0 ? qsTr("Change linked contact") : qsTr("Link to contact")
                visible: facePipeline.contactsEnabled
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/SelectContactDialog.qml"), {
                        personName: personName
                    })
                    dialog.accepted.connect(function() {
                        facePipeline.linkPersonToContact(personId, dialog.selectedContactId)
                        contactId = dialog.selectedContactId
                    })
                }
            }
            MenuItem {
                text: qsTr("Unlink contact")
                visible: facePipeline.contactsEnabled && contactId.length > 0
                onClicked: {
                    facePipeline.linkPersonToContact(personId, "")
                    contactId = ""
                }
            }
            MenuItem {
                text: qsTr("Delete")
                onClicked: {
                    Remorse.popupAction(page, qsTr("Deleting %1").arg(personName), function() {
                        facePipeline.deletePerson(personId)
                        pageStack.pop()
                    })
                }
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: personName
            }

            // Statistics card
            Item {
                width: parent.width
                height: statsCard.height

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

                        Label {
                            text: photosModel.count + " " + (photosModel.count === 1 ? qsTr("photo") : qsTr("photos"))
                            font.pixelSize: Theme.fontSizeHuge
                            font.bold: true
                            color: Theme.highlightColor
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Label {
                            text: qsTr("with this person")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.secondaryColor
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }

            SectionHeader {
                text: qsTr("Photos")
                visible: photosModel.count > 0
            }

            // Photo grid
            Grid {
                id: photoGrid
                width: parent.width
                columns: 3
                spacing: Theme.paddingSmall

                Repeater {
                    model: photosModel

                    delegate: ListItem {
                        id: photoItem
                        width: photoGrid.width / 3
                        height: width
                        contentHeight: width

                        // Wrap content in Item to fix ContextMenu positioning
                        contentItem.children: [
                            Image {
                                id: photoImage
                                anchors.fill: parent
                                anchors.margins: Theme.paddingSmall / 2
                                source: model.file_path ? "file://" + model.file_path : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                clip: true

                                // Limit source size to save memory
                                sourceSize.width: 400
                                sourceSize.height: 400

                                BusyIndicator {
                                    anchors.centerIn: parent
                                    running: parent.status === Image.Loading
                                    size: BusyIndicatorSize.Small
                                }

                                // Border with different color for verified vs auto-matched
                                Rectangle {
                                    anchors.fill: parent
                                    color: "transparent"
                                    border.color: model.verified ? Theme.rgba(Theme.secondaryHighlightColor, 0.8) : Theme.rgba(Theme.highlightColor, 0.3)
                                    border.width: model.verified ? 2 : 1
                                }

                                // Verified badge (manual identification - checkmark)
                                Rectangle {
                                    visible: model.verified === true
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: Theme.paddingSmall
                                    width: Theme.iconSizeSmall
                                    height: Theme.iconSizeSmall
                                    radius: width / 2
                                    color: Theme.rgba("#4CAF50", 0.95)
                                    border.color: "white"
                                    border.width: 2
                                    z: 100

                                    Label {
                                        anchors.centerIn: parent
                                        text: "✓"
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: true
                                        color: "white"
                                    }
                                }

                                // Auto-matched badge (AI icon)
                                Rectangle {
                                    visible: model.verified === false && model.similarity_score > 0
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: Theme.paddingSmall
                                    width: Theme.iconSizeSmall
                                    height: Theme.iconSizeSmall
                                    radius: width / 2
                                    color: Theme.rgba("#2196F3", 0.9)
                                    border.color: "white"
                                    border.width: 2
                                    z: 100

                                    Label {
                                        anchors.centerIn: parent
                                        text: "✦"
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: true
                                        color: "white"
                                    }
                                }

                                // Similarity score badge (for auto-matched)
                                Rectangle {
                                    visible: model.verified === false && model.similarity_score > 0
                                    anchors.bottom: parent.bottom
                                    anchors.right: parent.right
                                    anchors.margins: Theme.paddingSmall
                                    width: scoreLabel.width + Theme.paddingSmall
                                    height: scoreLabel.height + Theme.paddingSmall / 2
                                    radius: Theme.paddingSmall / 2
                                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.8)
                                    z: 100

                                    Label {
                                        id: scoreLabel
                                        anchors.centerIn: parent
                                        text: Math.round(model.similarity_score * 100) + "%"
                                        font.pixelSize: Theme.fontSizeTiny
                                        color: Theme.primaryColor
                                    }
                                }
                            }
                        ]

                        onClicked: {
                            pageStack.push(Qt.resolvedUrl("PhotoViewerPage.qml"), {
                                photoPath: model.file_path
                            })
                        }

                        menu: ContextMenu {
                            MenuItem {
                                text: qsTr("Remove from person")
                                onClicked: {
                                    photoItem.remorseAction(qsTr("Removing"), function() {
                                        if (facePipeline.removePersonFromPhoto(page.personId, model.photo_id)) {
                                            photosModel.remove(index)
                                        }
                                    })
                                }
                            }

                            MenuItem {
                                text: qsTr("View full photo")
                                onClicked: {
                                    pageStack.push(Qt.resolvedUrl("PhotoViewerPage.qml"), {
                                        photoPath: model.file_path
                                    })
                                }
                            }
                        }
                    }
                }
            }

            ViewPlaceholder {
                enabled: photosModel.count === 0
                text: qsTr("No photos")
                hintText: qsTr("This person hasn't been detected in any photos yet")
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
        }

        VerticalScrollDecorator {}
    }
}
