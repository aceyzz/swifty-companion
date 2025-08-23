import Foundation

struct CampusInfoRaw: Decodable {
    struct Language: Decodable { let id: Int?; let name: String?; let identifier: String? }
    struct EndpointRaw: Decodable { let id: Int?; let url: String?; let description: String? }

    let id: Int
    let name: String
    let time_zone: String?
    let language: Language?
    let users_count: Int?
    let country: String?
    let address: String?
    let zip: String?
    let city: String?
    let website: String?
    let facebook: String?
    let twitter: String?
    let active: Bool?
    let `public`: Bool?
    let email_extension: String?
    let default_hidden_phone: Bool?
    let endpoint: EndpointRaw?
}

struct CampusEventRaw: Decodable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    let location: String?
    let kind: String?
    let max_people: Int?
    let nbr_subscribers: Int?
    let begin_at: String?
    let end_at: String?
    let campus_ids: [Int]
    let cursus_ids: [Int]
}

struct CampusLocationRaw: Decodable {
    let id: Int?
    let end_at: String?
    let begin_at: String?
    let primary: Bool?
    let host: String?
    let campus_id: Int?
}

struct CampusDashboard: Codable {
    struct Info: Codable {
        let id: Int
        let name: String
        let city: String?
        let country: String?
        let timeZone: String?
        let website: URL?
        let usersCount: Int?
        let addressFull: String?
    }
    struct Event: Identifiable, Codable {
        let id: Int
        let title: String
        let when: String
        let location: String?
        let badges: [String]
        let description: String?
    }

    let info: Info
    let activeUsersCount: Int
    let upcomingEvents: [Event]
    let fetchedAt: Date
}

struct CachedCampus: Codable {
    let campusId: Int
    let dashboard: CampusDashboard
}

actor CampusCache {
    private let url: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(campusId: Int, filenamePrefix: String = "campus_cache") {
        let safe = String(campusId)
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.url = dir.appendingPathComponent("\(filenamePrefix)_\(safe).json")
    }

    func load() async -> CachedCampus? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CachedCampus.self, from: data)
    }

    func save(_ cache: CachedCampus) async {
        guard let data = try? encoder.encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clear() async { try? FileManager.default.removeItem(at: url) }
}

final class CampusRepository {
    static let shared = CampusRepository()
    private let api = APIClient.shared

    func dashboard(campusId: Int) async throws -> CampusDashboard {
        async let info = fetchInfo(campusId: campusId)
        async let activeCount = activeUsersCount(campusId: campusId)
        async let events = upcomingEvents(campusId: campusId, limit: 20)
        let i = try await info
        let c = try await activeCount
        let e = try await events
        let addressPieces = [i.address, i.zip, i.city].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let addressFull = addressPieces.isEmpty ? nil : addressPieces.joined(separator: ", ")
        let vm = CampusDashboard(
            info: .init(
                id: i.id,
                name: i.name,
                city: i.city,
                country: i.country,
                timeZone: i.time_zone,
                website: i.website.flatMap(URL.init(string:)),
                usersCount: i.users_count,
                addressFull: addressFull
            ),
            activeUsersCount: c,
            upcomingEvents: e.map(Self.mapEvent),
            fetchedAt: Date()
        )
        return vm
    }

    func fetchInfo(campusId: Int) async throws -> CampusInfoRaw {
        try await api.request(Endpoint(path: "/v2/campus/\(campusId)"), as: CampusInfoRaw.self)
    }

    func activeUsersCount(campusId: Int) async throws -> Int {
        let all: [CampusLocationRaw] = try await api.pagedRequest { page in
            Endpoint(
                path: "/v2/campus/\(campusId)/locations",
                queryItems: [
                    URLQueryItem(name: "filter[active]", value: "true"),
                    URLQueryItem(name: "page[size]", value: "100"),
                    URLQueryItem(name: "page", value: "\(page)")
                ]
            )
        }
        return all.count
    }

    func upcomingEvents(campusId: Int, limit: Int = 50) async throws -> [CampusEventRaw] {
        let all: [CampusEventRaw] = try await api.pagedRequest { page in
            Endpoint(
                path: "/v2/campus/\(campusId)/events",
                queryItems: [
                    URLQueryItem(name: "filter[future]", value: "true"),
                    URLQueryItem(name: "page[size]", value: "100"),
                    URLQueryItem(name: "page", value: "\(page)")
                ]
            )
        }
        let sorted = all.sorted {
            guard let a = DateParser.iso($0.begin_at), let b = DateParser.iso($1.begin_at) else {
                return $0.begin_at ?? "" < $1.begin_at ?? ""
            }
            return a < b
        }
        return Array(sorted.prefix(limit))
    }

    private static func mapEvent(_ e: CampusEventRaw) -> CampusDashboard.Event {
        let start = DateParser.iso(e.begin_at)
        let end = DateParser.iso(e.end_at)
        let when: String = {
            let df = UserProfile.Formatters.shortDate
            if let s = start, let t = end {
                return "\(df.string(from: s)) — \(df.string(from: t))"
            } else if let s = start {
                return df.string(from: s)
            } else {
                return "Date à venir"
            }
        }()
        var badges: [String] = []
        if let kind = e.kind, !kind.isEmpty { badges.append(kind.capitalized) }
        if let n = e.nbr_subscribers { badges.append("Inscrits \(n)") }
        if let max = e.max_people { badges.append("Places \(max)") }
        return .init(
            id: e.id,
            title: e.name,
            when: when,
            location: (e.location?.isEmpty == false) ? e.location : nil,
            badges: badges,
            description: e.description
        )
    }
}

@MainActor
final class CampusLoader: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed }

    let campusId: Int
    let autoRefresh: Bool
    private let refreshInterval: TimeInterval = 300
    private let cacheTTL: TimeInterval = 300

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var dashboard: CampusDashboard?
    @Published private(set) var lastUpdated: Date?

    private let repo = CampusRepository.shared
    private let cache: CampusCache
    private var loopTask: Task<Void, Never>?
    private var refreshToken: Int = 0
    private var isPriming = true

    init(campusId: Int, autoRefresh: Bool = true) {
        self.campusId = campusId
        self.autoRefresh = autoRefresh
        self.cache = CampusCache(campusId: campusId)
    }

    func start() {
        cancel()
        isPriming = true
        loopTask = Task { [weak self] in
            guard let self else { return }
            if let cached = await cache.load() {
                self.dashboard = cached.dashboard
                self.lastUpdated = cached.dashboard.fetchedAt
                if Date().timeIntervalSince(cached.dashboard.fetchedAt) < cacheTTL {
                    self.state = .loaded
                } else {
                    self.state = .loading
                    await self.refreshNow()
                }
            } else {
                self.state = .loading
                await self.refreshNow()
            }
            if self.autoRefresh {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(self.refreshInterval * 1_000_000_000))
                    await self.refreshNow()
                }
            }
        }
    }

    func stop() {
        cancel()
        dashboard = nil
        lastUpdated = nil
        state = .idle
        isPriming = true
    }

    private func cancel() {
        loopTask?.cancel()
        loopTask = nil
        refreshToken &+= 1
    }

    func refreshNow() async {
        let token = refreshToken &+ 1
        refreshToken = token
        state = .loading
        do {
            let dash = try await repo.dashboard(campusId: campusId)
            if token != refreshToken { return }
            dashboard = dash
            lastUpdated = dash.fetchedAt
            state = .loaded
            await cache.save(.init(campusId: campusId, dashboard: dash))
        } catch {
            if token != refreshToken { return }
            if dashboard != nil {
                state = .loaded
            } else {
                state = .failed
            }
        }
        isPriming = false
    }
}
