import Foundation

/// Tracks which photos have been imported using their PhotoKit local identifiers.
///
/// Persists to a JSON file in Application Support so it survives app restarts.
/// Prunes entries older than 90 days to keep the file small.

class ImportTracker {
    private var records: [String: ImportRecord] = [:]  // keyed by PHAsset.localIdentifier
    private let storageURL: URL
    private let maxAgeDays = 90

    struct ImportRecord: Codable {
        let vaultPath: String
        let importedAt: Date
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("DailyPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.storageURL = appDir.appendingPathComponent("imported.json")
        load()
    }

    // ── Query ──

    func hasBeenImported(id: String) -> Bool {
        records[id] != nil
    }

    // ── Record ──

    func markImported(id: String, path: String) {
        records[id] = ImportRecord(vaultPath: path, importedAt: Date())
    }

    var totalTracked: Int { records.count }

    // ── Persistence ──

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([String: ImportRecord].self, from: data) else {
            return
        }
        records = decoded
        prune()
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func prune() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: Date())!
        records = records.filter { $0.value.importedAt > cutoff }
    }
}
