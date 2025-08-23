import SwiftUI
import OSLog

struct SearchView: View {
    @EnvironmentObject var profileStore: ProfileStore
    @StateObject private var vm = UserSearchViewModel()
    @FocusState private var searchFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Recherche")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                ClassicSearchField(
                    text: $vm.searchText,
                    isLoading: vm.isSearching,
                    onSubmit: {
                        searchFocused = false
                        vm.submit()
                    },
                    focus: $searchFocused
                )

                LazyVStack(spacing: 16) {
                    SectionCard(title: "Résultats") {
                        switch vm.state {
                        case .idle:
                            ContentUnavailableView("Recherche un étudiant", systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        case .loading:
                            LoadingListPlaceholder(lines: 4)
                        case .failed(let message):
                            RetryRow(title: message) {
                                searchFocused = false
                                vm.submit(force: true)
                            }
                        case .loaded(let items):
                            if items.isEmpty {
                                ContentUnavailableView("Aucun résultat", systemImage: "person.fill.questionmark")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(items) { u in
                                        InfoPillRow(
                                            leading: u.imageURL.map(InfoPillRow.Leading.url),
                                            title: u.displayName?.isEmpty == false ? (u.displayName ?? u.login) : u.login,
                                            subtitle: u.displayName?.isEmpty == false ? u.login : nil,
                                            onTap: {
                                                searchFocused = false
                                                vm.select(user: u)
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }

                    if let updated = vm.lastUpdated {
                        Text("Actualisé: \(updated.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.immediately)
        .background(KeyboardDismissArea { searchFocused = false })
        .onAppear { vm.bootstrap(currentCampusId: profileStore.loader?.profile?.campusId) }
        .onChange(of: profileStore.loader?.profile?.campusId) { _, newId in
            vm.bootstrap(currentCampusId: newId)
        }
        .fullScreenCover(item: $vm.presentedLogin) { presented in
            UserProfileScreen(login: presented.id)
        }
        .animation(.snappy, value: vm.stateKey)
        .sensoryFeedback(.success, trigger: vm.feedbackSuccessTick)
        .sensoryFeedback(.error, trigger: vm.feedbackErrorTick)
    }
}

struct ClassicSearchField: View {
    @Binding var text: String
    let isLoading: Bool
    let onSubmit: () -> Void
    var focus: FocusState<Bool>.Binding
    private var canSubmit: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && !isLoading }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Rechercher un login…", text: $text)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .keyboardType(.asciiCapable)
                .submitLabel(.search)
                .focused(focus)
                .onSubmit { if canSubmit { onSubmit() } }
            if !text.isEmpty {
                Button {
                    text = ""
                    focus.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .disabled(isLoading)
            }
            Button {
                onSubmit()
            } label: {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Rechercher").font(.callout.weight(.semibold))
                }
            }
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color("AccentColor").opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color("AccentColor").opacity(0.18), lineWidth: 1))
    }
}

@MainActor
final class UserSearchViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded([UserSummary])
        case failed(String)
    }

    @Published var searchText: String = ""
    @Published private(set) var state: State = .idle
    @Published private(set) var lastUpdated: Date?
    @Published var presentedLogin: PresentedLogin?
    @Published var feedbackSuccessTick = false
    @Published var feedbackErrorTick = false

    var isSearching: Bool {
        if case .loading = state { return true }
        return false
    }

    var stateKey: String {
        switch state {
        case .idle: return "idle"
        case .loading: return "loading"
        case .failed: return "failed"
        case .loaded(let arr): return "loaded_\(arr.count)"
        }
    }

    struct PresentedLogin: Identifiable, Equatable { let id: String }

    private let repo = SearchRepository.shared
    private var campusId: Int?
    private var searchTask: Task<Void, Never>?
    private var lastOpen: (login: String, at: Date)?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "search")

    func bootstrap(currentCampusId: Int?) {
        campusId = currentCampusId
    }

    func submit(force: Bool = false) {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { state = .idle; return }
        guard q.count >= 2 else { state = .failed("Saisis au moins 2 caractères"); feedbackErrorTick.toggle(); return }
        if !force, case .loading = state { return }
        state = .loading
        lastUpdated = nil
        searchTask?.cancel()
        let query = q
        let campus = campusId
        logger.log("Searching users for query '\(query, privacy: .private(mask: .hash))'")
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                var results = try await repo.searchUsers(query: query, limit: 15)
                if let campus {
                    results.sort { l, r in
                        let lp = (l.primaryCampusId == campus) ? 0 : 1
                        let rp = (r.primaryCampusId == campus) ? 0 : 1
                        if lp != rp { return lp < rp }
                        return l.login.localizedCaseInsensitiveCompare(r.login) == .orderedAscending
                    }
                }
                if Task.isCancelled { return }
                self.state = .loaded(results)
                self.lastUpdated = Date()
                self.logger.log("Search succeeded with \(results.count) result(s)")
                self.feedbackSuccessTick.toggle()
            } catch {
                if Task.isCancelled { return }
                self.state = .failed("Erreur lors de la recherche")
                self.logger.error("Search failed: \(String(describing: error), privacy: .public)")
                self.feedbackErrorTick.toggle()
            }
        }
    }

    func select(user: UserSummary) {
        let now = Date()
        if let last = lastOpen, last.login == user.login, now.timeIntervalSince(last.at) < 0.8 { return }
        lastOpen = (user.login, now)
        presentedLogin = .init(id: user.login)
    }
}

struct UserProfileScreen: View {
    let login: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var loader: UserProfileLoader

    init(login: String) {
        self.login = login
        _loader = StateObject(wrappedValue: UserProfileLoader(login: login, autoRefresh: true))
    }

    var body: some View {
        NavigationStack {
            UserProfileView(loader: loader)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                    }
                    ToolbarItem(placement: .principal) {
                        Text(login).font(.headline)
                    }
                }
        }
        .onAppear { loader.start() }
        .onDisappear { loader.stop() }
    }
}

private struct KeyboardDismissArea: View {
    let action: () -> Void
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { action() }
    }
}
