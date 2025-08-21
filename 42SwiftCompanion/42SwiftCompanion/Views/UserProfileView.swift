import SwiftUI
import Charts

struct UserProfileView: View {
    @ObservedObject var loader: UserProfileLoader

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                LoadableSection(title: "Identité", state: loader.basicState) {
                    VStack(spacing: 8) {
                        Color.gray.frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 16)).redacted(reason: .placeholder)
                        LoadingListPlaceholder(lines: 2, compact: true)
                    }
                } failed: {
                    RetryRow(title: "Impossible de charger le profil") { loader.retryBasic() }
                } content: {
                    if let p = loader.profile {
                        VStack(spacing: 8) {
                            if let url = p.imageURL {
                                RemoteImage(url: url, cornerRadius: 16)
                                    .frame(width: 120, height: 120)
                            } else {
                                Color.gray.frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 16)).redacted(reason: .placeholder)
                            }
                            ProfileTextList(texts: [p.displayName], font: .title)
                            ProfileTextList(texts: [p.userNameWithTitle == p.login ? p.login : (p.userNameWithTitle ?? p.login)], font: .subheadline)
                            ProfileTextList(texts: [p.displayableHostOrNA], font: .subheadline)
                        }
                    }
                }

                LoadableSection(title: "Contact et campus", state: loader.basicState) {
                    LoadingListPlaceholder(lines: 3, compact: true)
                } failed: {
                    RetryRow(title: "Impossible de charger le contact") { loader.retryBasic() }
                } content: {
                    if let p = loader.profile, !p.displayableContact.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ProfileTextList(texts: p.displayableContact, font: .subheadline)
                            if let lang = loader.profile?.campusLanguage, !lang.isEmpty {
                                ProfileTextList(texts: ["Langue du campus: \(lang)"], font: .footnote)
                            }
                        }
                    } else {
                        EmptyRow(text: "Aucune information")
                    }
                }

                LoadableSection(title: "Statut et cursus", state: loader.basicState) {
                    LoadingListPlaceholder(lines: 2, compact: true)
                } failed: {
                    RetryRow(title: "Impossible de charger le statut") { loader.retryBasic() }
                } content: {
                    if let p = loader.profile, !(p.displayableStatus.isEmpty && p.displayableCursus.isEmpty) {
                        VStack(alignment: .leading, spacing: 8) {
                            ProfileTextList(texts: p.displayableStatus, font: .subheadline)
                            ProfileTextList(texts: p.displayableCursus, font: .subheadline)
                        }
                    } else {
                        EmptyRow(text: "Aucune information")
                    }
                }

                LoadableSection(title: "Points", state: loader.basicState) {
                    LoadingListPlaceholder(lines: 1, compact: true)
                } failed: {
                    RetryRow(title: "Impossible de charger les points") { loader.retryBasic() }
                } content: {
                    if let p = loader.profile {
                        ProfileTextList(texts: ["Wallet: \(p.wallet) | Points: \(p.correctionPoint)"], font: .subheadline)
                    }
                }

                LoadableSection(title: "Log time", state: loader.logState) {
                    LoadingListPlaceholder(lines: 1, compact: true)
                } failed: {
                    RetryRow(title: "Impossible de charger le log time") { loader.retryLog() }
                } content: {
                    WeeklyLogCard(logs: loader.weeklyLog)
                }

                LoadableSection(title: "Coalitions", state: loader.coalitionsState) {
                    LoadingListPlaceholder(lines: 2, compact: true)
                } failed: {
                    RetryRow(title: "Impossible de charger les coalitions") { loader.retryCoalitions() }
                } content: {
                    if let p = loader.profile, !p.displayableCoalitions.isEmpty {
                        ProfileTextList(texts: p.displayableCoalitions)
                    } else {
                        EmptyRow(text: "Aucune coalition")
                    }
                }

                LoadableSection(title: "Succès", state: loader.basicState) {
                    LoadingListPlaceholder(lines: 2, compact: true)
                } failed: {
                    RetryRow(title: "Impossible de charger les succès") { loader.retryBasic() }
                } content: {
                    if let p = loader.profile, !p.achievements.isEmpty {
                        AchievementsListView(achievements: p.achievements)
                    } else {
                        EmptyRow(text: "Aucun succès")
                    }
                }

                LoadableSection(title: "Projets en cours", state: loader.projectsState) {
                    LoadingListPlaceholder(lines: 2)
                } failed: {
                    RetryRow(title: "Impossible de charger les projets") { loader.retryProjects() }
                } content: {
                    if let p = loader.profile {
                        ActiveProjectsListView(profile: p)
                    } else {
                        EmptyRow(text: "Aucune donnée")
                    }
                }

                LoadableSection(title: "Projets terminés", state: loader.projectsState) {
                    LoadingListPlaceholder(lines: 3)
                } failed: {
                    RetryRow(title: "Impossible de charger les projets") { loader.retryProjects() }
                } content: {
                    if let p = loader.profile {
                        FinishedProjectsListView(profile: p)
                    } else {
                        EmptyRow(text: "Aucune donnée")
                    }
                }

                if let updated = loader.lastUpdated {
                    Text("Actualisé: \(updated.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LoadableSection<Content: View, Loading: View, Failed: View>: View {
    let title: String
    let state: UserProfileLoader.SectionLoadState
    let loading: Loading
    let failed: Failed
    let content: Content

    init(title: String,
         state: UserProfileLoader.SectionLoadState,
         @ViewBuilder loading: () -> Loading,
         @ViewBuilder failed: () -> Failed,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.state = state
        self.loading = loading()
        self.failed = failed()
        self.content = content()
    }

    var body: some View {
        SectionCard(title: title) {
            switch state {
            case .loading, .idle: loading
            case .failed: failed
            case .loaded: content
            }
        }
    }
}

struct MyProfileView: View {
    @EnvironmentObject var profileStore: ProfileStore
    var body: some View {
        if let loader = profileStore.loader {
            UserProfileView(loader: loader)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let content: Content
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Color.accentColor).padding(.bottom, 4)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.accentColor.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.accentColor.opacity(0.18), lineWidth: 1.5))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 8)
    }
}

struct ProfileTextList: View {
    let texts: [String]
    var font: Font = .body
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(texts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, id: \.self) { text in
                Text(text).font(font)
            }
        }
    }
}

struct WeeklyLogCard: View {
    let logs: [DailyLog]

    private var sorted: [DailyLog] {
        if logs.isEmpty {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone.current
            let today = cal.startOfDay(for: Date())
            return (0..<14).compactMap { i in
                guard let d = cal.date(byAdding: .day, value: -(13 - i), to: today) else { return nil }
                return DailyLog(date: d, hours: 0)
            }
        } else {
            return logs.sorted { $0.date < $1.date }
        }
    }

    private var totalHours: Double { sorted.reduce(0) { $0 + $1.hours } }
    private var avgHours: Double { sorted.isEmpty ? 0 : totalHours / Double(sorted.count) }
    private var yMax: Double { max(1, ceil((sorted.map(\.hours).max() ?? 0) + 0.5)) }

    private var xDomain: ClosedRange<Date> {
        let cal = Calendar.current
        guard let first = sorted.first?.date, let last = sorted.last?.date else {
            let s = cal.startOfDay(for: Date())
            let e = cal.date(byAdding: .day, value: 1, to: s) ?? s
            return s...e
        }
        let s = cal.startOfDay(for: first)
        let e = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: last)) ?? last
        return s...e
    }

    private var hasAnyData: Bool { sorted.contains { $0.hours > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart(sorted) { item in
                BarMark(x: .value("Date", item.date), y: .value("Heures", item.hours))
                    .cornerRadius(8)
                    .foregroundStyle(Color.accentColor)
                    .opacity(item.hours > 0 ? 1 : 0.35)
                if item.hours > 0 {
                    PointMark(x: .value("Date", item.date), y: .value("Heures", item.hours))
                }
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: 0...yMax)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = value.as(Date.self) { Text(d, format: .dateTime.weekday(.narrow)) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(v.formatted(.number.precision(.fractionLength(0)))) }
                    }
                }
            }
            .frame(height: 140)
            .overlay {
                if !hasAnyData {
                    VStack(spacing: 6) {
                        Image(systemName: "wave.3.right.circle").font(.title3).foregroundStyle(.secondary)
                        Text("Aucune présence sur les 14 derniers jours").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 10) {
                StatPill(title: "Total", value: formattedHours(totalHours))
                StatPill(title: "Moyenne", value: formattedHours(avgHours))
                Spacer()
            }
        }
    }

    private func formattedHours(_ h: Double) -> String {
        let minutes = Int((h * 60).rounded())
        let hh = minutes / 60
        let mm = minutes % 60
        return mm == 0 ? "\(hh) h" : "\(hh) h \(mm) min"
    }
}

private struct StatPill: View {
    let title: String
    let value: String
    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.accentColor.opacity(0.2), lineWidth: 1))
    }
}

struct LoadingListPlaceholder: View {
    let lines: Int
    var compact: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            ForEach(0..<lines, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8).fill(.gray.opacity(0.3)).frame(height: compact ? 10 : 14).redacted(reason: .placeholder)
            }
        }
    }
}

struct RetryRow: View {
    let title: String
    let action: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(title).font(.subheadline)
            Spacer()
            Button("Réessayer", action: action)
        }
    }
}

struct EmptyRow: View {
    let text: String
    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
    }
}

private struct CursusFilterModel: Equatable {
    struct Option: Identifiable, Hashable {
        let id: Int
        let title: String
    }

    let options: [Option]
    let defaultId: Int?

    init(profile: UserProfile, restrictToIds: Set<Int>) {
        let nameById = Dictionary(uniqueKeysWithValues: profile.cursus.map { ($0.id, $0.name ?? "Cursus \($0.id)") })
        let present = profile.cursus.filter { restrictToIds.contains($0.id) }
        let ordered = present.sorted { lhs, rhs in
            let l = lhs.endAt ?? lhs.beginAt ?? .distantPast
            let r = rhs.endAt ?? rhs.beginAt ?? .distantPast
            return l > r
        }
        self.options = ordered.map { Option(id: $0.id, title: nameById[$0.id] ?? "Cursus \($0.id)") }
        self.defaultId = options.first?.id
    }
}

private struct ProjectsPicker: View {
    let options: [CursusFilterModel.Option]
    @Binding var selection: Int

    var body: some View {
        Picker("Cursus", selection: $selection) {
            ForEach(options) { opt in
                Text(opt.title).tag(opt.id)
            }
        }
        .pickerStyle(.menu)
        .tint(.accentColor)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private let projectsSectionMaxHeight: CGFloat = 420

private struct ActiveProjectsListView: View {
    let profile: UserProfile
    @State private var selectedCursusId: Int
    @State private var presented: UserProfile.ActiveProject?
    private let filter: CursusFilterModel

    init(profile: UserProfile) {
        self.profile = profile
        let ids = Set(profile.activeProjects.compactMap { $0.cursusId })
        let f = CursusFilterModel(profile: profile, restrictToIds: ids)
        self.filter = f
        _selectedCursusId = State(initialValue: f.defaultId ?? ids.sorted().first ?? 0)
    }

    private var itemsSorted: [UserProfile.ActiveProject] {
        profile.activeProjects
            .filter { $0.cursusId == selectedCursusId }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    var body: some View {
        if filter.options.isEmpty {
            EmptyRow(text: "Aucun projet en cours")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ProjectsPicker(options: filter.options, selection: $selectedCursusId)
                if itemsSorted.isEmpty {
                    EmptyRow(text: "Aucun projet pour ce cursus")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(itemsSorted) { p in
                                InfoPillRow(
                                    leading: .system("hammer.fill"),
                                    title: p.name,
                                    subtitle: [p.status, p.teamStatus].compactMap { $0 }.joined(separator: " • "),
                                    badges: badgeTexts(for: p),
                                    onTap: { presented = p }
                                )
                            }
                        }
                        .padding(.trailing, 2)
                    }
                    .frame(maxHeight: projectsSectionMaxHeight)
                    .scrollIndicators(.visible)
                }
            }
            .animation(.snappy, value: selectedCursusId)
            .sheet(item: $presented) { p in
                ActiveProjectDetailSheet(project: p)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func badgeTexts(for p: UserProfile.ActiveProject) -> [String] {
        var arr: [String] = []
        if let d = p.createdAt { arr.append(UserProfile.Formatters.shortDate.string(from: d)) }
        if let r = p.retry, r > 0 { arr.append("Tentative \(r)") }
        return arr
    }
}

private struct FinishedProjectsListView: View {
    let profile: UserProfile
    @State private var selectedCursusId: Int
    @State private var presented: UserProfile.Project?
    private let filter: CursusFilterModel

    init(profile: UserProfile) {
        self.profile = profile
        let ids = Set(profile.finishedProjects.compactMap { $0.cursusId })
        let f = CursusFilterModel(profile: profile, restrictToIds: ids)
        self.filter = f
        _selectedCursusId = State(initialValue: f.defaultId ?? ids.sorted().first ?? 0)
    }

    private var itemsSorted: [UserProfile.Project] {
        profile.finishedProjects
            .filter { $0.cursusId == selectedCursusId }
            .sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }
    }

    var body: some View {
        if filter.options.isEmpty {
            EmptyRow(text: "Aucun projet terminé")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ProjectsPicker(options: filter.options, selection: $selectedCursusId)
                if itemsSorted.isEmpty {
                    EmptyRow(text: "Aucun projet pour ce cursus")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(itemsSorted) { p in
                                InfoPillRow(
                                    leading: .system("checkmark.seal.fill"),
                                    title: p.name,
                                    subtitle: nil,
                                    badges: badgeTexts(for: p),
                                    onTap: { presented = p }
                                )
                            }
                        }
                        .padding(.trailing, 2)
                    }
                    .frame(maxHeight: projectsSectionMaxHeight)
                    .scrollIndicators(.visible)
                }
            }
            .animation(.snappy, value: selectedCursusId)
            .sheet(item: $presented) { p in
                FinishedProjectDetailSheet(project: p)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func badgeTexts(for p: UserProfile.Project) -> [String] {
        var arr: [String] = []
        arr.append("Note \(p.finalMark ?? 0)")
        if let v = p.validated { arr.append(v ? "Validé" : "Non validé") }
        if let d = p.closedAt { arr.append(UserProfile.Formatters.shortDate.string(from: d)) }
        if let r = p.retry, r > 0 { arr.append("Tentative \(r)") }
        return arr
    }
}

private struct ActiveProjectDetailSheet: View {
    let project: UserProfile.ActiveProject

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "hammer.fill")
                        .frame(width: 48, height: 48)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name).font(.title3).bold()
                        HStack(spacing: 8) {
                            if let s = project.status { CapsuleBadge(text: s) }
                            if let ts = project.teamStatus { CapsuleBadge(text: ts) }
                            if let r = project.retry, r > 0 { CapsuleBadge(text: "Tentative \(r)") }
                        }
                    }
                    Spacer()
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    if let d = project.createdAt {
                        HStack {
                            Image(systemName: "calendar")
                            Text(UserProfile.Formatters.shortDate.string(from: d)).font(.subheadline)
                        }
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Détails")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct FinishedProjectDetailSheet: View {
    let project: UserProfile.Project

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .frame(width: 48, height: 48)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name).font(.title3).bold()
                        HStack(spacing: 8) {
                            CapsuleBadge(text: "Note \(project.finalMark ?? 0)")
                            if let v = project.validated { CapsuleBadge(text: v ? "Validé" : "Non validé") }
                            if let r = project.retry, r > 0 { CapsuleBadge(text: "Tentative \(r)") }
                        }
                    }
                    Spacer()
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    if let d = project.closedAt {
                        HStack {
                            Image(systemName: "calendar")
                            Text(UserProfile.Formatters.shortDate.string(from: d)).font(.subheadline)
                        }
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Détails")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct AchievementsListView: View {
    struct Group: Identifiable, Equatable {
        let id: String
        let name: String
        let symbol: String
        let count: Int
        let variants: [UserProfile.Achievement]
        static func == (lhs: Group, rhs: Group) -> Bool { lhs.id == rhs.id }
    }

    let achievements: [UserProfile.Achievement]
    @State private var presented: Group?

    private var groups: [Group] {
        let map = Dictionary(grouping: achievements, by: { $0.name })
        return map.values.map { arr in
            let name = arr.first?.name ?? UUID().uuidString
            let symbol = AchievementIconProvider.symbol(for: name, description: arr.first?.description)
            let variants = arr.sorted {
                let a = $0.count ?? 1
                let b = $1.count ?? 1
                if a == b { return $0.id < $1.id }
                return a > b
            }
            return Group(id: name, name: name, symbol: symbol, count: arr.count, variants: variants)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(groups) { g in
                InfoPillRow(
                    leading: .system(g.symbol),
                    title: g.name,
                    subtitle: "×\(g.count)",
                    badges: [],
                    onTap: { presented = g }
                )
            }
        }
        .sheet(item: $presented) { g in
            AchievementGroupSheet(group: g)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct AchievementGroupSheet: View {
    let group: AchievementsListView.Group

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: group.symbol)
                        .frame(width: 48, height: 48)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name).font(.title3).bold()
                        Text("Total ×\(group.count)").font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Divider()
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(group.variants) { a in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "trophy.fill")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(a.name).font(.subheadline)
                                Text(a.description).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.06)))
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Détails")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
