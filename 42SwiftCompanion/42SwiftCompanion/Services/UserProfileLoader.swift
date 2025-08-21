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
        loader = l
        l.start()
    }

    func stop() {
        loader?.clearCache()
        loader?.stop()
        loader = nil
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
    private var cache: ProfileCache
    private var loopTask: Task<Void, Never>?
    private let refreshInterval: TimeInterval = 300
    private var lastFetchAt: Date?
    private var refreshToken: Int = 0

    init(login: String, autoRefresh: Bool = true, daysWindow: Int = 14) {
        self.login = login
        self.autoRefresh = autoRefresh
        self.daysWindow = daysWindow
        self.cache = ProfileCache(login: login)
    }

    func start() {
        cancel()
        loopTask = Task { [weak self] in
            guard let self else { return }
            if let cached = await cache.load() {
                applyCached(cached)
            }
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
    }

    func clearCache() {
        Task { await cache.clear() }
    }

    private func cancel() {
        loopTask?.cancel()
        loopTask = nil
        refreshToken &+= 1
    }

    private func applyCached(_ cached: CachedProfile) {
        profile = cached.profile
        weeklyLog = cached.logs ?? []
        lastFetchAt = cached.fetchedAt
        basicState = .loaded
        if !(cached.profile.coalitions.isEmpty) { coalitionsState = .loaded }
        if !(cached.profile.finishedProjects.isEmpty && cached.profile.activeProjects.isEmpty) { projectsState = .loaded }
        if cached.profile.currentHost != nil { hostState = .loaded }
        if cached.logs != nil { logState = .loaded }
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
            await cache.save(snapshot)
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

    func refreshNow() async {
        guard !login.isEmpty else { return }
        let token = refreshToken &+ 1
        refreshToken = token
        beginRefreshing()
        do {
            let basic = try await repo.basicProfile(login: login)
            if token != refreshToken { return }
            profile = basic
            basicState = .loaded
        } catch {
            if token != refreshToken { return }
            markFailed(\.basicState)
        }

        async let coalitionsResult: ([CoalitionRaw], [CoalitionUserRaw])? = try? await repo.fetchCoalitions(login: login)
        async let projectsResult: [ProjectRaw]? = try? await repo.fetchProjects(login: login)
        async let hostResult: String? = try? await locRepo.fetchCurrentHost(login: login)
        async let logsResult: [DailyLog]? = try? await locRepo.lastDaysStats(login: login, days: daysWindow)

        let c = await coalitionsResult
        if token != refreshToken { return }
        if let c, let current = profile {
            profile = repo.applyCoalitions(to: current, coalitions: c)
            coalitionsState = .loaded
        } else {
            markFailed(\.coalitionsState)
        }

        let pjs = await projectsResult
        if token != refreshToken { return }
        if let pjs, let current = profile {
            profile = repo.applyProjects(to: current, projects: pjs)
            projectsState = .loaded
        } else {
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
        if profile?.coalitions.isEmpty ?? true { coalitionsState = .loading }
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
        if (profile?.finishedProjects.isEmpty ?? true) && (profile?.activeProjects.isEmpty ?? true) { projectsState = .loading }
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
        if profile?.currentHost == nil { hostState = .loading }
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
        if weeklyLog.isEmpty { logState = .loading }
        if let logs = try? await locRepo.lastDaysStats(login: login, days: daysWindow) {
            weeklyLog = logs
            logState = .loaded
            await endSnapshotSave()
        } else {
            markFailed(\.logState)
        }
    }
}
