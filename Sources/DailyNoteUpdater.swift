import Foundation

struct DailyNoteUpdateResult {
    let didWrite: Bool
    let warning: String?
}

struct DailyNoteUpdater {
    private let heading = "## Photos"

    func appendPhotos(
        filenames: [String],
        settings: ImportSettings,
        dateString: String
    ) throws -> DailyNoteUpdateResult {
        let noteDirectory = (settings.vaultPath as NSString).appendingPathComponent(settings.dailyNotesSubfolder)
        let notePath = (noteDirectory as NSString).appendingPathComponent("\(dateString).md")

        guard FileManager.default.fileExists(atPath: notePath) else {
            return DailyNoteUpdateResult(didWrite: false, warning: nil)
        }

        let existing = try String(contentsOfFile: notePath, encoding: .utf8)
        let photoSubfolder = settings.resolvedPhotoSubfolder(for: dateString)
        let embeds = filenames.map { "![[\(photoSubfolder)/\($0)]]" }
        let updated = Self.upsertPhotoSection(in: existing, embeds: embeds, heading: heading)

        guard updated != existing else {
            return DailyNoteUpdateResult(didWrite: false, warning: nil)
        }

        try updated.write(toFile: notePath, atomically: true, encoding: .utf8)
        return DailyNoteUpdateResult(didWrite: true, warning: nil)
    }

    static func upsertPhotoSection(
        in content: String,
        embeds: [String],
        heading: String = "## Photos"
    ) -> String {
        guard !embeds.isEmpty else { return content }

        var lines = content.components(separatedBy: .newlines)
        if lines.last == "" {
            lines.removeLast()
        }

        if let sectionIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == heading }) {
            let sectionEnd = findSectionEnd(in: lines, from: sectionIndex + 1)
            let existingSectionLines = Array(lines[(sectionIndex + 1)..<sectionEnd])
            let existingEmbeds = Set(
                existingSectionLines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("![[") }
            )
            let missingEmbeds = embeds.filter { !existingEmbeds.contains($0) }

            guard !missingEmbeds.isEmpty else {
                return content
            }

            var updatedSectionLines = existingSectionLines
            if updatedSectionLines.isEmpty {
                updatedSectionLines = [""]
            } else if updatedSectionLines.last?.isEmpty == false {
                updatedSectionLines.append("")
            }

            updatedSectionLines.append(contentsOf: missingEmbeds)

            let updatedLines =
                Array(lines[..<sectionIndex]) +
                [heading] +
                updatedSectionLines +
                Array(lines[sectionEnd..<lines.count])
            return normalize(updatedLines)
        }

        var updated = content
        if !updated.hasSuffix("\n") && !updated.isEmpty {
            updated.append("\n")
        }
        if !updated.isEmpty {
            updated.append("\n")
        }
        updated.append("\(heading)\n\n")
        updated.append(embeds.joined(separator: "\n"))
        updated.append("\n")
        return updated
    }

    private static func findSectionEnd(in lines: [String], from start: Int) -> Int {
        for index in start..<lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if index > start, trimmed.hasPrefix("## "), trimmed != "## Photos" {
                return index
            }
        }
        return lines.count
    }

    private static func normalize(_ lines: [String]) -> String {
        lines.joined(separator: "\n") + "\n"
    }
}
