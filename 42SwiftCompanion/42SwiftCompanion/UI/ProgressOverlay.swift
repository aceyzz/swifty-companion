import SwiftUI

struct BlockingProgressOverlay: View {
    let title: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(radius: 8)
        }
        .transition(.opacity)
    }
}
