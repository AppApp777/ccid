import Foundation

/// A place where a phrase appears in a session's transcript.
public struct TranscriptHit: Hashable, Sendable {
    public enum Speaker: String, Hashable, Sendable {
        case you
        case claude
        case tool
    }

    public var sessionID: String
    public var speaker: Speaker
    /// A short window of text around the phrase, on one line.
    public var snippet: String
}

/// Looks for an exact phrase across whole transcripts, for when a title isn't enough to go on.
public enum TranscriptSearch {
    public static func search(_ phrase: String, in sessions: [Session], concurrency: Int = 4) async -> [TranscriptHit] {
        let targets = sessions.compactMap { session in session.transcript.map { (session.id, $0) } }
        return await withTaskGroup(of: TranscriptHit?.self) { group in
            var pending = targets.makeIterator()
            for _ in 0..<max(1, concurrency) {
                guard let (id, url) = pending.next() else { break }
                group.addTask { find(phrase, in: url, sessionID: id) }
            }
            var hits: [TranscriptHit] = []
            while let result = await group.next() {
                if let result { hits.append(result) }
                if Task.isCancelled { group.cancelAll(); break }
                if let (id, url) = pending.next() {
                    group.addTask { find(phrase, in: url, sessionID: id) }
                }
            }
            return hits
        }
    }

    /// The most recent place the phrase appears, or nil.
    public static func find(_ phrase: String, in url: URL, sessionID: String) -> TranscriptHit? {
        guard !phrase.isEmpty, !Task.isCancelled,
              let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        var last: Int?
        data.withUnsafeBytes { (haystack: UnsafeRawBufferPointer) in
            guard let base = haystack.baseAddress else { return }
            for needle in needles(for: phrase) {
                needle.withUnsafeBytes { (pattern: UnsafeRawBufferPointer) in
                    guard let patternBase = pattern.baseAddress else { return }
                    var start = 0
                    while start < haystack.count,
                          let match = memmem(base + start, haystack.count - start, patternBase, pattern.count) {
                        let offset = base.distance(to: UnsafeRawPointer(match))
                        last = max(last ?? offset, offset)
                        start = offset + 1
                    }
                }
            }
        }
        guard let offset = last else { return nil }
        return hit(around: offset, in: data, phrase: phrase, sessionID: sessionID)
    }

    /// The phrase as typed and in its usual capitalisations, each also as it looks inside a JSON string
    /// (quotes, backslashes, line breaks), so "Progress bar" still finds "progress bar".
    static func needles(for phrase: String) -> [Data] {
        let lower = phrase.lowercased()
        var needles: [Data] = []
        for variant in [phrase, lower, lower.prefix(1).uppercased() + lower.dropFirst()] {
            for form in [variant, jsonEscaped(variant)] where !needles.contains(Data(form.utf8)) {
                needles.append(Data(form.utf8))
            }
        }
        return needles
    }

    private static func jsonEscaped(_ text: String) -> String {
        var escaped = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default:
                if scalar.value < 0x20 { escaped += String(format: "\\u%04x", scalar.value) }
                else { escaped.unicodeScalars.append(scalar) }
            }
        }
        return escaped
    }

    private static func hit(around offset: Int, in data: Data, phrase: String, sessionID: String) -> TranscriptHit {
        let newline = UInt8(ascii: "\n")
        let searchFloor = max(0, offset - (8 << 20))
        let lineStart = data[searchFloor..<offset].lastIndex(of: newline).map { $0 + 1 } ?? searchFloor
        let lineEnd = data[offset...].firstIndex(of: newline) ?? data.endIndex
        if lineEnd - lineStart < 16 << 20,
           let record = TranscriptReader.parse(data.subdata(in: lineStart..<lineEnd)),
           let text = strings(in: record["message"] ?? record)
               .first(where: { $0.range(of: phrase, options: .caseInsensitive) != nil }) {
            return TranscriptHit(sessionID: sessionID, speaker: speaker(of: record), snippet: window(text, around: phrase))
        }
        let from = max(lineStart, offset - 160), to = min(lineEnd, offset + 320)
        let raw = String(decoding: data.subdata(in: from..<to), as: UTF8.self)
        return TranscriptHit(sessionID: sessionID, speaker: .tool, snippet: window(raw, around: phrase))
    }

    private static func speaker(of record: [String: Any]) -> TranscriptHit.Speaker {
        switch record["type"] as? String {
        case "assistant": return .claude
        case "user": return TranscriptReader.humanText(record) != nil ? .you : .tool
        default: return .tool
        }
    }

    private static func strings(in value: Any) -> [String] {
        if let text = value as? String { return [text] }
        if let list = value as? [Any] { return list.flatMap(strings(in:)) }
        if let object = value as? [String: Any] { return object.values.flatMap(strings(in:)) }
        return []
    }

    /// About 30 characters of lead-in and 90 after, collapsed to one line.
    static func window(_ text: String, around phrase: String) -> String {
        let flat = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard let range = flat.range(of: phrase) ?? flat.range(of: phrase, options: .caseInsensitive) else {
            return String(flat.prefix(120))
        }
        let start = flat.index(range.lowerBound, offsetBy: -30, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(range.upperBound, offsetBy: 90, limitedBy: flat.endIndex) ?? flat.endIndex
        return (start > flat.startIndex ? "…" : "") + flat[start..<end] + (end < flat.endIndex ? "…" : "")
    }
}
