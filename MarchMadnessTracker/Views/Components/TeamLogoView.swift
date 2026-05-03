import SwiftUI

struct TeamLogoView: View {
    let url: URL?
    var size: CGFloat = 20

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                case .failure:
                    fallbackIcon
                case .empty:
                    ProgressView()
                        .frame(width: size, height: size)
                        .scaleEffect(0.5)
                @unknown default:
                    fallbackIcon
                }
            }
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        // Generic circle-person so it doesn't look basketball-specific
        Image(systemName: "person.circle.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size * 0.85, height: size * 0.85)
            .foregroundStyle(.secondary.opacity(0.6))
            .frame(width: size, height: size)
    }
}
