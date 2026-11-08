import Cocoa

/// Downloads team logos from MLB's public static asset host and caches them
/// in memory and on disk. Logos are the clubs' trademarks, so none ship in
/// the app bundle; the first launch fetches them as they are needed.
final class TeamLogoStore {

    static let shared = TeamLogoStore()

    /// Posted on the main queue when a logo finishes downloading.
    /// `userInfo["teamId"]` carries the team's MLB Stats API id.
    static let didLoadLogo = Notification.Name("TeamLogoStore.didLoadLogo")

    private var memory: [Int: NSImage] = [:]
    private var inFlight: Set<Int> = []
    private var failedAt: [Int: Date] = [:]
    private let retryInterval: TimeInterval = 10 * 60
    private let session = URLSession(configuration: .ephemeral)
    private let directory: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundleId = Bundle.main.bundleIdentifier ?? "OnDeckApp"
        directory = caches.appendingPathComponent(bundleId, isDirectory: true)
            .appendingPathComponent("TeamLogos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Returns the cached logo, or nil while it downloads. Call from the main
    /// queue; `didLoadLogo` fires once the image is available. A failed
    /// download is not retried for `retryInterval`.
    func image(for teamId: Int) -> NSImage? {
        if let img = memory[teamId] { return img }
        if let img = NSImage(contentsOf: fileURL(for: teamId)) {
            memory[teamId] = img
            return img
        }
        download(teamId)
        return nil
    }

    private func fileURL(for teamId: Int) -> URL {
        directory.appendingPathComponent("\(teamId).svg")
    }

    private func download(_ teamId: Int) {
        if let failed = failedAt[teamId], Date().timeIntervalSince(failed) < retryInterval { return }
        guard !inFlight.contains(teamId),
              let url = URL(string: "https://www.mlbstatic.com/team-logos/\(teamId).svg")
        else { return }
        inFlight.insert(teamId)

        session.dataTask(with: url) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(teamId)
                guard let data,
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let img = NSImage(data: data)
                else {
                    self.failedAt[teamId] = Date()
                    return
                }
                self.failedAt[teamId] = nil
                try? data.write(to: self.fileURL(for: teamId), options: .atomic)
                self.memory[teamId] = img
                NotificationCenter.default.post(name: Self.didLoadLogo, object: self,
                                                userInfo: ["teamId": teamId])
            }
        }.resume()
    }
}
