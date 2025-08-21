import SwiftUI
import Charts

struct UserProfileView: View {
    @ObservedObject var loader: UserProfileLoader

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
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
                                AsyncImage(url: url) { image in
                                    image.resizable().aspectRatio(contentMode: .fit)
                                } placeholder: {
                                    Color.gray.frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 16))
                                }
                                .frame(width: 120, height: 120)
                            } else {
                                Color.gray.frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 16)).redacted(reason: .placeholder)
                            }
                            ProfileTextList(texts: [p.displayName], font: .title)
                            ProfileTextList(texts: [p.login], font: .subheadline)
                            ProfileTextList(texts: [p.displayableHostOrNA], font: .subheadline)
                        }
                    }
                }

                LoadableSection(title: "Contact et campus", state: loader.basicState) {
                    LoadingListPlaceholder(lines: 2, compact: true)
                } failed: {
                    RetryRow(title: "Impossible de charger le contact") { loader.retryBasic() }
                } content: {
                    if let p = loader.profile, !p.displayableContact.isEmpty {
                        ProfileTextList(texts: p.displayableContact, font: .subheadline)
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
                    if let p = loader.profile, !p.displayableAchievements.isEmpty {
                        ProfileTextList(texts: p.displayableAchievements)
                    } else {
                        EmptyRow(text: "Aucun succès")
                    }
                }

				LoadableSection(title: "Projets en cours", state: loader.projectsState) {
                    LoadingListPlaceholder(lines: 2)
                } failed: {
                    RetryRow(title: "Impossible de charger les projets") { loader.retryProjects() }
                } content: {
                    if let p = loader.profile, !p.displayableActiveProjects.isEmpty {
                        ProfileTextList(texts: p.displayableActiveProjects)
                    } else {
                        EmptyRow(text: "Aucun projet en cours")
                    }
                }

                LoadableSection(title: "Projets terminés", state: loader.projectsState) {
                    LoadingListPlaceholder(lines: 3)
                } failed: {
                    RetryRow(title: "Impossible de charger les projets") { loader.retryProjects() }
                } content: {
                    if let p = loader.profile, !p.displayableFinishedProjects.isEmpty {
                        ProfileTextList(texts: p.displayableFinishedProjects)
                    } else {
                        EmptyRow(text: "Aucun projet terminé")
                    }
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

    private var avgHours: Double {
        guard !sorted.isEmpty else { return 0 }
        return totalHours / Double(sorted.count)
    }

    private var yMax: Double {
        let m = sorted.map(\.hours).max() ?? 0
        return max(1, ceil(m + 0.5))
    }

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
