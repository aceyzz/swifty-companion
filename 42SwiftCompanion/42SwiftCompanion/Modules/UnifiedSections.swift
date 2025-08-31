import SwiftUI

struct UnifiedItemsSection: View {
    let title: String
    let state: UserProfileLoader.SectionLoadState
    let source: ItemsSource
    let emptyText: String
    let maxHeight: CGFloat?
    let onRetry: (() -> Void)?

    init(title: String,
         state: UserProfileLoader.SectionLoadState,
         source: ItemsSource,
         emptyText: String,
         maxHeight: CGFloat?,
         onRetry: (() -> Void)? = nil) {
        self.title = title
        self.state = state
        self.source = source
        self.emptyText = emptyText
        self.maxHeight = maxHeight
        self.onRetry = onRetry
    }

    @State private var presented: ProfileItem?
    @State private var selectedId: Int?

    var body: some View {
        SectionCard(title: title) {
            switch state {
            case .loading, .idle:
                LoadingListPlaceholder(lines: 2)
            case .failed:
                if let onRetry {
                    RetryRow(title: "Impossible de charger les projets", action: onRetry)
                } else {
                    EmptyRow(text: "Erreur")
                }
            case .loaded:
                switch source {
                case .flat(let items):
                    itemsView(items: items)
                case .grouped(let g):
                    if g.options.isEmpty {
                        ContentUnavailableView(emptyText, systemImage: "tray")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            let binding = Binding(
                                get: { selectedId ?? g.defaultId },
                                set: { selectedId = $0 }
                            )
                            let options = g.options.keys.sorted().compactMap { id -> KeyValue in
                                KeyValue(id: id, label: g.options[id] ?? "Cursus \(id)")
                            }
                            ChipsBar(items: options, selection: binding) { $0.label }

                            let effective = selectedId ?? g.defaultId
                            let items = g.itemsById[effective] ?? []
                            itemsView(items: items)
                        }
                        .task(id: Array(g.itemsById.keys).sorted()) {
                            let keys = Array(g.itemsById.keys).sorted()
                            if selectedId == nil { selectedId = g.defaultId }
                            else if let sel = selectedId, !keys.contains(sel) { selectedId = g.defaultId }
                        }
                        .animation(.snappy, value: selectedId)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func itemsView(items: [ProfileItem]) -> some View {
        if items.isEmpty {
            ContentUnavailableView(emptyText, systemImage: "tray")
                .frame(maxWidth: .infinity, alignment: .leading)
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
            .scrollDisabled(items.count <= 6)
            .frame(maxHeight: maxHeight)
            .scrollIndicators(.visible)
            .sheet(item: $presented) { it in
                ItemDetailSheet(item: it)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private struct KeyValue: Identifiable, Hashable {
        let id: Int
        let label: String
    }
}

struct UnifiedItemsCarouselSection: View {
    let title: String
    let state: UserProfileLoader.SectionLoadState
    let source: ItemsSource
    let emptyText: String
    let maxHeight: CGFloat?
    let onRetry: (() -> Void)?

    init(title: String,
         state: UserProfileLoader.SectionLoadState,
         source: ItemsSource,
         emptyText: String,
         maxHeight: CGFloat?,
         onRetry: (() -> Void)? = nil) {
        self.title = title
        self.state = state
        self.source = source
        self.emptyText = emptyText
        self.maxHeight = maxHeight
        self.onRetry = onRetry
    }

    @State private var presented: ProfileItem?
    @State private var selectedId: Int?

    var body: some View {
        SectionCard(title: title) {
            switch state {
            case .loading, .idle:
                LoadingListPlaceholder(lines: 1, compact: true)
            case .failed:
                if let onRetry {
                    RetryRow(title: "Impossible de charger les achievements", action: onRetry)
                } else {
                    EmptyRow(text: "Erreur")
                }
            case .loaded:
                switch source {
                case .flat(let items):
                    itemsCarousel(items: items)
                        .scrollIndicators(.hidden)
                case .grouped(let g):
                    if g.options.isEmpty {
                        ContentUnavailableView(emptyText, systemImage: "tray")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            let binding = Binding(
                                get: { selectedId ?? g.defaultId },
                                set: { selectedId = $0 }
                            )
                            let options = g.options.keys.sorted().compactMap { id -> KeyValue in
                                KeyValue(id: id, label: g.options[id] ?? "Cursus \(id)")
                            }
                            ChipsBar(items: options, selection: binding) { $0.label }
                            let effective = selectedId ?? g.defaultId
                            let items = g.itemsById[effective] ?? []
                            itemsCarousel(items: items)
                                .scrollIndicators(.hidden)
                        }
                        .task(id: Array(g.itemsById.keys).sorted()) {
                            let keys = Array(g.itemsById.keys).sorted()
                            if selectedId == nil { selectedId = g.defaultId }
                            else if let sel = selectedId, !keys.contains(sel) { selectedId = g.defaultId }
                        }
                        .animation(.snappy, value: selectedId)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func itemsCarousel(items: [ProfileItem]) -> some View {
        if items.isEmpty {
            ContentUnavailableView(emptyText, systemImage: "tray")
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { it in
                        ItemCard(item: it)
                            .onTapGesture { presented = it }
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxHeight: maxHeight)
            .scrollIndicators(.hidden)
            .sheet(item: $presented) { it in
                ItemDetailSheet(item: it)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private struct ItemCard: View {
        @EnvironmentObject var theme: Theme
        let item: ProfileItem

        var body: some View {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(theme.accentColor.opacity(0.12))
                        .frame(width: 76, height: 76)
                    Image(systemName: item.icon)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(Color(red: 0.75, green: 0.75, blue: 0.75))
                }
                .frame(maxWidth: .infinity)

                Text(item.title)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .center)

                if let s = item.subtitle, !s.isEmpty {
                    Text(s)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                if !item.badges.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(item.badges.prefix(3).enumerated()), id: \.offset) { _, b in
                            CapsuleBadge(text: b)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 150, height: 150, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 2)
            )
        }
    }

    private struct KeyValue: Identifiable, Hashable {
        let id: Int
        let label: String
    }
}
