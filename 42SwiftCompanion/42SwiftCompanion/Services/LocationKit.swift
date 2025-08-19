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
        let now = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return [] }
        let locations = try await fetchLocations(login: login, from: start, to: now)
        return aggregate(locs: locations, from: start, to: now)
    }

    private func fetchLocations(login: String, from: Date, to: Date) async throws -> [LocationRaw] {
        let fmt = ISO8601DateFormatter()
        let fromStr = fmt.string(from: from)
        let toStr = fmt.string(from: to)
        return try await api.pagedRequest { page in
            Endpoint(
                path: "/v2/users/\(login)/locations",
                queryItems: [
                    URLQueryItem(name: "range[begin_at]", value: "\(fromStr),\(toStr)"),
                    URLQueryItem(name: "page[size]", value: "100"),
                    URLQueryItem(name: "page", value: "\(page)")
                ]
            )
        }
    }

    private func aggregate(locs: [LocationRaw], from: Date, to: Date) -> [DailyLog] {
        var bucket: [Date: TimeInterval] = [:]
        let cal = Calendar.current
        var day = cal.startOfDay(for: from)
        while day <= to {
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
                let nextDay = cal.date(byAdding: .day, value: 1, to: dayStart) ?? end
                let segmentEnd = min(end, nextDay)
                let delta = max(0, segmentEnd.timeIntervalSince(start))
                bucket[dayStart, default: 0] += delta
                start = segmentEnd
            }
        }
        let keys = bucket.keys.sorted()
        return keys.map { DailyLog(date: $0, hours: (bucket[$0] ?? 0) / 3600.0) }
    }
}
