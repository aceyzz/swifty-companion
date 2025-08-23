import SwiftUI

actor SecureImageLoader {
    static let shared = SecureImageLoader()
    private let cache = NSCache<NSURL, NSData>()
    private var tasks: [NSURL: Task<Data, Error>] = [:]

    init() {
        cache.countLimit = 512
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func data(for url: URL) async throws -> Data {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            return cached as Data
        }
        if let existing = tasks[key] {
            return try await existing.value
        }
        let task = Task<Data, Error> {
            var req = URLRequest(url: url)
            if url.host == "api.intra.42.fr", let token = await AuthService.shared.accessToken, !token.isEmpty {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, _) = try await URLSession.shared.data(for: req)
            try Task.checkCancellation()
            cache.setObject(data as NSData, forKey: key, cost: data.count)
            return data
        }
        tasks[key] = task
        defer { tasks[key] = nil }
        return try await task.value
    }
}

struct RemoteImage: View {
    let url: URL?
    let cornerRadius: CGFloat
    @State private var image: UIImage?

    init(url: URL?, cornerRadius: CGFloat = 8) {
        self.url = url
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.25)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { image = nil; return }
        do {
            let data = try await SecureImageLoader.shared.data(for: url)
            if Task.isCancelled { return }
            image = UIImage(data: data, scale: UIScreen.main.scale)
        } catch {
            image = nil
        }
    }
}

struct AchievementIconProvider {
    static func symbol(for name: String, description: String?) -> String {
        let n = name.lowercased()
        let d = description?.lowercased() ?? ""
        if n.contains("piscine") || d.contains("piscine") { return "figure.pool.swim" }
        if n.contains("exam") || n.contains("examen") || d.contains("exam") { return "checkmark.seal.fill" }
        if n.contains("project") || n.contains("projet") || d.contains("project") { return "hammer.fill" }
        if n.contains("rank") || n.contains("rang") || n.contains("crown") { return "crown.fill" }
        if n.contains("score") || d.contains("score") { return "chart.line.uptrend.xyaxis" }
        if n.contains("level") || n.contains("niveau") { return "arrow.up.right.circle.fill" }
        if n.contains("bug") || n.contains("fix") || n.contains("correction") || d.contains("fix") { return "wrench.and.screwdriver.fill" }
        if n.contains("xp") || d.contains("xp") { return "sparkles" }
        if n.contains("team") || n.contains("groupe") { return "person.3.fill" }
        if n.contains("algo") || n.contains("algorithm") { return "point.topleft.down.curvedto.point.bottomright.up" }
        return fallback(for: name + (description ?? ""))
    }

    private static func fallback(for seed: String) -> String {
        let pool = ["trophy.fill", "rosette", "star.fill", "seal.fill"]
        let idx = stableIndex(seed: seed, count: pool.count)
        return pool[idx]
    }

    private static func stableIndex(seed: String, count: Int) -> Int {
        var sum = 0
        for u in seed.unicodeScalars { sum &+= Int(u.value) }
        return abs(sum) % max(count, 1)
    }
}
