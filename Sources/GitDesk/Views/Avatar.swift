import AppKit
import CryptoKit
import SwiftUI

/// Fetches and caches author avatars from Gravatar (or GitHub for GitHub noreply addresses).
/// Misses are cached too, so each address is only looked up once per launch.
@MainActor
final class AvatarCache {
    static let shared = AvatarCache()

    private var images: [String: NSImage?] = [:]
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 64 << 20)
        return URLSession(configuration: config)
    }()

    func image(for email: String) async -> NSImage? {
        let key = email.trimmed.lowercased()
        guard !key.isEmpty else { return nil }
        if let cached = images[key] { return cached }
        if let task = inFlight[key] { return await task.value }

        let url = Self.url(for: key)
        let session = session
        let task = Task<NSImage?, Never> {
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return NSImage(data: data)
        }
        inFlight[key] = task
        let image = await task.value
        images[key] = image
        inFlight[key] = nil
        return image
    }

    /// GitHub noreply addresses ("12345+name@users.noreply.github.com") map to that GitHub account's avatar;
    /// everything else goes to Gravatar, which returns 404 (`d=404`) when there's no avatar so we can fall back to initials.
    private static func url(for email: String) -> URL {
        if email.hasSuffix("@users.noreply.github.com") {
            let local = email.split(separator: "@").first.map(String.init) ?? ""
            if let id = local.split(separator: "+").first, Int(id) != nil {
                return URL(string: "https://avatars.githubusercontent.com/u/\(id)?s=80")!
            }
            return URL(string: "https://github.com/\(local).png?size=80")!
        }
        let hash = SHA256.hash(data: Data(email.utf8)).map { String(format: "%02x", $0) }.joined()
        return URL(string: "https://gravatar.com/avatar/\(hash)?s=80&d=404")!
    }
}

/// Round author avatar with an initials fallback.
struct AvatarView: View {
    let name: String
    let email: String
    let size: CGFloat

    @AppStorage("useGravatar") private var useGravatar = true
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
            } else {
                Circle().fill(fallbackColour)
                Text(initials)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .help("\(name) <\(email)>")
        .task(id: "\(email)|\(useGravatar)") {
            image = useGravatar ? await AvatarCache.shared.image(for: email) : nil
        }
    }

    private var initials: String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        let letters = parts.count > 1 ? [parts.first!, parts.last!] : Array(parts.prefix(1))
        return letters.compactMap(\.first).map { String($0).uppercased() }.joined()
    }

    /// Stable colour per author, so the same person always gets the same fallback.
    private var fallbackColour: Color {
        let sum = email.lowercased().unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Theme.lane(sum).opacity(0.85)
    }
}
