import Foundation

/// Where Claude keeps the files ccid reads. ccid never writes to any of them.
public struct Locations: Sendable, Hashable {
    /// Claude desktop app: one small JSON file per session (title, folder, archive state, forks).
    public var desktopSessions: URL
    /// Claude Code: one JSONL transcript per session, grouped by project folder.
    public var projects: URL

    public init(desktopSessions: URL, projects: URL) {
        self.desktopSessions = desktopSessions
        self.projects = projects
    }

    public static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) -> Locations {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let config: URL
        if let custom = environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            config = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            config = home.appendingPathComponent(".claude", isDirectory: true)
        }
        return Locations(
            desktopSessions: home.appendingPathComponent(
                "Library/Application Support/Claude/claude-code-sessions", isDirectory: true),
            projects: config.appendingPathComponent("projects", isDirectory: true))
    }
}
