import SwiftUI
import OSLog

@MainActor
final class AppState: ObservableObject {
    @Published var isImporting = false
    @Published var lastImportTime: Date? = nil
    @Published var lastImportCount: Int = 0
    @Published var statusMessage: String = "Idle"
    @Published var recentImports: [RecentImport] = []
    @Published var trackedPhotoCount: Int = 0

    @Published var autoImportEnabled: Bool {
        didSet {
            defaults.set(autoImportEnabled, forKey: "autoImportEnabled")
            autoImportEnabled ? startTimer() : stopTimer()
        }
    }

    @Published var intervalMinutes: Int {
        didSet {
            defaults.set(intervalMinutes, forKey: "intervalMinutes")
            if autoImportEnabled {
                startTimer()
            }
        }
    }

    @Published var vaultPath: String {
        didSet { defaults.set(vaultPath, forKey: "vaultPath") }
    }

    @Published var photoSubfolder: String {
        didSet { defaults.set(photoSubfolder, forKey: "photoSubfolder") }
    }

    @Published var dateFormat: String {
        didSet { defaults.set(dateFormat, forKey: "dateFormat") }
    }

    @Published var convertToJpeg: Bool {
        didSet { defaults.set(convertToJpeg, forKey: "convertToJpeg") }
    }

    @Published var appendToDailyNote: Bool {
        didSet { defaults.set(appendToDailyNote, forKey: "appendToDailyNote") }
    }

    @Published var dailyNotePathTemplate: String {
        didSet { defaults.set(dailyNotePathTemplate, forKey: "dailyNotePathTemplate") }
    }

    @Published var dailyNoteHeading: String {
        didSet { defaults.set(dailyNoteHeading, forKey: "dailyNoteHeading") }
    }

    @Published var hasVaultAccess: Bool = false

    let updater: Updater

    private let defaults: UserDefaults
    private let importCoordinator: any ImportCoordinating
    private let logger = Logger(subsystem: "com.hiroki.daily-photos", category: "AppState")
    private var timer: Timer?

    init(
        defaults: UserDefaults = .standard,
        importCoordinator: any ImportCoordinating = ImportCoordinator(),
        updater: Updater = Updater(),
        startBackgroundTasks: Bool = true
    ) {
        self.defaults = defaults
        self.importCoordinator = importCoordinator
        self.updater = updater

        self.autoImportEnabled = defaults.bool(forKey: "autoImportEnabled")
        self.intervalMinutes = defaults.object(forKey: "intervalMinutes") as? Int ?? 30
        self.vaultPath = defaults.string(forKey: "vaultPath") ?? ""
        self.photoSubfolder = defaults.string(forKey: "photoSubfolder") ?? "Photos/{{date}}"
        self.dateFormat = defaults.string(forKey: "dateFormat") ?? "yyyy-MM-dd"
        self.convertToJpeg = defaults.object(forKey: "convertToJpeg") as? Bool ?? true
        self.appendToDailyNote = defaults.object(forKey: "appendToDailyNote") as? Bool ?? true
        self.dailyNotePathTemplate = defaults.string(forKey: "dailyNotePathTemplate")
            ?? "\(defaults.string(forKey: "dailyNotesSubfolder") ?? "Daily Notes")/{{date}}.md"
        self.dailyNoteHeading = defaults.string(forKey: "dailyNoteHeading") ?? "## Photos"

        self.hasVaultAccess = restoreVaultBookmark()

        if startBackgroundTasks, autoImportEnabled {
            startTimer()
        }

        if startBackgroundTasks {
            updater.startPeriodicChecks()
        }

        Task { [weak self] in
            await self?.refreshTrackedPhotoCount()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func runImport(dateRange: ImportDateRange? = nil) async {
        guard !vaultPath.isEmpty else {
            statusMessage = "No vault path set"
            return
        }

        guard !isImporting else {
            statusMessage = "Import already in progress"
            return
        }

        isImporting = true
        statusMessage = "Checking for new photos…"

        let settings = ImportSettings(
            vaultPath: vaultPath,
            photoSubfolder: photoSubfolder,
            dateFormat: dateFormat,
            convertToJpeg: convertToJpeg,
            appendToDailyNote: appendToDailyNote,
            dailyNotePathTemplate: dailyNotePathTemplate,
            dailyNoteHeading: dailyNoteHeading
        )
        let resolvedDateRange = dateRange ?? .single(Date())
        let updateStatus: @Sendable (String) async -> Void = { [self] message in
            await MainActor.run {
                statusMessage = message
            }
        }

        defer { isImporting = false }

        do {
            let result = try await importCoordinator.runImport(
                settings: settings,
                dateRange: resolvedDateRange,
                progress: updateStatus
            )

            if result.importedCount > 0 {
                let timestamp = Date()
                lastImportTime = timestamp
                lastImportCount = result.importedCount

                let imported = result.importedFilenames.map {
                    RecentImport(filename: $0, timestamp: timestamp)
                }
                recentImports = Array((imported + recentImports).prefix(20))
            }

            statusMessage = result.statusSummary
            await refreshTrackedPhotoCount()

            for warning in result.warnings {
                logger.warning("\(warning, privacy: .public)")
            }
        } catch ImportCoordinatorError.importAlreadyRunning {
            statusMessage = "Import already in progress"
        } catch {
            logger.error("Import failed: \(error.localizedDescription, privacy: .public)")
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    func saveVaultBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(bookmark, forKey: "vaultBookmark")
            vaultPath = url.path
            hasVaultAccess = true
        } catch {
            logger.error("Failed to save bookmark: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startTimer() {
        stopTimer()

        let interval = TimeInterval(intervalMinutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.runImport() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func refreshTrackedPhotoCount() async {
        trackedPhotoCount = await importCoordinator.trackedCount()
    }

    private func restoreVaultBookmark() -> Bool {
        guard let data = defaults.data(forKey: "vaultBookmark") else { return false }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return false
        }

        if isStale {
            saveVaultBookmark(for: url)
        }

        return url.startAccessingSecurityScopedResource()
    }
}

struct RecentImport: Identifiable {
    let id = UUID()
    let filename: String
    let timestamp: Date
}
