import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/faceutils.js" as FaceUtils

Page {
    id: page

    property int photosProcessed: 0
    property int facesDetected: 0
    property var faceManager: facePipeline

    allowedOrientations: Orientation.All

    // People model (for auto-matched faces)
    ListModel {
        id: peopleModel
    }

    // Unknown faces count
    property int unknownFacesCount: 0

    Component.onCompleted: {
        refreshData()
    }

    function refreshData() {
        if (!faceManager || !faceManager.initialized) return

        // Get all people with their photo counts
        peopleModel.clear()
        var people = faceManager.getAllPeople()
        for (var i = 0; i < people.length; i++) {
            peopleModel.append(people[i])
        }

        // Get unknown faces count
        var unmappedFaces = faceManager.getUnmappedFaces()
        unknownFacesCount = unmappedFaces.length
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("Scan Complete")
            }

            // Summary card
            Item {
                width: parent.width
                height: summaryCard.height

                Rectangle {
                    id: summaryCard
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    height: summaryColumn.height + 2 * Theme.paddingLarge
                    x: Theme.horizontalPageMargin
                    radius: Theme.paddingSmall
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)

                    Column {
                        id: summaryColumn
                        width: parent.width - 2 * Theme.paddingLarge
                        anchors.centerIn: parent
                        spacing: Theme.paddingMedium

                        Label {
                            width: parent.width
                            text: qsTr("Scan summary")
                            font.pixelSize: Theme.fontSizeLarge
                            color: Theme.highlightColor
                            wrapMode: Text.WordWrap
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.paddingLarge

                            // Photos processed
                            Column {
                                width: (parent.width - Theme.paddingLarge) / 2
                                spacing: Theme.paddingSmall

                                Label {
                                    text: photosProcessed
                                    font.pixelSize: Theme.fontSizeHuge
                                    font.bold: true
                                    color: Theme.highlightColor
                                }

                                Label {
                                    text: photosProcessed === 1 ? qsTr("photo") : qsTr("photos")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.secondaryColor
                                }
                            }

                            // Faces detected
                            Column {
                                width: (parent.width - Theme.paddingLarge) / 2
                                spacing: Theme.paddingSmall

                                Label {
                                    text: facesDetected
                                    font.pixelSize: Theme.fontSizeHuge
                                    font.bold: true
                                    color: Theme.highlightColor
                                }

                                Label {
                                    text: facesDetected === 1 ? qsTr("face") : qsTr("faces")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.secondaryColor
                                }
                            }
                        }
                    }
                }
            }

            // Unknown faces first: identifying them is the main action
            // after a scan, so it must not be buried below the people list
            SectionHeader {
                text: qsTr("Unknown faces")
                visible: unknownFacesCount > 0
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: unknownFacesCount === 1
                    ? qsTr("1 face needs to be identified")
                    : qsTr("%n faces need to be identified", "", unknownFacesCount)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                wrapMode: Text.WordWrap
                visible: unknownFacesCount > 0
            }

            // Action button to review unknown faces
            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeMedium
                visible: unknownFacesCount > 0

                Rectangle {
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    height: parent.height - Theme.paddingMedium
                    x: Theme.horizontalPageMargin
                    y: Theme.paddingMedium / 2
                    radius: Theme.paddingSmall
                    color: Theme.rgba(Theme.highlightBackgroundColor, parent.parent.highlighted ? 0.3 : 0.15)
                    border.color: Theme.rgba(Theme.highlightColor, 0.3)
                    border.width: 1

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.paddingMedium

                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            source: "image://theme/icon-m-person"
                            width: Theme.iconSizeMedium
                            height: Theme.iconSizeMedium
                        }

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Review unknown faces")
                            color: Theme.highlightColor
                            font.pixelSize: Theme.fontSizeMedium
                        }
                    }
                }

                onClicked: {
                    pageStack.push(Qt.resolvedUrl("UnknownFacesPage.qml"))
                }
            }

            // Separator between the two sections
            Rectangle {
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: 1
                x: Theme.horizontalPageMargin
                color: Theme.rgba(Theme.highlightColor, 0.1)
                visible: unknownFacesCount > 0 && peopleModel.count > 0
            }

            // Auto-matched faces section
            SectionHeader {
                text: qsTr("Recognized people")
                visible: peopleModel.count > 0
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: unknownFacesCount === 0
                    ? qsTr("All photos were automatically attached to these people:")
                    : qsTr("These faces were automatically matched to people you've already identified:")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                wrapMode: Text.WordWrap
                visible: peopleModel.count > 0
            }

            // List of people with new faces
            Repeater {
                model: peopleModel

                delegate: BackgroundItem {
                    width: column.width
                    height: Theme.itemSizeSmall
                    enabled: false  // Not clickable from this page

                    Row {
                        anchors {
                            left: parent.left
                            leftMargin: Theme.horizontalPageMargin
                            right: parent.right
                            rightMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: Theme.paddingMedium

                        // Avatar (best face of the person, icon fallback)
                        Rectangle {
                            width: Theme.iconSizeMedium
                            height: Theme.iconSizeMedium
                            radius: width / 2
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
                                color: Theme.primaryColor
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
                }
            }

            // Empty state for recognized people
            ViewPlaceholder {
                enabled: peopleModel.count === 0 && unknownFacesCount === 0
                text: qsTr("No faces detected")
                hintText: qsTr("No faces were found in your photos")
            }

            // Spacer
            Item {
                width: parent.width
                height: Theme.paddingLarge
            }

            // Done button
            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeSmall

                Rectangle {
                    width: Theme.buttonWidthMedium
                    height: parent.height - Theme.paddingMedium
                    anchors.centerIn: parent
                    radius: Theme.paddingSmall
                    color: Theme.rgba(Theme.highlightColor, parent.parent.highlighted ? 0.3 : 0.2)

                    Label {
                        anchors.centerIn: parent
                        text: qsTr("Done")
                        color: Theme.primaryColor
                        font.pixelSize: Theme.fontSizeMedium
                    }
                }

                onClicked: {
                    // Pop back to main page (remove both ScanResultsPage and ScanningPage)
                    pageStack.pop(pageStack.previousPage(pageStack.previousPage(page)))
                }
            }

            // Spacer
            Item {
                width: parent.width
                height: Theme.paddingLarge * 2
            }
        }

        VerticalScrollDecorator {}
    }
}
