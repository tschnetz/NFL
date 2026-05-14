import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum TeamLogoStyle {
    case logo
    case helmet

    var assetNamespace: String {
        switch self {
        case .logo: "Logos"
        case .helmet: "Helmets"
        }
    }
}

struct TeamLogoView: View {
    let abbr: String
    var size: CGFloat = 28
    var style: TeamLogoStyle = .logo

    private let repo = TeamRepository.shared

    var body: some View {
        Group {
            if hasBundledImage {
                Image("\(style.assetNamespace)/\(abbr)").resizable().scaledToFit()
            } else if style == .logo, let url = logoURL {
                AsyncImage(url: url, transaction: Transaction(animation: .default)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .empty, .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .task { await repo.ensureLoaded() }
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var hasBundledImage: Bool {
        #if canImport(UIKit)
        return UIImage(named: "\(style.assetNamespace)/\(abbr)") != nil
        #else
        return false
        #endif
    }

    private var accessibilityLabel: String {
        let descriptor = style == .helmet ? "helmet" : "logo"
        if let name = repo.team(abbr: abbr)?.displayName { return "\(name) \(descriptor)" }
        return "\(abbr) \(descriptor)"
    }

    private var logoURL: URL? {
        guard let raw = repo.team(abbr: abbr)?.logoUrl else { return nil }
        return URL(string: raw)
    }

    private var placeholder: some View {
        Text(abbr.prefix(3))
            .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(.background.tertiary, in: .circle)
    }
}
