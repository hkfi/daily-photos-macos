import Foundation
import Photos

enum ImportOutputFormat: String, Codable, Sendable {
    case jpeg
    case original
}

struct ImportSettings: Sendable {
    let vaultPath: String
    let photoSubfolder: String
    let dateFormat: String
    let convertToJpeg: Bool
    let appendToDailyNote: Bool
    let dailyNotePathTemplate: String
    let dailyNoteHeading: String

    var outputFormat: ImportOutputFormat {
        convertToJpeg ? .jpeg : .original
    }

    func resolvedDateString(for date: Date) -> String {
        Self.format(date, as: dateFormat.isEmpty ? "yyyy-MM-dd" : dateFormat)
    }

    func resolvedPhotoSubfolder(for date: Date) -> String {
        resolveTemplate(photoSubfolder, for: date)
    }

    func resolvedDailyNotePath(for date: Date) -> String {
        let template = dailyNotePathTemplate.isEmpty ? "Daily Notes/{{date}}.md" : dailyNotePathTemplate
        return resolveTemplate(template, for: date)
    }

    private func resolveTemplate(_ template: String, for date: Date) -> String {
        template
            .replacingOccurrences(of: "{{date}}", with: resolvedDateString(for: date))
            .replacingOccurrences(of: "{{year}}", with: Self.format(date, as: "yyyy"))
            .replacingOccurrences(of: "{{month}}", with: Self.format(date, as: "MM"))
            .replacingOccurrences(of: "{{day}}", with: Self.format(date, as: "dd"))
    }

    private static func format(_ date: Date, as format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

struct ImportRunResult: Sendable {
    let importedFilenames: [String]
    let importedCount: Int
    let statusSummary: String
    let warnings: [String]
}

struct ImportDateRange: Sendable, Equatable {
    let startDate: Date
    let endDate: Date

    init(startDate: Date, endDate: Date) {
        if startDate <= endDate {
            self.startDate = startDate
            self.endDate = endDate
        } else {
            self.startDate = endDate
            self.endDate = startDate
        }
    }

    static func single(_ date: Date) -> ImportDateRange {
        ImportDateRange(startDate: date, endDate: date)
    }
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
        dateRange: ImportDateRange,
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
        dateRange: ImportDateRange,
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> ImportRunResult {
        guard !isRunning else {
            throw ImportCoordinatorError.importAlreadyRunning
        }

        isRunning = true
        defer { isRunning = false }

        let days = Self.days(in: dateRange)
        var importedFilenames: [String] = []
        var warnings: [String] = []

        await progress("Checking for new photos…")

        for (dayIndex, day) in days.enumerated() {
            let dateString = settings.resolvedDateString(for: day)
            let targetSubfolder = settings.resolvedPhotoSubfolder(for: day)
            let targetDirectory = (settings.vaultPath as NSString).appendingPathComponent(targetSubfolder)

            if days.count > 1 {
                await progress("Checking \(dateString) (\(dayIndex + 1)/\(days.count))…")
            }

            let photos = try await importer.fetchPhotos(for: day)
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
                continue
            }

            try FileManager.default.createDirectory(atPath: targetDirectory, withIntermediateDirectories: true)

            var dayImportedFilenames: [String] = []

            for (index, candidate) in candidates.enumerated() {
                let dayPrefix = days.count > 1 ? "\(dateString): " : ""
                await progress("\(dayPrefix)Importing \(index + 1)/\(candidates.count)…")

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
                dayImportedFilenames.append(result.filename)
            }

            importedFilenames.append(contentsOf: dayImportedFilenames)

            if settings.appendToDailyNote {
                let noteResult = try noteUpdater.appendPhotos(
                    filenames: dayImportedFilenames,
                    settings: settings,
                    date: day
                )

                if let warning = noteResult.warning {
                    warnings.append(warning)
                }
            }
        }

        guard !importedFilenames.isEmpty else {
            return ImportRunResult(
                importedFilenames: [],
                importedCount: 0,
                statusSummary: "No new photos",
                warnings: warnings
            )
        }

        tracker.save()

        return ImportRunResult(
            importedFilenames: importedFilenames,
            importedCount: importedFilenames.count,
            statusSummary: Self.statusSummary(importedCount: importedFilenames.count, dayCount: days.count),
            warnings: warnings
        )
    }

    private static func days(in range: ImportDateRange) -> [Date] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: range.startDate)
        let end = calendar.startOfDay(for: range.endDate)

        var days: [Date] = []
        var current = start

        while current <= end {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return days
    }

    private static func statusSummary(importedCount: Int, dayCount: Int) -> String {
        if dayCount <= 1 {
            return "Imported \(importedCount) photo(s)"
        }

        return "Imported \(importedCount) photo(s) across \(dayCount) day(s)"
    }
}

private struct PlannedImport {
    let asset: PHAsset
    let canonicalRelativePath: String
}
