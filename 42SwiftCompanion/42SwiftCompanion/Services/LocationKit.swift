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
        let endpoint = Endpoint(
            path: "/v2/users/\(login)/locations",
            queryItems: [
                URLQueryItem(name: "filter[active]", value: "true"),
                URLQueryItem(name: "page[size]", value: "1")
            ]
        )
        let items: [LocationRaw] = try await api.request(endpoint, as: [LocationRaw].self)
        return items.first?.host
    }

    func lastDaysStats(login: String, days: Int) async throws -> [DailyLog] {
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: startOfToday) else { return zeros(from: startOfToday, days: days) }
        let fromStr = DateParser.isoString(start)
        let toStr = DateParser.isoString(now)
        do {
            async let byBegin = ranged(login: login, key: "begin_at", fromStr: fromStr, toStr: toStr)
            async let byEnd = ranged(login: login, key: "end_at", fromStr: fromStr, toStr: toStr)
            async let active = activeOnly(login: login)
            let merged = deduplicated((try await byBegin) + (try await byEnd) + (try await active))
            let logs = aggregate(locs: merged, from: start, to: now)
            return Array(logs.suffix(days))
        } catch {
            let lookbackDays = max(days * 2, 14)
            guard let threshold = cal.date(byAdding: .day, value: -lookbackDays, to: startOfToday) else { return zeros(from: startOfToday, days: days) }
            let recent = try await recentWithoutRange(login: login, stopWhenOlderThan: threshold)
            let logs = aggregate(locs: recent, from: start, to: now)
            return Array(logs.suffix(days))
        }
    }

    private func ranged(login: String, key: String, fromStr: String, toStr: String) async throws -> [LocationRaw] {
        try await api.pagedRequest { page in
            Endpoint(
                path: "/v2/users/\(login)/locations",
                queryItems: [
                    URLQueryItem(name: "range[\(key)]", value: "\(fromStr),\(toStr)"),
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

    private func recentWithoutRange(login: String, stopWhenOlderThan threshold: Date) async throws -> [LocationRaw] {
        var all: [LocationRaw] = []
        var page = 1
        var shouldContinue = true
        while shouldContinue {
            let endpoint = Endpoint(
                path: "/v2/users/\(login)/locations",
                queryItems: [
                    URLQueryItem(name: "page[size]", value: "100"),
                    URLQueryItem(name: "page", value: "\(page)")
                ]
            )
            let items: [LocationRaw] = try await api.request(endpoint, as: [LocationRaw].self)
            if items.isEmpty { break }
            all.append(contentsOf: items)
            if items.last.map({ DateParser.iso($0.begin_at) ?? .distantPast }) ?? .distantPast < threshold {
                shouldContinue = false
            } else {
                page += 1
            }
        }
        return deduplicated(all)
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

    private func aggregate(locs: [LocationRaw], from: Date, to: Date) -> [DailyLog] {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: from)
        let endDay = cal.startOfDay(for: to)
        var bucket: [Date: TimeInterval] = [:]
        var day = startDay
        while day <= endDay {
            bucket[day] = 0
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        for l in locs {
            guard let rawStart = DateParser.iso(l.begin_at) else { continue }
            let rawEnd = l.end_at.flatMap(DateParser.iso) ?? to
            var start = max(rawStart, from)
            let end = min(rawEnd, to)
            if end <= start { continue }
            while start < end {
                let dayStart = cal.startOfDay(for: start)
                let nextDay = cal.date(byAdding: .day, value: 1, to: dayStart)!
                let segmentEnd = min(end, nextDay)
                let delta = max(0, segmentEnd.timeIntervalSince(start))
                bucket[dayStart, default: 0] += delta
                start = segmentEnd
            }
        }
        let keys = bucket.keys.sorted()
        return keys.map { DailyLog(date: $0, hours: (bucket[$0] ?? 0) / 3600.0) }
    }

    private func zeros(from todayStart: Date, days: Int) -> [DailyLog] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -(days - 1), to: todayStart) ?? todayStart
        return (0..<days).compactMap { i in
            let d = cal.date(byAdding: .day, value: i, to: start) ?? start
            return DailyLog(date: d, hours: 0)
        }
    }
}
