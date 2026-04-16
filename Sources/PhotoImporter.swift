import Foundation
import Photos
import AppKit

/// Wraps PhotoKit to query today's photos and export them to disk.
///
/// PhotoKit advantages over osxphotos:
///  - Native Apple framework, no Python dependency
///  - Proper permission prompt (not Full Disk Access)
///  - Can request specific image formats and sizes
///  - Stable local identifiers for tracking

struct ExportResult {
    let filename: String
    let filePath: String
}

class PhotoImporter {

    // ────────────────────────────────────────────
    //  Authorization
    // ────────────────────────────────────────────

    /// Request read-only access to the user's photo library.
    /// Returns true if authorized.
    func requestAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return newStatus == .authorized || newStatus == .limited
        default:
            return false
        }
    }

    // ────────────────────────────────────────────
    //  Query: get today's photos
    // ────────────────────────────────────────────

    /// Fetch all photos taken today from the user's Photos library.
    func fetchTodaysPhotos() async throws -> [PHAsset] {
        guard await requestAccess() else {
            throw ImportError.notAuthorized
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@ AND mediaType == %d",
            startOfDay as NSDate,
            endOfDay as NSDate,
            PHAssetMediaType.image.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let results = PHAsset.fetchAssets(with: options)

        var assets: [PHAsset] = []
        results.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        return assets
    }

    /// Fetch photos for a specific date (for manual imports of past days).
    func fetchPhotos(for date: Date) async throws -> [PHAsset] {
        guard await requestAccess() else {
            throw ImportError.notAuthorized
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@ AND mediaType == %d",
            startOfDay as NSDate,
            endOfDay as NSDate,
            PHAssetMediaType.image.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let results = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        results.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    // ────────────────────────────────────────────
    //  Export: write a photo to disk
    // ────────────────────────────────────────────

    /// Export a single PHAsset to the target directory.
    /// Returns the filename and full path of the exported file.
    func plannedFilename(for asset: PHAsset, asJpeg: Bool) throws -> String {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let primaryResource = resources.first else {
            throw ImportError.noResource
        }

        let originalFilename = primaryResource.originalFilename
        let baseName = (originalFilename as NSString).deletingPathExtension
        let ext = asJpeg ? "jpg" : (originalFilename as NSString).pathExtension
        return "\(baseName).\(ext)"
    }

    func exportPhoto(
        _ asset: PHAsset,
        to directory: String,
        asJpeg: Bool
    ) async throws -> ExportResult {

        // Determine filename from the asset's resource
        let resources = PHAssetResource.assetResources(for: asset)
        guard let primaryResource = resources.first else {
            throw ImportError.noResource
        }

        let plannedFilename = try plannedFilename(for: asset, asJpeg: asJpeg)
        let baseName = (plannedFilename as NSString).deletingPathExtension
        let ext = (plannedFilename as NSString).pathExtension

        // Handle filename collisions
        let filename = uniqueFilename(base: baseName, ext: ext, in: directory)
        let destPath = (directory as NSString).appendingPathComponent(filename)

        if asJpeg {
            // Request JPEG data via PHImageManager
            let data = try await requestImageData(for: asset, asJpeg: true)
            try data.write(to: URL(fileURLWithPath: destPath))
        } else {
            // Export original file via PHAssetResourceManager
            try await exportOriginalResource(primaryResource, to: destPath)
        }

        return ExportResult(filename: filename, filePath: destPath)
    }

    // ────────────────────────────────────────────
    //  Private: image data requests
    // ────────────────────────────────────────────

    /// Request image data from PhotoKit, optionally converting to JPEG.
    private func requestImageData(for asset: PHAsset, asJpeg: Bool) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true  // Download from iCloud if needed
            options.isSynchronous = false

            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, dataUTI, orientation, info in

                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let imageData = data else {
                    continuation.resume(throwing: ImportError.noImageData)
                    return
                }

                if asJpeg, let image = NSImage(data: imageData) {
                    // Convert to JPEG
                    guard let tiff = image.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiff),
                          let jpegData = bitmap.representation(
                              using: .jpeg,
                              properties: [.compressionFactor: 0.92]
                          ) else {
                        continuation.resume(throwing: ImportError.conversionFailed)
                        return
                    }
                    continuation.resume(returning: jpegData)
                } else {
                    continuation.resume(returning: imageData)
                }
            }
        }
    }

    /// Export the original resource file (preserves HEIC, RAW, etc.).
    private func exportOriginalResource(_ resource: PHAssetResource, to path: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let url = URL(fileURLWithPath: path)
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true

            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: url,
                options: options
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // ────────────────────────────────────────────
    //  Helpers
    // ────────────────────────────────────────────

    /// Generate a unique filename if one already exists in the directory.
    private func uniqueFilename(base: String, ext: String, in directory: String) -> String {
        let fm = FileManager.default
        var candidate = "\(base).\(ext)"
        var counter = 1

        while fm.fileExists(atPath: (directory as NSString).appendingPathComponent(candidate)) {
            candidate = "\(base)-\(counter).\(ext)"
            counter += 1
        }

        return candidate
    }
}

// ────────────────────────────────────────────
//  Errors
// ────────────────────────────────────────────

enum ImportError: LocalizedError {
    case notAuthorized
    case noResource
    case noImageData
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Photos access not authorized. Open System Settings → Privacy → Photos."
        case .noResource:
            return "Could not find image resource for this photo."
        case .noImageData:
            return "Could not retrieve image data."
        case .conversionFailed:
            return "Failed to convert image to JPEG."
        }
    }
}
