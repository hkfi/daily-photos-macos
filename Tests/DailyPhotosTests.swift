import XCTest
@testable import DailyPhotos

final class DailyPhotosTests: XCTestCase {
    func testIsNewerHandlesEquivalentAndExpandedVersions() {
        XCTAssertFalse(Updater.isNewer(remote: "1.2.3", current: "1.2.3"))
        XCTAssertFalse(Updater.isNewer(remote: "1.2", current: "1.2.0"))
        XCTAssertTrue(Updater.isNewer(remote: "1.2.1", current: "1.2"))
        XCTAssertTrue(Updater.isNewer(remote: "2.0", current: "1.9.9"))
        XCTAssertFalse(Updater.isNewer(remote: "1.1.9", current: "1.2.0"))
    }

    func testValidateCandidateAppRejectsWrongBundleIdentifier() throws {
        let directory = try makeTemporaryDirectory()
        let appURL = try makeAppBundle(
            in: directory,
            name: "DailyPhotos",
            bundleIdentifier: "com.example.other",
            version: "9.9.9"
        )

        XCTAssertThrowsError(
            try Updater.validateCandidateApp(
                at: appURL,
                expectedBundleIdentifier: "com.hiroki.daily-photos",
                currentVersion: "0.1.0"
            )
        ) { error in
            XCTAssertEqual(error as? UpdateError, .unexpectedBundleIdentifier)
        }
    }

    func testValidateCandidateAppRejectsNonNewerVersion() throws {
        let directory = try makeTemporaryDirectory()
        let appURL = try makeAppBundle(
            in: directory,
            name: "DailyPhotos",
            bundleIdentifier: "com.hiroki.daily-photos",
            version: "0.1.0"
        )

        XCTAssertThrowsError(
            try Updater.validateCandidateApp(
                at: appURL,
                expectedBundleIdentifier: "com.hiroki.daily-photos",
                currentVersion: "0.1.0"
            )
        ) { error in
            XCTAssertEqual(error as? UpdateError, .nonNewerVersion)
        }
    }

    func testFindSingleAppBundleRejectsMissingAppBundle() throws {
        let directory = try makeTemporaryDirectory()
        XCTAssertThrowsError(try Updater.findSingleAppBundle(in: directory)) { error in
            XCTAssertEqual(error as? UpdateError, .appNotFound)
        }
    }

    func testDailyNoteUpdaterAddsPhotosSectionWhenMissing() {
        let original = "# Daily Note\n\nHello"
        let updated = DailyNoteUpdater.upsertPhotoSection(
            in: original,
            embeds: ["![[Photos/2026-04-15/IMG_0001.jpg]]"]
        )

        XCTAssertTrue(updated.contains("## Photos"))
        XCTAssertTrue(updated.contains("![[Photos/2026-04-15/IMG_0001.jpg]]"))
        XCTAssertTrue(updated.contains("Hello"))
    }

    func testDailyNoteUpdaterAppendsOnlyMissingEmbeds() {
        let original = """
        # Daily Note

        ## Photos

        ![[Photos/2026-04-15/IMG_0001.jpg]]
        """

        let updated = DailyNoteUpdater.upsertPhotoSection(
            in: original,
            embeds: [
                "![[Photos/2026-04-15/IMG_0001.jpg]]",
                "![[Photos/2026-04-15/IMG_0002.jpg]]"
            ]
        )

        XCTAssertEqual(updated.components(separatedBy: "![[Photos/2026-04-15/IMG_0001.jpg]]").count - 1, 1)
        XCTAssertEqual(updated.components(separatedBy: "![[Photos/2026-04-15/IMG_0002.jpg]]").count - 1, 1)
    }

    func testDailyNoteUpdaterPreservesSurroundingContent() {
        let original = """
        # Daily Note

        Intro

        ## Photos

        ![[Photos/2026-04-15/IMG_0001.jpg]]

        ## Tasks

        - Finish report
        """

        let updated = DailyNoteUpdater.upsertPhotoSection(
            in: original,
            embeds: ["![[Photos/2026-04-15/IMG_0002.jpg]]"]
        )

        XCTAssertTrue(updated.contains("## Tasks"))
        XCTAssertTrue(updated.contains("- Finish report"))
        XCTAssertEqual(updated.components(separatedBy: "## Tasks").count - 1, 1)
    }

    func testDailyNoteUpdaterUsesCustomPathTemplateAndHeading() throws {
        let vaultURL = try makeTemporaryDirectory()
        let noteURL = vaultURL
            .appendingPathComponent("Journal", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("2026-04-15.md")
        try FileManager.default.createDirectory(
            at: noteURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# Daily Note\n".write(to: noteURL, atomically: true, encoding: .utf8)

        let settings = ImportSettings(
            vaultPath: vaultURL.path,
            photoSubfolder: "Media/{{date}}",
            dateFormat: "yyyy-MM-dd",
            convertToJpeg: true,
            appendToDailyNote: true,
            dailyNotePathTemplate: "Journal/{{year}}/{{date}}.md",
            dailyNoteHeading: "## Camera Roll"
        )
        let date = ISO8601DateFormatter().date(from: "2026-04-15T12:00:00Z")!

        _ = try DailyNoteUpdater().appendPhotos(
            filenames: ["IMG_0001.jpg"],
            settings: settings,
            date: date
        )

        let updated = try String(contentsOf: noteURL, encoding: .utf8)
        XCTAssertTrue(updated.contains("## Camera Roll"))
        XCTAssertTrue(updated.contains("![[Media/2026-04-15/IMG_0001.jpg]]"))
    }

    func testImportTrackerTreatsSameAssetAndDestinationAsImported() throws {
        let trackerURL = try makeTemporaryDirectory().appendingPathComponent("tracker.json")
        let tracker = ImportTracker(storageURL: trackerURL, now: { Date(timeIntervalSince1970: 1_000) })

        tracker.markImported(
            assetIdentifier: "asset-1",
            targetRelativePath: "Photos/2026-04-15/IMG_0001.jpg",
            outputFormat: .jpeg
        )

        XCTAssertTrue(
            tracker.hasBeenImported(
                assetIdentifier: "asset-1",
                targetRelativePath: "Photos/2026-04-15/IMG_0001.jpg",
                outputFormat: .jpeg,
                vaultRootPath: "/Vault"
            )
        )
    }

    func testImportTrackerAllowsDifferentDestinationOrFormat() throws {
        let trackerURL = try makeTemporaryDirectory().appendingPathComponent("tracker.json")
        let tracker = ImportTracker(storageURL: trackerURL, now: { Date(timeIntervalSince1970: 1_000) })

        tracker.markImported(
            assetIdentifier: "asset-1",
            targetRelativePath: "Photos/2026-04-15/IMG_0001.jpg",
            outputFormat: .jpeg
        )

        XCTAssertFalse(
            tracker.hasBeenImported(
                assetIdentifier: "asset-1",
                targetRelativePath: "Photos/2026-04-16/IMG_0001.jpg",
                outputFormat: .jpeg,
                vaultRootPath: "/Vault"
            )
        )
        XCTAssertFalse(
            tracker.hasBeenImported(
                assetIdentifier: "asset-1",
                targetRelativePath: "Photos/2026-04-15/IMG_0001.heic",
                outputFormat: .original,
                vaultRootPath: "/Vault"
            )
        )
    }

    func testImportTrackerMigratesLegacyRecords() throws {
        let trackerURL = try makeTemporaryDirectory().appendingPathComponent("tracker.json")
        let importedAt = "2026-04-15T12:00:00Z"
        let legacy = [
            "asset-1": ["vaultPath": "/Vault/Photos/2026-04-15/IMG_0001.jpg", "importedAt": importedAt]
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: trackerURL)

        let formatter = ISO8601DateFormatter()
        let currentDate = formatter.date(from: "2026-05-01T12:00:00Z")!
        let tracker = ImportTracker(storageURL: trackerURL, now: { currentDate })

        XCTAssertTrue(
            tracker.hasBeenImported(
                assetIdentifier: "asset-1",
                targetRelativePath: "Photos/2026-04-15/IMG_0001.jpg",
                outputFormat: .jpeg,
                vaultRootPath: "/Vault"
            )
        )
        XCTAssertFalse(
            tracker.hasBeenImported(
                assetIdentifier: "asset-1",
                targetRelativePath: "Photos/2026-04-15/IMG_0002.jpg",
                outputFormat: .jpeg,
                vaultRootPath: "/Vault"
            )
        )

        tracker.save()
        let saved = try String(contentsOf: trackerURL, encoding: .utf8)
        XCTAssertTrue(saved.contains("assetIdentifier"))
    }

    func testImportTrackerPrunesStaleRecords() throws {
        let trackerURL = try makeTemporaryDirectory().appendingPathComponent("tracker.json")
        let oldDate = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 0))
        let legacy = [
            "asset-1": ["vaultPath": "/Vault/Photos/2025-01-01/IMG_0001.jpg", "importedAt": oldDate]
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy, options: [])
        try data.write(to: trackerURL)

        let tracker = ImportTracker(storageURL: trackerURL, now: { Date(timeIntervalSince1970: 10_000_000) })
        tracker.save()

        XCTAssertEqual(tracker.totalTracked, 0)
    }

    @MainActor
    func testAppStateIgnoresSecondImportTriggerWhileRunning() async {
        let defaults = makeUserDefaults()
        let coordinator = FakeImportCoordinator()
        let appState = AppState(
            defaults: defaults,
            importCoordinator: coordinator,
            updater: Updater(),
            startBackgroundTasks: false
        )
        appState.vaultPath = "/Vault"

        let firstRun = Task { await appState.runImport() }
        await coordinator.waitForInvocationCount(1)
        await appState.runImport()
        await coordinator.resume()
        await firstRun.value

        let invocationCount = await coordinator.invocationCountValue()
        XCTAssertEqual(invocationCount, 1)
    }

    @MainActor
    func testAppStateSuccessfulImportUpdatesState() async {
        let defaults = makeUserDefaults()
        let coordinator = FakeImportCoordinator()
        await coordinator.setTrackedCount(3)
        await coordinator.setResult(
            ImportRunResult(
                importedFilenames: ["IMG_0001.jpg", "IMG_0002.jpg"],
                importedCount: 2,
                statusSummary: "Imported 2 photo(s)",
                warnings: []
            )
        )

        let appState = AppState(
            defaults: defaults,
            importCoordinator: coordinator,
            updater: Updater(),
            startBackgroundTasks: false
        )
        appState.vaultPath = "/Vault"

        await appState.runImport()

        XCTAssertEqual(appState.lastImportCount, 2)
        XCTAssertEqual(appState.recentImports.count, 2)
        XCTAssertEqual(appState.statusMessage, "Imported 2 photo(s)")
        XCTAssertFalse(appState.isImporting)
    }

    @MainActor
    func testAppStateForwardsDateRangeToCoordinator() async {
        let defaults = makeUserDefaults()
        let coordinator = FakeImportCoordinator()
        await coordinator.setResult(
            ImportRunResult(
                importedFilenames: [],
                importedCount: 0,
                statusSummary: "No new photos",
                warnings: []
            )
        )

        let appState = AppState(
            defaults: defaults,
            importCoordinator: coordinator,
            updater: Updater(),
            startBackgroundTasks: false
        )
        appState.vaultPath = "/Vault"

        let startDate = ISO8601DateFormatter().date(from: "2026-04-10T12:00:00Z")!
        let endDate = ISO8601DateFormatter().date(from: "2026-04-15T12:00:00Z")!
        await appState.runImport(dateRange: ImportDateRange(startDate: startDate, endDate: endDate))

        let recordedRange = await coordinator.lastDateRangeValue()
        XCTAssertEqual(recordedRange, ImportDateRange(startDate: startDate, endDate: endDate))
    }

    @MainActor
    func testAppStateNoNewPhotosClearsImportingState() async {
        let defaults = makeUserDefaults()
        let coordinator = FakeImportCoordinator()
        await coordinator.setResult(
            ImportRunResult(
                importedFilenames: [],
                importedCount: 0,
                statusSummary: "No new photos",
                warnings: []
            )
        )

        let appState = AppState(
            defaults: defaults,
            importCoordinator: coordinator,
            updater: Updater(),
            startBackgroundTasks: false
        )
        appState.vaultPath = "/Vault"

        await appState.runImport()

        XCTAssertEqual(appState.statusMessage, "No new photos")
        XCTAssertFalse(appState.isImporting)
    }

    @MainActor
    func testAppStateErrorPathSurfacesFailure() async {
        let defaults = makeUserDefaults()
        let coordinator = FakeImportCoordinator()
        await coordinator.setError(TestError.failed)

        let appState = AppState(
            defaults: defaults,
            importCoordinator: coordinator,
            updater: Updater(),
            startBackgroundTasks: false
        )
        appState.vaultPath = "/Vault"

        await appState.runImport()

        XCTAssertTrue(appState.statusMessage.contains("Error:"))
        XCTAssertFalse(appState.isImporting)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func makeAppBundle(
        in directory: URL,
        name: String,
        bundleIdentifier: String,
        version: String
    ) throws -> URL {
        let appURL = directory.appendingPathComponent("\(name).app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)

        let infoPlist = contentsURL.appendingPathComponent("Info.plist")
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleShortVersionString": version,
            "CFBundleVersion": "1",
            "CFBundleExecutable": name
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: infoPlist)

        let executable = macOSURL.appendingPathComponent(name)
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        return appURL
    }

    @MainActor
    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "DailyPhotosTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

private enum TestError: LocalizedError {
    case failed

    var errorDescription: String? {
        switch self {
        case .failed:
            return "Coordinator failed"
        }
    }
}

private actor FakeImportCoordinator: ImportCoordinating {
    private(set) var invocationCount = 0
    private var lastDateRange: ImportDateRange?
    private var trackedCountValue = 0
    private var result = ImportRunResult(
        importedFilenames: [],
        importedCount: 0,
        statusSummary: "No new photos",
        warnings: []
    )
    private var nextError: Error?
    private var shouldSuspend = true
    private var continuation: CheckedContinuation<Void, Never>?

    func trackedCount() async -> Int {
        trackedCountValue
    }

    func runImport(
        settings: ImportSettings,
        dateRange: ImportDateRange,
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> ImportRunResult {
        invocationCount += 1
        lastDateRange = dateRange
        await progress("Checking for new photos…")

        if shouldSuspend {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.continuation = continuation
            }
            shouldSuspend = false
        }

        if let nextError {
            throw nextError
        }

        return result
    }

    func setTrackedCount(_ count: Int) {
        trackedCountValue = count
    }

    func setResult(_ result: ImportRunResult) {
        self.result = result
        shouldSuspend = false
        nextError = nil
    }

    func setError(_ error: Error) {
        nextError = error
        shouldSuspend = false
    }

    func waitForInvocationCount(_ expected: Int) async {
        while invocationCount < expected {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }

    func invocationCountValue() -> Int {
        invocationCount
    }

    func lastDateRangeValue() -> ImportDateRange? {
        lastDateRange
    }
}
