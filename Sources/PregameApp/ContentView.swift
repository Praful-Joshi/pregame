import AppKit
import Combine
import PregameCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var document: MixDocument
    @Environment(\.undoManager) private var undo
    @StateObject private var analysis = AnalysisController()
    @StateObject private var editor = TransitionEditorModel()
    @StateObject private var player = MixPlayerModel()
    @ObservedObject private var stems = StemController.shared
    @State private var showExport = false
    @State private var infoTrack: ProjectTrack?
    @State private var selection = Set<ProjectTrack.ID>()
    @State private var showHarmonize = false
    @State private var showCompare = false
    @State private var alert: String?
    @State private var window: NSWindow?
    @State private var followingSelection = false
    @State private var showRelocate = false
    @State private var showConsent = false

    var body: some View {
        commands(sheets(split))
    }

    private var split: some View {
        NavigationSplitView {
            PlaylistSidebar(document: document, editor: editor, selection: $selection,
                            showInfo: { infoTrack = $0 }, alert: $alert)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 420)
        } detail: {
            detail
        }
    }

    @AppStorage("timelineHeight") private var timelineHeight: Double = 150
    @State private var dragStartHeight: Double?

    /// Timeline over editor, with a draggable divider (SwiftUI, so it stays
    /// below the toolbar).
    private var detail: some View {
            VStack(spacing: 0) {
                MixTimelineView(document: document, player: player, editor: editor)
                    .frame(height: timelineHeight)
                Rectangle().fill(.separator).frame(height: 1)
                    .overlay { Color.clear.frame(height: 7).contentShape(Rectangle()) }
                    .onHover { h in if h { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                        let base = dragStartHeight ?? timelineHeight
                        if dragStartHeight == nil { dragStartHeight = base }
                        timelineHeight = min(260, max(110, base + v.translation.height))
                    }.onEnded { _ in dragStartHeight = nil })
                TransitionEditorView(document: document, model: editor, player: player)
                    .frame(minHeight: 320)
            }
            .overlay(alignment: .top) { AnalysisProgressLine(analysis: analysis) }
            .overlay(alignment: .topTrailing) { StemExportStatus() }
    }

    private func sheets(_ content: some View) -> some View {
        content
        .background(WindowAccessor(window: $window))
        .toolbar { toolbar }
        .sheet(isPresented: $showHarmonize) { HarmonizeSheet(document: document) }
        .sheet(isPresented: $showCompare) { CompareSheet(document: document) }
        .sheet(isPresented: $showExport) { ExportSheet(document: document, windowTitle: window?.title ?? "Mix") }
        .sheet(isPresented: $showRelocate) {
            RelocateSheet(document: document) {
                analysis.retryFailed(in: document)
                stems.retry(document.project.tracks)
                requestStems()
            }
        }
        .sheet(isPresented: $showConsent) { ConsentPrompt() }
        .sheet(item: $infoTrack) { t in
            VStack(alignment: .leading, spacing: Space.xl) {
                TrackDetail(document: document, trackID: t.id)
                HStack { Spacer(); Button("Done") { infoTrack = nil }.keyboardShortcut(.defaultAction) }
            }
            .padding(Space.xxl).frame(width: 900)
        }
        .alert(alert ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func commands(_ content: some View) -> some View {
        content
        .onAppear {
            analysis.analyseMissing(in: document)
            player.attach(document)
            editor.attach(document, player: player)
            debugAutoplay()
            requestStems()
            // A Mix whose Tracks can't be reached asks where their folders are now.
            showRelocate = !document.project.missingFolders().isEmpty
            askConsentIfNeeded()
        }
        .onDisappear { player.pause(); player.engine.stop() }
        .onChange(of: showRelocate) { if !showRelocate { askConsentIfNeeded() } }
        .onChange(of: window) { if let window { document.markLocatedChanges(in: window) } }
        .onChange(of: document.project.tracks.count) { analysis.analyseMissing(in: document) }
        .onChange(of: document.project) { player.refresh(); editor.refresh(); requestStems() }
        .onChange(of: editor.index) { requestStems() }
        .onReceive(NotificationCenter.default.publisher(for: StemController.finished)) { _ in
            player.reloadStems(); editor.invalidate()
        }
        .onReceive(notifications(.separateAll)) { _ in stems.request(document.project.included) }
        .onReceive(notifications(.exportStemFiles)) { _ in Panels.exportStemFiles(document.project.included) }
        .onReceive(NotificationCenter.default.publisher(for: AnalysisCache.editsChanged)) { _ in
            player.refresh(); editor.refresh()
        }
        .onChange(of: selection) {
            // Selection that follows the playhead mustn't seek back.
            if followingSelection { followingSelection = false; return }
            if selection.count == 1, let id = selection.first { editor.select(track: id) }
        }
        .onChange(of: player.playingTrack) {
            // The playing song stays highlighted (the list's own selection).
            guard let id = player.playingTrack, selection != [id] else { return }
            followingSelection = true
            selection = [id]
        }
        .onReceive(notifications(.addFolder)) { _ in addFolder(recursive: false) }
        .onReceive(notifications(.addFolderRecursive)) { _ in addFolder(recursive: true) }
        .onReceive(notifications(.addFiles)) { _ in addFiles() }
        .onReceive(notifications(.importRun)) { _ in importRun() }
        .onReceive(notifications(.exportCSV)) { _ in export(csv: true) }
        .onReceive(notifications(.exportM3U)) { _ in export(csv: false) }
        .onReceive(notifications(.harmonize)) { _ in showHarmonize = true }
        .onReceive(notifications(.compare)) { _ in showCompare = true }
        .onReceive(notifications(.writeTags)) { _ in writeOverridesToTags() }
        .onReceive(notifications(.locateMissing)) { _ in
            if document.project.missingFolders().isEmpty { alert = "Every track in this mix was found." }
            else { showRelocate = true }
        }
        .onReceive(notifications(.exportMix)) { _ in showExport = true }
        .onReceive(notifications(.getInfo)) { _ in
            if let id = selection.first { infoTrack = document.project.tracks.first { $0.id == id } }
        }
    }

    /// Songs in transitions that use stem lanes get separated (the one being
    /// edited first).
    private func requestStems() {
        let project = document.project
        let byId = Dictionary(uniqueKeysWithValues: project.tracks.map { ($0.id, $0) })
        let resolved = project.resolvedTransitions()
        func tracks(_ r: ResolvedTransition) -> [ProjectTrack] { [byId[r.info.from], byId[r.info.to]].compactMap { $0 } }
        let needing = resolved.filter { r in LaneKind.stems.contains { r.spec.lane($0) != nil } }
        stems.request(needing.flatMap(tracks))
        if let cur = editor.current, LaneKind.stems.contains(where: { editor.draft?.lane($0) != nil || cur.spec.lane($0) != nil }) {
            stems.request(tracks(cur), urgent: true)
        }
    }

    /// Menu commands, delivered only to this document's window.
    private func notifications(_ name: Notification.Name) -> AnyPublisher<Notification, Never> {
        NotificationCenter.default.publisher(for: name)
            .filter { [window] in window != nil && ($0.object as? NSWindow) == window }
            .eraseToAnyPublisher()
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { addFolder(recursive: false) } label: { Label("Add Folder", systemImage: "plus") }
                .help("Add a folder of tracks (⇧⌘O)")
        }
        ToolbarItem(placement: .principal) {
            TransportBar(document: document, player: player, editor: editor)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { showHarmonize = true } label: { Label("Harmonize", systemImage: "wand.and.stars") }
                .help("Reorder for harmonic flow (⇧⌘H)")
                .disabled(document.project.included.count < 2)
            Button { showCompare = true } label: { Label("Compare", systemImage: "arrow.left.arrow.right") }
                .help("Score another track order with the same settings (⇧⌘K)")
            Menu {
                Button("Mix (WAV / MP3)…") { showExport = true }
                Divider()
                Button("Track List (CSV)…") { export(csv: true) }
                Button("Playlist (M3U)…") { export(csv: false) }
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
            .help("Export the mix (⌘E) or the track list")
        }
    }

    /// Debug: PREGAME_AUTOPLAY=1 plays from 10 s before the first transition
    /// (with PREGAME_MUTE for silence), to check Follow without a person.
    private func debugAutoplay() {
        // Debug: PREGAME_SELECT=n selects the n-th song (1-based), as a click would.
        if let n = ProcessInfo.processInfo.environment["PREGAME_SELECT"].flatMap(Int.init) {
            Task { @MainActor in
                while player.layout == nil { try? await Task.sleep(for: .seconds(1)) }
                if let t = document.project.included[safe: n - 1] { selection = [t.id] }
            }
        }
        // Debug: PREGAME_STEM_PRESET=1 applies Stem Swap to the first transition.
        if ProcessInfo.processInfo.environment["PREGAME_STEM_PRESET"] != nil {
            Task { @MainActor in
                while editor.draft == nil { try? await Task.sleep(for: .seconds(1)) }
                editor.applyPreset("Stem Swap", undo: nil)
            }
        }
        guard ProcessInfo.processInfo.environment["PREGAME_AUTOPLAY"] != nil else { return }
        Task { @MainActor in
            while player.layout == nil { try? await Task.sleep(for: .seconds(1)) }
            guard let w = player.layout?.windows.first else { return }
            player.play(from: max(0, w.globalStart - Int(10 * mixSampleRate)))
        }
    }

    /// The one-time question about crash reports and usage data, in one
    /// window, once no other sheet is up.
    private func askConsentIfNeeded() {
        if !showRelocate, Telemetry.shared.claimPrompt() { showConsent = true }
    }

    // MARK: Actions

    private func addFolder(recursive: Bool) {
        guard let folder = Panels.chooseFolder(prompt: "Add") else { return }
        addTracks(scanFolder(folder, recursive: recursive))
    }

    private func addFiles() {
        addTracks(Panels.chooseAudioFiles())
    }

    private func addTracks(_ urls: [URL]) {
        let existing = Set(document.project.tracks.map(\.path))
        let new = urls.filter { !existing.contains($0.path) }.map(ProjectTrack.from)
        guard !new.isEmpty else {
            if !urls.isEmpty { alert = "Those tracks are already in this mix." }
            return
        }
        let wasEmpty = document.project.tracks.isEmpty
        document.perform("Add Tracks", undo: undo) { $0.tracks += new }
        if wasEmpty { Telemetry.shared.record(.mixCreated) }
        Telemetry.shared.record(.tracksAdded(count: new.count))
    }

    private func importRun() {
        guard let folder = Panels.chooseFolder(prompt: "Import", message: "Choose a run folder inside <set>/harmonized/") else { return }
        do {
            let imported = try MixProject.importRun(folder)
            let wasEmpty = document.project.tracks.isEmpty
            document.perform("Import Harmonize Run", undo: undo) { $0 = imported }
            if wasEmpty, !imported.tracks.isEmpty { Telemetry.shared.record(.mixCreated) }
        } catch {
            alert = error.localizedDescription
        }
    }

    private func export(csv: Bool) {
        let name = (window?.title ?? "Mix").replacingOccurrences(of: ".hmix", with: "")
        guard let url = Panels.save(name: name + (csv ? ".csv" : ".m3u8")) else { return }
        do {
            try (csv ? document.project.csv() : document.project.m3u8())
                .write(to: url, atomically: true, encoding: .utf8)
        } catch {
            alert = error.localizedDescription
        }
    }

    private func writeOverridesToTags() {
        let targets = document.project.tracks.filter(\.isOverridden)
        guard !targets.isEmpty else { alert = "No overridden keys or BPMs to write."; return }
        let failed = targets.filter { !writeTags($0.url, key: $0.keyOverride, bpm: $0.bpmOverride) }
        document.perform("Write Tags", undo: undo) { p in
            for t in targets where !failed.contains(t) {
                guard let i = p.tracks.firstIndex(where: { $0.id == t.id }) else { continue }
                if let k = t.keyOverride { p.tracks[i].tagKey = k }
                if let b = t.bpmOverride { p.tracks[i].tagBpm = b }
            }
        }
        alert = failed.isEmpty ? "Wrote \(targets.count) track(s)."
            : "Couldn't write: " + failed.map(\.filename).joined(separator: ", ")
    }
}

/// Gives a view access to its hosting window (to route menu commands).
struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { window = v.window }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        if window == nil { DispatchQueue.main.async { window = nsView.window } }
    }
}

enum Panels {
    static func chooseFolder(prompt: String, message: String? = nil, start: URL? = nil) -> URL? {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = prompt
        p.message = message ?? ""
        if let start { p.directoryURL = start }
        return p.runModal() == .OK ? p.url : nil
    }

    /// Ask where STEM files go (remembers the last folder), then export.
    @MainActor static func exportStemFiles(_ tracks: [ProjectTrack]) {
        guard !tracks.isEmpty else { return }
        let last = UserDefaults.standard.string(forKey: StemController.exportFolderKey).map { URL(fileURLWithPath: $0) }
        guard let folder = chooseFolder(prompt: "Export",
                                        message: "Choose a folder for the STEM files (add it to Mixxx 2.6's library)",
                                        start: last) else { return }
        StemController.shared.exportStemFiles(tracks, to: folder)
    }

    static func chooseAudioFiles() -> [URL] {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.allowedContentTypes = [.audio]
        return p.runModal() == .OK ? p.urls : []
    }

    static func save(name: String) -> URL? {
        let p = NSSavePanel()
        p.nameFieldStringValue = name
        return p.runModal() == .OK ? p.url : nil
    }
}
