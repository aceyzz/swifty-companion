import Foundation

final class SlotsRepository {
    static let shared = SlotsRepository()
    private let api = APIClient.shared
    private var cachedUserId: Int?

    private func currentUserId() async throws -> Int {
        if let cachedUserId { return cachedUserId }
        let me = try await api.request(Endpoint(path: "/v2/me"), as: Me.self)
        cachedUserId = me.id
        return me.id
    }

    func anchorBegin(forDay day: Date, timeZone: TimeZone = .current) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let now = Date()
        let startOfDay = cal.startOfDay(for: day)
        if cal.isDate(day, inSameDayAs: now) {
            let lead = now.addingTimeInterval(30 * 60)
            let zeroSec = cal.date(bySetting: .second, value: 0, of: lead) ?? lead
            let minute = cal.component(.minute, from: zeroSec)
            let add = (15 - (minute % 15)) % 15
            return cal.date(byAdding: .minute, value: add, to: zeroSec) ?? zeroSec
        } else {
            return startOfDay
        }
    }

    func myEvaluationSlots(forDay day: Date, timeZone: TimeZone = .current) async throws -> [EvaluationSlot] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let startOfDay = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let begin = anchorBegin(forDay: day, timeZone: timeZone)
        let items = [
            URLQueryItem(name: "range[begin_at]", value: "\(DateParser.isoString(begin)),\(DateParser.isoString(end))"),
            URLQueryItem(name: "page[size]", value: "100")
        ]
        let ep = Endpoint(path: "/v2/me/slots", queryItems: items)
        return try await api.request(ep, as: [EvaluationSlot].self)
    }

    func createEvaluationSlot(begin: Date, end: Date) async throws -> [EvaluationSlot] {
        let uid = try await currentUserId()
        let payload: [String: Any] = [
            "slot": [
                "user_id": uid,
                "begin_at": DateParser.isoString(begin),
                "end_at": DateParser.isoString(end)
            ]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        let ep = Endpoint(path: "/v2/slots",
                          method: .post,
                          headers: ["Content-Type": "application/json"],
                          body: body)
        return try await api.request(ep, as: [EvaluationSlot].self)
    }

    func scaleTeam(id: Int) async throws -> JSONValue {
        try await api.request(Endpoint(path: "/v2/scale_teams/\(id)"), as: JSONValue.self)
    }

    func fetchScaleTeamsDetails(ids: [Int]) async -> [Int: JSONValue] {
        var result: [Int: JSONValue] = [:]
        await withTaskGroup(of: (Int, JSONValue?).self) { group in
            for id in ids {
                group.addTask {
                    let val = try? await self.scaleTeam(id: id)
                    return (id, val)
                }
            }
            for await (id, val) in group {
                if let v = val { result[id] = v }
            }
        }
        return result
    }

    func deleteEvaluationSlots(ids: [Int]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { try await self.deleteEvaluationSlot(id: id) }
            }
            try await group.waitForAll()
        }
    }

    func deleteEvaluationSlot(id: Int) async throws {
        let ep = Endpoint(path: "/v2/slots/\(id)", method: .delete)
        do {
            struct _NoContent: Decodable {}
            _ = try await api.request(ep, as: _NoContent.self)
        } catch let e as APIError {
            if case .decoding = e { return }
            throw e
        } catch {
            throw error
        }
    }

    func fetchSlotsDetails(ids: [Int]) async -> [Int: EvaluationSlot] {
        if ids.isEmpty { return [:] }
        
        let cache = NetworkCache.shared
        var result: [Int: EvaluationSlot] = [:]
        var missingIds: [Int] = []
        
        for id in Set(ids) {
            let cacheKey = await cache.cacheKey(for: "/v2/slots/\(id)")
            if let cached = await cache.get(EvaluationSlot.self, forKey: cacheKey) {
                result[id] = cached
            } else {
                missingIds.append(id)
            }
        }
        
        if missingIds.isEmpty { return result }
        
        await withTaskGroup(of: [EvaluationSlot].self) { group in
            let chunkSize = 50
            for chunk in missingIds.chunked(into: chunkSize) {
                group.addTask {
                    let list = chunk.map(String.init).joined(separator: ",")
                    let ep = Endpoint(path: "/v2/slots",
                                      queryItems: [
                                        URLQueryItem(name: "filter[id]", value: list),
                                        URLQueryItem(name: "page[size]", value: "100")
                                      ])
                    return (try? await self.api.request(ep, as: [EvaluationSlot].self)) ?? []
                }
            }
            
            for await slots in group {
                for slot in slots {
                    result[slot.id] = slot
                    let cacheKey = await cache.cacheKey(for: "/v2/slots/\(slot.id)")
                    await cache.set(slot, forKey: cacheKey, ttl: 120)
                }
            }
        }
        
        return result
    }
}

extension SlotsRepository {
    func upcomingScaleTeamsAsCorrected() async throws -> [UpcomingScaleTeamRaw] {
        let ep = Endpoint(
            path: "/v2/me/scale_teams/as_corrected",
            queryItems: [URLQueryItem(name: "filter[future]", value: "true"),
                         URLQueryItem(name: "page[size]", value: "100")]
        )
        return try await api.request(ep, as: [UpcomingScaleTeamRaw].self)
    }

    func upcomingScaleTeamsAsCorrector() async throws -> [UpcomingScaleTeamRaw] {
        let ep = Endpoint(
            path: "/v2/me/scale_teams/as_corrector",
            queryItems: [URLQueryItem(name: "filter[future]", value: "true"),
                         URLQueryItem(name: "page[size]", value: "100")]
        )
        return try await api.request(ep, as: [UpcomingScaleTeamRaw].self)
    }

    func fetchProjectNames(ids: [Int]) async -> [Int: String] {
        if ids.isEmpty { return [:] }
        
        let cache = NetworkCache.shared
        var result: [Int: String] = [:]
        var missingIds: [Int] = []
        
        for id in Set(ids) {
            let cacheKey = await cache.cacheKey(for: "/v2/projects/\(id)")
            if let cached = await cache.get(String.self, forKey: cacheKey) {
                result[id] = cached
            } else {
                missingIds.append(id)
            }
        }
        
        if missingIds.isEmpty { return result }
        
        await withTaskGroup(of: (Int, String?).self) { group in
            for id in missingIds {
                group.addTask {
                    let name = try? await self.projectName(id: id)
                    if let name {
                        let cacheKey = await cache.cacheKey(for: "/v2/projects/\(id)")
                        await cache.set(name, forKey: cacheKey, ttl: 3600)
                    }
                    return (id, name)
                }
            }
            for await (id, name) in group {
                if let name { result[id] = name }
            }
        }
        return result
    }

    private func projectName(id: Int) async throws -> String {
        struct ProjectShort: Decodable { let id: Int; let name: String }
        let ep = Endpoint(path: "/v2/projects/\(id)")
        let p: ProjectShort = try await api.request(ep, as: ProjectShort.self)
        return p.name
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
