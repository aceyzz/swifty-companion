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
    var todayActiveSince: Date? = nil

    @State private var tooltipIndex: Int?
    @State private var tooltipText: String = ""

    private var series: [DailyLog] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
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
        if let since = todayActiveSince {
            let d = cal.startOfDay(for: Date())
            let extra = max(0, Date().timeIntervalSince(since) / 3600)
            bucket[d, default: 0] += extra
        }
        return bucket.keys.sorted().map { DailyLog(date: $0, hours: min(bucket[$0] ?? 0, 24)) }
    }

    private var firstRow: ArraySlice<DailyLog> { series.prefix(7) }
    private var secondRow: ArraySlice<DailyLog> { series.suffix(7) }

    private func dayNumber(_ date: Date) -> String {
        Calendar.current.component(.day, from: date).description
    }

    private func opacity(for hours: Double) -> Double {
        guard hours > 0 else { return 0.15 }
        let r = min(max(hours / 24.0, 0), 1)
        return 0.25 + 0.75 * r
    }

    private func formattedHours(_ h: Double) -> String {
        let minutes = Int((h * 60).rounded())
        let hh = minutes / 60
        let mm = minutes % 60
        return String(format: "%02dh%02d", hh, mm)
    }

    private func cell(_ item: DailyLog, index: Int) -> some View {
        let op = opacity(for: item.hours)
        return ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.accentColor.opacity(op))
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
            Text(dayNumber(item.date))
                .font(.caption2.weight(.semibold))
                .minimumScaleFactor(0.7)
                .foregroundStyle(.primary.opacity(op > 0.6 ? 0.95 : 0.7))
        }
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
        .onTapGesture {
            tooltipIndex = index
            tooltipText = formattedHours(item.hours)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { if tooltipIndex == index { tooltipIndex = nil } }
        }
        .overlay(alignment: .top) {
            if tooltipIndex == index {
                Text(tooltipText)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(radius: 2, y: 1)
                    .fixedSize()
                    .offset(y: -26)
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(1)
            }
        }
        .accessibilityLabel(Text("\(dayNumber(item.date))"))
        .accessibilityValue(Text(formattedHours(item.hours)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Présence en cluster sur 14 jours")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Array(firstRow.enumerated()), id: \.offset) { idx, item in
                        cell(item, index: idx)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(Array(secondRow.enumerated()), id: \.offset) { idx, item in
                        cell(item, index: 7 + idx)
                    }
                }
            }
        }
    }
}
