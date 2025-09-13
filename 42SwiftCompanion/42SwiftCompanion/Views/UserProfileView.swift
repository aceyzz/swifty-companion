import SwiftUI
import Charts

private let achievementsSectionMaxHeight: CGFloat = 320
private let finishedProjectsSectionMaxHeight: CGFloat = 360
private let projectsSectionMaxHeight: CGFloat = 420

struct UserProfileView: View {
    @ObservedObject var loader: UserProfileLoader

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Mon profil")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                LazyVStack(spacing: 24) {
                    LoadableSection(title: "Identité", state: loader.basicState) {
                        IdentitySkeleton()
                    } failed: {
                        RetryRow(title: "Impossible de charger le profil") { loader.retryBasic() }
                    } content: {
                        if let p = loader.profile {
                            VStack(alignment: .leading, spacing: 16) {
                                IdentityCard(profile: p)
                                HStack(spacing: 12) {
                                    StatCard(style: .compact, title: "Wallet", value: "\(p.wallet)", systemImage: "creditcard.fill")
                                    StatCard(style: .compact, title: "Points d’évaluations", value: "\(p.correctionPoint)", systemImage: "scalemass.fill")
                                    Spacer()
                                }
                                HStack(spacing: 12) {
                                    let hostParts = p.displayableHostOrNA.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                                    let hostTitle = hostParts.first ?? "Cluster"
                                    let hostValue = hostParts.count > 1 ? hostParts[1] : hostParts.first ?? ""
                                    let showLink = hostValue != "Non disponible"
                                    InfoPillRow(
                                        leading: .system("desktopcomputer"),
                                        title: String(hostTitle),
                                        subtitle: String(hostValue),
                                        badges: [],
                                        onTap: showLink ? {
                                            if let url = URL(string: "https://meta.intra.42.fr/clusters") {
                                                UIApplication.shared.open(url)
                                            }
                                        } : nil
                                    )
                                }
                            }
                        } else {
                            IdentitySkeleton()
                        }
                    }

                    LoadableSection(title: "À propos", state: loader.basicState) {
                        LoadingListPlaceholder(lines: 2, compact: true)
                    } failed: {
                        RetryRow(title: "Impossible de charger le statut") { loader.retryBasic() }
                    } content: {
                        if let p = loader.profile, !(p.displayableStatus.isEmpty && p.cursus.isEmpty) {
                            StatusCursusCard(profile: p)
                        } else {
                            ContentUnavailableView("Aucune information", systemImage: "info.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    LoadableSection(title: "Coalitions", state: loader.coalitionsState) {
                        LoadingListPlaceholder(lines: 2, compact: true)
                    } failed: {
                        RetryRow(title: "Impossible de charger les coalitions") { loader.retryCoalitions() }
                    } content: {
                        if let p = loader.profile {
                            CoalitionsCard(profile: p)
                        } else {
                            LoadingListPlaceholder(lines: 2, compact: true)
                        }
                    }

                    LogTimeSection(loader: loader)

                    if let p = loader.profile {
                        UnifiedItemsCarouselSection(
                            title: "Achievements",
                            state: loader.basicState,
                            source: .flat(ItemsBuilder.achievements(from: p)),
                            emptyText: "Aucun Achievements",
                            maxHeight: achievementsSectionMaxHeight
                        )

                        UnifiedItemsSection(
                            title: "En cours",
                            state: loader.projectsState,
                            source: .grouped(ItemsBuilder.activeProjectsGrouped(from: p)),
                            emptyText: "Aucun projet pour ce cursus",
                            maxHeight: projectsSectionMaxHeight,
                            onRetry: { loader.retryProjects() }
                        )

                        UnifiedItemsSection(
                            title: "Projets terminés",
                            state: loader.projectsState,
                            source: .grouped(ItemsBuilder.finishedProjectsGrouped(from: p)),
                            emptyText: "Aucun projet pour ce cursus",
                            maxHeight: finishedProjectsSectionMaxHeight,
                            onRetry: { loader.retryProjects() }
                        )
                    } else {
                        LoadableSection(title: "Achievements", state: loader.basicState) {
                            LoadingListPlaceholder(lines: 2, compact: true)
                        } failed: {
                            EmptyRow(text: "Erreur")
                        } content: {
                            ContentUnavailableView("Aucun Achievements", systemImage: "trophy")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        LoadableSection(title: "Projets en cours", state: loader.projectsState) {
                            LoadingListPlaceholder(lines: 2)
                        } failed: {
                            EmptyRow(text: "Erreur")
                        } content: {
                            ContentUnavailableView("Aucune donnée", systemImage: "hammer")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        LoadableSection(title: "Projets terminés", state: loader.projectsState) {
                            LoadingListPlaceholder(lines: 3)
                        } failed: {
                            EmptyRow(text: "Erreur")
                        } content: {
                            ContentUnavailableView("Aucune donnée", systemImage: "checkmark.seal")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let updated = loader.lastUpdated {
                        Text("Actualisé: \(updated.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .refreshable { await loader.refreshNow() }
        .animation(.snappy, value: loader.basicState)
        .animation(.snappy, value: loader.projectsState)
        .animation(.snappy, value: loader.coalitionsState)
        .animation(.snappy, value: loader.logState)
    }
}

struct IdentityCard: View {
    let profile: UserProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Avatar(url: profile.imageURL)
                VStack(alignment: .leading, spacing: 8) {
                    Text(profile.displayName).font(.title3.weight(.semibold))
                    Text(profile.userNameWithTitle == profile.login ? profile.login : (profile.userNameWithTitle ?? profile.login))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let active = profile.isActive {
                        Text(active ? "Actif" : "Inactif")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(active ? .green : .red)
                    }
                }
                Spacer()
            }
            if !profile.displayableContact.isEmpty || !(profile.campusLanguage ?? "").isEmpty {
                VStack(spacing: 10) {
                    ForEach(profile.displayableContact, id: \.self) { line in
                        LabeledContent {
                            if isEmail(line) {
                                if let url = URL(string: "mailto:\(line.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? line)") {
                                    Link(line, destination: url).font(.subheadline)
                                } else {
                                    Text(line).font(.subheadline)
                                }
                            } else if isPhone(line) {
                                let digits = line.filter { $0.isNumber }
                                if let url = URL(string: "tel://\(digits)") {
                                    Link(line, destination: url).font(.subheadline)
                                } else {
                                    Text(line).font(.subheadline)
                                }
                            } else if isCampusLine(line) || isDetectedAddress(line) {
                                Button {
                                    if let q = campusAddressQuery() {
                                        MapModule.openAddress(q, name: profile.campusName ?? profile.displayName)
                                    } else {
                                        MapModule.openAddress(line, name: profile.displayName)
                                    }
                                } label: {
                                    Text(line).font(.subheadline).underline()
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(line).font(.subheadline)
                            }
                        } label: {
                            Image(systemName: iconForContact(line)).frame(width: 18)
                        }
                    }
                    if let lang = profile.campusLanguage, !lang.isEmpty {
                        LabeledContent {
                            Text(lang).font(.subheadline)
                        } label: {
                            Image(systemName: "globe").frame(width: 18)
                        }
                    }
                }
            } else {
                ContentUnavailableView("Aucune information", systemImage: "info.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func iconForContact(_ s: String) -> String {
        if isEmail(s) { return "envelope" }
        if isCampusLine(s) || isDetectedAddress(s) { return "mappin.and.ellipse" }
        if isPhone(s) { return "phone" }
        return "person"
    }

    private func isEmail(_ s: String) -> Bool {
        s.contains("@")
    }

    private func isPhone(_ s: String) -> Bool {
        s.filter { $0.isNumber }.count >= 6
    }

    private func isCampusLine(_ s: String) -> Bool {
        guard let name = profile.campusName, !name.isEmpty else { return false }
        if s.localizedCaseInsensitiveContains(name) { return true }
        if let city = profile.campusCity, s.localizedCaseInsensitiveContains(city) { return true }
        if let country = profile.campusCountry, s.localizedCaseInsensitiveContains(country) { return true }
        return false
    }

    private func campusAddressQuery() -> String? {
        let parts = [profile.campusName, profile.campusCity, profile.campusCountry].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }

    private func isDetectedAddress(_ s: String) -> Bool {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) else { return false }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        if let match = detector.firstMatch(in: s, options: [], range: range) {
            return match.resultType == .address && match.range.length >= 6
        }
        return false
    }
}

struct IdentitySkeleton: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 16).fill(.gray.opacity(0.25)).frame(width: 120, height: 120)
            VStack(alignment: .leading, spacing: 12) {
                LoadingListPlaceholder(lines: 2, compact: true)
                LoadingListPlaceholder(lines: 3, compact: true)
            }
            Spacer()
        }
        .redacted(reason: .placeholder)
    }
}

struct Avatar: View {
    let url: URL?
    var body: some View {
        Group {
            if let u = url {
                RemoteImage(url: u, cornerRadius: 16)
            } else {
                Color.gray.opacity(0.25)
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct FilterChip: View {
    @EnvironmentObject var theme: Theme
    let text: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? theme.accentColor.opacity(0.18) : theme.accentColor.opacity(0.08))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isSelected ? theme.accentColor.opacity(0.45) : theme.accentColor.opacity(0.2),
                                lineWidth: isSelected ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

struct StatCard: View {
    @EnvironmentObject var theme: Theme
    let style: StatCardStyle
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        Group {
            switch style {
            case .compact:
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.caption2).foregroundStyle(.secondary)
                        Text(value).font(.callout.weight(.semibold))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            case .regular:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: systemImage)
                        Text(title).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(value).font(.title3.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.accentColor.opacity(0.18), lineWidth: 1)
        )
    }
}

struct StatusCursusCard: View {
    let profile: UserProfile
    @State private var selectedCursusId: Int?

    private var orderedCursus: [UserProfile.Cursus] {
        profile.cursus.sorted {
            let l = $0.endAt ?? $0.beginAt ?? .distantPast
            let r = $1.endAt ?? $1.beginAt ?? .distantPast
            return l > r
        }
    }

    private var selected: UserProfile.Cursus? {
        if let id = selectedCursusId { return orderedCursus.first(where: { $0.id == id }) }
        return orderedCursus.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !profile.displayableStatus.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(profile.displayableStatus, id: \.self) { s in
                        Label(s, systemImage: iconForStatus(s))
                            .font(.subheadline)
                    }
                }
            }

            if !orderedCursus.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    let binding = Binding(
                        get: { selectedCursusId ?? orderedCursus.first?.id ?? 0 },
                        set: { selectedCursusId = $0 }
                    )
                    ChipsBar(items: orderedCursus, selection: binding) { $0.name ?? "Cursus \($0.id)" }

                    if let c = selected {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "graduationcap.fill")
                                Text(title(for: c)).font(.subheadline)
                                Spacer()
                            }
                            if let level = c.level {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Niveau \(level.formatted(.number.precision(.fractionLength(2))))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    ProgressView(value: levelFraction(level))
                                        .progressViewStyle(.linear)
                                        .tint(.accentColor)
                                }
                            } else {
                                Text("Niveau indisponible").font(.caption).foregroundStyle(.secondary)
                            }
							if !c.skills.isEmpty {
								VStack(alignment: .leading, spacing: 0) {
									HStack(spacing: 8) {
										Image(systemName: "star.fill")
										Text("Skills").font(.subheadline)
									}
									ScrollView(.horizontal, showsIndicators: false) {
										HStack(spacing: 8) {
											ForEach(c.skills) { sk in
												let label = sk.level.map { "\(sk.name) - lvl.\(String(format: "%.2f", $0))" } ?? sk.name
												FilterChip(text: label, isSelected: false, action: {})
											}
										}
										.padding(.top, 6)
									}
									.frame(maxWidth: .infinity)
								}
								.padding(.top, 12)
							}
                        }
                    }
                }
                .task(id: orderedCursus.map(\.id)) {
                    let ids = orderedCursus.map(\.id)
                    if selectedCursusId == nil { selectedCursusId = ids.first }
                    else if let sel = selectedCursusId, !ids.contains(sel) { selectedCursusId = ids.first }
                }
                .animation(.snappy, value: selectedCursusId)
            }

            if profile.displayableStatus.isEmpty && orderedCursus.isEmpty {
                ContentUnavailableView("Aucune information", systemImage: "info.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func title(for c: UserProfile.Cursus) -> String {
        var s = c.name ?? "Cursus"
        if let grade = c.grade, !grade.isEmpty { s += " — \(grade)" }
        return s
    }

    private func levelFraction(_ level: Double) -> Double {
        let f = level.truncatingRemainder(dividingBy: 1)
        return max(0, min(1, f))
    }

    private func iconForStatus(_ s: String) -> String {
        if s.localizedCaseInsensitiveContains("Actif") { return "bolt.fill" }
        if s.localizedCaseInsensitiveContains("Piscine") { return "figure.pool.swim" }
        return "person.crop.circle"
    }
}

struct CoalitionsCard: View {
    let profile: UserProfile
    @State private var selectedCoalitionId: Int?

    private var orderedCoalitions: [UserProfile.Coalition] {
        profile.coalitions.sorted { ($0.score ?? 0) > ($1.score ?? 0) }
    }

    private var selected: UserProfile.Coalition? {
        if let id = selectedCoalitionId { return orderedCoalitions.first(where: { $0.id == id }) }
        return orderedCoalitions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !orderedCoalitions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    let binding = Binding(
                        get: { selectedCoalitionId ?? orderedCoalitions.first?.id ?? 0 },
                        set: { selectedCoalitionId = $0 }
                    )
                    ChipsBar(items: orderedCoalitions, selection: binding) { $0.name }

                    if let c = selected {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: "flag.2.crossed.fill")
                                Text(c.name).font(.subheadline.weight(.semibold))
                                Spacer()
                            }
                            HStack(spacing: 10) {
                                StatCard(style: .regular, title: "Score", value: "\(c.score ?? 0)", systemImage: "chart.line.uptrend.xyaxis")
                                StatCard(style: .regular, title: "Rang", value: c.rank.map { "#\($0)" } ?? "—", systemImage: "crown.fill")
                            }
                        }
                    }
                }
                .task(id: orderedCoalitions.map(\.id)) {
                    let ids = orderedCoalitions.map(\.id)
                    if selectedCoalitionId == nil { selectedCoalitionId = ids.first }
                    else if let sel = selectedCoalitionId, !ids.contains(sel) { selectedCoalitionId = ids.first }
                }
                .animation(.snappy, value: selectedCoalitionId)
            } else {
                ContentUnavailableView("Aucune coalition", systemImage: "flag.slash")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct MyProfileView: View {
    @EnvironmentObject var profileStore: ProfileStore
    var body: some View {
        Group {
            if let loader = profileStore.loader {
                UserProfileView(loader: loader)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: profileStore.loader?.login) {
            if profileStore.loader == nil { profileStore.start() }
        }
        .animation(.snappy, value: profileStore.loader?.login)
    }
}

enum ItemsSource {
    case flat([ProfileItem])
    case grouped(GroupedItems)
    struct GroupedItems {
        let options: [Int: String]
        let itemsById: [Int: [ProfileItem]]
        var defaultId: Int {
            if let last = options.keys.sorted(by: >).first { return last }
            return options.keys.first ?? 0
        }
    }
}
