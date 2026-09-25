import Foundation

public enum CCID {
    public static let version = "1.0.0"
}

public enum Formatting {
    /// Chinese when it's the first language in System Settings; English otherwise.
    public static var prefersChinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
    }

    /// "now", "5m", "3h", "Yesterday", "4d", "Sep 21" — or the Chinese equivalents.
    public static func relative(_ date: Date, now: Date = Date(), chinese: Bool = prefersChinese) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let calendar = Calendar.current
        if seconds < 60 { return chinese ? "刚刚" : "now" }
        if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return chinese ? "\(minutes) 分钟前" : "\(minutes)m"
        }
        if calendar.isDate(date, inSameDayAs: now) || seconds < 6 * 3600 {
            let hours = Int(seconds / 3600)
            return chinese ? "\(hours) 小时前" : "\(hours)h"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return chinese ? "昨天" : "Yesterday"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days < 7 { return chinese ? "\(days) 天前" : "\(days)d" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: chinese ? "zh_Hans" : "en_US")
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "yMMMd")
        return formatter.string(from: date)
    }

    /// Terminal columns a string takes up: CJK and emoji count as two.
    public static func displayWidth(_ text: String) -> Int {
        text.reduce(0) { $0 + columns(of: $1) }
    }

    /// Cuts a string to fit `width` terminal columns, ending with "…" when shortened.
    public static func truncate(_ text: String, width: Int) -> String {
        guard width > 0 else { return "" }
        guard displayWidth(text) > width else { return text }
        var result = ""
        var used = 0
        for character in text {
            let w = columns(of: character)
            if used + w > width - 1 { break }
            result.append(character)
            used += w
        }
        return result + "…"
    }

    private static func columns(of character: Character) -> Int {
        guard let scalar = character.unicodeScalars.first else { return 0 }
        if character.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) { return 2 }
        switch scalar.value {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60,
             0xFFE0...0xFFE6, 0x20000...0x3FFFD:
            return 2
        default:
            return scalar.properties.generalCategory == .nonspacingMark ? 0 : 1
        }
    }
}
