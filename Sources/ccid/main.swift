import CCIDCore
import Foundation

let environment = ProcessInfo.processInfo.environment
let chinese = Formatting.prefersChinese
func text(_ english: String, _ zh: String) -> String { chinese ? zh : english }

let help = text("""
    ccid — find Claude Code session IDs

    Usage
      ccid                  recent sessions
      ccid <words>…         filter by title, folder, pinyin, or the last thing you said
      ccid -g "a phrase"    sessions whose transcript contains the phrase

    Options
      -1, --id              print only the best match's ID (for scripts)
      -c, --copy            copy the best match's ID to the clipboard
      -r, --resume          print a command that reopens it: cd … && claude --resume …
      -l, --long            add a line with the last thing you said
      -a, --all             include archived sessions in the list
      -n, --limit N         show at most N sessions (default 15)
          --json            print JSON
      -h, --help            show this help
          --version         show the version
    """, """
    ccid —— 查 Claude Code 会话 ID

    用法
      ccid                  最近的会话
      ccid 关键词…          按标题、文件夹、拼音或最后说的话筛
      ccid -g "一句话"      在全部记录里找说过这句话的会话

    选项
      -1, --id              只输出最匹配那个的 ID（给脚本用）
      -c, --copy            复制最匹配那个的 ID
      -r, --resume          输出回到那个会话的命令：cd … && claude --resume …
      -l, --long            每个会话多一行：最后说的话
      -a, --all             列表里也显示已归档的
      -n, --limit N         最多显示几个（默认 15）
          --json            输出 JSON
      -h, --help            显示帮助
          --version         显示版本
    """)

struct Options {
    var words: [String] = []
    var phrase: String?
    var idOnly = false
    var copy = false
    var resume = false
    var long = false
    var all = false
    var json = false
    var limit = 15
}

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func parse(_ arguments: [String]) -> Options {
    var options = Options()
    var rest = arguments[...]
    while let argument = rest.popFirst() {
        switch argument {
        case "-1", "--id": options.idOnly = true
        case "-c", "--copy": options.copy = true
        case "-r", "--resume": options.resume = true
        case "-l", "--long": options.long = true
        case "-a", "--all": options.all = true
        case "--json": options.json = true
        case "-g", "--grep":
            guard let phrase = rest.popFirst(), !phrase.isEmpty else {
                fail(text("ccid: -g needs a phrase", "ccid：-g 后面要跟一句话"), code: 2)
            }
            options.phrase = phrase
        case "-n", "--limit":
            guard let value = rest.popFirst().flatMap(Int.init), value > 0 else {
                fail(text("ccid: -n needs a positive number", "ccid：-n 后面要跟正整数"), code: 2)
            }
            options.limit = value
        case "-h", "--help":
            print(help)
            exit(0)
        case "--version":
            print("ccid \(CCID.version)")
            exit(0)
        case "--":
            options.words += rest
            rest = []
        default:
            if argument.hasPrefix("-"), argument.count > 1 {
                fail(text("ccid: unknown option \(argument)\n\n", "ccid：没有这个选项 \(argument)\n\n") + help, code: 2)
            }
            options.words.append(argument)
        }
    }
    return options
}

// MARK: - Output

let colored = isatty(STDOUT_FILENO) != 0 && environment["NO_COLOR"] == nil
func style(_ text: String, _ code: String) -> String { colored && !text.isEmpty ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text }
func dim(_ text: String) -> String { style(text, "2") }
func bold(_ text: String) -> String { style(text, "1") }

func terminalWidth() -> Int {
    var size = winsize()
    if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 { return Int(size.ws_col) }
    return Int(environment["COLUMNS"] ?? "") ?? 100
}

func pad(_ text: String, to width: Int, right: Bool = false) -> String {
    let gap = String(repeating: " ", count: max(0, width - Formatting.displayWidth(text)))
    return right ? gap + text : text + gap
}

func highlight(_ snippet: String, _ phrase: String) -> String {
    guard colored, let range = snippet.range(of: phrase) ?? snippet.range(of: phrase, options: .caseInsensitive) else {
        return snippet
    }
    return String(snippet[..<range.lowerBound]) + style(String(snippet[range]), "1;33") + String(snippet[range.upperBound...])
}

func render(_ sessions: [Session], hits: [String: TranscriptHit], options: Options) {
    let now = Date()
    let width = terminalWidth()
    let current = environment["CLAUDE_CODE_SESSION_ID"]
    let shown = Array(sessions.prefix(options.limit))
    let whens = shown.map { Formatting.relative($0.lastActive, now: now) }
    let whenWidth = whens.map(Formatting.displayWidth).max() ?? 0
    let projectWidth = min(16, shown.map { Formatting.displayWidth($0.project) }.max() ?? 0)
    for (session, when) in zip(shown, whens) {
        let mark = session.id == current ? style("●", "32") + " " : "  "
        var line = mark + bold(session.id) + "  " + dim(pad(when, to: whenWidth, right: true)) + "  "
        if projectWidth > 0 {
            line += dim(pad(Formatting.truncate(session.project, width: projectWidth), to: projectWidth)) + "  "
        }
        let used = 2 + 36 + 2 + whenWidth + 2 + (projectWidth > 0 ? projectWidth + 2 : 0)
        var notes = ""
        if let parent = session.parentTitle { notes += "  ↳ " + parent }
        if session.isArchived { notes += text("  · archived", "  · 已归档") }
        let title = session.title.isEmpty ? text("(untitled)", "（无标题）") : session.title
        let room = max(12, width - used)
        let titleText = Formatting.truncate(title, width: room)
        let noteText = Formatting.truncate(notes, width: max(0, room - Formatting.displayWidth(titleText)))
        print(line + titleText + dim(noteText))
        if let hit = hits[session.id] {
            let who: String
            switch hit.speaker {
            case .you: who = text("you", "你")
            case .claude: who = "Claude"
            case .tool: who = text("tool", "工具")
            }
            let body = Formatting.truncate(hit.snippet, width: max(20, width - 6 - Formatting.displayWidth(who)))
            print("    " + dim(who + text(": ", "：")) + highlight(body, options.phrase ?? ""))
        } else if options.long, let said = session.lastPrompt {
            print("    " + dim("› " + Formatting.truncate(said, width: max(20, width - 6))))
        }
    }
    if sessions.count > shown.count {
        let more = sessions.count - shown.count
        print(dim(text("  … \(more) more (-n to show more)", "  …还有 \(more) 个（用 -n 多显示）")))
    }
}

func printJSON(_ sessions: [Session], hits: [String: TranscriptHit]) {
    let iso = ISO8601DateFormatter()
    let objects: [[String: Any]] = sessions.map { session in
        var object: [String: Any] = [
            "id": session.id,
            "title": session.title,
            "project": session.project,
            "lastActive": iso.string(from: session.lastActive),
            "archived": session.isArchived,
            "source": session.source.rawValue,
            "resumeCommand": session.resumeCommand,
        ]
        if let cwd = session.cwd { object["cwd"] = cwd }
        if let parent = session.parentTitle { object["forkedFrom"] = parent }
        if let said = session.lastPrompt { object["lastPrompt"] = said }
        if let hit = hits[session.id] { object["match"] = ["speaker": hit.speaker.rawValue, "snippet": hit.snippet] }
        return object
    }
    let data = (try? JSONSerialization.data(
        withJSONObject: objects, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("[]".utf8)
    print(String(decoding: data, as: UTF8.self))
}

func copyToClipboard(_ value: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["pbcopy"]
    let input = Pipe()
    process.standardInput = input
    do { try process.run() } catch { return false }
    input.fileHandleForWriting.write(Data(value.utf8))
    try? input.fileHandleForWriting.close()
    process.waitUntilExit()
    return process.terminationStatus == 0
}

// MARK: - Run

let options = parse(Array(CommandLine.arguments.dropFirst()))
let store = SessionStore(demo: environment["CCID_DEMO"] == "1")
let sessions = store.sessions()
let query = options.words.joined(separator: " ")
var results: [Session]
var hits: [String: TranscriptHit] = [:]

if let phrase = options.phrase {
    let searching = isatty(STDERR_FILENO) != 0 && !options.json
    if searching {
        FileHandle.standardError.write(Data(dim(text("Searching \(sessions.count) transcripts…", "正在搜 \(sessions.count) 份记录…")).utf8))
    }
    for hit in await TranscriptSearch.search(phrase, in: sessions) { hits[hit.sessionID] = hit }
    if searching { FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8)) }
    let found = sessions.filter { hits[$0.id] != nil }
    results = query.isEmpty ? found : SessionSearch.rank(found, query: query)
} else if !query.isEmpty {
    results = SessionSearch.rank(sessions, query: query)
} else {
    results = options.all ? sessions : sessions.filter { !$0.isArchived }
}

guard let best = results.first else {
    if sessions.isEmpty {
        fail(text("No Claude Code sessions found.", "没找到任何 Claude Code 会话。"), code: 1)
    }
    let asked = options.phrase ?? query
    fail(text("Nothing matches “\(asked)”.", "没有匹配“\(asked)”的会话。"), code: 1)
}

if options.idOnly {
    print(best.id)
} else if options.resume {
    print(best.resumeCommand)
} else if options.copy {
    guard copyToClipboard(best.id) else { fail(text("ccid: couldn't reach the clipboard", "ccid：剪贴板用不了"), code: 1) }
    let title = best.title.isEmpty ? text("(untitled)", "（无标题）") : best.title
    FileHandle.standardError.write(Data((text("Copied ", "已复制 ") + bold(best.id) + dim("  " + title) + "\n").utf8))
} else if options.json {
    printJSON(Array(results.prefix(options.limit)), hits: hits)
} else {
    render(results, hits: hits, options: options)
}
