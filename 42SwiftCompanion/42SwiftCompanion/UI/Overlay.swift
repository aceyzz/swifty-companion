import SwiftUI

struct DeletionHUD: View {
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
