import AppKit
import PregameCore
import SwiftUI

@main
struct PregameApp: App {
    // Start watching audio devices at launch (so the menu and engines agree).
    @ObservedObject private var outputs: AudioOutputs

    init() {
        // Before anything reads a setting or opens a cache, so the settings and
        // data from before the sandbox come through (ADR-0003).
        LegacyDefaults.migrateIfNeeded()
        DataFolders.copyLegacyDataIfNeeded()
        // Launch into a new, empty Mix rather than the system Open panel.
        // File > Open and Open Recent still reach saved Mixes.
        UserDefaults.standard.register(defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
        outputs = AudioOutputs.shared
        _ = Updates.shared   // starts the updater, so automatic checks run
        // Crash reports start only if the Mix Host agreed (docs/privacy.md).
        Telemetry.shared.start()
        Telemetry.shared.record(.appLaunched)
    }

    var body: some Scene {
        DocumentGroup(newDocument: { MixDocument() }) { file in
            ContentView(document: file.document)
                .tint(Ink.accent)
                .frame(minWidth: 1200, minHeight: 720)
        }
        .commands {
            CommandGroup(after: .appInfo) { CheckForUpdatesButton() }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Add Folder…") { post(.addFolder) }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Add Folder Including Subfolders…") { post(.addFolderRecursive) }
                Button("Add Files…") { post(.addFiles) }
                Divider()
                Button("Import Harmonize Run…") { post(.importRun) }
            }
            CommandGroup(after: .importExport) {
                Button("Export Mix…") { post(.exportMix) }.keyboardShortcut("e", modifiers: .command)
                Button("Export Track List (CSV)…") { post(.exportCSV) }.keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Export Playlist (M3U)…") { post(.exportM3U) }
            }
            CommandMenu("Playback") {
                OutputDevicePicker()
                Button("Sound Settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                }
            }
            CommandMenu("Mix") {
                Button("Harmonize…") { post(.harmonize) }.keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Compare with Another Order…") { post(.compare) }.keyboardShortcut("k", modifiers: [.command, .shift])
                Divider()
                Button("Separate Stems for All Songs") { post(.separateAll) }
                Button("Export STEM Files for Mixxx…") { post(.exportStemFiles) }
                Divider()
                Button("Write Overrides to File Tags") { post(.writeTags) }
                Button("Locate Missing Tracks…") { post(.locateMissing) }
                Button("Get Info") { post(.getInfo) }.keyboardShortcut("i", modifiers: .command)
            }
        }
        // After the DocumentGroup: SwiftUI opens the first scene at launch, and
        // with Settings first the app opened on Settings instead of a Mix.
        Settings { SettingsView().tint(Ink.accent).onAppear { _ = AudioOutputs.shared } }
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: NSApp.keyWindow)
    }
}

extension Notification.Name {
    static let addFolder = Notification.Name("addFolder")
    static let addFolderRecursive = Notification.Name("addFolderRecursive")
    static let addFiles = Notification.Name("addFiles")
    static let importRun = Notification.Name("importRun")
    static let exportCSV = Notification.Name("exportCSV")
    static let exportM3U = Notification.Name("exportM3U")
    static let harmonize = Notification.Name("harmonize")
    static let compare = Notification.Name("compare")
    static let writeTags = Notification.Name("writeTags")
    static let exportMix = Notification.Name("exportMix")
    static let getInfo = Notification.Name("getInfo")
    static let locateMissing = Notification.Name("locateMissing")
    static let separateAll = Notification.Name("separateAll")
    static let exportStemFiles = Notification.Name("exportStemFiles")
}
