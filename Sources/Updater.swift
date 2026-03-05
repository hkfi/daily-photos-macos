import Foundation
import SwiftUI

/// Checks GitHub Releases for newer versions and handles self-updating.
class Updater: ObservableObject {
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var releaseNotes: String?
    @Published var downloadURL: URL?
    @Published var isChecking = false
    @Published var isUpdating = false
    @Published var updateError: String?

    private let owner = "hkfi"
    private let repo = "daily-photos-macos"
    private let assetName = "DailyPhotos.app.zip"

    /// Interval between automatic update checks (24 hours).
    private let checkInterval: TimeInterval = 24 * 60 * 60
    private var checkTimer: Timer?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: - Lifecycle

    func startPeriodicChecks() {
        // Check once on launch (with a short delay so the UI is ready)
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            await checkForUpdates()
        }

        // Then check every 24 hours
        checkTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.checkForUpdates() }
        }
    }

    // MARK: - Check

    @MainActor
    func checkForUpdates() async {
        guard !isChecking, !isUpdating else { return }
        isChecking = true
        updateError = nil

        defer { isChecking = false }

        do {
            let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return // Silently ignore — no release yet or rate-limited
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                return
            }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            if isNewer(remote: remoteVersion, current: currentVersion) {
                latestVersion = remoteVersion
                releaseNotes = json["body"] as? String

                // Find the zip asset
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String,
                           name == assetName,
                           let urlString = asset["browser_download_url"] as? String,
                           let assetURL = URL(string: urlString) {
                            downloadURL = assetURL
                            break
                        }
                    }
                }

                updateAvailable = downloadURL != nil
            } else {
                updateAvailable = false
                latestVersion = nil
            }
        } catch {
            print("Update check failed: \(error)")
        }
    }

    // MARK: - Download & Install

    @MainActor
    func downloadAndInstall() async {
        guard let downloadURL, !isUpdating else { return }
        isUpdating = true
        updateError = nil

        do {
            // 1. Download the zip
            let (tempZipURL, _) = try await URLSession.shared.download(from: downloadURL)

            // 2. Create a temp directory for extraction
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("DailyPhotos-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // 3. Unzip
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-xk", tempZipURL.path, tempDir.path]
            try unzip.run()
            unzip.waitUntilExit()

            guard unzip.terminationStatus == 0 else {
                throw UpdateError.extractionFailed
            }

            // 4. Find the .app in the extracted contents
            let contents = try FileManager.default.contentsOfDirectory(
                at: tempDir, includingPropertiesForKeys: nil
            )
            guard let newAppURL = contents.first(where: { $0.pathExtension == "app" }) else {
                throw UpdateError.appNotFound
            }

            // 5. Determine current app location
            let currentAppURL = Bundle.main.bundleURL

            // 6. Write a relaunch script and execute it
            let script = """
            #!/bin/bash
            # Wait for the app to quit
            while pgrep -x "DailyPhotos" > /dev/null; do
                sleep 0.5
            done
            # Replace the old app
            rm -rf "\(currentAppURL.path)"
            cp -R "\(newAppURL.path)" "\(currentAppURL.path)"
            # Clean up temp files
            rm -rf "\(tempDir.path)"
            rm -rf "\(tempZipURL.path)"
            # Relaunch
            open "\(currentAppURL.path)"
            # Self-delete
            rm -f "$0"
            """

            let scriptURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("dailyphotos-update.sh")
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)

            // Make executable
            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["+x", scriptURL.path]
            try chmod.run()
            chmod.waitUntilExit()

            // Launch the script in background
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
            launcher.arguments = [scriptURL.path]
            try launcher.run()

            // 7. Quit the current app
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }

        } catch {
            isUpdating = false
            updateError = "Update failed: \(error.localizedDescription)"
            print("Update failed: \(error)")
        }
    }

    // MARK: - Version Comparison

    /// Returns true if `remote` is newer than `current` using semver comparison.
    private func isNewer(remote: String, current: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }

        // Pad to 3 components
        let rp = r + Array(repeating: 0, count: max(0, 3 - r.count))
        let cp = c + Array(repeating: 0, count: max(0, 3 - c.count))

        for i in 0..<3 {
            if rp[i] > cp[i] { return true }
            if rp[i] < cp[i] { return false }
        }
        return false
    }
}

enum UpdateError: LocalizedError {
    case extractionFailed
    case appNotFound

    var errorDescription: String? {
        switch self {
        case .extractionFailed: return "Failed to extract the update archive."
        case .appNotFound: return "Could not find the app in the update archive."
        }
    }
}
