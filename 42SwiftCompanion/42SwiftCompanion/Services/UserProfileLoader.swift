import Foundation
import SwiftUI

@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published private(set) var loader: UserProfileLoader?

    func start() {
        let login = AuthService.shared.getCurrentUserLogin()
        guard !login.isEmpty else { return }
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
    @Published private(set) var coalitionsState: SectionLoadState = .idle
    @Published private(set) var projectsState: SectionLoadState = .idle
    @Published private(set) var weeklyLog: [DailyLog] = []

    private let repo = ProfileRepository.shared
    private let locRepo = LocationRepository.shared
    private let cache: ProfileCache
    private var loopTask: Task<Void, Never>?

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
                self.profile = cached.profile
                self.coalitionsState = cached.profile.coalitions.isEmpty ? .idle : .loaded
                self.projectsState = (cached.profile.finishedProjects.isEmpty && cached.profile.activeProjects.isEmpty) ? .idle : .loaded
            }
            await self.refreshNow()
            if self.autoRefresh {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
                    await self.refreshNow()
                }
            }
        }
    }

    func stop() {
        cancel()
        profile = nil
        coalitionsState = .idle
        projectsState = .idle
        weeklyLog = []
        lastUpdated = nil
    }

    func clearCache() {
        Task { await cache.clear() }
    }

    private func cancel() {
        loopTask?.cancel()
        loopTask = nil
    }

    func refreshNow() async {
        guard !login.isEmpty else { return }
        do {
            let basic = try await repo.basicProfile(login: login)
            profile = basic
            coalitionsState = .loading
            projectsState = .loading

            async let coalitions = repo.fetchCoalitions(login: login)
            async let projects = repo.fetchProjects(login: login)
            async let host = locRepo.fetchCurrentHost(login: login)
            async let stats = locRepo.lastDaysStats(login: login, days: daysWindow)

            do {
                let c = try await coalitions
                if let current = profile {
                    profile = repo.applyCoalitions(to: current, coalitions: c)
                }
                coalitionsState = .loaded
            } catch {
                coalitionsState = .failed
            }

            do {
                let p = try await projects
                if let current = profile {
                    profile = repo.applyProjects(to: current, projects: p)
                }
                projectsState = .loaded
            } catch {
                projectsState = .failed
            }

            if let h = try? await host, let current = profile {
                profile = repo.applyCurrentHost(to: current, host: h)
            }

            weeklyLog = (try? await stats) ?? []

            if let p = profile {
                await cache.save(CachedProfile(profile: p, fetchedAt: Date()))
            }
        } catch {}
    }

    func retryCoalitions() {
        Task { await refreshCoalitionsOnly() }
    }

    func retryProjects() {
        Task { await refreshProjectsOnly() }
    }

    private func refreshCoalitionsOnly() async {
        guard !login.isEmpty else { return }
        coalitionsState = .loading
        do {
            let c = try await repo.fetchCoalitions(login: login)
            if let current = profile {
                profile = repo.applyCoalitions(to: current, coalitions: c)
                coalitionsState = .loaded
                if let p = profile { await cache.save(CachedProfile(profile: p, fetchedAt: Date())) }
            }
        } catch {
            coalitionsState = .failed
        }
    }

    private func refreshProjectsOnly() async {
        guard !login.isEmpty else { return }
        projectsState = .loading
        do {
            let pjs = try await repo.fetchProjects(login: login)
            if let current = profile {
                profile = repo.applyProjects(to: current, projects: pjs)
                projectsState = .loaded
                if let p = profile { await cache.save(CachedProfile(profile: p, fetchedAt: Date())) }
            }
        } catch {
            projectsState = .failed
        }
    }
}
