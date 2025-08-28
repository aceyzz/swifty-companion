import SwiftUI
import Foundation

final class UpcomingEvaluationsViewModel: ObservableObject {
    enum State: Equatable { case idle, loading, loaded([UpcomingEvaluation]), failed(String) }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastUpdated: Date?
    @Published var selected: UpcomingEvaluation?

    private let repo = SlotsRepository.shared

    var isLoading: Bool { if case .loading = state { return true } else { return false } }
    var stateKey: String {
        switch state {
        case .idle: return "idle"
        case .loading: return "loading"
        case .failed: return "failed"
        case .loaded(let items): return "loaded_\(items.count)"
        }
    }

    func refresh() async {
        await MainActor.run {
            self.state = .loading
            self.lastUpdated = nil
        }
        do {
            async let asCorrectedRaw = repo.upcomingScaleTeamsAsCorrected()
            async let asCorrectorRaw = repo.upcomingScaleTeamsAsCorrector()
            let corrected = try await asCorrectedRaw
            let corrector = try await asCorrectorRaw

            let allProjectIds = Set((corrected + corrector).compactMap { $0.team?.project_id })
            let names = await repo.fetchProjectNames(ids: Array(allProjectIds))

            var items: [UpcomingEvaluation] = []
            items.append(contentsOf: corrected.compactMap { Self.map(raw: $0, role: .corrected, names: names) })
            items.append(contentsOf: corrector.compactMap { Self.map(raw: $0, role: .corrector, names: names) })
            items.sort { (l, r) in
                let ld = l.beginAt ?? .distantFuture
                let rd = r.beginAt ?? .distantFuture
                return ld < rd
            }
            let loadedItems = items

            await MainActor.run {
                self.state = .loaded(loadedItems)
                self.lastUpdated = Date()
            }
        } catch {
            await MainActor.run {
                self.state = .failed("Impossible de charger les évaluations à venir")
            }
        }
    }

    private static func normalizeOneLine(_ s: String?) -> String? {
        guard let s else { return nil }
        let replaced = s.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let compact = replaced.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let trimmed = compact.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func logins(from value: JSONValue?) -> [String] {
        guard let v = value else { return [] }
        switch v {
        case .array(let arr):
            return arr.compactMap { el in
                if case .object(let o) = el {
                    if case .string(let login)? = o["login"] { return login }
                    if case .object(let inner)? = o["user"], case .string(let login)? = inner["login"] { return login }
                } else if case .string(let s) = el {
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty, t != "invisible" { return t }
                }
                return nil
            }
        case .object(let o):
            if case .string(let login)? = o["login"] { return [login] }
            if case .object(let inner)? = o["user"], case .string(let login)? = inner["login"] { return [login] }
            return []
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t.isEmpty || t == "invisible") ? [] : [t]
        default:
            return []
        }
    }

    private static func login(from value: JSONValue?) -> String? {
        logins(from: value).first
    }

    private static func map(raw: UpcomingScaleTeamRaw, role: UpcomingEvaluation.Role, names: [Int: String]) -> UpcomingEvaluation? {
        let begin = DateParser.iso(raw.begin_at)
        let durSec = raw.scale?.duration ?? 0
        let end = begin?.addingTimeInterval(TimeInterval(durSec))
        let pid = raw.team?.project_id
        let pname = pid.flatMap { names[$0] }
        let intro = normalizeOneLine(raw.scale?.introduction_md)
        let guide = normalizeOneLine(raw.scale?.guidelines_md)
        let disclaim = normalizeOneLine(raw.scale?.disclaimer_md)
        let corrected = logins(from: raw.correcteds)
        let corrector = login(from: raw.corrector)
        return UpcomingEvaluation(
            id: raw.id,
            role: role,
            beginAt: begin,
            endAt: end,
            projectName: pname,
            correctedLogins: corrected,
            correctorLogin: corrector,
            introLine: intro,
            guidelinesLine: guide,
            disclaimerLine: disclaim,
            durationMinutes: max(0, durSec / 60)
        )
    }
}

struct UpcomingEvaluationsView: View {
    @StateObject private var vm = UpcomingEvaluationsViewModel()

    var body: some View {
        SectionCard(title: "À venir") {
            VStack(alignment: .leading, spacing: 12) {
                ActionBar(
                    isLoading: vm.isLoading,
                    lastUpdated: vm.lastUpdated
                ) { Task { await vm.refresh() } }
                Group {
                    switch vm.state {
                    case .idle:
                        ContentUnavailableView(
                            "Appuie sur « Rafraîchir » pour charger tes évaluations",
                            systemImage: "calendar.badge.clock"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity.combined(with: .move(edge: .top)))

                    case .loading:
                        LoadingListPlaceholder(lines: 2)
                            .transition(.opacity)

                    case .failed(let msg):
                        RetryRow(title: msg) { Task { await vm.refresh() } }
                            .transition(.opacity.combined(with: .move(edge: .top)))

                    case .loaded(let items):
                        if items.isEmpty {
                            ContentUnavailableView("Aucune évaluation à venir.", systemImage: "calendar.badge.checkmark")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(items) { it in
                                    InfoPillRow(
                                        leading: .system("calendar"),
                                        title: it.projectName ?? "Projet inconnu",
                                        subtitle: rangeText(it),
                                        badges: badges(it),
                                        onTap: { withAnimation(.snappy) { vm.selected = it } },
                                        iconTint: it.role == .corrector ? .red : .green
                                    )
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                }
                .id(vm.stateKey)
            }
        }
        .onAppear { if case .idle = vm.state { Task { await vm.refresh() } } }
        .sheet(item: Binding(get: { vm.selected }, set: { vm.selected = $0 })) { it in
            UpcomingEvaluationDetailSheet(item: it) { withAnimation(.snappy) { vm.selected = nil } }
        }
        .animation(.snappy, value: vm.stateKey)
    }

    private func rangeText(_ it: UpcomingEvaluation) -> String {
        guard let s = it.beginAt, let e = it.endAt else { return "Heure inconnue" }
        return SlotsViewModel.dayShortFormatter.string(from: s).capitalized + " • " +
        SlotsViewModel.hourFormatter.string(from: s) + " – " + SlotsViewModel.hourFormatter.string(from: e)
    }

    private func badges(_ it: UpcomingEvaluation) -> [String] {
        var arr: [String] = []
        arr.append(it.role == .corrector ? "À donner" : "À recevoir")
        if !it.correctedLogins.isEmpty { arr.append("Évalué: \(it.correctedLogins.joined(separator: ", "))") }
        if let c = it.correctorLogin { arr.append("Correcteur: \(c)") }
        if it.durationMinutes > 0 { arr.append("\(it.durationMinutes) min") }
        return arr
    }
}

struct UpcomingEvaluationDetailSheet: View {
    let item: UpcomingEvaluation
    let dismiss: () -> Void

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    SectionCard(title: "Évaluation") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Projet") { Text(item.projectName ?? "Inconnu").font(.callout.weight(.semibold)) }
                            if let s = item.beginAt, let e = item.endAt {
                                LabeledContent("Début") { Text(s.formatted(date: .abbreviated, time: .shortened)).font(.callout) }
                                LabeledContent("Fin") { Text(e.formatted(date: .omitted, time: .shortened)).font(.callout) }
                            }
                            if item.durationMinutes > 0 {
                                LabeledContent("Durée") { Text("\(item.durationMinutes) min").font(.callout) }
                            }
                            LabeledContent("Rôle") { Text(item.role == .corrector ? "Corriger" : "Être corrigé").font(.callout) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    SectionCard(title: "Participants") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let c = item.correctorLogin {
                                LabeledContent("Correcteur") { Text(c).font(.callout) }
                            }
                            if !item.correctedLogins.isEmpty {
                                LabeledContent("Évalués") { Text(item.correctedLogins.joined(separator: ", ")).font(.callout) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    SectionCard(title: "Consignes") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let s = item.introLine { LabeledContent("Introduction") { Text(s).font(.callout) } }
                            if let s = item.guidelinesLine { LabeledContent("Guidelines") { Text(s).font(.callout) } }
                            if let s = item.disclaimerLine { LabeledContent("Disclaimer") { Text(s).font(.callout) } }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle("Détails")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}
