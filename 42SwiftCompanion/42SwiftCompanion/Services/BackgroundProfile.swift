import Foundation

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
