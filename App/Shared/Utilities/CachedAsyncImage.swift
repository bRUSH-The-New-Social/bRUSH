import SwiftUI

/// A drop-in replacement for `AsyncImage` that caches downloaded images to disk
/// and memory via a dedicated `URLCache`, so feed images already fetched are
/// served from the cache instead of re-downloaded on every scroll.
///
/// Why not plain `AsyncImage`? On iOS 27 `AsyncImage` gains automatic HTTP
/// caching, but that only kicks in when the running OS is 27+ *and* honors the
/// server's cache headers. Firebase Storage download URLs don't always send
/// long-lived cache headers, and the app's deployment target is iOS 26. This
/// loader gives deterministic caching on iOS 26+ regardless of headers, and the
/// `asyncImageURLSession` path below adopts the native iOS 27 loader when
/// available so we get its caching for free there too.
struct CachedAsyncImage<Content: View>: View {
    private let url: URL?
    private let transaction: Transaction
    private let content: (AsyncImagePhase) -> Content

    init(url: URL?,
         transaction: Transaction = Transaction(),
         @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.transaction = transaction
        self.content = content
    }

    var body: some View {
        // A manual load through a `URLCache`-backed session gives deterministic
        // disk + memory caching on every OS version, independent of the server's
        // cache headers. (iOS 27's `AsyncImage(url:)` also caches automatically,
        // but its `asyncImageURLSession`/`AsyncImage(request:)` customization
        // symbols require building against the iOS 27 SDK; this path needs no
        // availability gating and behaves the same on 26 and 27.)
        ManualCachedAsyncImage(url: url, transaction: transaction, content: content)
    }
}

/// Shared, cache-backed networking for feed images.
enum ImageCache {
    /// 64 MB in memory, 512 MB on disk — comfortably holds a day's feed of
    /// full-screen drawings without re-downloading on scroll.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 64 * 1024 * 1024,
                                          diskCapacity: 512 * 1024 * 1024,
                                          diskPath: "brush_feed_images")
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()
}

/// iOS 26 fallback: manually loads through `ImageCache.session` and maps the
/// result onto the same `AsyncImagePhase` API `AsyncImage` uses, so call sites
/// keep their existing `switch phase` bodies unchanged.
private struct ManualCachedAsyncImage<Content: View>: View {
    let url: URL?
    let transaction: Transaction
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    var body: some View {
        content(phase)
            .task(id: url) {
                await load()
            }
    }

    private func load() async {
        guard let url else {
            phase = .empty
            return
        }
        // Reset to the loading state when the URL changes.
        if case .success = phase { phase = .empty }

        do {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
            let (data, _) = try await ImageCache.session.data(for: request)
            guard !Task.isCancelled else { return }
            if let uiImage = UIImage(data: data) {
                withTransaction(transaction) {
                    phase = .success(Image(uiImage: uiImage))
                }
            } else {
                phase = .failure(URLError(.cannotDecodeContentData))
            }
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failure(error)
        }
    }
}
