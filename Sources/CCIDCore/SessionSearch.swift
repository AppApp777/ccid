import Foundation

/// Ranks sessions against what someone typed. Every word must match somewhere; titles count most,
/// then IDs, folders, pinyin (so `zmt` finds 自媒体), and finally the last thing said.
public enum SessionSearch {
    public static func rank(_ sessions: [Session], query: String) -> [Session] {
        let tokens = query.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }
        guard !tokens.isEmpty else { return sessions }
        var scored: [(session: Session, score: Int)] = []
        for session in sessions {
            let fields = Fields(session)
            var total = 0
            var matchedAll = true
            for token in tokens {
                guard let score = fields.score(token) else { matchedAll = false; break }
                total += score
            }
            guard matchedAll else { continue }
            if session.isArchived { total -= 25 }
            scored.append((session, total))
        }
        return scored.sorted {
            $0.score != $1.score ? $0.score > $1.score : $0.session.lastActive > $1.session.lastActive
        }.map(\.session)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private struct Fields {
        let id: String
        let title: String
        let project: String
        let prompt: String
        let parent: String
        let pinyin: Pinyin?

        init(_ session: Session) {
            id = session.id.lowercased()
            title = SessionSearch.fold(session.title)
            project = SessionSearch.fold(session.project)
            prompt = SessionSearch.fold(session.lastPrompt ?? "")
            parent = SessionSearch.fold(session.parentTitle ?? "")
            pinyin = Pinyin.of(session.title)
        }

        func score(_ token: String) -> Int? {
            var best = 0
            if title.hasPrefix(token) { best = 120 }
            else if (" " + title).contains(" " + token) { best = 100 }
            else if title.contains(token) { best = 80 }
            if token.count >= 3, id.hasPrefix(token) { best = max(best, 110) }
            if project.hasPrefix(token) { best = max(best, 70) }
            else if project.contains(token) { best = max(best, 50) }
            if let score = pinyin?.score(token) { best = max(best, score) }
            if best == 0, prompt.contains(token) { best = 30 }
            if best == 0, parent.contains(token) { best = 15 }
            return best > 0 ? best : nil
        }
    }
}

/// Mandarin readings of a title, so Chinese titles can be found without switching input methods:
/// `zmt` or `zimeiti` finds 自媒体. The system transliterator knows one reading per character, so
/// common characters with several keep all of them — 重 is chong in 重构 but zhong in 重要.
struct Pinyin: Hashable, Sendable {
    /// One entry per Chinese character or Latin word in the title, each with every reading worth matching.
    let units: [[String]]

    private static let titles = Locked([String: Pinyin?]())
    private static let characters = Locked([Character: [String]]())

    static func of(_ text: String) -> Pinyin? {
        guard text.unicodeScalars.contains(where: isHan) else { return nil }
        if let cached = titles.value[text] { return cached }
        var units: [[String]] = []
        var word = ""
        for character in text {
            if character.isASCII, character.isLetter || character.isNumber {
                word.append(character)
                continue
            }
            if !word.isEmpty { units.append([word.lowercased()]) }
            word = ""
            if character.unicodeScalars.contains(where: isHan) { units.append(readings(of: character)) }
        }
        if !word.isEmpty { units.append([word.lowercased()]) }
        let result = Pinyin(units: units)
        titles.mutate { $0[text] = result }
        return result
    }

    /// 65 when the token spells the title from its first character, 55 from a later one.
    /// A single letter only counts at the start, so the first keystroke narrows without matching everything.
    func score(_ token: String) -> Int? {
        guard !token.isEmpty, token.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        if token.count == 1 { return spells(token, from: 0) ? 65 : nil }
        for start in units.indices where spells(token, from: start) {
            return start == 0 ? 65 : 55
        }
        return nil
    }

    /// One initial per character (`cg` → 重构), or whole readings run together (`chonggou`, `chongg`).
    private func spells(_ token: String, from start: Int) -> Bool {
        let letters = Array(token)
        if start + letters.count <= units.count,
           letters.indices.allSatisfy({ i in units[start + i].contains { $0.first == letters[i] } }) {
            return true
        }
        return spellsOut(token[...], from: start)
    }

    private func spellsOut(_ rest: Substring, from index: Int) -> Bool {
        guard !rest.isEmpty else { return true }
        guard index < units.count else { return false }
        for reading in units[index] {
            if reading.hasPrefix(rest) { return true }
            if rest.hasPrefix(reading), spellsOut(rest.dropFirst(reading.count), from: index + 1) { return true }
        }
        return false
    }

    private static func readings(of character: Character) -> [String] {
        if let cached = characters.value[character] { return cached }
        var result: [String] = []
        if let toned = String(character).applyingTransform(.mandarinToLatin, reverse: false) {
            let plain = (toned.applyingTransform(.stripDiacritics, reverse: false) ?? toned).lowercased()
            if !plain.isEmpty, plain.allSatisfy({ $0.isASCII && $0.isLetter }) {
                result.append(plain)
                // ü is typed as v: 绿 → lv as well as lu.
                if toned.contains("ü") { result.append(plain.replacingOccurrences(of: "u", with: "v")) }
            }
        }
        for reading in alternates[character] ?? [] where !result.contains(reading) {
            result.append(reading)
        }
        characters.mutate { $0[character] = result }
        return result
    }

    /// Everyday characters with more than one reading, all readings listed, tones dropped.
    private static let alternates: [Character: [String]] = [
        "重": ["zhong", "chong"], "长": ["chang", "zhang"], "行": ["xing", "hang"], "调": ["diao", "tiao"],
        "还": ["hai", "huan"], "乐": ["le", "yue"], "传": ["chuan", "zhuan"], "率": ["lv", "lu", "shuai"],
        "模": ["mo", "mu"], "参": ["can", "shen", "cen"], "解": ["jie", "xie"], "省": ["sheng", "xing"],
        "藏": ["cang", "zang"], "朝": ["chao", "zhao"], "降": ["jiang", "xiang"], "称": ["cheng", "chen"],
        "数": ["shu", "shuo"], "差": ["cha", "chai", "ci"], "单": ["dan", "shan", "chan"], "卡": ["ka", "qia"],
        "系": ["xi", "ji"], "校": ["xiao", "jiao"], "和": ["he", "huo", "hu"], "会": ["hui", "kuai"],
        "便": ["bian", "pian"], "薄": ["bao", "bo"], "露": ["lu", "lou"], "落": ["luo", "la", "lao"],
        "血": ["xue", "xie"], "给": ["gei", "ji"], "区": ["qu", "ou"], "奇": ["qi", "ji"], "什": ["shen", "shi"],
        "似": ["si", "shi"], "提": ["ti", "di"], "属": ["shu", "zhu"], "色": ["se", "shai"], "都": ["dou", "du"],
        "地": ["di", "de"], "得": ["de", "dei"], "的": ["de", "di"], "了": ["le", "liao"],
        "着": ["zhe", "zhao", "zhuo"], "觉": ["jue", "jiao"], "塞": ["sai", "se"], "盛": ["sheng", "cheng"],
        "厦": ["sha", "xia"], "宿": ["su", "xiu"], "恶": ["e", "wu"], "强": ["qiang", "jiang"],
        "度": ["du", "duo"], "没": ["mei", "mo"], "屏": ["ping", "bing"], "弹": ["dan", "tan"],
        "曝": ["pu", "bao"], "拓": ["tuo", "ta"], "叶": ["ye", "xie"], "择": ["ze", "zhai"],
        "粘": ["nian", "zhan"], "殖": ["zhi", "shi"], "爪": ["zhua", "zhao"], "综": ["zong", "zeng"],
        "壳": ["ke", "qiao"], "纤": ["xian", "qian"], "削": ["xiao", "xue"], "说": ["shuo", "shui"],
        "熟": ["shu", "shou"], "夹": ["jia", "ga"], "见": ["jian", "xian"], "角": ["jiao", "jue"],
        "劲": ["jin", "jing"], "尾": ["wei", "yi"], "吓": ["xia", "he"], "仔": ["zai", "zi"],
        "识": ["shi", "zhi"], "曾": ["ceng", "zeng"], "大": ["da", "dai"], "扎": ["zha", "za"],
        "仇": ["chou", "qiu"], "圈": ["quan", "juan"], "查": ["cha", "zha"], "折": ["zhe", "she"],
        "佛": ["fo", "fu"], "咖": ["ka", "ga"], "期": ["qi", "ji"], "处": ["chu"], "空": ["kong"],
    ]

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2EBEF: return true
        default: return false
        }
    }
}
