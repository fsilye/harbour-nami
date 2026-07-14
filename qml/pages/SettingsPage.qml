import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0

Page {
    id: page

    property var stats: ({})
    // Whitelist of folders Nami is allowed to scan (internal storage + SD card)
    property var scanFolders: []

    allowedOrientations: Orientation.All

    function loadStatistics() {
        if (facePipeline && facePipeline.initialized) {
            stats = facePipeline.getStatistics()
            loadFolders()
        }
    }

    function loadFolders() {
        var raw = facePipeline.getSetting("scan_folders", "")
        if (raw.length > 0) {
            scanFolders = raw.split("\n").filter(function (f) { return f.length > 0 })
        } else {
            // Backward compat: migrate the single legacy folder
            var legacy = facePipeline.getSetting("gallery_path", "")
            scanFolders = legacy.length > 0 ? [legacy] : [defaultGalleryPath]
        }
    }

    function saveFolders() {
        facePipeline.setSetting("scan_folders", scanFolders.join("\n"))
    }

    function addFolder(path) {
        if (!path || scanFolders.indexOf(path) >= 0) return
        var copy = scanFolders.slice()
        copy.push(path)
        scanFolders = copy
        saveFolders()
    }

    function removeFolder(path) {
        var copy = scanFolders.filter(function (f) { return f !== path })
        // Never leave the whitelist empty: fall back to the default folder
        if (copy.length === 0) copy = [defaultGalleryPath]
        scanFolders = copy
        saveFolders()
    }

    Component.onCompleted: {
        loadStatistics()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        VerticalScrollDecorator {}

        Column {
            id: column
            width: page.width

            PageHeader {
                title: qsTr("Settings")
            }

            SectionHeader {
                text: qsTr("Privacy")
            }

            TextArea {
                width: parent.width
                readOnly: true
                label: qsTr("On-device processing")
                text: qsTr("All face recognition processing happens locally on your device. No data is sent to external servers.")
            }

            TextSwitch {
                text: qsTr("Contacts integration")
                description: qsTr("Let you link people to your device contacts. When off, Nami never reads your contacts, even though the permission is granted.")
                enabled: facePipeline && facePipeline.initialized
                automaticCheck: false
                checked: facePipeline && facePipeline.contactsEnabled
                onClicked: facePipeline.contactsEnabled = !facePipeline.contactsEnabled
            }

            SectionHeader {
                text: qsTr("Scanned folders")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Nami only scans the folders listed here. Add a folder on the SD card to include external photos.")
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: scanFolders

                delegate: ListItem {
                    width: parent.width
                    contentHeight: Theme.itemSizeSmall
                    enabled: facePipeline && facePipeline.initialized

                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData
                        truncationMode: TruncationMode.Fade
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    menu: ContextMenu {
                        MenuItem {
                            text: qsTr("Remove")
                            onClicked: removeFolder(modelData)
                        }
                    }
                }
            }

            Button {
                x: Theme.horizontalPageMargin
                text: qsTr("Add folder")
                enabled: facePipeline && facePipeline.initialized
                onClicked: pageStack.push(folderPickerComponent)

                Component {
                    id: folderPickerComponent
                    FolderPickerDialog {
                        title: qsTr("Select folder to scan")
                        onAccepted: addFolder(selectedPath)
                    }
                }
            }

            SectionHeader {
                text: qsTr("Display")
            }

            ComboBox {
                id: layoutCombo
                width: parent.width
                label: qsTr("People layout")
                enabled: facePipeline && facePipeline.initialized

                // Guard against writes while the initial value is applied:
                // a declarative currentIndex binding gets clamped before the
                // menu items exist, so the value must be set imperatively
                property bool ready: false

                menu: ContextMenu {
                    MenuItem { text: qsTr("List") }
                    MenuItem { text: qsTr("Grid ×2") }
                    MenuItem { text: qsTr("Grid ×4") }
                }

                Component.onCompleted: {
                    if (facePipeline && facePipeline.initialized) {
                        // "grid" is the legacy value for the 2-column grid
                        var mode = facePipeline.getSetting("people_view_mode", "list")
                        currentIndex = (mode === "grid4") ? 2
                                     : (mode === "grid2" || mode === "grid") ? 1
                                     : 0
                    }
                    ready = true
                }

                onCurrentIndexChanged: {
                    if (!ready) return
                    var mode = currentIndex === 2 ? "grid4"
                             : currentIndex === 1 ? "grid2"
                             : "list"
                    facePipeline.setSetting("people_view_mode", mode)
                }
            }

            Slider {
                width: parent.width
                label: qsTr("Memories time window")
                minimumValue: 1
                maximumValue: 45
                stepSize: 1
                valueText: value + " " + qsTr("days")
                enabled: facePipeline && facePipeline.initialized

                Component.onCompleted: {
                    if (facePipeline && facePipeline.initialized) {
                        value = parseInt(facePipeline.getSetting("memories_window_days", "20"))
                    }
                }

                onReleased: {
                    facePipeline.setSetting("memories_window_days", Math.round(value).toString())
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Memories show photos taken within this many days around today's date in previous years")
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                wrapMode: Text.WordWrap
            }

            SectionHeader {
                text: qsTr("Scanning")
            }

            Slider {
                id: thresholdSlider
                width: parent.width
                label: qsTr("Recognition strictness")
                minimumValue: 0.65
                maximumValue: 0.80
                stepSize: 0.01
                valueText: Math.round(value * 100) + "%"
                enabled: facePipeline && facePipeline.initialized

                Component.onCompleted: {
                    if (facePipeline && facePipeline.initialized) {
                        value = parseFloat(facePipeline.getSetting("auto_match_threshold", "0.72"))
                    }
                }

                onReleased: {
                    facePipeline.setSetting("auto_match_threshold", value.toFixed(2))
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Higher values reduce wrong matches but leave more faces to identify manually")
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                wrapMode: Text.WordWrap
            }

            SectionHeader {
                text: qsTr("Storage")
            }

            DetailItem {
                label: qsTr("Detected faces")
                value: stats.total_faces || 0
            }

            DetailItem {
                label: qsTr("Named people")
                value: stats.total_people || 0
            }

            DetailItem {
                label: qsTr("Storage used")
                value: {
                    var bytes = stats.db_size_bytes || 0
                    if (bytes < 1024) return bytes + " B"
                    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB"
                    return (bytes / (1024 * 1024)).toFixed(1) + " MB"
                }
            }

            SectionHeader {
                text: qsTr("Data Management")
            }

            ButtonLayout {
                Button {
                    text: qsTr("Export data")
                    enabled: facePipeline && facePipeline.initialized
                    onClicked: {
                        var path = facePipeline.exportData()
                        exportResultLabel.text = path
                            ? qsTr("Exported to %1").arg(path)
                            : qsTr("Export failed")
                    }
                }

                Button {
                    text: qsTr("Clear all data")
                    enabled: facePipeline && facePipeline.initialized
                    onClicked: {
                        var remorse = Remorse.popupAction(page, qsTr("Deleting all data"), function() {
                            if (facePipeline.deleteAllData()) {
                                loadStatistics()
                            }
                        })
                    }
                }
            }

            Label {
                id: exportResultLabel
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                wrapMode: Text.Wrap
                visible: text.length > 0
            }
        }
    }
}
