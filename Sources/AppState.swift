import SwiftUI
import Combine

/// Central observable state shared across the menu bar view and settings.
/// Manages the import timer, status display, and user preferences.

class AppState: ObservableObject {
    // ── UI state ──
    @Published var isImporting = false
    @Published var lastImportTime: Date? = nil
    @Published var lastImportCount: Int = 0
    @Published var statusMessage: String = "Idle"
    @Published var recentImports: [RecentImport] = []

    // ── Settings (persisted via @AppStorage in SettingsView,
    //    but we mirror them here so the timer can react) ──
    @Published var autoImportEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoImportEnabled, forKey: "autoImportEnabled")
            autoImportEnabled ? startTimer() : stopTimer()
        }
    }
    @Published var intervalMinutes: Int {
        didSet {
            UserDefaults.standard.set(intervalMinutes, forKey: "intervalMinutes")
            if autoImportEnabled { startTimer() } // Restart with new interval
        }
    }
    @Published var vaultPath: String {
        didSet { UserDefaults.standard.set(vaultPath, forKey: "vaultPath") }
    }
    @Published var photoSubfolder: String {
        didSet { UserDefaults.standard.set(photoSubfolder, forKey: "photoSubfolder") }
    }
    @Published var convertToJpeg: Bool {
        didSet { UserDefaults.standard.set(convertToJpeg, forKey: "convertToJpeg") }
    }
    @Published var appendToDailyNote: Bool {
        didSet { UserDefaults.standard.set(appendToDailyNote, forKey: "appendToDailyNote") }
    }
    @Published var dailyNotesSubfolder: String {
        didSet { UserDefaults.standard.set(dailyNotesSubfolder, forKey: "dailyNotesSubfolder") }
    }

    // ── Internal ──
    let importer = PhotoImporter()
    let tracker = ImportTracker()
    private var timer: Timer?

    // ── Bookmarks (for sandboxed file access) ──
    @Published var hasVaultAccess: Bool = false

    init() {
        let defaults = UserDefaults.standard
        self.autoImportEnabled = defaults.bool(forKey: "autoImportEnabled")
        self.intervalMinutes = defaults.object(forKey: "intervalMinutes") as? Int ?? 30
        self.vaultPath = defaults.string(forKey: "vaultPath") ?? ""
        self.photoSubfolder = defaults.string(forKey: "photoSubfolder") ?? "Photos/{{date}}"
        self.convertToJpeg = defaults.object(forKey: "convertToJpeg") as? Bool ?? true
        self.appendToDailyNote = defaults.object(forKey: "appendToDailyNote") as? Bool ?? true
        self.dailyNotesSubfolder = defaults.string(forKey: "dailyNotesSubfolder") ?? "Daily Notes"

        // Restore saved vault bookmark
        self.hasVaultAccess = restoreVaultBookmark()

        if autoImportEnabled {
            startTimer()
        }
    }

    // ────────────────────────────────────────────
    //  Import
    // ────────────────────────────────────────────
    @MainActor
    func runImport() async {
        guard !vaultPath.isEmpty else {
            statusMessage = "No vault path set"
            return
        }

        isImporting = true
        statusMessage = "Checking for new photos…"

        do {
            // 1. Fetch today's photos via PhotoKit
            let photos = try await importer.fetchTodaysPhotos()

            // 2. Filter already-imported
            let newPhotos = photos.filter { !tracker.hasBeenImported(id: $0.localIdentifier) }

            guard !newPhotos.isEmpty else {
                statusMessage = "No new photos"
                isImporting = false
                return
            }

            // 3. Build target folder path
            let today = Self.todayString()
            let subfolder = photoSubfolder.replacingOccurrences(of: "{{date}}", with: today)
            let targetDir = (vaultPath as NSString).appendingPathComponent(subfolder)

            // Create directory if needed
            try FileManager.default.createDirectory(
                atPath: targetDir, withIntermediateDirectories: true
            )

            // 4. Export each photo
            var imported: [RecentImport] = []
            for photo in newPhotos {
                statusMessage = "Importing \(imported.count + 1)/\(newPhotos.count)…"

                let result = try await importer.exportPhoto(
                    photo,
                    to: targetDir,
                    asJpeg: convertToJpeg
                )

                tracker.markImported(id: photo.localIdentifier, path: result.filePath)
                imported.append(RecentImport(
                    filename: result.filename,
                    timestamp: Date()
                ))
            }

            // 5. Optionally append to daily note
            if appendToDailyNote {
                appendPhotosToNote(imported.map(\.filename), date: today)
            }

            // 6. Update state
            lastImportTime = Date()
            lastImportCount = imported.count
            recentImports = (imported + recentImports).prefix(20).map { $0 }
            statusMessage = "Imported \(imported.count) photo(s)"
            tracker.save()

        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            print("Import failed: \(error)")
        }

        isImporting = false
    }

    // ────────────────────────────────────────────
    //  Timer
    // ────────────────────────────────────────────
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

    // ────────────────────────────────────────────
    //  Daily note
    // ────────────────────────────────────────────
    private func appendPhotosToNote(_ filenames: [String], date: String) {
        let noteDir = (vaultPath as NSString).appendingPathComponent(dailyNotesSubfolder)
        let notePath = (noteDir as NSString).appendingPathComponent("\(date).md")

        let subfolder = photoSubfolder.replacingOccurrences(of: "{{date}}", with: date)
        let embeds = filenames.map { "![[\(subfolder)/\($0)]]" }.joined(separator: "\n")
        let section = "\n\n## Photos\n\n\(embeds)\n"

        let fm = FileManager.default
        if fm.fileExists(atPath: notePath) {
            if let existing = try? String(contentsOfFile: notePath, encoding: .utf8),
               !existing.contains("## Photos") {
                try? (existing + section).write(toFile: notePath, atomically: true, encoding: .utf8)
            }
        }
        // Don't create the note if it doesn't exist — let Obsidian handle that.
    }

    // ────────────────────────────────────────────
    //  Vault bookmark (sandbox-safe folder access)
    // ────────────────────────────────────────────
    func saveVaultBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: "vaultBookmark")
            vaultPath = url.path
            hasVaultAccess = true
        } catch {
            print("Failed to save bookmark: \(error)")
        }
    }

    private func restoreVaultBookmark() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: "vaultBookmark") else { return false }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                  options: .withSecurityScope,
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &isStale) else { return false }
        if isStale {
            // Re-save the bookmark
            saveVaultBookmark(for: url)
        }
        return url.startAccessingSecurityScopedResource()
    }

    // ────────────────────────────────────────────
    //  Helpers
    // ────────────────────────────────────────────
    static func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}

struct RecentImport: Identifiable {
    let id = UUID()
    let filename: String
    let timestamp: Date
}
