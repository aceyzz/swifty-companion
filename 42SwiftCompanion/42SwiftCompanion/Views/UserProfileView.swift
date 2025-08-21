import SwiftUI
import Charts

private let achievementsSectionMaxHeight: CGFloat = 320
private let finishedProjectsSectionMaxHeight: CGFloat = 360
private let projectsSectionMaxHeight: CGFloat = 420

struct UserProfileView: View {
    @ObservedObject var loader: UserProfileLoader

    var body: some View {
        ScrollView {
			LazyVStack(spacing: 24) {
				LoadableSection(title: "Identité", state: loader.basicState) {
					HStack(alignment: .top, spacing: 16) {
						VStack(alignment: .leading, spacing: 16) {
							VStack(alignment: .leading, spacing: 8) {
								LoadingListPlaceholder(lines: 2, compact: true)
							}
							VStack(alignment: .leading, spacing: 8) {
								LoadingListPlaceholder(lines: 3, compact: true)
							}
						}
						Spacer()
						VStack(spacing: 6) {
							Color.gray
								.frame(width: 120, height: 120)
								.clipShape(RoundedRectangle(cornerRadius: 16))
								.redacted(reason: .placeholder)
						}
					}
				} failed: {
					RetryRow(title: "Impossible de charger le profil") { loader.retryBasic() }
				} content: {
					if let p = loader.profile {
						HStack(alignment: .top, spacing: 16) {
							VStack(alignment: .leading, spacing: 16) {
								VStack(alignment: .leading, spacing: 8) {
									ProfileTextList(texts: [p.displayName], font: .headline)
									ProfileTextList(texts: [p.userNameWithTitle == p.login ? p.login : (p.userNameWithTitle ?? p.login)], font: .caption)
									ProfileTextList(texts: [p.displayableHostOrNA], font: .caption)
								}
								if !p.displayableContact.isEmpty {
									VStack(alignment: .leading, spacing: 8) {
										ProfileTextList(texts: p.displayableContact, font: .caption)
										if let lang = loader.profile?.campusLanguage, !lang.isEmpty {
											ProfileTextList(texts: ["Langue du campus: \(lang)"], font: .caption2)
										}
									}
								} else {
									EmptyRow(text: "Aucune information")
								}
							}
							Spacer()
							VStack(spacing: 6) {
								if let url = p.imageURL {
									RemoteImage(url: url, cornerRadius: 16)
										.frame(width: 120, height: 120)
								} else {
									Color.gray
										.frame(width: 120, height: 120)
										.clipShape(RoundedRectangle(cornerRadius: 16))
										.redacted(reason: .placeholder)
								}
							}
						}
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

                if let p = loader.profile {
                    UnifiedItemsSection(
                        title: "Succès",
                        state: loader.basicState,
                        source: .flat(ItemsBuilder.achievements(from: p)),
                        emptyText: "Aucun succès",
                        maxHeight: achievementsSectionMaxHeight
                    )

                    UnifiedItemsSection(
                        title: "Projets en cours",
                        state: loader.projectsState,
                        source: .grouped(ItemsBuilder.activeProjectsGrouped(from: p)),
                        emptyText: "Aucun projet pour ce cursus",
                        maxHeight: projectsSectionMaxHeight
                    )

                    UnifiedItemsSection(
                        title: "Projets terminés",
                        state: loader.projectsState,
                        source: .grouped(ItemsBuilder.finishedProjectsGrouped(from: p)),
                        emptyText: "Aucun projet pour ce cursus",
                        maxHeight: finishedProjectsSectionMaxHeight
                    )
                } else {
                    LoadableSection(title: "Succès", state: loader.basicState) { LoadingListPlaceholder(lines: 2, compact: true) } failed: { EmptyRow(text: "Erreur") } content: { EmptyRow(text: "Aucun succès") }
                    LoadableSection(title: "Projets en cours", state: loader.projectsState) { LoadingListPlaceholder(lines: 2) } failed: { EmptyRow(text: "Erreur") } content: { EmptyRow(text: "Aucune donnée") }
                    LoadableSection(title: "Projets terminés", state: loader.projectsState) { LoadingListPlaceholder(lines: 3) } failed: { EmptyRow(text: "Erreur") } content: { EmptyRow(text: "Aucune donnée") }
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
			Text("Présence en cluster sur les 14 derniers jours (en heures)")
				.font(.caption)
				.foregroundStyle(.secondary)
				.padding(.bottom, 8)
			Chart(sorted) { item in
				BarMark(x: .value("Date", item.date, unit: .day), y: .value("Heures", item.hours))
					.cornerRadius(8)
					.foregroundStyle(Color.accentColor)
					.opacity(item.hours > 0 ? 1 : 0.35)
				if item.hours > 0 {
					PointMark(x: .value("Date", item.date, unit: .day), y: .value("Heures", item.hours))
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
                        .fill(LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.7), location: 0.5),
                            .init(color: .clear, location: 1)
                        ], startPoint: .leading, endPoint: .trailing))
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

    @State private var presented: ProfileItem?
    @State private var selectedId: Int = 0

    var body: some View {
        SectionCard(title: title) {
            switch state {
            case .loading, .idle:
                LoadingListPlaceholder(lines: 2)
            case .failed:
                EmptyRow(text: "Erreur")
            case .loaded:
                switch source {
                case .flat(let items):
                    itemsView(items: items)
                case .grouped(let g):
                    if g.options.isEmpty {
                        EmptyRow(text: emptyText)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Cursus", selection: $selectedId) {
                                ForEach(g.options.keys.sorted(), id: \.self) { key in
                                    Text(g.options[key] ?? "Cursus \(key)").tag(key)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.accentColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            let items = g.itemsById[selectedId] ?? []
                            itemsView(items: items)
                        }
                        .onAppear { if selectedId == 0 { selectedId = g.defaultId } }
                        .animation(.snappy, value: selectedId)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func itemsView(items: [ProfileItem]) -> some View {
        if items.isEmpty {
            EmptyRow(text: emptyText)
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
            .frame(maxHeight: maxHeight)
            .scrollIndicators(.visible)
            .sheet(item: $presented) { it in
                ItemDetailSheet(item: it)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

private struct ItemDetailSheet: View {
    let item: ProfileItem
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: item.sheetIcon)
                        .frame(width: 48, height: 48)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.12)))
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
                        Text(item.sheetSubtexts[idx]).font(.subheadline)
                    }
                    if let link = item.link {
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                            Link("Ouvrir le lien", destination: link)
                                .font(.subheadline)
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
                if let r = p.retry, r > 0 { badges.append("Tentative \(r)") }
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
                if let r = p.retry, r > 0 { badges.append("Tentative \(r)") }
                return ProfileItem(
                    id: p.id,
                    icon: "checkmark.seal.fill",
                    title: p.name,
                    subtitle: nil,
                    badges: badges,
                    sheetIcon: "checkmark.seal.fill",
                    sheetTitle: p.name,
                    sheetSubtexts: badges,
                    link: nil
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
