import Foundation
import Testing
@testable import CCIDCore

@Suite struct SessionSearchTests {
    private func session(_ title: String, id: String = UUID().uuidString.lowercased(), project: String = "app",
                         said: String? = nil, archived: Bool = false, minutesAgo: Double = 0) -> Session {
        Session(id: id, title: title, project: project,
                lastActive: Date(timeIntervalSince1970: 1_780_000_000 - minutesAgo * 60),
                isArchived: archived, lastPrompt: said)
    }

    @Test func titleStartBeatsTitleMiddle() {
        let ranked = SessionSearch.rank([session("Fix the deploy script"), session("Deploy dashboard")], query: "deploy")
        #expect(ranked.map(\.title) == ["Deploy dashboard", "Fix the deploy script"])
    }

    @Test func everyWordMustMatch() {
        let ranked = SessionSearch.rank(
            [session("Pricing page copy", project: "site"), session("Pricing API", project: "api")],
            query: "pricing site")
        #expect(ranked.map(\.title) == ["Pricing page copy"])
    }

    @Test func idPrefixesNeedThreeCharacters() {
        let target = session("Anything", id: "3f9c2a71-5b8e-4d0a-9e6f-1c2b7d8a4e10")
        #expect(SessionSearch.rank([target], query: "3f9").count == 1)
        #expect(SessionSearch.rank([target], query: "3f").isEmpty)
    }

    @Test func pinyinFindsChineseTitles() {
        let sessions = [session("自媒体选题"), session("重构登录中间件"), session("修一下第三行的弹窗")]
        func titles(_ query: String) -> [String] { SessionSearch.rank(sessions, query: query).map(\.title) }
        #expect(titles("zmt") == ["自媒体选题"])
        #expect(titles("zimeiti") == ["自媒体选题"])
        #expect(titles("xuanti") == ["自媒体选题"])
        #expect(titles("cg") == ["重构登录中间件"], "重 reads chong here, not the transliterator's zhong")
        #expect(titles("chonggou") == ["重构登录中间件"])
        #expect(titles("chongg") == ["重构登录中间件"], "the last syllable can be half typed")
        #expect(titles("tanchuang") == ["修一下第三行的弹窗"])
        #expect(titles("dsh") == ["修一下第三行的弹窗"])
        #expect(titles("ou").isEmpty, "matches start at a character, never mid-syllable")
        #expect(titles("x") == ["修一下第三行的弹窗"], "one letter only matches the first character, not 选")
    }

    @Test func archivedSessionsSinkAndOldPromptsStillCount() {
        let ranked = SessionSearch.rank([
            session("Release notes", archived: true),
            session("Release checklist", minutesAgo: 90),
            session("Unrelated", said: "draft the release email"),
        ], query: "release")
        #expect(ranked.map(\.title) == ["Release checklist", "Release notes", "Unrelated"])
    }

    @Test func widthAndCaseDoNotMatter() {
        #expect(SessionSearch.rank([session("ＡＰＩ Gateway")], query: "api gateway").count == 1)
    }
}

@Suite struct FormattingTests {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    @Test func relativeTimes() {
        #expect(Formatting.relative(now - 20, now: now, chinese: false) == "now")
        #expect(Formatting.relative(now - 300, now: now, chinese: false) == "5m")
        #expect(Formatting.relative(now - 300, now: now, chinese: true) == "5 分钟前")
        #expect(Formatting.relative(now - 3 * 3600, now: now, chinese: false) == "3h")
        #expect(Formatting.relative(now - 4 * 86400, now: now, chinese: true) == "4 天前")
    }

    @Test func terminalWidths() {
        #expect(Formatting.displayWidth("abc") == 3)
        #expect(Formatting.displayWidth("会话") == 4)
        #expect(Formatting.truncate("会话编号查找", width: 7) == "会话编…")
        #expect(Formatting.truncate("short", width: 10) == "short")
    }
}
