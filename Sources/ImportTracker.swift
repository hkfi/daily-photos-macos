import Foundation

final class ImportTracker {
    struct ImportRecord: Codable {
        let assetIdentifier: String
        let targetRelativePath: String
        let outputFormat: ImportOutputFormat
        let importedAt: Date
        let legacyAbsolutePath: String?
    }

    private struct LegacyImportRecord: Codable {
        let vaultPath: String
        let importedAt: Date
    }

    private var records: [String: ImportRecord] = [:]
    private let storageURL: URL
    private let maxAgeDays = 90
    private let now: () -> Date

    init(storageURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.now = now

        if let storageURL {
            self.storageURL = storageURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDirectory = appSupport.appendingPathComponent("DailyPhotos", isDirectory: true)
            try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            self.storageURL = appDirectory.appendingPathComponent("imported.json")
        }

        load()
    }

    var totalTracked: Int {
        records.count
    }

    func hasBeenImported(
        assetIdentifier: String,
        targetRelativePath: String,
        outputFormat: ImportOutputFormat,
        vaultRootPath: String
    ) -> Bool {
        prune()

        let key = Self.fingerprint(
            assetIdentifier: assetIdentifier,
            targetRelativePath: targetRelativePath,
            outputFormat: outputFormat
        )

        if records[key] != nil {
            return true
        }

        let absoluteTargetPath = (vaultRootPath as NSString).appendingPathComponent(targetRelativePath)
        return records.values.contains {
            $0.assetIdentifier == assetIdentifier &&
            $0.legacyAbsolutePath == absoluteTargetPath &&
            $0.outputFormat == outputFormat
        }
    }

    func markImported(
        assetIdentifier: String,
        targetRelativePath: String,
        outputFormat: ImportOutputFormat
    ) {
        let key = Self.fingerprint(
            assetIdentifier: assetIdentifier,
            targetRelativePath: targetRelativePath,
            outputFormat: outputFormat
        )

        records[key] = ImportRecord(
            assetIdentifier: assetIdentifier,
            targetRelativePath: targetRelativePath,
            outputFormat: outputFormat,
            importedAt: now(),
            legacyAbsolutePath: nil
        )
    }

    func save() {
        prune()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? Data(contentsOf: storageURL) else { return }

        if let decoded = try? decoder.decode([String: ImportRecord].self, from: data) {
            records = decoded
            prune()
            return
        }

        if let legacy = try? decoder.decode([String: LegacyImportRecord].self, from: data) {
            records = legacy.reduce(into: [:]) { partialResult, item in
                let outputFormat = Self.outputFormat(forLegacyPath: item.value.vaultPath)
                partialResult[Self.legacyKey(assetIdentifier: item.key)] = ImportRecord(
                    assetIdentifier: item.key,
                    targetRelativePath: "",
                    outputFormat: outputFormat,
                    importedAt: item.value.importedAt,
                    legacyAbsolutePath: item.value.vaultPath
                )
            }
            prune()
        }
    }

    private func prune() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: now())!
        records = records.filter { $0.value.importedAt > cutoff }
    }

    private static func fingerprint(
        assetIdentifier: String,
        targetRelativePath: String,
        outputFormat: ImportOutputFormat
    ) -> String {
        "\(assetIdentifier)|\(targetRelativePath)|\(outputFormat.rawValue)"
    }

    private static func legacyKey(assetIdentifier: String) -> String {
        "legacy|\(assetIdentifier)"
    }

    private static func outputFormat(forLegacyPath path: String) -> ImportOutputFormat {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg"].contains(ext) ? .jpeg : .original
    }
}
