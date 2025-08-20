import SwiftUI
import Charts

struct UserProfileView: View {
    let login: String
    @StateObject private var loader: UserProfileLoader

    init(login: String) {
        self.login = login
        _loader = StateObject(wrappedValue: UserProfileLoader(login: login))
    }

    var body: some View {
        VStack {
            if let profile = loader.profile {
                ScrollView {
                    VStack(spacing: 24) {
                        SectionCard(title: "Identité") {
                            VStack(spacing: 8) {
                                if let url = profile.imageURL {
                                    AsyncImage(url: url) { image in
                                        image.resizable().aspectRatio(contentMode: .fit)
                                    } placeholder: {
                                        Color.gray.frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 16))
                                    }
                                    .frame(width: 120, height: 120)
                                } else {
                                    Color.gray.frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 16)).redacted(reason: .placeholder)
                                }
                                ProfileTextList(texts: [profile.displayName], font: .title)
                                ProfileTextList(texts: [profile.login], font: .subheadline)
                                ProfileTextList(texts: [profile.displayableHostOrNA], font: .subheadline)
                            }
                        }
                        SectionCard(title: "Contact et campus") {
                            if profile.displayableContact.isEmpty {
                                LoadingListPlaceholder(lines: 2, compact: true)
                            } else {
                                ProfileTextList(texts: profile.displayableContact, font: .subheadline)
                            }
                        }
                        SectionCard(title: "Statut et cursus") {
                            if profile.displayableStatus.isEmpty && profile.displayableCursus.isEmpty {
                                LoadingListPlaceholder(lines: 2, compact: true)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    ProfileTextList(texts: profile.displayableStatus, font: .subheadline)
                                    ProfileTextList(texts: profile.displayableCursus, font: .subheadline)
                                }
                            }
                        }
                        SectionCard(title: "Points") {
                            ProfileTextList(texts: ["Wallet: \(profile.wallet) | Points: \(profile.correctionPoint)"], font: .subheadline)
                        }
                        SectionCard(title: "Log time") {
                            WeeklyLogCard(logs: loader.weeklyLog)
                        }
                        SectionCard(title: "Coalitions") {
                            switch loader.coalitionsState {
                            case .loading:
                                LoadingListPlaceholder(lines: 2, compact: true)
                            case .failed:
                                RetryRow(title: "Impossible de charger les coalitions") { loader.retryCoalitions() }
                            default:
                                if profile.displayableCoalitions.isEmpty {
                                    EmptyRow(text: "Aucune coalition")
                                } else {
                                    ProfileTextList(texts: profile.displayableCoalitions)
                                }
                            }
                        }
                        SectionCard(title: "Succès") {
                            if profile.displayableAchievements.isEmpty {
                                EmptyRow(text: "Aucun succès")
                            } else {
                                ProfileTextList(texts: profile.displayableAchievements)
                            }
                        }
                        SectionCard(title: "Projets terminés") {
                            switch loader.projectsState {
                            case .loading:
                                LoadingListPlaceholder(lines: 3)
                            case .failed:
                                RetryRow(title: "Impossible de charger les projets") { loader.retryProjects() }
                            default:
                                if profile.displayableFinishedProjects.isEmpty {
                                    EmptyRow(text: "Aucun projet terminé")
                                } else {
                                    ProfileTextList(texts: profile.displayableFinishedProjects)
                                }
                            }
                        }
                        SectionCard(title: "Projets en cours") {
                            switch loader.projectsState {
                            case .loading:
                                LoadingListPlaceholder(lines: 2)
                            case .failed:
                                RetryRow(title: "Impossible de charger les projets") { loader.retryProjects() }
                            default:
                                if profile.displayableActiveProjects.isEmpty {
                                    EmptyRow(text: "Aucun projet en cours")
                                } else {
                                    ProfileTextList(texts: profile.displayableActiveProjects)
                                }
                            }
                        }
                        if !profile.displayableHost.isEmpty {
                            SectionCard(title: "Poste") {
                                ProfileTextList(texts: profile.displayableHost)
                            }
                        }
                    }
                    .padding()
                }
            } else {
                ProgressView()
            }
        }
        .onAppear { loader.start() }
        .onDisappear { loader.stop() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MyProfileView: View {
    @EnvironmentObject var authService: AuthService
    var body: some View {
        let login = authService.getCurrentUserLogin()
        Group {
            if login.isEmpty {
                ProgressView()
            } else {
                UserProfileView(login: login)
            }
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
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 4)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1.5)
        )
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

    private var totalHours: Double {
        sorted.reduce(0) { $0 + $1.hours }
    }

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

    private var hasAnyData: Bool {
        sorted.contains { $0.hours > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                StatPill(title: "Total", value: formattedHours(totalHours))
                StatPill(title: "Moyenne", value: formattedHours(avgHours))
                Spacer()
            }
            Chart(sorted) { item in
                BarMark(
                    x: .value("Date", item.date),
                    y: .value("Heures", item.hours)
                )
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
                        if let d = value.as(Date.self) {
                            Text(d, format: .dateTime.weekday(.narrow))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(v.formatted(.number.precision(.fractionLength(0))))
                        }
                    }
                }
            }
            .frame(height: 140)
            .overlay {
                if !hasAnyData {
                    VStack(spacing: 6) {
                        Image(systemName: "wave.3.right.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("Aucune présence sur les 14 derniers jours")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
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
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }
}

struct LoadingListPlaceholder: View {
    let lines: Int
    var compact: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            ForEach(0..<lines, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8)
                    .fill(.gray.opacity(0.3))
                    .frame(height: compact ? 10 : 14)
                    .redacted(reason: .placeholder)
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
            Text(title)
                .font(.subheadline)
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
