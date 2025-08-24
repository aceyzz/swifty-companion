import SwiftUI
import Foundation

struct SlotsPageView: View {
    @StateObject private var vm = SlotsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Slots")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                SectionCard(title: "") {
                    HStack(spacing: 12) {
                        Button(action: {
                            withAnimation(.snappy) { vm.shiftDay(by: -1) }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 32, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .opacity(vm.canGoPrevious ? 1.0 : 0)
                        .disabled(!vm.canGoPrevious)

                        Spacer()

                        VStack(alignment: .center, spacing: 2) {
                            Text(vm.weekdayTitle).font(.headline)
                            Text(vm.dayLongTitle).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)

                        Spacer()

                        Button(action: {
                            withAnimation(.snappy) { vm.shiftDay(by: +1) }
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 32, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }

                SectionCard(title: "Mes slots") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Button {
                                Task { await vm.refresh() }
                            } label: {
                                HStack(spacing: 8) {
                                    if vm.isLoading {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text(vm.isLoading ? "Rafraîchissement…" : "Rafraîchir")
                                        .font(.callout.weight(.semibold))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.systemGray6)))
                            }
                            .buttonStyle(.plain)

                            if let updated = vm.lastUpdated {
                                Spacer()
                                Text(updated.formatted(date: .abbreviated, time: .shortened))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        switch vm.state {
                        case .idle:
                            ContentUnavailableView("Appuie sur « Rafraîchir » pour charger tes créneaux", systemImage: "calendar.badge.clock")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        case .loading:
                            LoadingListPlaceholder(lines: 3)
                        case .failed(let message):
                            RetryRow(title: message) {
                                Task { await vm.refresh(force: true) }
                            }
                        case .loaded(let groups):
                            if groups.isEmpty {
                                ContentUnavailableView("Aucun slot pour ce jour", systemImage: "calendar.badge.exclamationmark")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(groups) { g in
                                        InfoPillRow(
                                            leading: .system(g.isReserved ? "calendar.badge.checkmark" : "calendar.badge.clock"),
                                            title: vm.label(for: g),
                                            subtitle: vm.rangeText(for: g),
                                            badges: vm.badges(for: g),
                                            onTap: nil,
                                            iconTint: vm.iconTint(for: g)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear { vm.bootstrap() }
        .animation(.snappy, value: vm.stateKey)
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
final class SlotsViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded([DisplaySlot])
        case failed(String)
    }

    @Published var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @Published var showDatePicker = false
    @Published private(set) var state: State = .idle
    @Published private(set) var lastUpdated: Date?

    private var fetchTask: Task<Void, Never>?
    private let repo = SlotsRepository.shared

    var isLoading: Bool { if case .loading = state { return true } else { return false } }

    var stateKey: String {
        switch state {
        case .idle: return "idle"
        case .loading: return "loading"
        case .failed: return "failed"
        case .loaded(let arr): return "loaded_\(arr.count)"
        }
    }

    var todayStart: Date { Calendar.current.startOfDay(for: Date()) }
    var canGoPrevious: Bool { selectedDay > todayStart }
    var dateRange: ClosedRange<Date> { todayStart...Date.distantFuture }

    func bootstrap() {}

    func setToday() {
        selectedDay = todayStart
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
                await repo.debugPrintSlots(forDay: day)
                if Task.isCancelled { return }
                var groups = self.mergeContiguous(raw)
                let ids = Set(groups.compactMap(\.scaleTeamId))
                if !ids.isEmpty {
                    let details = await repo.fetchScaleTeamsDetails(ids: Array(ids))
                    for i in groups.indices {
                        if let id = groups[i].scaleTeamId, let det = details[id] {
                            groups[i].scaleTeam = det
                        }
                    }
                }
                self.state = .loaded(groups)
                self.lastUpdated = Date()
            } catch {
                if Task.isCancelled { return }
                self.state = .failed("Impossible de charger les slots")
            }
        }
    }

    private func mergeContiguous(_ slots: [EvaluationSlot]) -> [DisplaySlot] {
        let items = slots.compactMap { s -> (EvaluationSlot, Date, Date, Bool, Int?)? in
            guard let b = DateParser.iso(s.begin_at), let e = DateParser.iso(s.end_at) else { return nil }
            let stid = scaleTeamId(from: s.scale_team)
            let reserved = stid != nil
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
            } else if it.3 == currentReserved, let ce = currentEnd, abs(it.1.timeIntervalSince(ce)) < 0.5, (!it.3 || it.4 == currentScaleTeamId) {
                currentIds.append(it.0.id)
                currentEnd = it.2
            } else {
                let idStr = currentIds.map(String.init).joined(separator: "-") + (currentReserved == true ? ":r" : ":f")
                out.append(DisplaySlot(id: idStr, slotIds: currentIds, begin: currentBegin, end: currentEnd, isReserved: currentReserved ?? false, scaleTeamId: currentScaleTeamId, scaleTeam: nil))
                currentIds = [it.0.id]
                currentBegin = it.1
                currentEnd = it.2
                currentReserved = it.3
                currentScaleTeamId = it.4
            }
        }
        if !currentIds.isEmpty {
            let idStr = currentIds.map(String.init).joined(separator: "-") + (currentReserved == true ? ":r" : ":f")
            out.append(DisplaySlot(id: idStr, slotIds: currentIds, begin: currentBegin, end: currentEnd, isReserved: currentReserved ?? false, scaleTeamId: currentScaleTeamId, scaleTeam: nil))
        }
        return out
    }

    private func scaleTeamId(from value: JSONValue?) -> Int? {
        guard let v = value else { return nil }
        switch v {
        case .number(let d):
            return Int(d)
        case .string(let s):
            return Int(s)
        case .object(let o):
            if case .number(let d)? = o["id"] { return Int(d) }
            if case .string(let s)? = o["id"] { return Int(s) }
            return nil
        default:
            return nil
        }
    }

    private var dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale.current
        df.dateFormat = "EEEE d MMMM yyyy"
        return df
    }()

    private var weekdayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale.current
        df.dateFormat = "EEEE"
        return df
    }()

    private var hourFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale.current
        df.timeStyle = .short
        df.dateStyle = .none
        return df
    }()

    var weekdayTitle: String { weekdayFormatter.string(from: selectedDay).capitalized }
    var dayLongTitle: String { dayFormatter.string(from: selectedDay).capitalized }

    func rangeText(for group: DisplaySlot) -> String {
        guard let s = group.begin, let e = group.end else { return "Heure inconnue" }
        return "\(hourFormatter.string(from: s)) – \(hourFormatter.string(from: e))"
    }

    func label(for group: DisplaySlot) -> String {
        group.isReserved ? "Réservé" : "Disponible"
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

    func iconTint(for group: DisplaySlot) -> Color {
        group.isReserved ? .red : .green
    }
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

struct EvaluationSlot: Decodable, Identifiable, Equatable {
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

final class SlotsRepository {
    static let shared = SlotsRepository()
    private let api = APIClient.shared

    func myEvaluationSlots(forDay day: Date, timeZone: TimeZone = .current) async throws -> [EvaluationSlot] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let now = Date()
        let startOfDay = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let begin: Date = {
            if cal.isDate(day, inSameDayAs: now) {
                let lead = now.addingTimeInterval(30 * 60)
                let zeroSec = cal.date(bySetting: .second, value: 0, of: lead) ?? lead
                let minute = cal.component(.minute, from: zeroSec)
                let add = (15 - (minute % 15)) % 15
                return cal.date(byAdding: .minute, value: add, to: zeroSec) ?? zeroSec
            } else {
                return startOfDay
            }
        }()
        let items = [
            URLQueryItem(name: "range[begin_at]", value: "\(DateParser.isoString(begin)),\(DateParser.isoString(end))"),
            URLQueryItem(name: "page[size]", value: "100")
        ]
        let ep = Endpoint(path: "/v2/me/slots", queryItems: items)
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
                    if let val { self.debugPrintScaleTeam(id: id, payload: val) }
                    return (id, val)
                }
            }
            for await (id, val) in group {
                if let v = val { result[id] = v }
            }
        }
        return result
    }

	func debugPrintSlots(forDay day: Date, timeZone: TimeZone = .current) async {
		var cal = Calendar(identifier: .gregorian)
		cal.timeZone = timeZone
		let now = Date()
		let startOfDay = cal.startOfDay(for: day)
		let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
		let begin: Date = {
			if cal.isDate(day, inSameDayAs: now) {
				let lead = now.addingTimeInterval(30 * 60)
				let zeroSec = cal.date(bySetting: .second, value: 0, of: lead) ?? lead
				let minute = cal.component(.minute, from: zeroSec)
				let add = (15 - (minute % 15)) % 15
				return cal.date(byAdding: .minute, value: add, to: zeroSec) ?? zeroSec
			} else {
				return startOfDay
			}
		}()
		let items = [
			URLQueryItem(name: "range[begin_at]", value: "\(DateParser.isoString(begin)),\(DateParser.isoString(end))"),
			URLQueryItem(name: "page[size]", value: "100")
		]
		let ep = Endpoint(path: "/v2/me/slots", queryItems: items)
		do {
			let raw: [JSONValue] = try await api.request(ep, as: [JSONValue].self)
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

    func debugPrintScaleTeam(id: Int, payload: JSONValue) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? enc.encode(payload), let text = String(data: data, encoding: .utf8) {
            print("==== /v2/scale_teams/\(id) RAW ====\n\(text)\n====================================")
        }
    }
}
