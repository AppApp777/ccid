import Foundation

/// Made-up sessions for screenshots and demos (`CCID_DEMO=1`), so nobody's real work is on show.
public enum DemoSessions {
    public static func make(now: Date = Date(), chinese: Bool = Formatting.prefersChinese) -> [Session] {
        let rows = chinese ? chineseRows : englishRows
        return rows.enumerated().map { index, row in
            Session(
                id: ids[index],
                hostID: "local_demo\(index)",
                title: row.title,
                cwd: "/Users/demo/code/\(row.project)",
                project: row.project,
                lastActive: now.addingTimeInterval(-row.minutesAgo * 60),
                isArchived: row.archived,
                parentTitle: row.forkOf,
                source: .desktop,
                transcript: nil,
                lastPrompt: row.said)
        }
    }

    private struct Row {
        let title: String
        let project: String
        let minutesAgo: Double
        let said: String
        var forkOf: String? = nil
        var archived = false
    }

    private static let ids = [
        "3f9c2a71-5b8e-4d0a-9e6f-1c2b7d8a4e10", "8a41d0c3-27f6-4b19-a3e2-5d9f0b6c7e21",
        "c7e205b9-9d13-4f8a-b640-2e7a1f93d5c8", "15b8f6e2-a4c7-4e3d-8f91-0c6d2b7a9e34",
        "e2d94a17-6c3b-4f05-9a8e-7b1c5d3f6a02", "9b0c7e4d-1f82-4a6c-b3d5-8e2f4a7c1b96",
        "4d6a1c8e-3b97-4e2f-a0c5-6f8b2d9e3a71", "a8f3e9b2-5c14-4d7a-8e60-3b9c1f4d2e85",
        "6e1b4d9a-8f25-4c3e-b7a1-2d5c9e0f8b43",
    ]

    private static let englishRows: [Row] = [
        Row(title: "Refactor auth middleware", project: "api-server", minutesAgo: 2,
            said: "Split token refresh into its own module, keep the old export for now"),
        Row(title: "Onboarding flow polish (fork)", project: "web-app", minutesAgo: 26,
            said: "Try the version where step two can be skipped", forkOf: "Onboarding flow polish"),
        Row(title: "Flaky CI on arm64 runners", project: "infra", minutesAgo: 95,
            said: "Run the failing job twenty times with the cache disabled"),
        Row(title: "Pricing page copy", project: "marketing-site", minutesAgo: 240,
            said: "Make the annual plan the default and cut the FAQ to five questions"),
        Row(title: "Weekly metrics notebook", project: "analytics", minutesAgo: 60 * 26,
            said: "Group retention by signup week, not calendar week"),
        Row(title: "Migrate settings to SwiftData", project: "ios-app", minutesAgo: 60 * 50,
            said: "Keep a read-only fallback for people still on the old schema"),
        Row(title: "Release notes 2.4", project: "docs", minutesAgo: 60 * 75,
            said: "Lead with offline mode, it's what people asked for"),
        Row(title: "Onboarding flow polish", project: "web-app", minutesAgo: 60 * 98,
            said: "The progress bar jumps on step three, can you smooth it out?"),
        Row(title: "Rust port of the diff engine", project: "diffcore", minutesAgo: 60 * 24 * 12,
            said: "Benchmark against the C version before we go further", archived: true),
    ]

    private static let chineseRows: [Row] = [
        Row(title: "重构登录中间件", project: "api-server", minutesAgo: 2,
            said: "把刷新令牌拆成单独的模块，旧的导出先留着"),
        Row(title: "新手引导打磨 (fork)", project: "web-app", minutesAgo: 26,
            said: "试试第二步可以跳过的那一版", forkOf: "新手引导打磨"),
        Row(title: "arm64 上的 CI 偶发失败", project: "infra", minutesAgo: 95,
            said: "关掉缓存，把失败的那个任务连跑二十次"),
        Row(title: "定价页文案", project: "marketing-site", minutesAgo: 240,
            said: "默认选年付，常见问题砍到五条"),
        Row(title: "每周数据看板", project: "analytics", minutesAgo: 60 * 26,
            said: "留存按注册周分组，不要按自然周"),
        Row(title: "设置迁移到 SwiftData", project: "ios-app", minutesAgo: 60 * 50,
            said: "旧数据结构的用户保留一个只读兜底"),
        Row(title: "2.4 版更新说明", project: "docs", minutesAgo: 60 * 75,
            said: "开头先讲离线模式，大家最想要的就是这个"),
        Row(title: "新手引导打磨", project: "web-app", minutesAgo: 60 * 98,
            said: "第三步进度条会跳一下，能不能顺一点？"),
        Row(title: "用 Rust 重写 diff 引擎", project: "diffcore", minutesAgo: 60 * 24 * 12,
            said: "先跟 C 版本跑个基准再往下做", archived: true),
    ]
}
