import Foundation
import SwiftUI

enum StatCardStyle { case compact, regular }

enum ItemsBuilder {
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

struct ItemDetailSheet: View {
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

struct ChipsBar<Item: Identifiable>: View where Item.ID: Equatable {
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
