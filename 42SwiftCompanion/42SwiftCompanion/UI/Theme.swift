import SwiftUI

final class Theme: ObservableObject {
    static let shared = Theme()
    @Published private(set) var accentColor: Color = Color("AccentColor")

    private init() {}

    func apply(hex: String?) {
        if let hex, let c = Color.fromHex(hex) {
            accentColor = c
        } else {
            accentColor = Color("AccentColor")
        }
    }

    func reset() {
        accentColor = Color("AccentColor")
    }
}

extension Color {
    static func fromHex(_ hex: String) -> Color? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8 else { return nil }
        var rgba: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&rgba) else { return nil }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((rgba & 0xFF0000) >> 16) / 255.0
            g = Double((rgba & 0x00FF00) >> 8) / 255.0
            b = Double(rgba & 0x0000FF) / 255.0
            a = 1.0
        } else {
            r = Double((rgba & 0xFF000000) >> 24) / 255.0
            g = Double((rgba & 0x00FF0000) >> 16) / 255.0
            b = Double((rgba & 0x0000FF00) >> 8) / 255.0
            a = Double(rgba & 0x000000FF) / 255.0
        }
        return Color(red: r, green: g, blue: b, opacity: a)
    }
}
