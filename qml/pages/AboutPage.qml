import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    allowedOrientations: Orientation.All

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        VerticalScrollDecorator {}

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("About")
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                // App launcher icon (resolved from hicolor by the theme)
                source: "image://theme/harbour-nami"
                width: Theme.iconSizeLauncher * 2
                height: width
                sourceSize.width: width
                sourceSize.height: height
            }

            Item {
                width: parent.width
                height: Theme.paddingMedium
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Nami"
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeHuge
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "v" + appVersion
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeMedium
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
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Intelligent photo organization using on-device face recognition")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            SectionHeader {
                text: qsTr("Features")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: "• " + qsTr("100% on-device processing, no internet required") + "\n" +
                      "• " + qsTr("Automatic face detection and recognition") + "\n" +
                      "• " + qsTr("People gallery in list or grid layout") + "\n" +
                      "• " + qsTr("Link people to your device contacts") + "\n" +
                      "• " + qsTr("Events grouped by day") + "\n" +
                      "• " + qsTr("Memories from previous years") + "\n" +
                      "• " + qsTr("Scan folders of your choice, SD card included") + "\n" +
                      "• " + qsTr("Data export and full deletion (GDPR)")
                color: Theme.primaryColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            SectionHeader {
                text: qsTr("Technology")
            }

            DetailItem {
                label: qsTr("Platform")
                value: "Sailfish OS"
            }

            DetailItem {
                label: qsTr("Framework")
                value: "Qt 5 / Silica"
            }

            DetailItem {
                label: qsTr("ML Engine")
                value: "OpenCV / ONNX"
            }

            SectionHeader {
                text: qsTr("License")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Open Source Software")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Source Code")
                onClicked: Qt.openUrlExternally("https://github.com/nicosouv/harbour-nami")
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
        }
    }
}
