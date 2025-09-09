import Foundation
import SwiftUI

@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()
    @Published private(set) var loader: UserProfileLoader?

    func start() {
        let login = AuthService.shared.getCurrentUserLogin()
        start(for: login)
    }

    func start(for login: String) {
        guard !login.isEmpty else { return }
        if let l = loader, l.login == login { return }
        loader?.stop()
        let l = UserProfileLoader(login: login)
        l.onCoalitionsColor = { hex in
            Theme.shared.apply(hex: hex)
        }
        loader = l
        l.start()
    }

    func stop() {
        loader?.clearCache()
        loader?.stop()
        loader = nil
        Theme.shared.reset()
    }
}

@MainActor
final class UserProfileLoader: ObservableObject {
    enum SectionLoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }
    let login: String
    let autoRefresh: Bool
    let daysWindow: Int
    var onCoalitionsColor: ((String?) -> Void)?

    @Published private(set) var profile: UserProfile? { didSet { lastUpdated = Date() } }
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var basicState: SectionLoadState = .idle
    @Published private(set) var coalitionsState: SectionLoadState = .idle
    @Published private(set) var projectsState: SectionLoadState = .idle
    @Published private(set) var hostState: SectionLoadState = .idle
    @Published private(set) var logState: SectionLoadState = .idle
    @Published private(set) var weeklyLog: [DailyLog] = []

    private let repo = ProfileRepository.shared
    private let locRepo = LocationRepository.shared
    private let cache = NetworkCache.shared
    private var loopTask: Task<Void, Never>?
    private let refreshInterval: TimeInterval = 300
    private var lastFetchAt: Date?
    private var refreshToken: Int = 0
    private var isPriming = true

    init(login: String, autoRefresh: Bool = true, daysWindow: Int = 14) {
        self.login = login
        self.autoRefresh = autoRefresh
        self.daysWindow = daysWindow
    }

    func start() {
        cancel()
        isPriming = true
        loopTask = Task { [weak self] in
            guard let self else { return }
            await loadFromCache()
            await refreshNow()
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
        profile = nil
        basicState = .idle
        coalitionsState = .idle
        projectsState = .idle
        hostState = .idle
        logState = .idle
        weeklyLog = []
        lastUpdated = nil
        lastFetchAt = nil
        isPriming = true
    }

    func clearCache() {
        Task {
            let cacheKey = await cache.cacheKey(for: "/profile/\(login)")
            await cache.remove(forKey: cacheKey)
        }
    }

    private func cancel() {
        loopTask?.cancel()
        loopTask = nil
        refreshToken &+= 1
    }

    private func loadFromCache() async {
        let cacheKey = await cache.cacheKey(for: "/profile/\(login)")
        
        if let cached = await cache.get(CachedProfile.self, forKey: cacheKey) {
            profile = cached.profile
            weeklyLog = cached.logs ?? []
            lastFetchAt = cached.fetchedAt

            basicState = .loaded
            coalitionsState = cached.profile.coalitions.isEmpty ? .loading : .loaded
            projectsState = (cached.profile.finishedProjects.isEmpty && cached.profile.activeProjects.isEmpty) ? .loading : .loaded
            hostState = cached.profile.currentHost == nil ? .loading : .loaded
            logState = cached.logs == nil ? .loading : .loaded

            if !cached.profile.coalitions.isEmpty {
                onCoalitionsColor?(bestCoalitionHex(from: cached.profile))
            }
            
            let cacheAge = Date().timeIntervalSince(cached.fetchedAt)
            if cacheAge > 300 {
                isPriming = true
            }
        }
    }

    private func beginRefreshing() {
        if profile == nil { basicState = .loading }
        if profile?.coalitions.isEmpty ?? true { coalitionsState = .loading }
        if (profile?.finishedProjects.isEmpty ?? true) && (profile?.activeProjects.isEmpty ?? true) { projectsState = .loading }
        if profile?.currentHost == nil { hostState = .loading }
        if weeklyLog.isEmpty { logState = .loading }
    }

    private func endSnapshotSave() async {
        if let p = profile {
            let snapshot = CachedProfile(profile: p, fetchedAt: Date(), logs: weeklyLog)
            let cacheKey = await cache.cacheKey(for: "/profile/\(login)")
            await cache.set(snapshot, forKey: cacheKey, ttl: 1800)
            lastFetchAt = snapshot.fetchedAt
        }
    }

    private func markFailed(_ keyPath: ReferenceWritableKeyPath<UserProfileLoader, SectionLoadState>) {
        if keyPath == \.basicState { self[keyPath: keyPath] = profile == nil ? .failed : .loaded }
        else if keyPath == \.coalitionsState { self[keyPath: keyPath] = (profile?.coalitions.isEmpty ?? true) ? .failed : .loaded }
        else if keyPath == \.projectsState { self[keyPath: keyPath] = ((profile?.finishedProjects.isEmpty ?? true) && (profile?.activeProjects.isEmpty ?? true)) ? .failed : .loaded }
        else if keyPath == \.hostState { self[keyPath: keyPath] = profile?.currentHost == nil ? .failed : .loaded }
        else if keyPath == \.logState { self[keyPath: keyPath] = weeklyLog.isEmpty ? .failed : .loaded }
    }

	private func bestCoalitionHex(from profile: UserProfile) -> String? {
        return profile.coalitions.max(by: { ($0.score ?? 0) < ($1.score ?? 0) })?.color
    }

    func refreshNow() async {
        guard !login.isEmpty else { return }
        let token = refreshToken &+ 1
        refreshToken = token
        
        let shouldSkipRefresh = !isPriming && 
                              lastFetchAt != nil && 
                              Date().timeIntervalSince(lastFetchAt!) < 120
        
        if shouldSkipRefresh { return }
        
        beginRefreshing()
        defer { isPriming = false }

        async let profileDataResult = fetchProfileData()
        async let hostResult: String? = try? await locRepo.fetchCurrentHost(login: login)
        async let logsResult: [DailyLog]? = try? await locRepo.lastDaysStats(login: login, days: daysWindow)

        let profileData = await profileDataResult
        if token != refreshToken { return }
        
        if let (basic, coalitions, coalitionUsers, projects) = profileData {
            profile = repo.applyCoalitions(to: basic, coalitions: (coalitions, coalitionUsers))
            profile = repo.applyProjects(to: profile!, projects: projects)
            basicState = .loaded
            coalitionsState = .loaded
            projectsState = .loaded
            
            if let p = profile {
                onCoalitionsColor?(bestCoalitionHex(from: p))
            }
        } else {
            markFailed(\.basicState)
            markFailed(\.coalitionsState)
            markFailed(\.projectsState)
        }

        let h = await hostResult
        if token != refreshToken { return }
        if let h, let current = profile {
            profile = repo.applyCurrentHost(to: current, host: h)
            hostState = .loaded
        } else {
            markFailed(\.hostState)
        }

        let logs = await logsResult
        if token != refreshToken { return }
        if let logs {
            weeklyLog = logs
            logState = .loaded
        } else {
            markFailed(\.logState)
        }

        await endSnapshotSave()
    }
    
    private func fetchProfileData() async -> (UserProfile, [CoalitionRaw], [CoalitionUserRaw], [ProjectRaw])? {
        do {
            return try await repo.fetchCompleteProfile(login: login)
        } catch {
            return nil
        }
    }

    func retryBasic() { Task { await refreshBasicOnly() } }
    func retryCoalitions() { Task { await refreshCoalitionsOnly() } }
    func retryProjects() { Task { await refreshProjectsOnly() } }
    func retryHost() { Task { await refreshHostOnly() } }
    func retryLog() { Task { await refreshLogOnly() } }

    private func refreshBasicOnly() async {
        guard !login.isEmpty else { return }
        let token = refreshToken &+ 1
        refreshToken = token
        if profile == nil { basicState = .loading }
        do {
            let basic = try await repo.basicProfile(login: login)
            if token != refreshToken { return }
            profile = basic
            basicState = .loaded
            await endSnapshotSave()
        } catch {
            if token != refreshToken { return }
            markFailed(\.basicState)
        }
    }

    private func refreshCoalitionsOnly() async {
        guard !login.isEmpty else { return }
        coalitionsState = .loading
        do {
            let c = try await repo.fetchCoalitions(login: login)
            if let current = profile { profile = repo.applyCoalitions(to: current, coalitions: c) }
            coalitionsState = .loaded
            await endSnapshotSave()
        } catch {
            markFailed(\.coalitionsState)
        }
    }

    private func refreshProjectsOnly() async {
        guard !login.isEmpty else { return }
        projectsState = .loading
        do {
            let pjs = try await repo.fetchProjects(login: login)
            if let current = profile { profile = repo.applyProjects(to: current, projects: pjs) }
            projectsState = .loaded
            await endSnapshotSave()
        } catch {
            markFailed(\.projectsState)
        }
    }

    private func refreshHostOnly() async {
        guard !login.isEmpty else { return }
        hostState = .loading
        do {
            let h = try await locRepo.fetchCurrentHost(login: login)
            if let current = profile { profile = repo.applyCurrentHost(to: current, host: h) }
            hostState = .loaded
            await endSnapshotSave()
        } catch {
            markFailed(\.hostState)
        }
    }

    private func refreshLogOnly() async {
        guard !login.isEmpty else { return }
        logState = .loading
        do {
            let logs = try await locRepo.lastDaysStats(login: login, days: daysWindow)
            weeklyLog = logs
            logState = .loaded
            await endSnapshotSave()
        } catch {
            markFailed(\.logState)
        }
    }
}
