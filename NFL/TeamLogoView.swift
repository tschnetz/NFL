import SwiftUI

struct TeamLogoView: View {
    let abbr: String
    var size: CGFloat = 28

    private let repo = TeamRepository.shared

    var body: some View {
        Group {
            if let url = logoURL {
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
