import Foundation

struct CacheEntry<T: Codable>: Codable {
    let value: T
    let expiresAt: Date
    
    var isExpired: Bool { Date() > expiresAt }
}

actor NetworkCache {
    static let shared = NetworkCache()
    
    private var storage: [String: Data] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cleanupTask: Task<Void, Never>?
    private let persistenceURL: URL
    
    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        persistenceURL = cacheDir.appendingPathComponent("network_cache.json")
        
        Task {
            await loadFromDisk()
            await startCleanupTimer()
        }
    }
    
    private func loadFromDisk() async {
        guard let data = try? Data(contentsOf: persistenceURL),
              let diskStorage = try? decoder.decode([String: Data].self, from: data) else {
            return
        }
        storage = diskStorage
        await removeExpired()
    }
    
    private func saveToDisk() async {
        guard let data = try? encoder.encode(storage) else { return }
        try? data.write(to: persistenceURL, options: .atomic)
    }
    
    private func startCleanupTimer() async {
        cleanupTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                await removeExpired()
                await saveToDisk()
            }
        }
    }
    
    func set<T: Codable>(_ value: T, forKey key: String, ttl: TimeInterval = 300) {
        let entry = CacheEntry(value: value, expiresAt: Date().addingTimeInterval(ttl))
        if let data = try? encoder.encode(entry) {
            storage[key] = data
            Task { await saveToDisk() }
        }
    }
    
    func get<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = storage[key],
              let entry = try? decoder.decode(CacheEntry<T>.self, from: data) else { return nil }
        
        if entry.isExpired {
            storage.removeValue(forKey: key)
            Task { await saveToDisk() }
            return nil
        }
        
        return entry.value
    }
    
    func remove(forKey key: String) {
        storage.removeValue(forKey: key)
        Task { await saveToDisk() }
    }
    
    func removeExpired() async {
        let now = Date()
        var changed = false
        let keysToRemove = storage.compactMap { key, data -> String? in
            if let rawEntry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let expiresAtString = rawEntry["expiresAt"] as? String,
               let expiresAt = ISO8601DateFormatter().date(from: expiresAtString),
               expiresAt <= now {
                return key
            }
            return nil
        }
        if !keysToRemove.isEmpty {
            keysToRemove.forEach { storage.removeValue(forKey: $0) }
            changed = true
        }
        if changed {
            await saveToDisk()
        }
    }
    
    func clear() {
        storage.removeAll()
        Task { await saveToDisk() }
    }
    
    deinit {
        cleanupTask?.cancel()
    }
}

private struct AnyDecodable: Codable {
    init(from decoder: Decoder) throws {}
    func encode(to encoder: Encoder) throws {}
}

extension NetworkCache {
    func cacheKey(for endpoint: String, params: [String: String] = [:]) -> String {
        let sortedParams = params.sorted { $0.key < $1.key }
        let paramString = sortedParams.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        return paramString.isEmpty ? endpoint : "\(endpoint)?\(paramString)"
    }
}
