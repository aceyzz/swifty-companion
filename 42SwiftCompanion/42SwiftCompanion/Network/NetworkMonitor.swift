import Foundation
import Network
import SwiftUI

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isOnline: Bool = true
    @Published private(set) var isExpensive: Bool = false
    @Published private(set) var showOnlineToast: Bool = false

    private var monitor: NWPathMonitor?
    private var toastTask: Task<Void, Never>?

    func start() {
        guard monitor == nil else { return }
        let mon = NWPathMonitor()
        monitor = mon
        let queue = DispatchQueue(label: "network.monitor.queue")
        mon.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handle(path)
            }
        }
        mon.start(queue: queue)
    }

    func stop() {
        toastTask?.cancel()
        monitor?.cancel()
        monitor = nil
    }

    private func handle(_ path: NWPath) {
        isExpensive = path.isExpensive
        let nowOnline = path.status == .satisfied
        if nowOnline != isOnline {
            if nowOnline {
                isOnline = true
                showOnlineToast = true
                toastTask?.cancel()
                toastTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    self.showOnlineToast = false
                }
            } else {
                toastTask?.cancel()
                showOnlineToast = false
                isOnline = false
            }
        } else {
            isOnline = nowOnline
        }
    }
}

struct ConnectivityOverlay: View {
	let isOnline: Bool
	let showOnlineToast: Bool

	var body: some View {
		VStack {
			HStack {
				Spacer()
				if !isOnline {
					banner(
						icon: "wifi.slash",
						text: "Hors ligne",
						color: .orange,
						trailing: AnyView(ProgressView().controlSize(.small))
					)
					.transition(.move(edge: .top).combined(with: .opacity))
				} else if showOnlineToast {
					banner(
						icon: "checkmark.circle.fill",
						text: "De retour en ligne",
						color: .green,
						trailing: nil
					)
					.transition(.move(edge: .top).combined(with: .opacity))
				}
			}
			.padding(.top, 8)
			.padding(.trailing, 12)
			Spacer(minLength: 0)
		}
		.animation(.snappy, value: isOnline)
		.animation(.snappy, value: showOnlineToast)
	}

	private func banner(icon: String, text: String, color: Color, trailing: AnyView?) -> some View {
		HStack(spacing: 8) {
			Image(systemName: icon)
			Text(text).font(.callout.weight(.semibold))
			if let trailing { trailing }
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 10)
		.background(color.opacity(0.9), in: Capsule())
		.shadow(radius: 10, y: 6)
		.fixedSize()
		.accessibilityElement(children: .combine)
		.accessibilityLabel(text)
	}
}
