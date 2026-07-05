import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/faceutils.js" as FaceUtils

Dialog {
    id: dialog

    property int faceId
    property string photoPath
    property rect faceBbox

    property var faceManager: facePipeline
    property int selectedPersonId: -1
    property bool createNew: true  // Default to creating new person

    canAccept: (selectedPersonId > 0) || (createNew && newNameField.text.trim().length > 0)

    onAccepted: {
        if (createNew) {
            // Create new person from face
            var newName = newNameField.text.trim()
            facePipeline.identifyFace(faceId, -1, newName)
        } else if (selectedPersonId > 0) {
            // Assign to existing person
            facePipeline.identifyFace(faceId, selectedPersonId, "")
        }
    }

    // People model
    ListModel {
        id: peopleModel
    }

    Component.onCompleted: {
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

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            DialogHeader {
                acceptText: qsTr("Identify")
                cancelText: qsTr("Cancel")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Who is this?")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
                wrapMode: Text.WordWrap
            }

            // Cropped face preview
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.6
                height: width

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.paddingSmall
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.05)
                    border.color: Theme.rgba(Theme.highlightColor, 0.2)
                    border.width: 1
                    clip: true

                    Image {
                        id: faceImage
                        anchors.fill: parent
                        anchors.margins: 2
                        source: FaceUtils.cropUrl(photoPath,
                                                  faceBbox.x, faceBbox.y,
                                                  faceBbox.width, faceBbox.height,
                                                  false)
                        sourceSize.width: 512
                        sourceSize.height: 512
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true

                        BusyIndicator {
                            anchors.centerIn: parent
                            running: parent.status === Image.Loading
                        }
                    }
                }
            }

            // Show the face in its photo context
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("View in photo")
                onClicked: {
                    pageStack.push(Qt.resolvedUrl("../pages/FaceInPhotoPage.qml"), {
                        photoPath: photoPath,
                        bboxX: faceBbox.x,
                        bboxY: faceBbox.y,
                        bboxWidth: faceBbox.width,
                        bboxHeight: faceBbox.height
                    })
                }
            }

            // Create new person (default)
            Item {
                width: parent.width
                height: Theme.paddingMedium
            }

            TextField {
                id: newNameField
                width: parent.width
                label: qsTr("Person name")
                placeholderText: qsTr("Enter name (e.g., John, Mom, Friend)")
                focus: true

                EnterKey.enabled: text.trim().length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: {
                    if (canAccept) dialog.accept()
                }

                onTextChanged: {
                    if (text.trim().length > 0) {
                        createNew = true
                        selectedPersonId = -1
                    }
                }
            }

            // Separator
            Rectangle {
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: 1
                x: Theme.horizontalPageMargin
                color: Theme.rgba(Theme.highlightColor, 0.1)
                visible: peopleModel.count > 0
            }

            // Existing people section
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Or assign to existing person:")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
                visible: peopleModel.count > 0
            }

            Repeater {
                model: peopleModel

                delegate: BackgroundItem {
                    width: column.width
                    height: Theme.itemSizeSmall
                    highlighted: selectedPersonId === model.person_id

                    Row {
                        anchors {
                            left: parent.left
                            leftMargin: Theme.horizontalPageMargin
                            right: parent.right
                            rightMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: Theme.paddingMedium

                        // Avatar (best face of the person, generic icon fallback)
                        Rectangle {
                            width: Theme.iconSizeMedium
                            height: Theme.iconSizeMedium
                            radius: width / 2
                            color: Theme.rgba(Theme.highlightBackgroundColor, selectedPersonId === model.person_id ? 0.3 : 0.1)

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
                                source: "image://theme/icon-m-person"
                                width: Theme.iconSizeSmall
                                height: Theme.iconSizeSmall
                                visible: avatarImage.status !== Image.Ready
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - Theme.iconSizeMedium - Theme.paddingMedium

                            Label {
                                text: model.name
                                color: selectedPersonId === model.person_id ?
                                       Theme.highlightColor : Theme.primaryColor
                                truncationMode: TruncationMode.Fade
                                width: parent.width
                            }

                            Label {
                                text: model.photo_count + " " + (model.photo_count === 1 ? qsTr("photo") : qsTr("photos"))
                                color: Theme.secondaryColor
                                font.pixelSize: Theme.fontSizeExtraSmall
                                truncationMode: TruncationMode.Fade
                                width: parent.width
                            }
                        }
                    }

                    onClicked: {
                        selectedPersonId = model.person_id
                        createNew = false
                        newNameField.text = ""  // Clear name field
                    }
                }
            }

            // Empty state for existing people
            ViewPlaceholder {
                enabled: peopleModel.count === 0
                text: qsTr("No people yet")
                hintText: qsTr("Enter a name above to create the first person")
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
        }

        VerticalScrollDecorator {}
    }
}
