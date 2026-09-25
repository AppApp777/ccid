import Foundation

/// One Claude Code conversation, as it appears in the Claude app's sidebar or in the terminal.
public struct Session: Identifiable, Hashable, Sendable {
    public enum Source: String, Hashable, Sendable {
        case desktop
        case cli
    }

    /// The ID Claude Code uses everywhere: the transcript's file name and `claude --resume <id>`.
    public var id: String
    /// The desktop app's own handle for the session (`local_…`), when it lives there.
    public var hostID: String?
    /// Empty when the session has no title yet; callers show their own placeholder.
    public var title: String
    public var cwd: String?
    public var project: String
    public var lastActive: Date
    public var isArchived: Bool
    /// Set when the session was forked from another one; forking always creates a new ID.
    public var parentTitle: String?
    public var source: Source
    public var transcript: URL?
    /// The last thing typed into the session, cleaned up for display.
    public var lastPrompt: String?

    public init(
        id: String, hostID: String? = nil, title: String, cwd: String? = nil, project: String,
        lastActive: Date, isArchived: Bool = false, parentTitle: String? = nil,
        source: Source = .desktop, transcript: URL? = nil, lastPrompt: String? = nil
    ) {
        self.id = id
        self.hostID = hostID
        self.title = title
        self.cwd = cwd
        self.project = project
        self.lastActive = lastActive
        self.isArchived = isArchived
        self.parentTitle = parentTitle
        self.source = source
        self.transcript = transcript
        self.lastPrompt = lastPrompt
    }

    public var shortID: String { String(id.prefix(8)) }
    public var isFork: Bool { parentTitle != nil }

    /// A command that reopens this session in the terminal, from the folder it ran in.
    public var resumeCommand: String {
        let resume = "claude --resume \(id)"
        guard let cwd, !cwd.isEmpty else { return resume }
        return "cd \(ShellQuote.quote(cwd)) && \(resume)"
    }
}

public enum ShellQuote {
    private static let safe = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+@%:,=")

    public static func quote(_ text: String) -> String {
        if !text.isEmpty, text.unicodeScalars.allSatisfy(safe.contains) { return text }
        return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum ProjectName {
    /// A short, human name for the folder a session ran in.
    static func from(cwd: String?, home: String = NSHomeDirectory()) -> String {
        guard var path = cwd, !path.isEmpty else { return "" }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        if path == home { return "~" }
        if path.contains("/scratch-workspaces/") { return "scratch" }
        if let worktree = path.range(of: "/.claude/worktrees/") {
            path = String(path[..<worktree.lowerBound])
        }
        return (path as NSString).lastPathComponent
    }
}
