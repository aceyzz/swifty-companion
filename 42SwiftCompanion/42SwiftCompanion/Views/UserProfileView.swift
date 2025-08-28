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
                        UnifiedItemsSection(
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

                        LoadableSection(title: "En cours", state: loader.projectsState) {
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

private struct IdentityCard: View {
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
					// if profile.displayableHostOrNA != "Non disponible" {
					// 	if let url = URL(string: "https://meta.intra.42.fr/clusters") {
					// 		Link(profile.displayableHostOrNA, destination: url)
					// 			.font(.footnote)
					// 			.foregroundStyle(.secondary)
					// 	} else {
					// 		Text(profile.displayableHostOrNA)
					// 			.font(.footnote)
					// 			.foregroundStyle(.secondary)
					// 	}
					// } else {
					// 	Text(profile.displayableHostOrNA)
					// 		.font(.footnote)
					// 		.foregroundStyle(.secondary)
					// }
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

private struct IdentitySkeleton: View {
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

private struct Avatar: View {
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

private struct FilterChip: View {
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


private struct ChipsBar<Item: Identifiable>: View where Item.ID: Equatable {
    let items: [Item]
    @Binding var selection: Item.ID
    let label: (Item) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    let isSel = item.id == selection
                    FilterChip(text: label(item), isSelected: isSel) {
                        withAnimation(.snappy) { selection = item.id }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private enum StatCardStyle { case compact, regular }

private struct StatCard: View {
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

private struct StatusCursusCard: View {
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

private struct CoalitionsCard: View {
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

private struct LogTimeSection: View {
	@ObservedObject var loader: UserProfileLoader
	@State private var didAutoRetry = false
	@State private var lastRefreshMarker: Date?
	@State private var isRefreshing = false

	var body: some View {
		LoadableSection(title: "Log time", state: loader.logState) {
			LoadingListPlaceholder(lines: 1, compact: true)
		} failed: {
			RetryRow(title: "Impossible de charger le log time") { loader.retryLog() }
		} content: {
			VStack(alignment: .leading, spacing: 0) {
				WeeklyLogCard(logs: loader.weeklyLog)
				HStack {
					Spacer()
					Button {
						isRefreshing = true
						loader.retryLog()
						DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
							isRefreshing = false
						}
					} label: {
						Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath")
							.rotationEffect(isRefreshing ? .degrees(360) : .degrees(0))
							.animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
					}
					.buttonStyle(.plain)
				}
			}
		}
		.task {
			if loader.logState == .idle { loader.retryLog() }
		}
		.onChange(of: loader.lastUpdated) { newValue, _ in
			guard let stamp = newValue, stamp != lastRefreshMarker else { return }
			lastRefreshMarker = stamp
			if loader.logState != .loading { loader.retryLog() }
		}
		.onChange(of: loader.logState) { newValue, _ in
			if newValue == .loading { didAutoRetry = false }
			if newValue == .failed && !didAutoRetry {
				didAutoRetry = true
				loader.retryLog()
			}
		}
	}
}

struct WeeklyLogCard: View {
    @EnvironmentObject var theme: Theme
    let logs: [DailyLog]

    private var series: [DailyLog] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -13, to: today) ?? today

        var bucket: [Date: Double] = [:]
        for i in 0..<14 {
            if let d = cal.date(byAdding: .day, value: i, to: start) {
                bucket[cal.startOfDay(for: d)] = 0
            }
        }
        for l in logs {
            let d = cal.startOfDay(for: l.date)
            if bucket[d] != nil { bucket[d, default: 0] += l.hours }
        }
        return bucket.keys.sorted().map { DailyLog(date: $0, hours: bucket[$0] ?? 0) }
    }

    private var seriesKey: String {
        series.map { "\($0.date.timeIntervalSince1970)-\($0.hours)" }.joined(separator: "|")
    }

    private var totalHours: Double { series.reduce(0) { $0 + $1.hours } }
    private var avgHours: Double { series.isEmpty ? 0 : totalHours / Double(series.count) }
    private var yMax: Double { max(1, ceil((series.map(\.hours).max() ?? 0) + 0.5)) }

    private var xDomain: ClosedRange<Date> {
        let cal = Calendar.current
        guard let first = series.first?.date, let last = series.last?.date else {
            let s = cal.startOfDay(for: Date())
            let e = cal.date(byAdding: .day, value: 1, to: s) ?? s
            return s...e
        }
        let s = cal.startOfDay(for: first)
        let e = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: last)) ?? last
        return s...e
    }

    private var hasAnyData: Bool { series.contains { $0.hours > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Présence en cluster sur les 14 derniers jours (en heures)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            Chart(series) { item in
                BarMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Heures", item.hours)
                )
                .cornerRadius(8)
                .foregroundStyle(theme.accentColor)
                .opacity(item.hours > 0 ? 1 : 0.35)
            }
            .id(seriesKey)
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
    @EnvironmentObject var theme: Theme
    let title: String
    let value: String
    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.accentColor.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.accentColor.opacity(0.2), lineWidth: 1)
        )
    }
}

struct LoadingListPlaceholder: View {
    let lines: Int
    var compact: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            ForEach(0..<lines, id: \.self) { _ in
                ShimmerBar(height: compact ? 10 : 14)
            }
        }
    }
}

private struct ShimmerBar: View {
    let height: CGFloat
    @State private var animate = false
    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.25))
                .overlay {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .white.opacity(0.7), location: 0.5),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * 0.45)
                        .offset(x: animate ? geo.size.width : -geo.size.width)
                        .blendMode(.plusLighter)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(height: height)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
    }
}

private struct ProfileItem: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String?
    let badges: [String]
    let sheetIcon: String
    let sheetTitle: String
    let sheetSubtexts: [String]
    let link: URL?
}

private enum ItemsSource {
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

private struct UnifiedItemsSection: View {
    let title: String
    let state: UserProfileLoader.SectionLoadState
    let source: ItemsSource
    let emptyText: String
    let maxHeight: CGFloat?
    let onRetry: (() -> Void)?

    init(title: String,
         state: UserProfileLoader.SectionLoadState,
         source: ItemsSource,
         emptyText: String,
         maxHeight: CGFloat?,
         onRetry: (() -> Void)? = nil) {
        self.title = title
        self.state = state
        self.source = source
        self.emptyText = emptyText
        self.maxHeight = maxHeight
        self.onRetry = onRetry
    }

    @State private var presented: ProfileItem?
    @State private var selectedId: Int?

    var body: some View {
        SectionCard(title: title) {
            switch state {
            case .loading, .idle:
                LoadingListPlaceholder(lines: 2)
            case .failed:
                if let onRetry {
                    RetryRow(title: "Impossible de charger les projets", action: onRetry)
                } else {
                    EmptyRow(text: "Erreur")
                }
            case .loaded:
                switch source {
                case .flat(let items):
                    itemsView(items: items)
                case .grouped(let g):
                    if g.options.isEmpty {
                        ContentUnavailableView(emptyText, systemImage: "tray")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            let binding = Binding(
                                get: { selectedId ?? g.defaultId },
                                set: { selectedId = $0 }
                            )
                            let options = g.options.keys.sorted().compactMap { id -> KeyValue in
                                KeyValue(id: id, label: g.options[id] ?? "Cursus \(id)")
                            }
                            ChipsBar(items: options, selection: binding) { $0.label }

                            let effective = selectedId ?? g.defaultId
                            let items = g.itemsById[effective] ?? []
                            itemsView(items: items)
                        }
                        .task(id: Array(g.itemsById.keys).sorted()) {
                            let keys = Array(g.itemsById.keys).sorted()
                            if selectedId == nil { selectedId = g.defaultId }
                            else if let sel = selectedId, !keys.contains(sel) { selectedId = g.defaultId }
                        }
                        .animation(.snappy, value: selectedId)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func itemsView(items: [ProfileItem]) -> some View {
        if items.isEmpty {
            ContentUnavailableView(emptyText, systemImage: "tray")
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { it in
                        InfoPillRow(
                            leading: .system(it.icon),
                            title: it.title,
                            subtitle: it.subtitle,
                            badges: it.badges,
                            onTap: { presented = it }
                        )
                    }
                }
                .padding(.trailing, 2)
            }
            .scrollDisabled(items.count <= 6)
            .frame(maxHeight: maxHeight)
            .scrollIndicators(.visible)
            .sheet(item: $presented) { it in
                ItemDetailSheet(item: it)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private struct KeyValue: Identifiable, Hashable {
        let id: Int
        let label: String
    }
}


private struct ItemDetailSheet: View {
    @EnvironmentObject var theme: Theme
    let item: ProfileItem
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: item.sheetIcon)
                        .frame(width: 48, height: 48)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.accentColor.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.sheetTitle).font(.title3).bold()
                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                        }
                        if !item.badges.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(Array(item.badges.enumerated()), id: \.offset) { _, text in
                                    CapsuleBadge(text: text)
                                }
                            }
                        }
                    }
                    Spacer()
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(item.sheetSubtexts.indices, id: \.self) { idx in
                        let text = item.sheetSubtexts[idx]
                        if text.starts(with: "https://"), let url = URL(string: text) {
                            HStack(spacing: 8) {
                                Image(systemName: "link")
                                Link("Ouvrir le lien", destination: url)
                                    .font(.subheadline)
                            }
                        } else {
                            Text(text).font(.subheadline)
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

private enum ItemsBuilder {
    static func achievements(from profile: UserProfile) -> [ProfileItem] {
        let grouped = Dictionary(grouping: profile.achievements, by: { $0.name })
        let groups = grouped.values.map { arr -> ProfileItem in
            let first = arr.first
            let name = first?.name ?? ""
            let symbol = AchievementIconProvider.symbol(for: name, description: first?.description)
            let count = arr.count
            let subtitle = "×\(count)"
            let details = arr.sorted { ($0.count ?? 1) > ($1.count ?? 1) }.map { "\($0.name): \($0.description)" }
            return ProfileItem(
                id: name,
                icon: symbol,
                title: name,
                subtitle: subtitle,
                badges: [],
                sheetIcon: symbol,
                sheetTitle: name,
                sheetSubtexts: details,
                link: nil
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return groups
    }

    static func activeProjectsGrouped(from profile: UserProfile) -> ItemsSource.GroupedItems {
        let mapById = Dictionary(grouping: profile.activeProjects.compactMap { ap -> (Int, UserProfile.ActiveProject)? in
            guard let cid = ap.cursusId else { return nil }
            return (cid, ap)
        }, by: { $0.0 })
        let options = optionsMap(profile: profile, presentIds: Set(mapById.keys))
        let itemsById = Dictionary(uniqueKeysWithValues: mapById.map { (key, tupleArray) in
            let ordered = tupleArray
                .map { $0.1 }
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            let items = ordered.map { p in
                let subtitle = [p.status, p.teamStatus].compactMap { $0 }.joined(separator: " • ")
                var badges: [String] = []
                if let d = p.createdAt { badges.append(UserProfile.Formatters.shortDate.string(from: d)) }
                if let r = p.retry, r > 0 { badges.append("Retry \(r)") }
                var sheetLines: [String] = badges
                if let url = p.repoURL { sheetLines.append(url.absoluteString) }
                return ProfileItem(
                    id: p.id,
                    icon: "hammer.fill",
                    title: p.name,
                    subtitle: subtitle,
                    badges: badges,
                    sheetIcon: "hammer.fill",
                    sheetTitle: p.name,
                    sheetSubtexts: sheetLines,
                    link: p.repoURL
                )
            }
            return (key, items)
        })
        return .init(options: options, itemsById: itemsById)
    }

    static func finishedProjectsGrouped(from profile: UserProfile) -> ItemsSource.GroupedItems {
        let mapById = Dictionary(grouping: profile.finishedProjects.compactMap { fp -> (Int, UserProfile.Project)? in
            guard let cid = fp.cursusId else { return nil }
            return (cid, fp)
        }, by: { $0.0 })
        let options = optionsMap(profile: profile, presentIds: Set(mapById.keys))
        let itemsById = Dictionary(uniqueKeysWithValues: mapById.map { (key, tupleArray) in
            let ordered = tupleArray
                .map { $0.1 }
                .sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }
            let items = ordered.map { p in
                var badges: [String] = []
                if let d = p.closedAt { badges.append(UserProfile.Formatters.shortDate.string(from: d)) }
                if let v = p.validated { badges.append(v ? "Validé" : "Non validé") }
                if let m = p.finalMark { badges.append("Note \(m)") }
                if let r = p.retry, r > 0 { badges.append("Retry \(r)") }
                var sheetLines = badges
                if let url = p.projectURL { sheetLines.append(url.absoluteString) }
                return ProfileItem(
                    id: p.id,
                    icon: "checkmark.seal.fill",
                    title: p.name,
                    subtitle: nil,
                    badges: badges,
                    sheetIcon: "checkmark.seal.fill",
                    sheetTitle: p.name,
                    sheetSubtexts: sheetLines,
                    link: p.projectURL
                )
            }
            return (key, items)
        })
        return .init(options: options, itemsById: itemsById)
    }

    private static func optionsMap(profile: UserProfile, presentIds: Set<Int>) -> [Int: String] {
        let filtered = profile.cursus.filter { presentIds.contains($0.id) }
        var pairs: [(Int, String, Date?)] = filtered.map { c in
            let title = c.name ?? "Cursus \(c.id)"
            let order = c.endAt ?? c.beginAt
            return (c.id, title, order)
        }
        pairs.sort { (l, r) in
            let ld = l.2 ?? .distantPast
            let rd = r.2 ?? .distantPast
            return ld > rd
        }
        var map: [Int: String] = [:]
        for (id, title, _) in pairs { map[id] = title }
        return map
    }
}
