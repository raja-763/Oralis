import Foundation
import AppKit

/// Checks GitHub releases for a newer version of Oralis and opens the download page.
@MainActor
final class UpdateChecker: ObservableObject {

    @Published var latestVersion: String?
    @Published var isChecking = false
    @Published var updateAvailable = false
    @Published var releaseURL: URL?
    @Published var checkError: String?

    private let repoAPI = URL(string: "https://api.github.com/repos/raja-763/Oralis/releases/latest")!
    private let releasesPage = URL(string: "https://github.com/raja-763/Oralis/releases/latest")!

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func checkForUpdates() async {
        isChecking = true
        checkError = nil
        defer { isChecking = false }

        do {
            var req = URLRequest(url: repoAPI)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("Oralis/\(currentVersion)", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                checkError = "Could not reach GitHub."
                return
            }

            let release = try JSONDecoder().decode(GHRelease.self, from: data)
            let tag = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            latestVersion = tag

            // Find the first .dmg asset for direct download
            let dmgAsset = release.assets.first { $0.name.hasSuffix(".dmg") }
            releaseURL = dmgAsset.flatMap { URL(string: $0.browser_download_url) } ?? releasesPage

            updateAvailable = isNewer(tag, than: currentVersion)
        } catch {
            checkError = "Update check failed: \(error.localizedDescription)"
        }
    }

    func openDownloadPage() {
        // Open release page — user drags the new app to Applications
        NSWorkspace.shared.open(releaseURL ?? releasesPage)
    }

    // Downloads the DMG to ~/Downloads and opens it in Finder.
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0

    func downloadUpdate() async {
        guard let dmgURL = releaseURL, dmgURL.pathExtension == "dmg" else {
            openDownloadPage()
            return
        }

        isDownloading = true
        downloadProgress = 0

        let dest = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/Oralis-\(latestVersion ?? "latest").dmg")

        do {
            let (tempURL, _) = try await URLSession.shared.download(from: dmgURL)
            try? FileManager.default.moveItem(at: tempURL, to: dest)
            NSWorkspace.shared.activateFileViewerSelecting([dest])
            downloadProgress = 1
        } catch {
            // Fall back to browser
            openDownloadPage()
        }
        isDownloading = false
    }

    // Returns true if `remote` version string is greater than `local`.
    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        let count = max(r.count, l.count)
        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }
}

// MARK: - GitHub API shape

private struct GHRelease: Decodable {
    var tag_name: String
    var html_url: String
    var assets: [GHAsset]
}

private struct GHAsset: Decodable {
    var name: String
    var browser_download_url: String
}
