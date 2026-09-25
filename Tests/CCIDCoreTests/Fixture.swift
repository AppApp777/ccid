import Foundation
@testable import CCIDCore

/// A throwaway `~/.claude/projects` and desktop-app folder, so tests never read anyone's real sessions.
final class Fixture {
    let root: URL
    let locations: Locations

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ccid-tests-\(UUID().uuidString)")
        locations = Locations(
            desktopSessions: root.appendingPathComponent("claude-code-sessions"),
            projects: root.appendingPathComponent("projects"))
        try FileManager.default.createDirectory(at: locations.desktopSessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: locations.projects, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    /// Writes `projects/<folder>/<id>.jsonl`, one JSON object per line.
    @discardableResult
    func transcript(_ id: String, folder: String = "-Users-demo-code-app", records: [[String: Any]],
                    modified: Date? = nil) throws -> URL {
        let directory = locations.projects.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(id).jsonl")
        try Data(records.map(Fixture.line).joined().utf8).write(to: url)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url
    }

    /// Writes the desktop app's `claude-code-sessions/<group>/<group>/local_<host>.json`.
    func desktop(_ record: [String: Any], host: String) throws {
        let directory = locations.desktopSessions.appendingPathComponent("group/inner")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var record = record
        record["sessionId"] = host
        try JSONSerialization.data(withJSONObject: record).write(to: directory.appendingPathComponent("\(host).json"))
    }

    static func line(_ record: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    // Transcript records, shaped like Claude Code's.

    static func header(cwd: String, entrypoint: String) -> [String: Any] {
        ["type": "system", "cwd": cwd, "entrypoint": entrypoint]
    }

    static func user(_ text: String, human: Bool = true) -> [String: Any] {
        var record: [String: Any] = ["type": "user", "message": ["role": "user", "content": text]]
        if human { record["origin"] = ["kind": "human"] }
        return record
    }

    static func assistant(_ text: String) -> [String: Any] {
        ["type": "assistant", "message": ["role": "assistant", "content": [["type": "text", "text": text]]]]
    }

    static func toolResult(_ text: String) -> [String: Any] {
        ["type": "user", "toolUseResult": ["stdout": text],
         "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t1", "content": text]]]]
    }

    static func lastPrompt(_ text: String) -> [String: Any] {
        ["type": "last-prompt", "lastPrompt": text]
    }

    static func customTitle(_ text: String) -> [String: Any] {
        ["type": "custom-title", "customTitle": text]
    }
}
