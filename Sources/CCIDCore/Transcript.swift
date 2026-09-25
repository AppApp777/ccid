import Foundation

/// Turns raw prompt text into one clean line: no injected context blocks, no markup, no line breaks.
public enum TextCleaner {
    private static let comments = try! NSRegularExpression(pattern: #"<!--[\s\S]*?-->"#)
    private static let injected = try! NSRegularExpression(
        pattern: #"<(system-reminder|ide_opened_file|ide_selection|local-command-caveat|local-command-stdout|command-message|command-args)\b[^>]*>[\s\S]*?</\1>"#)
    private static let tags = try! NSRegularExpression(pattern: #"</?[A-Za-z][\w:-]*(?:\s[^<>]*)?/?>"#)

    public static func clean(_ text: String, limit: Int = 400) -> String? {
        var result = text
        for pattern in [comments, injected, tags] {
            result = pattern.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: " ")
        }
        let words = result.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard !words.isEmpty else { return nil }
        let line = words.joined(separator: " ")
        return line.count > limit ? String(line.prefix(limit)) : line
    }
}

/// What ccid needs from the start of a transcript.
public struct TranscriptHead: Hashable, Sendable {
    public var cwd: String?
    public var entrypoint: String?
    public var firstPrompt: String?
}

/// What ccid needs from the end of a transcript.
public struct TranscriptTail: Hashable, Sendable {
    public var lastPrompt: String?
    public var customTitle: String?
}

/// Reads just enough of a JSONL transcript. Transcripts can be hundreds of megabytes,
/// so nothing here loads a whole file unless the answer is only found at the far end.
public enum TranscriptReader {
    private static let newline = UInt8(ascii: "\n")

    public static func head(of url: URL, needsPrompt: Bool) -> TranscriptHead {
        var head = TranscriptHead()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return head }
        defer { try? handle.close() }
        let limit = needsPrompt ? 2 << 20 : 256 << 10
        var consumed = 0
        var carry = Data()
        while consumed < limit, let chunk = try? handle.read(upToCount: 16 << 10), !chunk.isEmpty {
            consumed += chunk.count
            var data = carry
            data.append(chunk)
            var start = data.startIndex
            while let end = data[start...].firstIndex(of: newline) {
                inspectHead(data[start..<end], into: &head, needsPrompt: needsPrompt)
                if head.cwd != nil, head.entrypoint != nil, !needsPrompt || head.firstPrompt != nil {
                    return head
                }
                start = end + 1
            }
            carry = Data(data[start...])
        }
        return head
    }

    public static func tail(of url: URL, wantsTitle: Bool, byteLimit: Int = 48 << 20) -> TranscriptTail {
        var tail = TranscriptTail()
        guard let handle = try? FileHandle(forReadingFrom: url),
              var offset = try? handle.seekToEnd() else { return tail }
        defer { try? handle.close() }
        var carry = Data()
        var scanned = 0
        // A title is only worth a short look; prompts are worth reading back much further.
        let titleWindow = 2 << 20
        while offset > 0, scanned < byteLimit {
            let size = UInt64(scanned < 256 << 10 ? 64 << 10 : 1 << 20)
            let step = min(size, offset)
            offset -= step
            guard (try? handle.seek(toOffset: offset)) != nil,
                  var data = try? handle.read(upToCount: Int(step)) else { break }
            scanned += data.count
            data.append(carry)
            var body = data[...]
            if offset > 0 {
                guard let first = data.firstIndex(of: newline) else { carry = data; continue }
                carry = Data(data[data.startIndex..<first])
                body = data[(first + 1)...]
            } else {
                carry = Data()
            }
            var end = body.endIndex
            while end > body.startIndex {
                let previous = body[body.startIndex..<end].lastIndex(of: newline)
                let start = previous.map { $0 + 1 } ?? body.startIndex
                if start < end { inspectTail(body[start..<end], into: &tail, wantsTitle: wantsTitle) }
                if tail.lastPrompt != nil, !wantsTitle || tail.customTitle != nil || scanned > titleWindow {
                    return tail
                }
                end = previous ?? body.startIndex
            }
        }
        return tail
    }

    // MARK: - Records

    private static let lastPromptKey = Data("\"last-prompt\"".utf8)
    private static let customTitleKey = Data("\"custom-title\"".utf8)
    private static let userKey = Data("\"user\"".utf8)
    private static let toolUseKey = Data("\"tool_use_id\"".utf8)

    private static func inspectTail(_ line: Data, into tail: inout TranscriptTail, wantsTitle: Bool) {
        if tail.lastPrompt == nil {
            if line.range(of: lastPromptKey) != nil, let record = parse(line),
               record["type"] as? String == "last-prompt", let prompt = record["lastPrompt"] as? String {
                tail.lastPrompt = TextCleaner.clean(prompt)
            } else if line.range(of: userKey) != nil, line.range(of: toolUseKey) == nil,
                      let record = parse(line), let text = humanText(record) {
                tail.lastPrompt = text
            }
        }
        if wantsTitle, tail.customTitle == nil, line.range(of: customTitleKey) != nil, let record = parse(line),
           record["type"] as? String == "custom-title", let title = record["customTitle"] as? String {
            tail.customTitle = TextCleaner.clean(title, limit: 200)
        }
    }

    private static func inspectHead(_ line: Data, into head: inout TranscriptHead, needsPrompt: Bool) {
        guard let record = parse(line) else { return }
        if head.cwd == nil, let cwd = record["cwd"] as? String, !cwd.isEmpty { head.cwd = cwd }
        if head.entrypoint == nil, let entrypoint = record["entrypoint"] as? String { head.entrypoint = entrypoint }
        if needsPrompt, head.firstPrompt == nil, let text = humanText(record) { head.firstPrompt = text }
    }

    static func parse(_ line: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }

    /// The text of a message the person typed; nil for tool output, injected context and system notes.
    static func humanText(_ record: [String: Any]) -> String? {
        guard record["type"] as? String == "user" else { return nil }
        if record["isMeta"] as? Bool == true || record["isCompactSummary"] as? Bool == true { return nil }
        if let result = record["toolUseResult"], !(result is NSNull) { return nil }
        let origin = record["origin"] as? [String: Any]
        if let origin, origin["kind"] as? String != "human" { return nil }
        guard let message = record["message"] as? [String: Any] else { return nil }
        let text: String
        if let content = message["content"] as? String {
            text = content
        } else if let blocks = message["content"] as? [[String: Any]] {
            if blocks.contains(where: { $0["type"] as? String == "tool_result" }) { return nil }
            text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: " ")
        } else {
            return nil
        }
        if origin == nil, text.drop(while: \.isWhitespace).hasPrefix("<") { return nil }
        guard let clean = TextCleaner.clean(text), !clean.hasPrefix("[Request interrupted") else { return nil }
        return clean
    }
}
