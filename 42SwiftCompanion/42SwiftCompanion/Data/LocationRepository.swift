import Foundation

struct DailyLog: Identifiable, Codable, Equatable {
    let date: Date
    let hours: Double
    var id: Date { date }
}

final class LocationRepository {
    static let shared = LocationRepository()
    private let api = APIClient.shared

    func fetchCurrentHost(login: String) async throws -> String? {
        let activeEndpoint = Endpoint(
            path: "/v2/users/\(login)/locations",
            queryItems: [
                URLQueryItem(name: "filter[active]", value: "true"),
                URLQueryItem(name: "page[size]", value: "1")
            ]
        )
        let activeItems: [LocationRaw] = try await api.request(activeEndpoint, as: [LocationRaw].self)
        if let first = activeItems.first, (first.end_at == nil || first.end_at?.isEmpty == true), let host = first.host, !host.isEmpty {
            return host
        }
        let recentEndpoint = Endpoint(
            path: "/v2/users/\(login)/locations",
            queryItems: [
                URLQueryItem(name: "page[size]", value: "30"),
                URLQueryItem(name: "page", value: "1")
            ]
        )
        let recent: [LocationRaw] = try await api.request(recentEndpoint, as: [LocationRaw].self)
        if let open = recent.first(where: { $0.end_at == nil || $0.end_at?.isEmpty == true }), let host = open.host, !host.isEmpty {
            return host
        }
        return nil
    }

    func lastDaysStats(login: String, days: Int) async throws -> [DailyLog] {
        let tz = TimeZone.current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let df = dayFormatter(timeZone: tz)
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        guard let beginDate = cal.date(byAdding: .day, value: -(days - 1), to: todayStart),
              let endExclusive = cal.date(byAdding: .day, value: 1, to: todayStart) else {
            return zeros(from: todayStart, days: days)
        }

        if let stats = try? await fetchStats(login: login, begin: beginDate, end: endExclusive, tz: tz, format: .isoDateTime),
           hasAnyValue(stats) {
            return mapStats(stats, begin: beginDate, days: days, df: df, cal: cal)
        }

        if let stats = try? await fetchStats(login: login, begin: beginDate, end: endExclusive, tz: tz, format: .dateOnly),
           hasAnyValue(stats) {
            return mapStats(stats, begin: beginDate, days: days, df: df, cal: cal)
        }

        let locsBegin = try? await ranged(login: login, key: "begin_at", from: beginDate, to: endExclusive)
        let locsEnd = try? await ranged(login: login, key: "end_at", from: beginDate, to: endExclusive)
        let active = try? await activeOnly(login: login)
        let merged = deduplicated((locsBegin ?? []) + (locsEnd ?? []) + (active ?? []))
        return aggregate(locs: merged, from: beginDate, to: endExclusive, cal: cal)
    }

    private enum RangeFormat { case isoDateTime, dateOnly }

    private func fetchStats(login: String, begin: Date, end: Date, tz: TimeZone, format: RangeFormat) async throws -> [String: String] {
        let df = dayFormatter(timeZone: tz)
        let beginParam: String
        let endParam: String
        switch format {
        case .isoDateTime:
            beginParam = DateParser.isoString(begin)
            endParam = DateParser.isoString(end)
        case .dateOnly:
            beginParam = df.string(from: begin)
            endParam = df.string(from: end)
        }
        let endpoint = Endpoint(
            path: "/v2/users/\(login)/locations_stats",
            queryItems: [
                URLQueryItem(name: "begin_at", value: beginParam),
                URLQueryItem(name: "end_at", value: endParam),
                URLQueryItem(name: "time_zone", value: tz.identifier)
            ]
        )
        return try await api.request(endpoint, as: [String: String].self)
    }

    private func hasAnyValue(_ stats: [String: String]) -> Bool {
        guard !stats.isEmpty else { return false }
        for v in stats.values where hoursFromDurationString(v) > 0 { return true }
        return false
    }

    private func mapStats(_ raw: [String: String], begin: Date, days: Int, df: DateFormatter, cal: Calendar) -> [DailyLog] {
        var out: [DailyLog] = []
        for i in 0..<days {
            guard let day = cal.date(byAdding: .day, value: i, to: begin) else { continue }
            let key = df.string(from: day)
            let h = raw[key].map(hoursFromDurationString) ?? 0
            out.append(DailyLog(date: day, hours: h))
        }
        return out
    }

    private func ranged(login: String, key: String, from: Date, to: Date) async throws -> [LocationRaw] {
        try await api.pagedRequest { page in
            Endpoint(
                path: "/v2/users/\(login)/locations",
                queryItems: [
                    URLQueryItem(name: "range[\(key)]", value: "\(DateParser.isoString(from)),\(DateParser.isoString(to))"),
                    URLQueryItem(name: "page[size]", value: "100"),
                    URLQueryItem(name: "page", value: "\(page)")
                ]
            )
        }
    }

    private func activeOnly(login: String) async throws -> [LocationRaw] {
        try await api.pagedRequest { page in
            Endpoint(
                path: "/v2/users/\(login)/locations",
                queryItems: [
                    URLQueryItem(name: "filter[active]", value: "true"),
                    URLQueryItem(name: "page[size]", value: "100"),
                    URLQueryItem(name: "page", value: "\(page)")
                ]
            )
        }
    }

    private func deduplicated(_ items: [LocationRaw]) -> [LocationRaw] {
        var seen: Set<Int> = []
        var result: [LocationRaw] = []
        for it in items {
            if let id = it.id {
                if seen.contains(id) { continue }
                seen.insert(id)
                result.append(it)
            } else {
                if !result.contains(where: { $0.begin_at == it.begin_at && $0.end_at == it.end_at && $0.host == it.host }) {
                    result.append(it)
                }
            }
        }
        return result
    }

    private func aggregate(locs: [LocationRaw], from: Date, to: Date, cal: Calendar) -> [DailyLog] {
        let startDay = cal.startOfDay(for: from)
        let endDay = cal.startOfDay(for: to)
        var bucket: [Date: TimeInterval] = [:]
        var day = startDay
        while day <= endDay {
            bucket[day] = 0
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        for l in locs {
            guard let rawStart = DateParser.iso(l.begin_at) else { continue }
            let rawEnd = l.end_at.flatMap(DateParser.iso) ?? to
            var s = max(rawStart, from)
            let e = min(rawEnd, to)
            if e <= s { continue }
            while s < e {
                let dayStart = cal.startOfDay(for: s)
                guard let nextDay = cal.date(byAdding: .day, value: 1, to: dayStart) else { break }
                let segmentEnd = min(e, nextDay)
                let delta = max(0, segmentEnd.timeIntervalSince(s))
                bucket[dayStart, default: 0] += delta
                s = segmentEnd
            }
        }
        let keys = bucket.keys.sorted()
        return keys.map { DailyLog(date: $0, hours: (bucket[$0] ?? 0) / 3600.0) }
    }

    private func hoursFromDurationString(_ s: String) -> Double {
        let parts = s.split(separator: ":")
        guard parts.count >= 2 else { return 0 }
        let h = Double(parts[0]) ?? 0
        let m = Double(parts[1]) ?? 0
        let sec = Double(parts.count >= 3 ? parts[2] : "0") ?? 0
        return h + m / 60 + sec / 3600
    }

    private func dayFormatter(timeZone: TimeZone) -> DateFormatter {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.timeZone = timeZone
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df
    }

    private func zeros(from todayStart: Date, days: Int) -> [DailyLog] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let start = cal.date(byAdding: .day, value: -(days - 1), to: todayStart) ?? todayStart
        return (0..<days).compactMap { i in
            let d = cal.date(byAdding: .day, value: i, to: start) ?? start
            return DailyLog(date: cal.startOfDay(for: d), hours: 0)
        }
    }
}
