import Foundation
import Photos

enum ImportOutputFormat: String, Codable, Sendable {
    case jpeg
    case original
}

struct ImportSettings: Sendable {
    let vaultPath: String
    let photoSubfolder: String
    let convertToJpeg: Bool
    let appendToDailyNote: Bool
    let dailyNotesSubfolder: String

    var outputFormat: ImportOutputFormat {
        convertToJpeg ? .jpeg : .original
    }

    func resolvedPhotoSubfolder(for dateString: String) -> String {
        photoSubfolder.replacingOccurrences(of: "{{date}}", with: dateString)
    }
}

struct ImportRunResult: Sendable {
    let importedFilenames: [String]
    let importedCount: Int
    let statusSummary: String
    let warnings: [String]
}

enum ImportCoordinatorError: LocalizedError {
    case importAlreadyRunning

    var errorDescription: String? {
        switch self {
        case .importAlreadyRunning:
            return "Import already in progress."
        }
    }
}

protocol ImportCoordinating: Sendable {
    func trackedCount() async -> Int
    func runImport(
        settings: ImportSettings,
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> ImportRunResult
}

actor ImportCoordinator: ImportCoordinating {
    private let importer: PhotoImporter
    private let tracker: ImportTracker
    private let noteUpdater: DailyNoteUpdater
    private var isRunning = false

    init(
        importer: PhotoImporter = PhotoImporter(),
        tracker: ImportTracker = ImportTracker(),
        noteUpdater: DailyNoteUpdater = DailyNoteUpdater()
    ) {
        self.importer = importer
        self.tracker = tracker
        self.noteUpdater = noteUpdater
    }

    func trackedCount() async -> Int {
        tracker.totalTracked
    }

    func runImport(
        settings: ImportSettings,
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> ImportRunResult {
        guard !isRunning else {
            throw ImportCoordinatorError.importAlreadyRunning
        }

        isRunning = true
        defer { isRunning = false }

        let today = Self.todayString()
        let targetSubfolder = settings.resolvedPhotoSubfolder(for: today)
        let targetDirectory = (settings.vaultPath as NSString).appendingPathComponent(targetSubfolder)

        await progress("Checking for new photos…")

        let photos = try await importer.fetchTodaysPhotos()
        try FileManager.default.createDirectory(atPath: targetDirectory, withIntermediateDirectories: true)

        let candidates = try photos.compactMap { asset -> PlannedImport? in
            let plannedFilename = try importer.plannedFilename(for: asset, asJpeg: settings.convertToJpeg)
            let relativePath = (targetSubfolder as NSString).appendingPathComponent(plannedFilename)

            guard !tracker.hasBeenImported(
                assetIdentifier: asset.localIdentifier,
                targetRelativePath: relativePath,
                outputFormat: settings.outputFormat,
                vaultRootPath: settings.vaultPath
            ) else {
                return nil
            }

            return PlannedImport(asset: asset, canonicalRelativePath: relativePath)
        }

        guard !candidates.isEmpty else {
            return ImportRunResult(
                importedFilenames: [],
                importedCount: 0,
                statusSummary: "No new photos",
                warnings: []
            )
        }

        var importedFilenames: [String] = []

        for (index, candidate) in candidates.enumerated() {
            await progress("Importing \(index + 1)/\(candidates.count)…")

            let result = try await importer.exportPhoto(
                candidate.asset,
                to: targetDirectory,
                asJpeg: settings.convertToJpeg
            )

            tracker.markImported(
                assetIdentifier: candidate.asset.localIdentifier,
                targetRelativePath: candidate.canonicalRelativePath,
                outputFormat: settings.outputFormat
            )
            importedFilenames.append(result.filename)
        }

        var warnings: [String] = []

        if settings.appendToDailyNote {
            let noteResult = try noteUpdater.appendPhotos(
                filenames: importedFilenames,
                settings: settings,
                dateString: today
            )

            if let warning = noteResult.warning {
                warnings.append(warning)
            }
        }

        tracker.save()

        return ImportRunResult(
            importedFilenames: importedFilenames,
            importedCount: importedFilenames.count,
            statusSummary: "Imported \(importedFilenames.count) photo(s)",
            warnings: warnings
        )
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

private struct PlannedImport {
    let asset: PHAsset
    let canonicalRelativePath: String
}
