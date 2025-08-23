import SwiftUI

struct BootView: View {
    var body: some View {
        ZStack {
            RadialGradient(colors: [.accentColor.opacity(0.2), .clear], center: .center, startRadius: 0, endRadius: 500)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text(appName).font(.title.bold())
                    Text("Initialisation…").font(.callout).foregroundStyle(.secondary)
                }
                ProgressView().controlSize(.large)
            }
            .padding(.horizontal, 24)
        }
    }

    private var appName: String {
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !name.isEmpty { return name }
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty { return name }
        return "App"
    }
}
