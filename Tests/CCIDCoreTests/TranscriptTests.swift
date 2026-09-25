import Foundation
import Testing
@testable import CCIDCore

@Suite struct TextCleanerTests {
    @Test func dropsInjectedContextAndMarkup() {
        let raw = """
        <system-reminder>Background the user never typed</system-reminder>
        Fix the <b>login</b> bug   <!-- note -->
        in   two places
        """
        #expect(TextCleaner.clean(raw) == "Fix the login bug in two places")
    }

    @Test func nothingLeftIsNil() {
        #expect(TextCleaner.clean("<ide_opened_file>a.swift</ide_opened_file>\n  ") == nil)
    }

    @Test func respectsTheLimit() {
        #expect(TextCleaner.clean(String(repeating: "a ", count: 50), limit: 9) == "a a a a a")
    }
}

@Suite struct TranscriptReaderTests {
    @Test func headFindsFolderEntrypointAndFirstHumanPrompt() throws {
        let fixture = try Fixture()
        let url = try fixture.transcript("s1", records: [
            Fixture.header(cwd: "/Users/demo/code/app", entrypoint: "cli"),
            Fixture.user("<command-message>init</command-message>", human: false),
            Fixture.toolResult("ok"),
            Fixture.user("Make the build faster"),
        ])
        let head = TranscriptReader.head(of: url, needsPrompt: true)
        #expect(head.cwd == "/Users/demo/code/app")
        #expect(head.entrypoint == "cli")
        #expect(head.firstPrompt == "Make the build faster")
    }

    @Test func tailPrefersTheNewestPrompt() throws {
        let fixture = try Fixture()
        let url = try fixture.transcript("s1", records: [
            Fixture.user("First thing I asked"),
            Fixture.assistant("Done."),
            Fixture.user("Now add tests"),
            Fixture.toolResult("12 passed"),
            Fixture.user("[Request interrupted by user]"),
            Fixture.assistant("Stopped."),
        ])
        #expect(TranscriptReader.tail(of: url, wantsTitle: false).lastPrompt == "Now add tests")
    }

    @Test func tailReadsLastPromptRecordsAndTitles() throws {
        let fixture = try Fixture()
        let url = try fixture.transcript("s1", records: [
            Fixture.customTitle("Old name"),
            Fixture.user("Earlier"),
            Fixture.customTitle("Payments cleanup"),
            Fixture.lastPrompt("Ship it <system-reminder>x</system-reminder>"),
        ])
        let tail = TranscriptReader.tail(of: url, wantsTitle: true)
        #expect(tail.lastPrompt == "Ship it")
        #expect(tail.customTitle == "Payments cleanup")
        #expect(TranscriptReader.tail(of: url, wantsTitle: false).customTitle == nil)
    }

    /// Records longer than a read chunk, so lines straddle chunk boundaries in both directions.
    @Test func linesAcrossChunkBoundaries() throws {
        let fixture = try Fixture()
        let long = String(repeating: "x", count: 300 << 10)
        let url = try fixture.transcript("s1", records: [
            Fixture.header(cwd: "/tmp/far", entrypoint: "cli"),
            Fixture.assistant(long),
            Fixture.user("The one after the long reply"),
            Fixture.assistant(long),
            Fixture.assistant(long),
        ])
        #expect(TranscriptReader.tail(of: url, wantsTitle: false).lastPrompt == "The one after the long reply")
        #expect(TranscriptReader.head(of: url, needsPrompt: true).firstPrompt == "The one after the long reply")
    }

    @Test func machineMessagesAreNotHuman() {
        #expect(TranscriptReader.humanText(Fixture.toolResult("output")) == nil)
        #expect(TranscriptReader.humanText(Fixture.user("<task-notification>done</task-notification>", human: false)) == nil)
        var meta = Fixture.user("Caveat")
        meta["isMeta"] = true
        #expect(TranscriptReader.humanText(meta) == nil)
        var agent = Fixture.user("From another agent")
        agent["origin"] = ["kind": "task"]
        #expect(TranscriptReader.humanText(agent) == nil)
        #expect(TranscriptReader.humanText(Fixture.user("Plain words", human: false)) == "Plain words")
    }
}

@Suite struct TranscriptSearchTests {
    @Test func findsTheLatestMentionAndWhoSaidIt() async throws {
        let fixture = try Fixture()
        let url = try fixture.transcript("s1", records: [
            Fixture.assistant("The progress bar is drawn in ProgressView.swift"),
            Fixture.user("Why does the progress bar jump on step three?"),
        ])
        let session = Session(id: "s1", title: "t", project: "app", lastActive: Date(), transcript: url)
        let hits = await TranscriptSearch.search("progress bar", in: [session])
        #expect(hits.count == 1)
        #expect(hits.first?.speaker == .you)
        #expect(hits.first?.snippet.contains("jump on step three") == true)
    }

    @Test func ignoresCaseAndFindsQuotedText() throws {
        let fixture = try Fixture()
        let url = try fixture.transcript("s1", records: [
            Fixture.assistant("Set the header to \"Hello, world\" and move on"),
        ])
        #expect(TranscriptSearch.find("Hello, World", in: url, sessionID: "s1")?.speaker == .claude)
        #expect(TranscriptSearch.find("\"Hello, world\"", in: url, sessionID: "s1") != nil)
        #expect(TranscriptSearch.find("goodbye", in: url, sessionID: "s1") == nil)
    }

    @Test func toolOutputIsLabelled() throws {
        let fixture = try Fixture()
        let url = try fixture.transcript("s1", records: [Fixture.toolResult("error: missing semicolon")])
        #expect(TranscriptSearch.find("missing semicolon", in: url, sessionID: "s1")?.speaker == .tool)
    }

    @Test func snippetsAreShortOneLineWindows() {
        let text = String(repeating: "lead ", count: 20) + "needle\nhere" + String(repeating: " tail", count: 40)
        let snippet = TranscriptSearch.window(text, around: "needle")
        #expect(snippet.hasPrefix("…") && snippet.hasSuffix("…"))
        #expect(!snippet.contains("\n"))
        #expect(snippet.count < 130)
    }
}
