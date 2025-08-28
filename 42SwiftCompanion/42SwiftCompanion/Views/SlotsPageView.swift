import SwiftUI
import Foundation
import UIKit

var DEBUG = true

struct SlotsPageView: View {
    @StateObject private var vm = SlotsViewModel()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
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

private struct ActionBar: View {
    let isLoading: Bool
    let lastUpdated: Date?
    let refresh: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: refresh) {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isLoading ? "Rafraîchissement…" : "Rafraîchir")
                        .font(.callout.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.systemGray6)))
            }
            .buttonStyle(.plain)

            if let updated = lastUpdated {
                Spacer()
                Text(updated.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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

private struct DeletionHUD: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Suppression…").font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(radius: 10, y: 6)
        .accessibilityLabel("Suppression en cours")
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

private struct ErrorBanner: View {
    let text: String
    var body: some View {
        VStack {
            Text(text)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.systemRed))
                        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                )
                .allowsHitTesting(false)
                .accessibilityLabel("Erreur: \(text)")
                .padding(.top, 8)
                .padding(.horizontal, 12)
            Spacer()
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
                if DEBUG { await debugPrintSlots(forDay: day) }
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
                let created = try await repo.createEvaluationSlot(begin: begin, end: end)
                if DEBUG { await debugPrintCreatedSlot(created) }
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

    private static var dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale.current
        df.dateFormat = "EEEE d MMMM yyyy"
        return df
    }()

    private static var dayShortFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale.current
        df.dateFormat = "EEE d MMM"
        return df
    }()

    private static var weekdayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale.current
        df.dateFormat = "EEEE"
        return df
    }()

    fileprivate static var hourFormatter: DateFormatter = {
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

struct DisplaySlot: Identifiable, Equatable {
    let id: String
    let slotIds: [Int]
    let begin: Date?
    let end: Date?
    let isReserved: Bool
    let scaleTeamId: Int?
    var scaleTeam: JSONValue?
}

struct EvaluationSlot: Codable, Identifiable, Equatable {
    let id: Int
    let begin_at: String?
    let end_at: String?
    let scale_team: JSONValue?
    let user: JSONValue?
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case object([String: JSONValue])
    case array([JSONValue])
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if c.decodeNil() { self = .null; return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid JSON")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        }
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

private struct Me: Decodable { let id: Int }

final class SlotsRepository {
    static let shared = SlotsRepository()
    private let api = APIClient.shared
    private var cachedUserId: Int?

    private func currentUserId() async throws -> Int {
        if let cachedUserId { return cachedUserId }
        let me = try await api.request(Endpoint(path: "/v2/me"), as: Me.self)
        cachedUserId = me.id
        return me.id
    }

    func anchorBegin(forDay day: Date, timeZone: TimeZone = .current) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let now = Date()
        let startOfDay = cal.startOfDay(for: day)
        if cal.isDate(day, inSameDayAs: now) {
            let lead = now.addingTimeInterval(30 * 60)
            let zeroSec = cal.date(bySetting: .second, value: 0, of: lead) ?? lead
            let minute = cal.component(.minute, from: zeroSec)
            let add = (15 - (minute % 15)) % 15
            return cal.date(byAdding: .minute, value: add, to: zeroSec) ?? zeroSec
        } else {
            return startOfDay
        }
    }

    func myEvaluationSlots(forDay day: Date, timeZone: TimeZone = .current) async throws -> [EvaluationSlot] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let startOfDay = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let begin = anchorBegin(forDay: day, timeZone: timeZone)
        let items = [
            URLQueryItem(name: "range[begin_at]", value: "\(DateParser.isoString(begin)),\(DateParser.isoString(end))"),
            URLQueryItem(name: "page[size]", value: "100")
        ]
        let ep = Endpoint(path: "/v2/me/slots", queryItems: items)
        return try await api.request(ep, as: [EvaluationSlot].self)
    }

    func createEvaluationSlot(begin: Date, end: Date) async throws -> [EvaluationSlot] {
        let uid = try await currentUserId()
        let payload: [String: Any] = [
            "slot": [
                "user_id": uid,
                "begin_at": DateParser.isoString(begin),
                "end_at": DateParser.isoString(end)
            ]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        let ep = Endpoint(path: "/v2/slots",
                          method: .post,
                          headers: ["Content-Type": "application/json"],
                          body: body)
        return try await api.request(ep, as: [EvaluationSlot].self)
    }

    func scaleTeam(id: Int) async throws -> JSONValue {
        try await api.request(Endpoint(path: "/v2/scale_teams/\(id)"), as: JSONValue.self)
    }

    func fetchScaleTeamsDetails(ids: [Int]) async -> [Int: JSONValue] {
        var result: [Int: JSONValue] = [:]
        await withTaskGroup(of: (Int, JSONValue?).self) { group in
            for id in ids {
                group.addTask {
                    let val = try? await self.scaleTeam(id: id)
                    if let val, DEBUG { await debugPrintScaleTeam(id: id, payload: val) }
                    return (id, val)
                }
            }
            for await (id, val) in group {
                if let v = val { result[id] = v }
            }
        }
        return result
    }

    func deleteEvaluationSlots(ids: [Int]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { try await self.deleteEvaluationSlot(id: id) }
            }
            try await group.waitForAll()
        }
    }

    func deleteEvaluationSlot(id: Int) async throws {
        let ep = Endpoint(path: "/v2/slots/\(id)", method: .delete)
        do {
            struct _NoContent: Decodable {}
            _ = try await api.request(ep, as: _NoContent.self)
        } catch let e as APIError {
            if case .decoding = e { return }
            throw e
        } catch {
            throw error
        }
    }

    func fetchSlotsDetails(ids: [Int]) async -> [Int: EvaluationSlot] {
        if ids.isEmpty { return [:] }
        var map: [Int: EvaluationSlot] = [:]
        let unique = Array(Set(ids)).sorted()
        let chunkSize = 50
        var idx = 0
        while idx < unique.count {
            let end = min(unique.count, idx + chunkSize)
            let chunk = Array(unique[idx..<end])
            let list = chunk.map(String.init).joined(separator: ",")
            let ep = Endpoint(path: "/v2/slots",
                              queryItems: [
                                URLQueryItem(name: "filter[id]", value: list),
                                URLQueryItem(name: "page[size]", value: "100")
                              ])
            if let page: [EvaluationSlot] = try? await api.request(ep, as: [EvaluationSlot].self) {
                for s in page { map[s.id] = s }
            }
            idx = end
        }
        return map
    }
}

private extension Date {
    func snappedToQuarterHour() -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: self)
        let minutes = comps.minute ?? 0
        let snapped = minutes - (minutes % 15)
        return cal.date(bySettingHour: comps.hour ?? 0, minute: snapped, second: 0, of: self) ?? self
    }
}

@MainActor
func debugPrintSlots(forDay day: Date, timeZone: TimeZone = .current) async {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = timeZone
    let repo = SlotsRepository.shared
    let startOfDay = cal.startOfDay(for: day)
    let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
    let begin = repo.anchorBegin(forDay: day, timeZone: timeZone)
    let items = [
        URLQueryItem(name: "range[begin_at]", value: "\(DateParser.isoString(begin)),\(DateParser.isoString(end))"),
        URLQueryItem(name: "page[size]", value: "100")
    ]
    let ep = Endpoint(path: "/v2/me/slots", queryItems: items)
    do {
        let raw: [JSONValue] = try await APIClient.shared.request(ep, as: [JSONValue].self)
        var output = ""
        var count = 0
        for slot in raw {
            if case .object(let dict) = slot {
                let beginAt = dict["begin_at"] ?? .null
                let endAt = dict["end_at"] ?? .null
                let id = dict["id"] ?? .null
                let scaleTeam = dict["scale_team"] ?? .null
                count += 1
                output += "##### SLOT \(count) #####\nid: \(id)\nbegin_at: \(beginAt)\nend_at: \(endAt)\nscale_team: \(scaleTeam)\n\n"
            }
        }
        print("==== /v2/me/slots KEYS ====\n\(output)===========================")
    } catch {
        print("==== /v2/me/slots RAW ERROR ====\n\(error)\n================================")
    }
}

@MainActor
func debugPrintScaleTeam(id: Int, payload: JSONValue) async {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    if let data = try? enc.encode(payload), let text = String(data: data, encoding: .utf8) {
        print("==== /v2/scale_teams/\(id) RAW ====\n\(text)\n====================================")
    }
}

@MainActor
func debugPrintCreatedSlot(_ slots: [EvaluationSlot]) async {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    if let data = try? enc.encode(slots), let text = String(data: data, encoding: .utf8) {
        print("==== CREATED /v2/slots ====\n\(text)\n===========================")
    }
}

func describeCreateFailure(begin: Date, end: Date, error: Error) -> String {
    let isoBegin = DateParser.isoString(begin)
    let isoEnd = DateParser.isoString(end)

    func readable(from body: String?) -> String? {
        guard let body, let data = body.data(using: .utf8) else { return nil }
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let s = dict["error"] as? String { return s }
            if let s = dict["message"] as? String { return s }
            if let errs = dict["errors"] as? [String: Any], !errs.isEmpty {
                let parts = errs.flatMap { key, val -> [String] in
                    if let arr = val as? [String] { return arr.map { "\(key): \($0)" } }
                    if let s = val as? String { return ["\(key): \(s)"] }
                    return []
                }
                if !parts.isEmpty { return parts.joined(separator: "\n") }
            }
        }
        return body
    }

    switch error {
    case let apiErr as APIError:
        switch apiErr {
        case .unauthorized:
            print("==== CREATE /v2/slots FAILED ====\nPayload: {\"slot\":{\"begin_at\":\"\(isoBegin)\",\"end_at\":\"\(isoEnd)\"}}\nError: UNAUTHORIZED\n==================================")
            return "Authentification requise. Réessaie après t’être reconnecté."
        case .rateLimited(let retry):
            print("==== CREATE /v2/slots FAILED ====\nPayload: {\"slot\":{\"begin_at\":\"\(isoBegin)\",\"end_at\":\"\(isoEnd)\"}}\nError: RATE_LIMITED retryAfter=\(retry ?? 0)\n==================================")
            return "Trop de requêtes. Réessaie dans quelques instants."
        case .http(let status, let body):
            let msg = readable(from: body)
            print("==== CREATE /v2/slots FAILED ====\nPayload: {\"slot\":{\"begin_at\":\"\(isoBegin)\",\"end_at\":\"\(isoEnd)\"}}\nStatus: \(status)\nBody: \(body ?? "<empty>")\n==================================")
            if let msg, !msg.isEmpty { return msg }
            if status == 422 { return "Paramètres invalides pour le slot." }
            if status == 403 { return "Tu n’as pas les droits pour créer un slot." }
            return "Erreur serveur (\(status))."
        case .decoding(let e):
            print("==== CREATE /v2/slots FAILED ====\nPayload: {\"slot\":{\"begin_at\":\"\(isoBegin)\",\"end_at\":\"\(isoEnd)\"}}\nDecoding: \(e)\n==================================")
            return "Réponse invalide du serveur."
        case .transport(let e):
            print("==== CREATE /v2/slots FAILED ====\nPayload: {\"slot\":{\"begin_at\":\"\(isoBegin)\",\"end_at\":\"\(isoEnd)\"}}\nTransport: \(e)\n==================================")
            switch e.code {
            case .notConnectedToInternet: return "Pas de connexion Internet."
            case .timedOut: return "Délai dépassé."
            default: return "Erreur réseau (\(e.code.rawValue))."
            }
        }
    default:
        let ns = error as NSError
        print("==== CREATE /v2/slots FAILED ====\nPayload: {\"slot\":{\"begin_at\":\"\(isoBegin)\",\"end_at\":\"\(isoEnd)\"}}\nError: [\(ns.domain)#\(ns.code)] \(ns.localizedDescription)\n==================================")
        return "La création du slot a échoué. \(ns.localizedDescription)"
    }
}

func describeDeleteFailure(ids: [Int], error: Error) -> String {
    switch error {
    case let apiErr as APIError:
        switch apiErr {
        case .unauthorized:
            return "Authentification requise. Réessaie après t’être reconnecté."
        case .rateLimited:
            return "Trop de requêtes. Réessaie dans quelques instants."
        case .http(let status, let body):
            if status == 403 { return "Tu n’as pas les droits pour supprimer ce slot." }
            if status == 404 { return "Ce slot n’existe plus." }
            if status == 409 { return "Ce slot ne peut pas être supprimé." }
            if let body, !body.isEmpty { return body }
            return "Erreur serveur (\(status))."
        case .decoding:
            return "Réponse invalide du serveur."
        case .transport(let e):
            switch e.code {
            case .notConnectedToInternet: return "Pas de connexion Internet."
            case .timedOut: return "Délai dépassé."
            default: return "Erreur réseau (\(e.code.rawValue))."
            }
        }
    default:
        let ns = error as NSError
        return "La suppression a échoué. \(ns.localizedDescription)"
    }
}
