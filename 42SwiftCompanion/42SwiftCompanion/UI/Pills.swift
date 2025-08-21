import SwiftUI

struct InfoPillRow: View {
    enum Leading {
        case url(URL)
        case system(String)
    }

    let leading: Leading?
    let title: String
    let subtitle: String?
    let badges: [String]
    let onTap: (() -> Void)?
    let iconTint: Color?

    init(leading: Leading? = nil, title: String, subtitle: String? = nil, badges: [String] = [], onTap: (() -> Void)? = nil, iconTint: Color? = nil) {
        self.leading = leading
        self.title = title
        self.subtitle = subtitle
        self.badges = badges
        self.onTap = onTap
        self.iconTint = iconTint
    }

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
        .contentShape(Rectangle())
    }

    private var content: some View {
        HStack(spacing: 12) {
            leadingView
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                if !badges.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(badges.enumerated()), id: \.offset) { _, text in
                            CapsuleBadge(text: text)
                        }
                    }
                }
            }
            Spacer()
            if onTap != nil {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.accentColor.opacity(0.18), lineWidth: 1))
    }

    @ViewBuilder
    private var leadingView: some View {
        switch leading {
        case .url(let u):
            RemoteImage(url: u, cornerRadius: 8)
                .frame(width: 34, height: 34)
        case .system(let name):
            Image(systemName: name)
                .foregroundStyle(iconTint ?? .primary)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill((iconTint ?? Color.accentColor).opacity(0.12)))
        case .none:
            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2)).frame(width: 34, height: 34)
        }
    }
}

struct CapsuleBadge: View {
    let text: String
    var tint: Color? = nil
    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(tint ?? .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill((tint ?? Color.accentColor).opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke((tint ?? Color.accentColor).opacity(0.2), lineWidth: 1))
    }
}
