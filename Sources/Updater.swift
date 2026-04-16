import Foundation
import SwiftUI
import AppKit
import OSLog

final class Updater: ObservableObject {
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
    private let expectedBundleIdentifier = "com.hiroki.daily-photos"
    private let checkInterval: TimeInterval = 24 * 60 * 60
    private let logger = Logger(subsystem: "com.hiroki.daily-photos", category: "Updater")

    private var checkTimer: Timer?
    private var hasStartedPeriodicChecks = false

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    deinit {
        checkTimer?.invalidate()
    }

    func startPeriodicChecks() {
        guard !hasStartedPeriodicChecks else { return }
        hasStartedPeriodicChecks = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await checkForUpdates()
        }

        checkTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.checkForUpdates()
            }
        }
    }

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
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                return
            }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            if Self.isNewer(remote: remoteVersion, current: currentVersion) {
                latestVersion = remoteVersion
                releaseNotes = json["body"] as? String
                downloadURL = nil

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
                clearAvailableUpdate()
            }
        } catch {
            logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    func downloadAndInstall() async {
        guard let downloadURL, !isUpdating else { return }

        isUpdating = true
        updateError = nil

        do {
            let stagingRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("DailyPhotos-update-\(UUID().uuidString)", isDirectory: true)
            let downloadDirectory = stagingRoot.appendingPathComponent("download", isDirectory: true)
            let extractDirectory = stagingRoot.appendingPathComponent("extract", isDirectory: true)

            try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: extractDirectory, withIntermediateDirectories: true)

            let downloadedZipURL = try await downloadArchive(from: downloadURL, into: downloadDirectory)
            try Self.unzipArchive(downloadedZipURL, to: extractDirectory)

            let appBundleURL = try Self.findSingleAppBundle(in: extractDirectory)
            let validatedBundleURL = try Self.validateCandidateApp(
                at: appBundleURL,
                expectedBundleIdentifier: expectedBundleIdentifier,
                currentVersion: currentVersion
            )

            try Self.verifyCodeSignature(at: validatedBundleURL)
            let scriptURL = try Self.writeInstallerScript(
                currentAppURL: Bundle.main.bundleURL,
                newAppURL: validatedBundleURL,
                stagingRoot: stagingRoot
            )
            try Self.makeExecutable(at: scriptURL)
            try Self.launchInstaller(at: scriptURL)

            isUpdating = false
            clearAvailableUpdate()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            logger.error("Update failed: \(error.localizedDescription, privacy: .public)")
            isUpdating = false
            updateError = "Update failed: \(error.localizedDescription)"
        }
    }

    static func isNewer(remote: String, current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let normalizedRemote = remoteParts + Array(repeating: 0, count: max(0, 3 - remoteParts.count))
        let normalizedCurrent = currentParts + Array(repeating: 0, count: max(0, 3 - currentParts.count))

        for index in 0..<3 {
            if normalizedRemote[index] > normalizedCurrent[index] { return true }
            if normalizedRemote[index] < normalizedCurrent[index] { return false }
        }

        return false
    }

    static func findSingleAppBundle(in directory: URL) throws -> URL {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw UpdateError.appNotFound
        }

        var appBundles: [URL] = []

        for case let url as URL in enumerator {
            if url.pathExtension == "app" {
                appBundles.append(url)
                enumerator.skipDescendants()
            }
        }

        guard appBundles.count == 1 else {
            throw appBundles.isEmpty ? UpdateError.appNotFound : UpdateError.multipleAppsFound
        }

        return appBundles[0]
    }

    static func validateCandidateApp(
        at appURL: URL,
        expectedBundleIdentifier: String,
        currentVersion: String
    ) throws -> URL {
        guard let bundle = Bundle(url: appURL) else {
            throw UpdateError.invalidBundle
        }

        guard bundle.bundleIdentifier == expectedBundleIdentifier else {
            throw UpdateError.unexpectedBundleIdentifier
        }

        let candidateVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        guard isNewer(remote: candidateVersion, current: currentVersion) else {
            throw UpdateError.nonNewerVersion
        }

        return appURL
    }

    private func clearAvailableUpdate() {
        updateAvailable = false
        latestVersion = nil
        releaseNotes = nil
        downloadURL = nil
    }

    private func downloadArchive(from remoteURL: URL, into directory: URL) async throws -> URL {
        let (temporaryURL, _) = try await URLSession.shared.download(from: remoteURL)
        let destinationURL = directory.appendingPathComponent(assetName)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    private static func unzipArchive(_ archiveURL: URL, to directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", archiveURL.path, directory.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw UpdateError.extractionFailed
        }
    }

    private static func verifyCodeSignature(at appURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", appURL.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw UpdateError.invalidCodeSignature
        }
    }

    private static func writeInstallerScript(
        currentAppURL: URL,
        newAppURL: URL,
        stagingRoot: URL
    ) throws -> URL {
        let parentDirectory = currentAppURL.deletingLastPathComponent()
        let stagedAppURL = parentDirectory.appendingPathComponent("\(currentAppURL.lastPathComponent).pending")
        let backupAppURL = parentDirectory.appendingPathComponent("\(currentAppURL.lastPathComponent).backup")
        let scriptURL = stagingRoot.appendingPathComponent("install-update.sh")

        let script = """
        #!/bin/bash
        set -euo pipefail

        APP_PATH="\(currentAppURL.path)"
        NEW_APP_PATH="\(newAppURL.path)"
        STAGED_APP_PATH="\(stagedAppURL.path)"
        BACKUP_APP_PATH="\(backupAppURL.path)"
        STAGING_ROOT="\(stagingRoot.path)"

        cleanup() {
          rm -rf "$STAGED_APP_PATH"
          rm -rf "$STAGING_ROOT"
        }

        restore_backup() {
          if [ -d "$BACKUP_APP_PATH" ] && [ ! -d "$APP_PATH" ]; then
            mv "$BACKUP_APP_PATH" "$APP_PATH"
          fi
        }

        trap 'restore_backup; cleanup; rm -f "$0"' EXIT

        while pgrep -x "DailyPhotos" > /dev/null; do
          sleep 0.5
        done

        rm -rf "$STAGED_APP_PATH"
        cp -R "$NEW_APP_PATH" "$STAGED_APP_PATH"

        rm -rf "$BACKUP_APP_PATH"
        mv "$APP_PATH" "$BACKUP_APP_PATH"
        mv "$STAGED_APP_PATH" "$APP_PATH"

        if open "$APP_PATH"; then
          rm -rf "$BACKUP_APP_PATH"
        else
          rm -rf "$APP_PATH"
          mv "$BACKUP_APP_PATH" "$APP_PATH"
          open "$APP_PATH"
          exit 1
        fi
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        return scriptURL
    }

    private static func makeExecutable(at scriptURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+x", scriptURL.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw UpdateError.failedToPrepareInstaller
        }
    }

    private static func launchInstaller(at scriptURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        try process.run()
    }
}

enum UpdateError: LocalizedError, Equatable {
    case extractionFailed
    case appNotFound
    case multipleAppsFound
    case invalidBundle
    case unexpectedBundleIdentifier
    case nonNewerVersion
    case invalidCodeSignature
    case failedToPrepareInstaller

    var errorDescription: String? {
        switch self {
        case .extractionFailed:
            return "Failed to extract the update archive."
        case .appNotFound:
            return "Could not find the app in the update archive."
        case .multipleAppsFound:
            return "The update archive contained more than one app bundle."
        case .invalidBundle:
            return "The update archive did not contain a valid app bundle."
        case .unexpectedBundleIdentifier:
            return "The downloaded app bundle did not match Daily Photos."
        case .nonNewerVersion:
            return "The downloaded version is not newer than the current app."
        case .invalidCodeSignature:
            return "The downloaded app failed code signature verification."
        case .failedToPrepareInstaller:
            return "Failed to prepare the installer."
        }
    }
}
