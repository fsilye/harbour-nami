import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/faceutils.js" as FaceUtils

Page {
    id: page

    property var faceManager: facePipeline
    property int currentIndex: 0
    property var currentFaces: []

    allowedOrientations: Orientation.All

    property var currentFace: currentIndex < currentFaces.length ? currentFaces[currentIndex] : null

    // Load unmapped faces
    function loadUnmappedFaces() {
        if (!faceManager || !faceManager.initialized) return

        currentFaces = faceManager.getUnmappedFaces()
        currentIndex = 0
    }

    // Ignore current face permanently (not a face, stranger, low quality)
    function skipFace() {
        if (currentFace) {
            facePipeline.ignoreFace(currentFace.face_id)
        }
        nextFace()
    }

    function nextFace() {
        if (currentIndex < currentFaces.length - 1) {
            currentIndex++
        } else {
            // No more faces
            pageStack.pop()
        }
    }

    // Identify face as new person or existing (optionally linking a contact)
    function identifyFace(personId, personName, contactId) {
        if (!currentFace) return

        facePipeline.identifyFace(currentFace.face_id, personId, personName, contactId || "")
        nextFace()
    }

    // People model for selection
    ListModel {
        id: peopleModel
    }

    Component.onCompleted: {
        loadUnmappedFaces()

        // Load existing people
        if (facePipeline && facePipeline.initialized) {
            var people = facePipeline.getAllPeople()
            for (var i = 0; i < people.length; i++) {
                peopleModel.append(people[i])
            }
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: qsTr("Skip all")
                onClicked: pageStack.pop()
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("Identify Faces")
            }

            // Progress indicator
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: currentFaces.length > 0
                    ? qsTr("%1 of %2").arg(currentIndex + 1).arg(currentFaces.length)
                    : qsTr("No faces to identify")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                horizontalAlignment: Text.AlignHCenter
            }

            // Cropped face card
            Item {
                id: faceCard
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.7
                height: width

                visible: currentFace !== null

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.paddingMedium
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                    border.color: Theme.rgba(Theme.highlightColor, 0.3)
                    border.width: 2
                    clip: true

                    Image {
                        id: faceImage
                        anchors.fill: parent
                        anchors.margins: 4
                        source: currentFace
                            ? FaceUtils.cropUrl(currentFace.photo_path,
                                                currentFace.bbox_x, currentFace.bbox_y,
                                                currentFace.bbox_width, currentFace.bbox_height,
                                                false)
                            : ""
                        sourceSize.width: 512
                        sourceSize.height: 512
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true

                        BusyIndicator {
                            anchors.centerIn: parent
                            running: parent.status === Image.Loading
                        }
                    }

                    // Detection confidence badge
                    Rectangle {
                        anchors {
                            top: parent.top
                            right: parent.right
                            margins: Theme.paddingMedium
                        }
                        width: confidenceLabel.width + Theme.paddingMedium * 2
                        height: confidenceLabel.height + Theme.paddingSmall * 2
                        radius: height / 2
                        color: Theme.rgba(Theme.highlightBackgroundColor, 0.8)

                        Label {
                            id: confidenceLabel
                            anchors.centerIn: parent
                            text: currentFace
                                ? Math.round(currentFace.confidence * 100) + "%"
                                : ""
                            font.pixelSize: Theme.fontSizeExtraSmall
                            font.bold: true
                            color: Theme.primaryColor
                        }
                    }
                }
            }

            // Show the face in its photo context
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("View in photo")
                visible: currentFace !== null
                onClicked: {
                    pageStack.push(Qt.resolvedUrl("FaceInPhotoPage.qml"), {
                        photoPath: currentFace.photo_path,
                        bboxX: currentFace.bbox_x,
                        bboxY: currentFace.bbox_y,
                        bboxWidth: currentFace.bbox_width,
                        bboxHeight: currentFace.bbox_height
                    })
                }
            }

            // Action buttons row
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingLarge * 2
                visible: currentFace !== null

                // Ignore button (left)
                IconButton {
                    icon.source: "image://theme/icon-m-dismiss"
                    onClicked: skipFace()

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: parent.height
                        radius: width / 2
                        color: Theme.rgba(Theme.errorColor, 0.2)
                        z: -1
                    }
                }

                // Identify button (right)
                IconButton {
                    icon.source: "image://theme/icon-m-acknowledge"
                    onClicked: {
                        // Open dialog to select person
                        var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/SelectPersonDialog.qml"), {
                            peopleModel: peopleModel,
                            allowContact: true
                        })
                        dialog.accepted.connect(function() {
                            if (dialog.selectedContactId.length > 0) {
                                identifyFace(-1, dialog.selectedContactName, dialog.selectedContactId)
                            } else if (dialog.createNew) {
                                identifyFace(-1, dialog.personName)
                            } else {
                                identifyFace(dialog.selectedPersonId, "")
                            }
                        })
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: parent.height
                        radius: width / 2
                        color: Theme.rgba(Theme.highlightColor, 0.2)
                        z: -1
                    }
                }
            }

            // Instructions
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("✗ Ignore (not a face or low quality, won't be shown again)\n✓ Identify (assign to a person)")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: currentFace !== null
            }

            // Completion message
            ViewPlaceholder {
                enabled: currentFaces.length === 0 || currentIndex >= currentFaces.length
                text: currentFaces.length === 0
                    ? qsTr("No faces to identify")
                    : qsTr("All done!")
                hintText: currentFaces.length === 0
                    ? qsTr("All detected faces have been identified")
                    : qsTr("You've reviewed all unknown faces")
            }
        }

        VerticalScrollDecorator {}
    }
}
