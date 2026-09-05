import Foundation

/// Downloads the server-delivered mobile core bundle (the JS "brain") and caches the
/// last successfully fetched copy, so the SDK keeps working offline and survives a
/// temporarily unreachable server. The bundle is versioned by bridge protocol in its
/// URL path: a v1 shell only ever asks for a v1-compatible bundle.
final class MobileCoreLoader {

    /// Bridge protocol version this shell speaks. Bump only on breaking bridge changes.
    static let bridgeProtocolVersion = 1

    internal static let cachedBundleKey = "mobileCoreBundleKey"
    internal static let cachedBundleURLKey = "mobileCoreBundleURLKey"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static func bundleURL(appUrl: String) -> URL? {
        return URL(string: "\(appUrl)/js/mobile/v\(bridgeProtocolVersion)/core.umd.cjs")
    }

    /// Fetches the bundle from the server, falling back to the cached copy on any failure.
    /// Completion is called with the JS source, or `nil` when neither network nor cache
    /// can provide one (the shell then falls back to its built-in native logic).
    func load(appUrl: String, completion: @escaping (String?) -> Void) {
        guard let url = MobileCoreLoader.bundleURL(appUrl: appUrl) else {
            completion(cachedBundle(for: appUrl))
            return
        }

        // Same timeout the APIClient uses for its requests.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let data = data,
                  let source = String(data: data, encoding: .utf8),
                  !source.isEmpty else {
                Formbricks.logger?.warning("Unable to fetch mobile core bundle from \(url.absoluteString), falling back to cached copy.")
                completion(self?.cachedBundle(for: appUrl))
                return
            }

            self?.cache(bundle: source, for: appUrl)
            completion(source)
        }
        task.resume()
    }

    private func cache(bundle: String, for appUrl: String) {
        UserDefaults.standard.set(bundle, forKey: MobileCoreLoader.cachedBundleKey)
        UserDefaults.standard.set(appUrl, forKey: MobileCoreLoader.cachedBundleURLKey)
    }

    private func cachedBundle(for appUrl: String) -> String? {
        // A cached brain from a different host must not run against this one.
        guard UserDefaults.standard.string(forKey: MobileCoreLoader.cachedBundleURLKey) == appUrl else { return nil }
        return UserDefaults.standard.string(forKey: MobileCoreLoader.cachedBundleKey)
    }
}
