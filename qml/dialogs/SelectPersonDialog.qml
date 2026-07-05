import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/faceutils.js" as FaceUtils

Dialog {
    id: dialog

    property var peopleModel
    property int selectedPersonId: -1
    property bool createNew: true
    property string personName: ""

    // Reusable for other flows (e.g. merging people)
    property string titleText: qsTr("Who is this?")
    property string acceptLabel: qsTr("Identify")
    property bool allowCreate: true
    property int excludePersonId: -1

    canAccept: (selectedPersonId > 0) || (createNew && allowCreate && newNameField.text.trim().length > 0)

    onAccepted: {
        if (createNew && allowCreate) {
            personName = newNameField.text.trim()
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            DialogHeader {
                acceptText: dialog.acceptLabel
                cancelText: qsTr("Cancel")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: dialog.titleText
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
            }

            Item {
                width: parent.width
                height: Theme.paddingMedium
            }

            // New person input
            TextField {
                id: newNameField
                width: parent.width
                label: qsTr("New person")
                placeholderText: qsTr("Enter name")
                focus: allowCreate
                visible: allowCreate

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
                visible: allowCreate && peopleModel && peopleModel.count > 0
            }

            // Existing people
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: allowCreate ? qsTr("Or select existing:") : qsTr("Select person:")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                visible: peopleModel && peopleModel.count > 0
            }

            Repeater {
                model: peopleModel

                delegate: BackgroundItem {
                    width: column.width
                    height: Theme.itemSizeSmall
                    visible: model.person_id !== dialog.excludePersonId
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

                        Item {
                            width: Theme.iconSizeMedium
                            height: Theme.iconSizeMedium
                            anchors.verticalCenter: parent.verticalCenter

                            Image {
                                id: avatarImage
                                anchors.fill: parent
                                source: FaceUtils.personAvatarUrl(facePipeline, model.person_id)
                                sourceSize.width: width
                                sourceSize.height: height
                                asynchronous: true
                            }

                            Icon {
                                anchors.centerIn: parent
                                source: "image://theme/icon-m-person"
                                visible: avatarImage.status !== Image.Ready
                                color: selectedPersonId === model.person_id
                                    ? Theme.highlightColor
                                    : Theme.primaryColor
                            }
                        }

                        Label {
                            text: model.name
                            color: selectedPersonId === model.person_id
                                ? Theme.highlightColor
                                : Theme.primaryColor
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    onClicked: {
                        selectedPersonId = model.person_id
                        createNew = false
                        newNameField.text = ""
                    }
                }
            }

            ViewPlaceholder {
                enabled: !peopleModel || peopleModel.count === 0
                text: qsTr("No people yet")
                hintText: qsTr("Enter a name to create the first person")
            }
        }

        VerticalScrollDecorator {}
    }
}
