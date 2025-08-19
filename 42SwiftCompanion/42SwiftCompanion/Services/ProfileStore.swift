import Foundation
import SwiftUI

@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    enum SectionLoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    @Published private(set) var profile: UserProfile? { didSet { lastUpdated = Date() } }
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var coalitionsState: SectionLoadState = .idle
    @Published private(set) var projectsState: SectionLoadState = .idle

    private let repo = ProfileRepository.shared
    private let cache = ProfileCache()
    private var loopTask: Task<Void, Never>?

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
        coalitionsState = .idle
        projectsState = .idle
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
            profile = basic
            coalitionsState = .loading
            projectsState = .loading

            let repoRef = repo
            let coalitionsTask = Task.detached(priority: .background) {
                try await repoRef.fetchCoalitions(login: login)
            }
            let projectsTask = Task.detached(priority: .background) {
                try await repoRef.fetchProjects(login: login)
            }

            do {
                let coalitions = try await coalitionsTask.value
                if let current = profile {
                    profile = repo.applyCoalitions(to: current, coalitions: coalitions)
                }
                coalitionsState = .loaded
            } catch {
                coalitionsState = .failed
            }

            do {
                let projects = try await projectsTask.value
                if let current = profile {
                    profile = repo.applyProjects(to: current, projects: projects)
                }
                projectsState = .loaded
            } catch {
                projectsState = .failed
            }

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
        let login = AuthService.shared.getCurrentUserLogin()
        guard !login.isEmpty else { return }

        coalitionsState = .loading
        do {
            let coalitions = try await repo.fetchCoalitions(login: login)
            if let current = profile {
                profile = repo.applyCoalitions(to: current, coalitions: coalitions)
                coalitionsState = .loaded
                if let p = profile { await cache.save(CachedProfile(profile: p, fetchedAt: Date())) }
            }
        } catch {
            coalitionsState = .failed
        }
    }

    private func refreshProjectsOnly() async {
        let login = AuthService.shared.getCurrentUserLogin()
        guard !login.isEmpty else { return }

        projectsState = .loading
        do {
            let projects = try await repo.fetchProjects(login: login)
            if let current = profile {
                profile = repo.applyProjects(to: current, projects: projects)
                projectsState = .loaded
                if let p = profile { await cache.save(CachedProfile(profile: p, fetchedAt: Date())) }
            }
        } catch {
            projectsState = .failed
        }
    }
}
