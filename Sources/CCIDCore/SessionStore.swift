import Foundation

/// Finds every Claude Code session on this Mac. Read-only, and cheap to call again:
/// transcripts are only re-read when their size or modification date changes.
public final class SessionStore: @unchecked Sendable {
    public let locations: Locations
    public let isDemo: Bool

    private struct Stamp: Hashable {
        let size: Int
        let modified: Date
    }

    private let lock = NSLock()
    private var heads: [URL: (stamp: Stamp, head: TranscriptHead, searchedPrompt: Bool)] = [:]
    private var tails: [URL: (stamp: Stamp, tail: TranscriptTail, soughtTitle: Bool)] = [:]

    public init(locations: Locations = .standard(), demo: Bool = false) {
        self.locations = locations
        self.isDemo = demo
    }

    /// All sessions, most recently active first. Archived sessions are included and flagged.
    public func sessions(now: Date = Date()) -> [Session] {
        if isDemo { return DemoSessions.make(now: now) }
        let transcripts = transcriptIndex()
        var sessions = desktopSessions(transcripts: transcripts)
        let known = Set(sessions.map(\.id))
        sessions += terminalSessions(transcripts: transcripts.filter { !known.contains($0.key) })
        return withDetails(sessions).sorted { $0.lastActive > $1.lastActive }
    }

    // MARK: - Claude desktop app

    private func desktopSessions(transcripts: [String: URL]) -> [Session] {
        var records: [[String: Any]] = []
        for file in metadataFiles() {
            guard let data = try? Data(contentsOf: file),
                  let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let id = record["cliSessionId"] as? String, !id.isEmpty else { continue }
            records.append(record)
        }
        var titleByHost: [String: String] = [:]
        for record in records {
            if let host = record["sessionId"] as? String { titleByHost[host] = record["title"] as? String ?? "" }
        }
        var byID: [String: Session] = [:]
        for record in records {
            let id = record["cliSessionId"] as! String
            let millis = [record["lastFocusedAt"], record["lastActivityAt"]]
                .compactMap { ($0 as? NSNumber)?.doubleValue }.max()
                ?? (record["createdAt"] as? NSNumber)?.doubleValue ?? 0
            let cwd = record["cwd"] as? String
            let session = Session(
                id: id,
                hostID: record["sessionId"] as? String,
                title: (record["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                cwd: cwd,
                project: ProjectName.from(cwd: cwd),
                lastActive: Date(timeIntervalSince1970: millis / 1000),
                isArchived: record["isArchived"] as? Bool ?? false,
                parentTitle: (record["forkedFromSessionId"] as? String).flatMap { titleByHost[$0] },
                source: .desktop,
                transcript: transcripts[id])
            if let existing = byID[id], existing.lastActive >= session.lastActive { continue }
            byID[id] = session
        }
        return Array(byID.values)
    }

    /// `claude-code-sessions/<group>/<group>/local_<id>.json`
    private func metadataFiles() -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []
        for group in (try? fm.contentsOfDirectory(at: locations.desktopSessions, includingPropertiesForKeys: nil)) ?? [] {
            for inner in (try? fm.contentsOfDirectory(at: group, includingPropertiesForKeys: nil)) ?? [] {
                for file in (try? fm.contentsOfDirectory(at: inner, includingPropertiesForKeys: nil)) ?? []
                where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
                    files.append(file)
                }
            }
        }
        return files
    }

    // MARK: - Claude Code in the terminal (and editors)

    /// Transcripts the desktop app doesn't list. Desktop-created ones without metadata are
    /// sessions the app has deleted or never showed; `sdk-*` ones are scripted runs.
    private func terminalSessions(transcripts: [String: URL]) -> [Session] {
        var sessions: [Session] = []
        for (id, url) in transcripts {
            guard let stamp = stamp(of: url) else { continue }
            let head = cachedHead(url, stamp: stamp)
            let entrypoint = head.entrypoint ?? ""
            if entrypoint == "claude-desktop" || entrypoint.hasPrefix("sdk") { continue }
            sessions.append(Session(
                id: id, title: "", cwd: head.cwd, project: ProjectName.from(cwd: head.cwd),
                lastActive: stamp.modified, source: .cli, transcript: url))
        }
        return sessions
    }

    /// `projects/<folder>/<session-id>.jsonl` → [session-id: file]
    private func transcriptIndex() -> [String: URL] {
        let fm = FileManager.default
        var index: [String: URL] = [:]
        for folder in (try? fm.contentsOfDirectory(at: locations.projects, includingPropertiesForKeys: nil)) ?? [] {
            for file in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            where file.pathExtension == "jsonl" {
                index[file.deletingPathExtension().lastPathComponent] = file
            }
        }
        return index
    }

    // MARK: - Details

    private func withDetails(_ sessions: [Session]) -> [Session] {
        let filled = Locked(sessions)
        DispatchQueue.concurrentPerform(iterations: sessions.count) { index in
            var session = sessions[index]
            guard let url = session.transcript, let stamp = stamp(of: url) else { return }
            let isTerminal = session.source == .cli
            // The app only saves its own timestamps now and then; the transcript is written as work happens.
            session.lastActive = max(session.lastActive, stamp.modified)
            let tail = cachedTail(url, stamp: stamp, wantsTitle: isTerminal)
            session.lastPrompt = tail.lastPrompt
            if isTerminal {
                session.title = tail.customTitle
                    ?? cachedHead(url, stamp: stamp, needsPrompt: true).firstPrompt.map { String($0.prefix(80)) }
                    ?? ""
            }
            filled.mutate { $0[index] = session }
        }
        return filled.value
    }

    private func stamp(of url: URL) -> Stamp? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize, let modified = values.contentModificationDate else { return nil }
        return Stamp(size: size, modified: modified)
    }

    private func cachedHead(_ url: URL, stamp: Stamp, needsPrompt: Bool = false) -> TranscriptHead {
        lock.lock()
        let cached = heads[url]
        lock.unlock()
        if let cached, cached.stamp == stamp, !needsPrompt || cached.searchedPrompt { return cached.head }
        let head = TranscriptReader.head(of: url, needsPrompt: needsPrompt)
        lock.lock()
        heads[url] = (stamp, head, needsPrompt)
        lock.unlock()
        return head
    }

    private func cachedTail(_ url: URL, stamp: Stamp, wantsTitle: Bool) -> TranscriptTail {
        lock.lock()
        let cached = tails[url]
        lock.unlock()
        if let cached, cached.stamp == stamp, !wantsTitle || cached.soughtTitle { return cached.tail }
        let tail = TranscriptReader.tail(of: url, wantsTitle: wantsTitle)
        lock.lock()
        tails[url] = (stamp, tail, wantsTitle)
        lock.unlock()
        return tail
    }
}

/// A value shared between threads, guarded by a lock.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&stored)
    }
}
