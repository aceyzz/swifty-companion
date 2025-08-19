import Foundation
import Combine

struct CachedProfile: Codable {
    let profile: UserProfile
    let fetchedAt: Date
}

actor ProfileCache {
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(filename: String = "profile_cache.json") {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.url = dir.appendingPathComponent(filename)
    }

    func load() async -> CachedProfile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CachedProfile.self, from: data)
    }

    func save(_ cache: CachedProfile) async {
        guard let data = try? encoder.encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clear() async {
        try? FileManager.default.removeItem(at: url)
    }
}

@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()
    @Published private(set) var profile: UserProfile?
    @Published private(set) var lastUpdated: Date?
    private let repo = ProfileRepository.shared
    private let cache = ProfileCache()
    private var loopTask: Task<Void, Never>?

    func start() {
        cancel()
        loopTask = Task { [weak self] in
            guard let self = self else { return }
            if let cached = await self.cache.load() {
                self.profile = cached.profile
                self.lastUpdated = cached.fetchedAt
            }
            await self.refreshNow()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
                await self.refreshNow()
            }
        }
    }

    func stop() {
        cancel()
        Task { await cache.clear() }
        profile = nil
        lastUpdated = nil
    }

    private func cancel() {
        loopTask?.cancel()
        loopTask = nil
    }

    func refreshNow() async {
    let login = AuthService.shared.getCurrentUserLogin()
        guard !login.isEmpty else { return }
        do {
            let basic = try await repo.basicProfile(login: login)
            self.profile = basic
            self.lastUpdated = Date()
            let pieces = try await repo.heavyPieces(login: login)
            let full = repo.assemble(user: UserInfoRaw(login: basic.login,
                                                       displayname: basic.displayName,
                                                       wallet: basic.wallet,
                                                       correction_point: basic.correctionPoint,
                                                       image: ImageRaw(link: basic.imageURL?.absoluteString ?? ""),
                                                       pool_month: basic.poolMonth,
                                                       pool_year: basic.poolYear,
                                                       campus: basic.campusName.map { [CampusRaw(name: $0)] } ?? [],
                                                       kind: basic.userKind,
                                                       achievements: basic.achievements.map { AchievementRaw(id: $0.id, name: $0.name, description: $0.description, image: $0.image?.absoluteString ?? "") },
                                                       is_active: basic.isActive,
                                                       email: basic.email,
                                                       phone: basic.phone,
                                                       titles_users: nil,
                                                       cursus_users: basic.cursus.map { cu in
                                                           CursusUserRaw(cursus_id: cu.id, grade: cu.grade, level: cu.level, begin_at: cu.beginAt.map { ISO8601DateFormatter().string(from: $0) }, end_at: cu.endAt.map { ISO8601DateFormatter().string(from: $0) }, cursus: CursusRaw(name: cu.name))
                                                       }),
                                   pieces: pieces)
            self.profile = full
            self.lastUpdated = Date()
            await cache.save(CachedProfile(profile: full, fetchedAt: self.lastUpdated ?? Date()))
        } catch {}
    }
}
