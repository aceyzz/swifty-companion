import SwiftUI
import Combine
import Charts
import Foundation

struct LogTimeSection: View {
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
