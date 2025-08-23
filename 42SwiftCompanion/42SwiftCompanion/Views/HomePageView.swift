import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject var profileStore: ProfileStore
    @StateObject private var loaderHolder = LoaderHolder()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Accueil")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                LazyVStack(spacing: 24) {
                    HomeSection(title: "Campus") {
                        switch loaderHolder.state {
                        case .loading, .idle:
                            LoadingListPlaceholder(lines: 3)
                        case .failed:
                            RetryRow(title: "Impossible de charger le campus") {
                                Task { await loaderHolder.refresh() }
                            }
                        case .loaded:
                            if let dash = loaderHolder.dashboard {
                                CampusInfoCard(info: dash.info, activeUsersCount: dash.activeUsersCount)
                            } else {
                                LoadingListPlaceholder(lines: 3)
                            }
                        }
                    }

                    HomeSection(title: "Événements à venir") {
                        switch loaderHolder.state {
                        case .loading, .idle:
                            LoadingListPlaceholder(lines: 3)
                        case .failed:
                            EmptyRow(text: "Erreur")
                        case .loaded:
                            if let events = loaderHolder.dashboard?.upcomingEvents, !events.isEmpty {
                                EventsList(events: events)
                            } else {
                                ContentUnavailableView("Aucun événement", systemImage: "calendar.badge.exclamationmark")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    if let updated = loaderHolder.lastUpdated {
                        Text("Actualisé: \(updated.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .padding()
        }
        .onAppear { loaderHolder.bootstrap(with: profileStore.loader?.profile?.campusId) }
        .onChange(of: profileStore.loader?.profile?.campusId) { _, newId in
            loaderHolder.bootstrap(with: newId)
        }
    }

    @MainActor
    private final class LoaderHolder: ObservableObject {
        @Published var dashboard: CampusDashboard?
        @Published var state: CampusLoader.LoadState = .idle
        @Published var lastUpdated: Date?

        private var loader: CampusLoader?

        func bootstrap(with campusId: Int?) {
            guard let id = campusId else { return }
            if loader?.campusId == id { return }
            loader?.stop()
            let l = CampusLoader(campusId: id)
            self.loader = l
            l.$state.assign(to: &$state)
            l.$dashboard.assign(to: &$dashboard)
            l.$lastUpdated.assign(to: &$lastUpdated)
            l.start()
        }

        func refresh() async {
            await loader?.refreshNow()
        }
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
                    iconTint: .accentColor
                )
            }
            if let site = info.website {
                InfoPillRow(
                    leading: .system("link"),
                    title: "Site web",
                    subtitle: site.absoluteString,
                    onTap: { UIApplication.shared.open(site) },
                    iconTint: .accentColor
                )
            }
            if let users = info.usersCount {
                InfoPillRow(
                    leading: .system("person.3.fill"),
                    title: "Étudiants inscrits",
                    subtitle: "\(users)",
                    iconTint: .secondary
                )
            }
            HStack(spacing: 12) {
                Image(systemName: "wifi")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Actuellement connectés").font(.caption2).foregroundStyle(.secondary)
                    Text("\(activeUsersCount)").font(.title3.weight(.semibold))
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color("AccentColor").opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color("AccentColor").opacity(0.18), lineWidth: 1))
        }
    }
}

private struct EventsList: View {
    let events: [CampusDashboard.Event]
    @State private var presented: CampusDashboard.Event?

    var body: some View {
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
        .sheet(item: $presented) { e in
            EventDetailSheet(event: e)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct EventDetailSheet: View {
    let event: CampusDashboard.Event
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .frame(width: 48, height: 48)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color("AccentColor").opacity(0.12)))
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
