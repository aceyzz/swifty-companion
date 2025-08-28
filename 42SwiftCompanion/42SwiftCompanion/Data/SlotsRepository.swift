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
        var map: [Int: EvaluationSlot] = [:]
        let unique = Array(Set(ids)).sorted()
        let chunkSize = 50
        var idx = 0
        while idx < unique.count {
            let end = min(unique.count, idx + chunkSize)
            let chunk = Array(unique[idx..<end])
            let list = chunk.map(String.init).joined(separator: ",")
            let ep = Endpoint(path: "/v2/slots",
                              queryItems: [
                                URLQueryItem(name: "filter[id]", value: list),
                                URLQueryItem(name: "page[size]", value: "100")
                              ])
            if let page: [EvaluationSlot] = try? await api.request(ep, as: [EvaluationSlot].self) {
                for s in page { map[s.id] = s }
            }
            idx = end
        }
        return map
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
        var map: [Int: String] = [:]
        await withTaskGroup(of: (Int, String?).self) { group in
            for id in Set(ids) {
                group.addTask {
                    let name = try? await self.projectName(id: id)
                    return (id, name)
                }
            }
            for await (id, name) in group {
                if let name { map[id] = name }
            }
        }
        return map
    }

    private func projectName(id: Int) async throws -> String {
        struct ProjectShort: Decodable { let id: Int; let name: String }
        let ep = Endpoint(path: "/v2/projects/\(id)")
        let p: ProjectShort = try await api.request(ep, as: ProjectShort.self)
        return p.name
    }
}
