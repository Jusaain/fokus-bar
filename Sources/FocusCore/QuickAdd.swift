import Foundation

/// Result of parsing a quick-add line such as "Angebot schreiben #Website @morgen !".
public struct QuickAddResult: Equatable, Sendable {
    public var title: String
    public var project: String?
    public var priority: Priority?
    public var dueDate: Date?
    public var hasTokens: Bool { project != nil || priority != nil || dueDate != nil }
}

/// Explicit tokens only, so normal words in a title are never swallowed:
/// `#Projekt` (underscore becomes a space), `!` or `!hoch` for high, `!niedrig` for low,
/// `@heute`, `@morgen`, `@übermorgen`, `@mo` … `@so` (next occurrence, today included), `@24.12.`
public enum QuickAddParser {
    private static let weekdays: [String: Int] = [
        "so": 1, "sonntag": 1, "mo": 2, "montag": 2, "di": 3, "dienstag": 3, "mi": 4, "mittwoch": 4,
        "do": 5, "donnerstag": 5, "fr": 6, "freitag": 6, "sa": 7, "samstag": 7
    ]

    public static func parse(_ input: String, now: Date, calendar: Calendar = .current, knownProjects: [String] = []) -> QuickAddResult {
        var words: [String] = []
        var result = QuickAddResult(title: "")
        for word in input.split(whereSeparator: \.isWhitespace).map(String.init) {
            let lower = word.lowercased()
            if word.count > 1, word.hasPrefix("#"), let first = word.dropFirst().first, first.isLetter {
                let name = word.dropFirst().replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .punctuationCharacters)
                if !name.isEmpty {
                    result.project = knownProjects.first { $0.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame } ?? name
                    continue
                }
            }
            if lower == "!" || lower == "!!" || lower == "!hoch" { result.priority = .high; continue }
            if lower == "!niedrig" { result.priority = .low; continue }
            if lower.hasPrefix("@"), let date = date(for: String(lower.dropFirst()), now: now, calendar: calendar) {
                result.dueDate = date
                continue
            }
            words.append(word)
        }
        let title = words.joined(separator: " ")
        guard !title.isEmpty else { return QuickAddResult(title: input.trimmingCharacters(in: .whitespacesAndNewlines)) }
        result.title = title
        return result
    }

    static func date(for token: String, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch token {
        case "heute": return today
        case "morgen": return calendar.date(byAdding: .day, value: 1, to: today)
        case "übermorgen", "uebermorgen": return calendar.date(byAdding: .day, value: 2, to: today)
        default: break
        }
        if let weekday = weekdays[token] {
            let current = calendar.component(.weekday, from: today)
            return calendar.date(byAdding: .day, value: (weekday - current + 7) % 7, to: today)
        }
        let parts = token.split(separator: ".", omittingEmptySubsequences: true)
        guard (2...3).contains(parts.count), let day = Int(parts[0]), let month = Int(parts[1]) else { return nil }
        var components = DateComponents(month: month, day: day)
        if parts.count == 3, let year = Int(parts[2]) {
            components.year = year < 100 ? 2000 + year : year
            guard let date = calendar.date(from: components), calendar.component(.day, from: date) == day, calendar.component(.month, from: date) == month else { return nil }
            return date
        }
        components.year = calendar.component(.year, from: today)
        guard var date = calendar.date(from: components), calendar.component(.day, from: date) == day, calendar.component(.month, from: date) == month else { return nil }
        if date < today, let next = calendar.date(byAdding: .year, value: 1, to: date) { date = next }
        return date
    }
}
