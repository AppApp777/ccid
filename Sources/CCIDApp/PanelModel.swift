import AppKit
import CCIDCore
import Observation

/// Everything the panel shows, and every action it can take.
@MainActor @Observable
final class PanelModel {
    enum Row: Identifiable, Equatable {
        case session(Session)
        case searchTranscripts(String)
        case note(String, busy: Bool)

        var id: String {
            switch self {
            case .session(let session): session.id
            case .searchTranscripts: "search-transcripts"
            case .note: "note"
            }
        }

        var isSelectable: Bool {
            if case .note = self { return false }
            return true
        }

        var height: CGFloat {
            if case .session = self { return Metrics.sessionRowHeight }
            return Metrics.actionRowHeight
        }
    }

    enum Mode: Equatable {
        case browse
        case searching(String)
        case found(String)
    }

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            if mode != .browse {
                searchTask?.cancel()
                mode = .browse
                hits = [:]
            }
            rebuild(keepSelection: false)
        }
    }

    private(set) var rows: [Row] = []
    private(set) var selectedID: String?
    private(set) var copiedID: String?
    private(set) var mode: Mode = .browse
    private(set) var hits: [String: TranscriptHit] = [:]
    private(set) var sessions: [Session] = []
    private(set) var hasLoaded = false
    private(set) var focusRequest = 0
    private(set) var now = Date()
    /// Keyboard moves scroll the list; pointer moves never do.
    private(set) var selectionFollowsKeyboard = false

    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored private let store: SessionStore
    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var pointerAtLastKey = NSPoint(x: -1, y: -1)

    init(store: SessionStore, pasteboard: NSPasteboard) {
        self.store = store
        self.pasteboard = pasteboard
    }

    var selectedRow: Row? {
        rows.first { $0.id == selectedID }
    }

    var selectedSession: Session? {
        guard case .session(let session)? = selectedRow else { return nil }
        return session
    }

    // MARK: - Lifecycle

    func prepareForShow() {
        searchTask?.cancel()
        copiedID = nil
        mode = .browse
        hits = [:]
        now = Date()
        if query.isEmpty { rebuild(keepSelection: false) } else { query = "" }
        focusRequest += 1
        pointerAtLastKey = NSEvent.mouseLocation
    }

    func didHide() {
        searchTask?.cancel()
        copiedID = nil
    }

    func refresh() {
        guard refreshTask == nil else { return }
        let store = self.store
        refreshTask = Task {
            let fresh = await Task.detached(priority: .userInitiated) { store.sessions() }.value
            sessions = fresh
            hasLoaded = true
            now = Date()
            refreshTask = nil
            if mode == .browse { rebuild(keepSelection: true) }
        }
    }

    private func rebuild(keepSelection: Bool) {
        let previous = selectedID
        switch mode {
        case .browse:
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            var list = text.isEmpty ? sessions.filter { !$0.isArchived } : SessionSearch.rank(sessions, query: text)
            list = Array(list.prefix(200))
            rows = list.map(Row.session) + (text.isEmpty ? [] : [.searchTranscripts(text)])
        case .searching:
            rows = [.note(String(localized: "Searching every transcript…"), busy: true)]
        case .found(let phrase):
            let found = sessions.filter { hits[$0.id] != nil }
            rows = found.isEmpty
                ? [.note(String(localized: "“\(phrase)” isn’t in any transcript."), busy: false)]
                : found.map(Row.session)
        }
        if keepSelection, let previous, rows.contains(where: { $0.id == previous }) { return }
        selectedID = rows.first(where: \.isSelectable)?.id
        selectionFollowsKeyboard = true
    }

    // MARK: - Selection

    func moveSelection(_ step: Int) {
        let selectable = rows.filter(\.isSelectable)
        guard !selectable.isEmpty else { return }
        let index = selectable.firstIndex(where: { $0.id == selectedID }) ?? -step
        let next = min(max(index + step, 0), selectable.count - 1)
        selectionFollowsKeyboard = true
        selectedID = selectable[next].id
        pointerAtLastKey = NSEvent.mouseLocation
    }

    /// Hovering selects, but only when the pointer really moved — not when the list slid under it.
    func pointerEntered(_ id: String) {
        let pointer = NSEvent.mouseLocation
        guard pointer != pointerAtLastKey else { return }
        pointerAtLastKey = pointer
        selectionFollowsKeyboard = false
        selectedID = id
    }

    // MARK: - Actions

    func activateSelection() {
        guard let row = selectedRow else { return }
        activate(row)
    }

    func activate(_ row: Row) {
        switch row {
        case .session(let session): copy(session.id, for: session)
        case .searchTranscripts(let phrase): searchTranscripts(phrase)
        case .note: break
        }
    }

    func copy(_ value: String, for session: Session) {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        selectedID = session.id
        copiedID = session.id
        Task {
            try? await Task.sleep(for: .milliseconds(520))
            onFinish?()
        }
    }

    func reveal(_ session: Session) {
        guard let url = session.transcript else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        onFinish?()
    }

    func searchTranscripts(_ phrase: String? = nil) {
        let text = (phrase ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searchTask?.cancel()
        mode = .searching(text)
        rebuild(keepSelection: false)
        let candidates = sessions
        searchTask = Task {
            let found = await TranscriptSearch.search(text, in: candidates)
            guard !Task.isCancelled, mode == .searching(text) else { return }
            hits = Dictionary(found.map { ($0.sessionID, $0) }, uniquingKeysWith: { first, _ in first })
            mode = .found(text)
            rebuild(keepSelection: false)
        }
    }

    /// Esc steps back one level at a time: transcript results, then the query, then the panel.
    func stepBack() -> Bool {
        if mode != .browse {
            searchTask?.cancel()
            mode = .browse
            hits = [:]
            rebuild(keepSelection: false)
            return true
        }
        if !query.isEmpty {
            query = ""
            return true
        }
        return false
    }
}
