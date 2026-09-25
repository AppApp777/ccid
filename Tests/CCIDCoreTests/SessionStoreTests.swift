import Foundation
import Testing
@testable import CCIDCore

@Suite struct SessionStoreTests {
    private let base = Date(timeIntervalSince1970: 1_780_000_000)

    private func millis(_ date: Date) -> Double { date.timeIntervalSince1970 * 1000 }

    @Test func desktopSessionsComeFromTheAppsMetadata() throws {
        let fixture = try Fixture()
        try fixture.desktop([
            "cliSessionId": "aaaa1111", "title": "Onboarding", "cwd": "/Users/demo/code/web",
            "lastActivityAt": millis(base), "isArchived": false,
        ], host: "local_parent")
        try fixture.desktop([
            "cliSessionId": "bbbb2222", "title": "Onboarding (fork)", "cwd": "/Users/demo/code/web",
            "lastActivityAt": millis(base + 60), "forkedFromSessionId": "local_parent",
        ], host: "local_child")
        try fixture.desktop([
            "cliSessionId": "cccc3333", "title": "Old spike", "lastFocusedAt": millis(base - 3600), "isArchived": true,
        ], host: "local_old")
        try fixture.transcript("aaaa1111", records: [
            Fixture.header(cwd: "/Users/demo/code/web", entrypoint: "claude-desktop"),
            Fixture.user("Tighten the copy on step two"),
        ], modified: base - 7200)

        let sessions = SessionStore(locations: fixture.locations).sessions()
        #expect(sessions.map(\.id) == ["bbbb2222", "aaaa1111", "cccc3333"])
        let child = try #require(sessions.first)
        #expect(child.parentTitle == "Onboarding")
        #expect(child.isFork)
        #expect(child.project == "web")
        let parent = sessions[1]
        #expect(parent.lastPrompt == "Tighten the copy on step two")
        #expect(parent.lastActive == base, "an older transcript must not pull the time back")
        #expect(sessions[2].isArchived)
    }

    @Test func aBusyTranscriptOutranksStaleMetadata() throws {
        let fixture = try Fixture()
        try fixture.desktop(["cliSessionId": "aaaa1111", "title": "Quiet", "lastActivityAt": millis(base)], host: "local_a")
        try fixture.desktop(["cliSessionId": "bbbb2222", "title": "Busy", "lastActivityAt": millis(base - 600)], host: "local_b")
        try fixture.transcript("bbbb2222", records: [Fixture.user("Still going")], modified: base + 300)
        let sessions = SessionStore(locations: fixture.locations).sessions()
        #expect(sessions.map(\.title) == ["Busy", "Quiet"])
        #expect(sessions[0].lastActive == base + 300)
    }

    @Test func duplicateMetadataKeepsTheNewest() throws {
        let fixture = try Fixture()
        try fixture.desktop(["cliSessionId": "aaaa1111", "title": "Before", "lastActivityAt": millis(base)], host: "local_1")
        try fixture.desktop(["cliSessionId": "aaaa1111", "title": "After", "lastActivityAt": millis(base + 5)], host: "local_2")
        let sessions = SessionStore(locations: fixture.locations).sessions()
        #expect(sessions.map(\.title) == ["After"])
    }

    @Test func terminalSessionsAreNamedByTitleOrFirstPrompt() throws {
        let fixture = try Fixture()
        try fixture.transcript("dddd4444", records: [
            Fixture.header(cwd: "/Users/demo/code/api", entrypoint: "cli"),
            Fixture.user("Profile the slow endpoint"),
            Fixture.customTitle("Latency hunt"),
            Fixture.user("Try the index on user_id"),
        ], modified: base)
        try fixture.transcript("eeee5555", records: [
            Fixture.header(cwd: "/Users/demo/code/api", entrypoint: "cli"),
            Fixture.user("Explain the retry loop"),
        ], modified: base - 60)
        let sessions = SessionStore(locations: fixture.locations).sessions()
        #expect(sessions.map(\.title) == ["Latency hunt", "Explain the retry loop"])
        #expect(sessions.allSatisfy { $0.source == .cli && $0.project == "api" })
        #expect(sessions[0].lastPrompt == "Try the index on user_id")
    }

    @Test func scriptedAndDeletedDesktopRunsStayHidden() throws {
        let fixture = try Fixture()
        try fixture.transcript("ffff6666", records: [Fixture.header(cwd: "/tmp", entrypoint: "sdk-cli")])
        try fixture.transcript("abab7777", records: [Fixture.header(cwd: "/tmp", entrypoint: "claude-desktop")])
        try fixture.transcript("cdcd8888", records: [Fixture.header(cwd: "/tmp", entrypoint: "cli")])
        let sessions = SessionStore(locations: fixture.locations).sessions()
        #expect(sessions.map(\.id) == ["cdcd8888"])
    }

    @Test func demoModeNeverTouchesTheDisk() {
        let nowhere = Locations(desktopSessions: URL(fileURLWithPath: "/nonexistent/a"),
                                projects: URL(fileURLWithPath: "/nonexistent/b"))
        let sessions = SessionStore(locations: nowhere, demo: true).sessions()
        #expect(sessions.count == 9)
        #expect(sessions.allSatisfy { $0.transcript == nil })
    }

    @Test func claudeConfigDirMovesTheTranscripts() {
        let custom = Locations.standard(environment: ["CLAUDE_CONFIG_DIR": "/opt/claude-config"])
        #expect(custom.projects.path == "/opt/claude-config/projects")
        #expect(Locations.standard(environment: [:]).projects.path.hasSuffix("/.claude/projects"))
    }
}

@Suite struct SessionTests {
    @Test func projectNames() {
        #expect(ProjectName.from(cwd: "/Users/demo", home: "/Users/demo") == "~")
        #expect(ProjectName.from(cwd: "/Users/demo/code/web/", home: "/Users/demo") == "web")
        #expect(ProjectName.from(cwd: "/Users/demo/code/web/.claude/worktrees/brave-otter", home: "/x") == "web")
        #expect(ProjectName.from(cwd: "/private/tmp/scratch-workspaces/abc", home: "/x") == "scratch")
        #expect(ProjectName.from(cwd: nil) == "")
    }

    @Test func resumeCommandQuotesTheFolder() {
        let plain = Session(id: "1234abcd", title: "", cwd: "/Users/demo/code/web", project: "web", lastActive: Date())
        #expect(plain.resumeCommand == "cd /Users/demo/code/web && claude --resume 1234abcd")
        let spaced = Session(id: "1234abcd", title: "", cwd: "/Users/demo/My Code/it's", project: "", lastActive: Date())
        #expect(spaced.resumeCommand == #"cd '/Users/demo/My Code/it'\''s' && claude --resume 1234abcd"#)
        let nowhere = Session(id: "1234abcd", title: "", project: "", lastActive: Date())
        #expect(nowhere.resumeCommand == "claude --resume 1234abcd")
        #expect(plain.shortID == "1234abcd")
    }
}
