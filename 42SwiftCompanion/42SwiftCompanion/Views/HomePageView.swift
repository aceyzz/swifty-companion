import SwiftUI
import UIKit
import Combine

private struct MePrimaryCampusRaw: Decodable { let primary_campus_id: Int? }

@MainActor
final class HomeCampusResolver {
    private var cached: Int?
    private let maxAttempts = 6

    func currentCampusId(profileStore: ProfileStore) async -> Int? {
        if let id = cached { return id }
        if let id = profileStore.loader?.profile?.campusId { cached = id; return id }
        do {
            let raw: MePrimaryCampusRaw = try await APIClient.shared.request(Endpoint(path: "/v2/me"), as: MePrimaryCampusRaw.self)
            cached = raw.primary_campus_id
            return cached
        } catch {
            return nil
        }
    }

    func resolveWithRetry(profileStore: ProfileStore, isAuthenticated: Bool) async -> Int? {
        if !isAuthenticated { return nil }
        if let id = await currentCampusId(profileStore: profileStore) { return id }
        var attempt = 0
        while attempt < maxAttempts {
            attempt += 1
            let delay = UInt64(pow(2, Double(attempt - 1)) * 0.6 * (1 + Double.random(in: 0...0.35)) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            if Task.isCancelled { return nil }
            if let id = await currentCampusId(profileStore: profileStore) { return id }
        }
        return nil
    }

    func invalidate() { cached = nil }
}

@MainActor
final class HomeDashboardViewModel: ObservableObject {
    @Published private(set) var state: CampusLoader.LoadState = .idle
    @Published private(set) var dashboard: CampusDashboard?
    @Published private(set) var lastUpdated: Date?

    private var loader: CampusLoader?
    private var currentCampusId: Int?
    private let resolver = HomeCampusResolver()
    private var resolveTask: Task<Void, Never>?
    private var attachTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var isBound = false

    func bind(profileStore: ProfileStore, authService: AuthService) {
        guard !isBound else { return }
        isBound = true

        authService.$isAuthenticated
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isAuth in
                guard let self else { return }
                if !isAuth { self.detach() }
                else {
                    self.resolveTask?.cancel()
                    self.resolveTask = Task { [weak self] in
                        guard let self else { return }
                        await self.resolveAndAttach(profileStore: profileStore, isAuthenticated: isAuth)
                    }
                }
            }
            .store(in: &cancellables)

        profileStore.$loader
            .map { loader -> AnyPublisher<Int?, Never> in
                guard let loader else { return Just(nil).eraseToAnyPublisher() }
                return loader.$profile.map { $0?.campusId }.removeDuplicates().eraseToAnyPublisher()
            }
            .switchToLatest()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] id in
                guard let self else { return }
                if let id { self.attach(campusId: id) }
            }
            .store(in: &cancellables)
    }

    func bootstrap(profileStore: ProfileStore, isAuthenticated: Bool) {
        resolveTask?.cancel()
        resolveTask = Task { [weak self] in
            guard let self else { return }
            await self.resolveAndAttach(profileStore: profileStore, isAuthenticated: isAuthenticated)
        }
    }

    func refresh() async {
        await loader?.refreshNow()
    }

    private func resolveAndAttach(profileStore: ProfileStore, isAuthenticated: Bool) async {
        guard isAuthenticated else { detach(); return }
        if let id = profileStore.loader?.profile?.campusId {
            attach(campusId: id)
            return
        }
        if let resolved = await resolver.resolveWithRetry(profileStore: profileStore, isAuthenticated: isAuthenticated) {
            attach(campusId: resolved)
        }
    }

    private func attach(campusId: Int?) {
        guard let id = campusId, id != currentCampusId else { return }
        currentCampusId = id
        attachTask?.cancel()
        loader?.stop()
        loader = nil
        dashboard = nil
        lastUpdated = nil
        state = .loading

        let l = CampusLoader(campusId: id)
        loader = l
        l.$state.assign(to: &$state)
        l.$dashboard.assign(to: &$dashboard)
        l.$lastUpdated.assign(to: &$lastUpdated)
        l.start()

        attachTask = Task { [weak l] in
            guard let l else { return }
            await l.refreshNow()
        }
    }

    private func detach() {
        resolver.invalidate()
        resolveTask?.cancel()
        resolveTask = nil
        attachTask?.cancel()
        attachTask = nil
        currentCampusId = nil
        loader?.stop()
        loader = nil
        dashboard = nil
        lastUpdated = nil
        state = .idle
    }
}

struct HomeView: View {
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var authService: AuthService
    @StateObject private var vm = HomeDashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Accueil")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                LazyVStack(spacing: 24) {
                    SectionCard(title: "Campus") {
                        switch vm.state {
                        case .idle, .loading:
                            LoadingListPlaceholder(lines: 3)
                        case .failed:
                            RetryRow(title: "Impossible de charger le campus") {
                                Task { await vm.refresh() }
                            }
                        case .loaded:
                            if let dash = vm.dashboard {
                                CampusInfoCard(info: dash.info, activeUsersCount: dash.activeUsersCount)
                            } else {
                                LoadingListPlaceholder(lines: 3)
                            }
                        }
                    }

                    SectionCard(title: "Événements à venir") {
                        switch vm.state {
                        case .idle, .loading:
                            LoadingListPlaceholder(lines: 3)
                        case .failed:
                            EmptyRow(text: "Erreur")
                        case .loaded:
                            if let events = vm.dashboard?.upcomingEvents, !events.isEmpty {
                                EventsList(events: events)
                            } else {
                                ContentUnavailableView("Aucun événement", systemImage: "calendar.badge.exclamationmark")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    if let updated = vm.lastUpdated {
                        Text("Actualisé: \(updated.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .padding()
        }
        .refreshable { await vm.refresh() }
        .task {
            vm.bind(profileStore: profileStore, authService: authService)
            vm.bootstrap(profileStore: profileStore, isAuthenticated: authService.isAuthenticated)
        }
        .animation(.snappy, value: vm.state)
    }
}

private struct HomeSection<Content: View>: View {
    let title: String
    let content: Content
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        SectionCard(title: title) { content }
    }
}

private struct CampusInfoCard: View {
    @EnvironmentObject var theme: Theme
    let info: CampusDashboard.Info
    let activeUsersCount: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "building.2.fill")
                Text(info.name).font(.title3.weight(.semibold))
                Spacer()
            }
            if let address = info.addressFull, !address.isEmpty {
                InfoPillRow(
                    leading: .system("mappin.and.ellipse"),
                    title: address,
                    subtitle: [info.city, info.country].compactMap { $0 }.joined(separator: " • "),
                    onTap: { MapModule.openAddress(address, name: info.name) },
                    iconTint: nil
                )
            }
            if let site = info.website {
                InfoPillRow(
                    leading: .system("link"),
                    title: "Site web",
                    subtitle: site.absoluteString,
                    onTap: { UIApplication.shared.open(site) },
                    iconTint: nil
                )
            }
            if let users = info.usersCount {
                InfoPillRow(
                    leading: .system("person.3.fill"),
                    title: "Étudiants inscrits",
                    subtitle: "\(users)",
                    iconTint: nil
                )
            }
            InfoPillRow(
                leading: .system("wifi"),
                title: "Actuellement connectés",
                subtitle: "\(activeUsersCount)",
                iconTint: nil
            )
        }
    }
}

private struct EventsList: View {
    @EnvironmentObject var theme: Theme
    let events: [CampusDashboard.Event]
    @State private var presented: CampusDashboard.Event?

    var body: some View {
        Group {
            if events.count > 4 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(events) { e in
                            InfoPillRow(
                                leading: .system("calendar"),
                                title: e.title,
                                subtitle: [e.when, e.location].compactMap { $0 }.joined(separator: " — "),
                                badges: e.badges,
                                onTap: { presented = e }
                            )
                        }
                    }
                }
                .frame(maxHeight: 300)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(events) { e in
                        InfoPillRow(
                            leading: .system("calendar"),
                            title: e.title,
                            subtitle: [e.when, e.location].compactMap { $0 }.joined(separator: " — "),
                            badges: e.badges,
                            onTap: { presented = e }
                        )
                    }
                }
            }
        }
        .sheet(item: $presented) { e in
            EventDetailSheet(event: e)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct EventDetailSheet: View {
    @EnvironmentObject var theme: Theme
    let event: CampusDashboard.Event

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .frame(width: 48, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(theme.accentColor.opacity(0.12))
                        )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title).font(.title3).bold()
                        Text(event.when).font(.footnote).foregroundStyle(.secondary)
                        if let loc = event.location, !loc.isEmpty {
                            Text(loc).font(.footnote)
                        }
                        if !event.badges.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(Array(event.badges.enumerated()), id: \.offset) { _, b in
                                    CapsuleBadge(text: b)
                                }
                            }
                        }
                    }
                    Spacer()
                }
                Divider()
                if let desc = event.description, !desc.isEmpty {
                    ScrollView { Text(desc).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading) }
                } else {
                    ContentUnavailableView("Pas de description", systemImage: "text.alignleft")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Détails de l’événement")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
