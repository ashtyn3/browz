import SwiftUI

/// Displays a site's favicon fetched from `<scheme>://<host>/favicon.ico`.
/// Falls back to `globe` (or `shield.fill` for private tabs) when the image
/// cannot be loaded or the URL has no parseable host.
struct FaviconView: View {
    let urlString: String
    var isPrivate: Bool = false
    /// Tint applied to the fallback SF Symbol.
    var fallbackColor: Color = .secondary

    private var faviconURL: URL? {
        guard !isPrivate,
              let url   = URL(string: urlString),
              let host  = url.host, !host.isEmpty,
              let scheme = url.scheme else { return nil }
        return URL(string: "\(scheme)://\(host)/favicon.ico")
    }

    var body: some View {
        Group {
            if isPrivate {
                fallbackIcon("shield.fill")
            } else if let faviconURL {
                AsyncImage(url: faviconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    default:
                        fallbackIcon("globe")
                    }
                }
            } else {
                fallbackIcon("globe")
            }
        }
    }

    private func fallbackIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13))
            .foregroundStyle(fallbackColor)
    }
}
