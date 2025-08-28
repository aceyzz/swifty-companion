import SwiftUI
import Foundation
import UIKit

struct SlotsPageView: View {
    @StateObject private var vm = SlotsViewModel()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Mes créneaux")
                            .font(.largeTitle.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)

                        UpcomingEvaluationsView()

                        Header(selectedDay: $vm.selectedDay,
                               weekdayTitle: vm.weekdayTitle,
                               dayLongTitle: vm.dayLongTitle,
                               canGoPrevious: vm.canGoPrevious,
                               goPrev: { vm.shiftDay(by: -1) },
                               goNext: { vm.shiftDay(by: +1) })

                        SectionCard(title: "Mes slots") {
                            VStack(alignment: .leading, spacing: 12) {
                                ActionBar(isLoading: vm.isLoading,
                                          lastUpdated: vm.lastUpdated,
                                          refresh: { Task { await vm.refresh() } })

                                Content(state: vm.state,
                                        label: vm.label(for:),
                                        rangeText: vm.rangeText(for:),
                                        badges: vm.badges(for:),
                                        tint: vm.iconTint(for:),
                                        isDeleting: vm.isDeleting(_ :),
                                        onDelete: { vm.askDelete($0) })
                            }
                        }
                    }
                    .padding()
                }

                CreateFab { vm.openCreateSheet() }
            }
            .onAppear { vm.bootstrap() }
            .onAppear { if case .idle = vm.state { Task { await vm.refresh() }}}
            .onChange(of: vm.selectedDay) { Task { await vm.refresh() }}
            .animation(.snappy, value: vm.stateKey)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $vm.showCreateSheet) {
                CreateSlotSheet(vm: vm)
            }
            .alert(item: $vm.alertItem) { item in
                Alert(title: Text(item.title), message: Text(item.message), dismissButton: .default(Text("OK")))
            }
            .confirmationDialog(
                "Supprimer ce slot ?",
                isPresented: Binding(get: { vm.pendingDeletion != nil },
                                    set: { if !$0 { vm.pendingDeletion = nil } }),
                presenting: vm.pendingDeletion
            ) { group in
                Button("Supprimer", role: .destructive) { Task { await vm.confirmDelete(group) } }
                Button("Annuler", role: .cancel) {}
            } message: { group in
                Text(vm.deleteSummary(for: group))
            }
            .overlay(alignment: .top) {
                if vm.isDeleting {
                    DeletionHUD()
                        .padding(.top, 8)
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .animation(.snappy, value: vm.isDeleting)
        }
    }
}

@MainActor
final class SlotsViewModel: ObservableObject {
    enum State: Equatable { case idle, loading, loaded([DisplaySlot]), failed(String) }

    struct AlertItem: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let message: String
    }

    @Published var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @Published private(set) var state: State = .idle
    @Published private(set) var lastUpdated: Date?

    @Published var showCreateSheet = false
    @Published var form = CreateSlotForm()
    @Published private(set) var isCreating = false
    @Published var alertItem: AlertItem?
    @Published var createErrorMessage: String?
    @Published var errorBannerText: String?

    @Published var pendingDeletion: DisplaySlot?
    @Published private(set) var isDeleting = false
    @Published private(set) var deletingSlotIds: Set<Int> = []

    private var fetchTask: Task<Void, Never>?
    private let repo = SlotsRepository.shared

    var isLoading: Bool { if case .loading = state { return true } else { return false } }
    var stateKey: String { switch state { case .idle: return "idle"; case .loading: return "loading"; case .failed: return "failed"; case .loaded(let arr): return "loaded_\(arr.count)" } }

    var todayStart: Date { Calendar.current.startOfDay(for: Date()) }
    var canGoPrevious: Bool { selectedDay > todayStart }
    var dateRange: ClosedRange<Date> { todayStart...Date.distantFuture }
    var createDateRange: ClosedRange<Date> {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let start = todayStart
        let end = cal.date(byAdding: .day, value: 14, to: start) ?? start
        return start...end
    }

    func askDelete(_ group: DisplaySlot) {
        pendingDeletion = group
    }

    func deleteSummary(for group: DisplaySlot) -> String {
        if let s = group.begin, let e = group.end {
            let d = Self.dayShortFormatter.string(from: s).capitalized
            let rs = Self.hourFormatter.string(from: s)
            let re = Self.hourFormatter.string(from: e)
            let seg = group.slotIds.count > 1 ? "ces \(group.slotIds.count) segments" : "ce segment"
            return "Supprimer \(seg) le \(d) de \(rs) à \(re) ?"
        } else {
            return "Supprimer ce slot ?"
        }
    }

    func confirmDelete(_ group: DisplaySlot) async {
        if isDeleting { return }
        isDeleting = true
        deletingSlotIds.formUnion(group.slotIds)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        defer {
            isDeleting = false
            pendingDeletion = nil
            deletingSlotIds.subtract(group.slotIds)
        }
        do {
            try await repo.deleteEvaluationSlots(ids: group.slotIds)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: 150_000_000)
            await refresh(force: true)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            let message = describeDeleteFailure(ids: group.slotIds, error: error)
            alertItem = .init(title: "Suppression impossible", message: message)
        }
    }

    func isDeleting(_ group: DisplaySlot) -> Bool {
        for id in group.slotIds {
            if deletingSlotIds.contains(id) { return true }
        }
        return false
    }

    func bootstrap() {}

    private func hasOverlap(existing: [EvaluationSlot], begin: Date, end: Date) -> Bool {
        for s in existing {
            guard let sb = DateParser.iso(s.begin_at), let se = DateParser.iso(s.end_at) else { continue }
            if begin < se && end > sb { return true }
        }
        return false
    }

    func shiftDay(by delta: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        if delta < 0, !canGoPrevious { return }
        let next = cal.date(byAdding: .day, value: delta, to: selectedDay) ?? selectedDay
        selectedDay = max(next, todayStart)
    }

    func refresh(force: Bool = false) async {
        if !force, case .loading = state { return }
        state = .loading
        lastUpdated = nil
        fetchTask?.cancel()
        let day = selectedDay
        fetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await repo.myEvaluationSlots(forDay: day)
                if Task.isCancelled { return }

                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = .current
                let nextDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: day))!
                let filtered = raw.filter { s in
                    guard let b = DateParser.iso(s.begin_at) else { return false }
                    return b < nextDay
                }

                let ids = filtered.map(\.id)
                let detailsMap = await repo.fetchSlotsDetails(ids: ids)

                var groups = Self.mergeContiguous(filtered, details: detailsMap)
                let scaleTeamIds = Set(groups.compactMap(\.scaleTeamId))
                if !scaleTeamIds.isEmpty {
                    let details = await repo.fetchScaleTeamsDetails(ids: Array(scaleTeamIds))
                    for i in groups.indices {
                        if let id = groups[i].scaleTeamId, let det = details[id] {
                            groups[i].scaleTeam = det
                        }
                    }
                }
                state = .loaded(groups)
                lastUpdated = Date()
            } catch {
                if Task.isCancelled { return }
                state = .failed("Impossible de charger les slots")
            }
        }
    }

    func label(for group: DisplaySlot) -> String { group.isReserved ? "Réservé" : "Disponible" }

    func rangeText(for group: DisplaySlot) -> String {
        guard let s = group.begin, let e = group.end else { return "Heure inconnue" }
        return Self.dayShortFormatter.string(from: s).capitalized + " • " +
            Self.hourFormatter.string(from: s) + " – " + Self.hourFormatter.string(from: e)
    }

    func badges(for group: DisplaySlot) -> [String] {
        var b: [String] = []
        b.append(group.isReserved ? "Réservé" : "Libre")
        if let id = group.scaleTeamId, group.isReserved { b.append("Équipe #\(id)") }
        if group.slotIds.count > 1 { b.append("\(group.slotIds.count) segments") }
        if let s = group.begin, let e = group.end {
            let secs = Int(e.timeIntervalSince(s))
            if secs > 0 {
                let h = secs / 3600
                let m = (secs % 3600) / 60
                if h > 0 && m > 0 { b.append("\(h) h \(m) min") }
                else if h > 0 { b.append("\(h) h") }
                else { b.append("\(m) min") }
            }
        }
        return b
    }

    func iconTint(for group: DisplaySlot) -> Color { group.isReserved ? .red : .green }

    var minSegments: Int { 1 }

    var createStartRange: ClosedRange<Date> {
        let minStart = repo.anchorBegin(forDay: form.day)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: form.day)) ?? form.day
        let latestStart = endOfDay.addingTimeInterval(-900)
        return minStart...latestStart
    }

    var createMaxSegments: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: form.day)) ?? form.day
        let seconds = max(0, endOfDay.timeIntervalSince(form.start))
        return max(0, Int(floor(seconds / 900)))
    }

    func openCreateSheet() {
        createErrorMessage = nil
        errorBannerText = nil
        form.day = selectedDay
        let anchor = repo.anchorBegin(forDay: form.day)
        form.start = max(anchor, Date()).snappedToQuarterHour()
        form.segments = min(max(minSegments, 1), max(minSegments, createMaxSegments))
        showCreateSheet = true
    }

    func dismissCreateSheet() {
        showCreateSheet = false
        createErrorMessage = nil
        errorBannerText = nil
    }

    func confirmCreate() async {
        if isCreating { return }
        if createMaxSegments < minSegments { presentCreateError("Plage invalide pour créer un slot (min. 15 min)."); return }
        isCreating = true
        createErrorMessage = nil
        errorBannerText = nil
        defer { isCreating = false }
        do {
            let existing = try await repo.myEvaluationSlots(forDay: form.day)
            let begin = form.start.snappedToQuarterHour()
            let end = form.end(forSegments: form.segments).snappedToQuarterHour()
            if hasOverlap(existing: existing, begin: begin, end: end) {
                presentCreateError("Ce créneau chevauche un autre slot.")
                return
            }
            do {
                _ = try await repo.createEvaluationSlot(begin: begin, end: end)
                await MainActor.run { self.showCreateSheet = false }
                try? await Task.sleep(nanoseconds: 150_000_000)
                await refresh(force: true)
            } catch {
                presentCreateError(describeCreateFailure(begin: begin, end: end, error: error))
            }
        } catch {
            presentCreateError("Impossible de charger les slots existants.")
        }
    }

    func syncFormAfterDayChange() {
        let minStart = repo.anchorBegin(forDay: form.day)
        form.start = max(minStart, form.start).snappedToQuarterHour()
        if createMaxSegments < form.segments { form.segments = max(minSegments, createMaxSegments) }
    }

    func syncFormAfterStartChange() {
        let snapped = form.start.snappedToQuarterHour()
        if snapped != form.start { form.start = snapped }
        if createMaxSegments < form.segments { form.segments = max(minSegments, createMaxSegments) }
    }

    func syncFormAfterSegmentsChange() {
        if createMaxSegments < form.segments { form.segments = max(minSegments, createMaxSegments) }
    }

    var weekdayTitle: String { Self.weekdayFormatter.string(from: selectedDay).capitalized }
    var dayLongTitle: String { Self.dayFormatter.string(from: selectedDay).capitalized }

    private static func hasScaleTeam(_ value: JSONValue?) -> Bool {
        guard let v = value else { return false }
        switch v {
        case .null: return false
        case .string(let s): return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return true
        }
    }

    private static func mergeContiguous(_ slots: [EvaluationSlot], details: [Int: EvaluationSlot]) -> [DisplaySlot] {
        let items = slots.compactMap { s -> (EvaluationSlot, Date, Date, Bool, Int?)? in
            guard let b = DateParser.iso(s.begin_at), let e = DateParser.iso(s.end_at) else { return nil }
            let resolved = details[s.id]
            let scaleValue = resolved?.scale_team ?? s.scale_team
            let reserved = hasScaleTeam(scaleValue)
            let stid = scaleTeamId(from: scaleValue)
            return (s, b, e, reserved, stid)
        }
        .sorted { l, r in
            if l.1 == r.1 { return l.2 < r.2 }
            return l.1 < r.1
        }

        var out: [DisplaySlot] = []
        var currentIds: [Int] = []
        var currentBegin: Date?
        var currentEnd: Date?
        var currentReserved: Bool?
        var currentScaleTeamId: Int?

        for it in items {
            if currentIds.isEmpty {
                currentIds = [it.0.id]
                currentBegin = it.1
                currentEnd = it.2
                currentReserved = it.3
                currentScaleTeamId = it.4
            } else if it.3 == currentReserved,
                      let ce = currentEnd,
                      abs(it.1.timeIntervalSince(ce)) < 0.5,
                      (!it.3 || it.4 == currentScaleTeamId) {
                currentIds.append(it.0.id)
                currentEnd = it.2
            } else {
                let idStr = currentIds.map(String.init).joined(separator: "-") + (currentReserved == true ? ":r" : ":f")
                out.append(DisplaySlot(id: idStr,
                                       slotIds: currentIds,
                                       begin: currentBegin,
                                       end: currentEnd,
                                       isReserved: currentReserved ?? false,
                                       scaleTeamId: currentScaleTeamId,
                                       scaleTeam: nil))
                currentIds = [it.0.id]
                currentBegin = it.1
                currentEnd = it.2
                currentReserved = it.3
                currentScaleTeamId = it.4
            }
        }

        if !currentIds.isEmpty {
            let idStr = currentIds.map(String.init).joined(separator: "-") + (currentReserved == true ? ":r" : ":f")
            out.append(DisplaySlot(id: idStr,
                                   slotIds: currentIds,
                                   begin: currentBegin,
                                   end: currentEnd,
                                   isReserved: currentReserved ?? false,
                                   scaleTeamId: currentScaleTeamId,
                                   scaleTeam: nil))
        }
        return out
    }

    private static func scaleTeamId(from value: JSONValue?) -> Int? {
        guard let v = value else { return nil }
        switch v {
        case .number(let d): return Int(d)
        case .string(let s): return Int(s)
        case .object(let o):
            if case .number(let d)? = o["id"] { return Int(d) }
            if case .string(let s)? = o["id"] { return Int(s) }
            return nil
        default: return nil
        }
    }

    static var dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale.current
        df.dateFormat = "EEEE d MMMM yyyy"
        return df
    }()

    static var dayShortFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale.current
        df.dateFormat = "EEE d MMM"
        return df
    }()

    static var weekdayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale.current
        df.dateFormat = "EEEE"
        return df
    }()

    static var hourFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale.current
        df.timeStyle = .short
        df.dateStyle = .none
        return df
    }()

    private func presentCreateError(_ message: String) {
        createErrorMessage = message
        errorBannerText = message
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self.errorBannerText == message { self.errorBannerText = nil }
        }
    }
}

private struct Header: View {
    @Binding var selectedDay: Date
    let weekdayTitle: String
    let dayLongTitle: String
    let canGoPrevious: Bool
    let goPrev: () -> Void
    let goNext: () -> Void

    var body: some View {
        SectionCard(title: "") {
            HStack(spacing: 12) {
                Button(action: { withAnimation(.snappy) { goPrev() }}) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 32, weight: .bold))
                }
                .buttonStyle(.plain)
                .opacity(canGoPrevious ? 1 : 0)
                .disabled(!canGoPrevious)

                Spacer()

                VStack(alignment: .center, spacing: 2) {
                    Text(weekdayTitle).font(.headline)
                    Text(dayLongTitle).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Spacer()

                Button(action: { withAnimation(.snappy) { goNext() }}) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 32, weight: .bold))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        }
    }
}

private struct Content: View {
    let state: SlotsViewModel.State
    let label: (DisplaySlot) -> String
    let rangeText: (DisplaySlot) -> String
    let badges: (DisplaySlot) -> [String]
    let tint: (DisplaySlot) -> Color
    let isDeleting: (DisplaySlot) -> Bool
    let onDelete: (DisplaySlot) -> Void

    var body: some View {
        switch state {
        case .idle:
            ContentUnavailableView("Appuie sur « Rafraîchir » pour charger tes créneaux", systemImage: "calendar.badge.clock")
                .frame(maxWidth: .infinity, alignment: .leading)
        case .loading:
            LoadingListPlaceholder(lines: 3)
        case .failed(let message):
            RetryRow(title: message) {}
        case .loaded(let groups):
            if groups.isEmpty {
                ContentUnavailableView("Aucun slot pour ce jour", systemImage: "calendar.badge.exclamationmark")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(groups) { g in
                        ZStack(alignment: .topTrailing) {
                            InfoPillRow(
                                leading: .system(g.isReserved ? "calendar.badge.checkmark" : "calendar.badge.clock"),
                                title: label(g),
                                subtitle: rangeText(g),
                                badges: badges(g),
                                onTap: nil,
                                iconTint: tint(g)
                            )
                            .opacity(isDeleting(g) ? 0.55 : 1)

                            Group {
                                if isDeleting(g) {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Button { onDelete(g) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 18, weight: .bold))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Supprimer ce slot")
                                }
                            }
                            .padding(6)
                        }
                    }
                }
            }
        }
    }
}

private struct CreateFab: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .padding(18)
                .background(Circle().fill(Color(.systemGreen)))
                .foregroundStyle(.white)
                .shadow(radius: 8, y: 3)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .accessibilityLabel("Poser un slot")
    }
}

struct CreateSlotSheet: View {
    @ObservedObject var vm: SlotsViewModel
    @Environment(\.verticalSizeClass) private var vClass
    @State private var selectedDetent: PresentationDetent = .medium

    private var adaptiveDetents: Set<PresentationDetent> {
        if vClass == .compact { return [.large] }
        return [.medium, .large]
    }

    var body: some View {
        GeometryReader { _ in
            ScrollView {
                VStack(spacing: 16) {
                    SectionCard(title: "Pose un slot") {
                        VStack(spacing: 14) {
                            HStack {
                                Text("Jour")
                                    .font(.body)
                                Spacer()
                                DatePicker("", selection: $vm.form.day, in: vm.createDateRange, displayedComponents: [.date])
                                    .labelsHidden()
                                    .datePickerStyle(.compact)
                                    .disabled(vm.isCreating)
                            }

                            HStack {
                                Text("Début")
                                    .font(.body)
                                Spacer()
                                DatePicker("", selection: $vm.form.start, in: vm.createStartRange, displayedComponents: [.hourAndMinute])
                                    .labelsHidden()
                                    .datePickerStyle(.compact)
                                    .disabled(vm.isCreating || vm.createMaxSegments < vm.minSegments)
                            }

                            HStack {
                                Text("Durée")
                                Spacer()
                                Text(vm.form.durationText).font(.callout.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }

                            Stepper(value: $vm.form.segments, in: vm.minSegments...vm.createMaxSegments) {
                                Text("Segments: \(vm.form.segments)")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .disabled(vm.isCreating || vm.createMaxSegments < vm.minSegments)
                        }
                    }

                    SectionCard(title: "Résumé") {
                        VStack(spacing: 6) {
                            HStack {
                                Text("Début")
                                Spacer()
                                Text(vm.form.startText).font(.callout.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            HStack {
                                Text("Fin")
                                Spacer()
                                Text(vm.form.endText).font(.callout.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button(role: .cancel) { vm.dismissCreateSheet() } label: {
                            Text("Annuler").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task { await vm.confirmCreate() }
                        } label: {
                            if vm.isCreating {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("Confirmer").frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isCreating || vm.createMaxSegments < vm.minSegments)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.visible)
            .padding(.top, 20)
        }
        .onAppear { selectedDetent = (vClass == .compact ? .large : .medium) }
        .onChange(of: vClass) { selectedDetent = (vClass == .compact ? .large : .medium) }
        .onChange(of: vm.form.day) { vm.syncFormAfterDayChange() }
        .onChange(of: vm.form.start) { vm.syncFormAfterStartChange() }
        .onChange(of: vm.form.segments) { vm.syncFormAfterSegmentsChange() }
        .presentationDragIndicator(.visible)
        .presentationDetents(adaptiveDetents, selection: $selectedDetent)
        .presentationContentInteraction(.scrolls)
        .interactiveDismissDisabled(vm.isCreating)
        .overlay(alignment: .top) {
            if let text = vm.errorBannerText {
                ErrorBanner(text: text)
                    .padding(.top, 8)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.snappy, value: vm.errorBannerText)
    }
}

@MainActor
struct CreateSlotForm: Equatable {
    var day: Date = Calendar.current.startOfDay(for: Date())
    var start: Date = Date()
    var segments: Int = 2
    var startText: String { SlotsViewModel.hourFormatter.string(from: start) }
    var endText: String { SlotsViewModel.hourFormatter.string(from: end(forSegments: segments)) }
    var durationText: String {
        let mins = segments * 15
        let h = mins / 60
        let m = mins % 60
        if h > 0 && m > 0 { return "\(h) h \(m) min" }
        if h > 0 { return "\(h) h" }
        return "\(m) min"
    }
    func end(forSegments segments: Int) -> Date { start.addingTimeInterval(TimeInterval(segments) * 900) }
}
