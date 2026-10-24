import SwiftUI
import UIKit
import ReaderCore

public enum AppTheme {
    public static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 17/255, green: 19/255, blue: 27/255, alpha: 1) : UIColor(red: 247/255, green: 248/255, blue: 252/255, alpha: 1)
    })
    public static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 28/255, green: 32/255, blue: 48/255, alpha: 1) : .white
    })
    public static let secondarySurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 39/255, green: 45/255, blue: 64/255, alpha: 1) : UIColor(red: 238/255, green: 240/255, blue: 246/255, alpha: 1)
    })
    public static let text = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 244/255, green: 245/255, blue: 251/255, alpha: 1) : UIColor(red: 25/255, green: 29/255, blue: 43/255, alpha: 1)
    })
    public static let secondaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 182/255, green: 189/255, blue: 208/255, alpha: 1) : UIColor(red: 93/255, green: 101/255, blue: 120/255, alpha: 1)
    })
    public static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 168/255, green: 170/255, blue: 1, alpha: 1) : UIColor(red: 69/255, green: 73/255, blue: 232/255, alpha: 1)
    })
    public static let primaryButton = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 85/255, green: 89/255, blue: 231/255, alpha: 1) : UIColor(red: 69/255, green: 73/255, blue: 232/255, alpha: 1)
    })
    public static let success = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 142/255, green: 213/255, blue: 178/255, alpha: 1) : UIColor(red: 35/255, green: 104/255, blue: 78/255, alpha: 1)
    })
    public static let successSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 24/255, green: 56/255, blue: 45/255, alpha: 1) : UIColor(red: 234/255, green: 245/255, blue: 239/255, alpha: 1)
    })
    public static let warning = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 244/255, green: 201/255, blue: 128/255, alpha: 1) : UIColor(red: 133/255, green: 83/255, blue: 8/255, alpha: 1)
    })
    public static let destructive = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 1, green: 156/255, blue: 165/255, alpha: 1) : UIColor(red: 180/255, green: 35/255, blue: 50/255, alpha: 1)
    })

    public static func languageName(for code: String) -> String {
        switch code {
        case "ja-JP": return "日本語"
        case "zh-CN": return "简体中文"
        case "en-US": return "English"
        default: return Locale(identifier: "zh_CN").localizedString(forIdentifier: code) ?? code
        }
    }
}

public extension View {
    func readerCard() -> some View {
        padding(16)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.secondarySurface, lineWidth: 0.7))
    }
}

public struct LocalBadge: View {
    public init() {}
    public var body: some View {
        Label("本地优先", systemImage: "internaldrive.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.success)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(AppTheme.successSurface, in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

public struct DocumentRow: View {
    public let document: ReaderDocument
    public init(document: ReaderDocument) { self.document = document }
    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: document.kind == .pdf ? "doc.richtext" : "text.alignleft")
                .font(.system(size: 19, weight: .medium)).foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 48).background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(document.title).font(.headline).foregroundStyle(AppTheme.text).lineLimit(2)
                Text("\(document.kind.label) · \(AppTheme.languageName(for: document.language)) · \(document.modifiedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(1)
                if document.position.progress > 0 {
                    ProgressView(value: min(1, max(0, document.position.progress))).tint(AppTheme.accent)
                        .accessibilityLabel("阅读进度 \(Int(document.position.progress * 100))%")
                }
            }
            Spacer(minLength: 0)
            if document.isFavorite { Image(systemName: "star.fill").foregroundStyle(.orange).accessibilityLabel("已收藏") }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
