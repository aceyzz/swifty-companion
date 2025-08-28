import Foundation

enum DateParser {
    private static let fUTCFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let fUTC: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func iso(_ str: String?) -> Date? {
        guard let s = str, !s.isEmpty else { return nil }
        return fUTCFrac.date(from: s) ?? fUTC.date(from: s)
    }
    static func isoString(_ date: Date) -> String {
        fUTCFrac.string(from: date)
    }
}

extension Date {
    func snappedToQuarterHour() -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: self)
        let minutes = comps.minute ?? 0
        let snapped = minutes - (minutes % 15)
        return cal.date(bySettingHour: comps.hour ?? 0, minute: snapped, second: 0, of: self) ?? self
    }
}
