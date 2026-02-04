import Foundation
import UIKit

/// Service for managing local file storage
actor StorageService {
    
    private let fileManager = FileManager.default
    
    /// Base directory for all Witness content
    private var baseDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let witnessDir = documentsPath.appendingPathComponent("WitnessContent", isDirectory: true)
        
        // Create if doesn't exist
        if !fileManager.fileExists(atPath: witnessDir.path) {
            try? fileManager.createDirectory(at: witnessDir, withIntermediateDirectories: true)
        }
        
        return witnessDir
    }
    
    /// Directory for original content files
    private var contentDirectory: URL {
        let dir = baseDirectory.appendingPathComponent("content", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    /// Directory for .ots proof files
    private var proofsDirectory: URL {
        let dir = baseDirectory.appendingPathComponent("proofs", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    /// Directory for thumbnails
    private var thumbnailsDirectory: URL {
        let dir = baseDirectory.appendingPathComponent("thumbnails", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    // MARK: - Content Storage
    
    /// Save image and return the filename
    func saveImage(_ image: UIImage, for itemId: UUID) async throws -> String {
        let filename = "\(itemId.uuidString).jpg"
        let url = contentDirectory.appendingPathComponent(filename)
        
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw StorageError.compressionFailed
        }
        
        try data.write(to: url)
        
        // Also create thumbnail
        await saveThumbnail(image, for: itemId)
        
        return filename
    }
    
    /// Save arbitrary file data and return the filename
    func saveFile(_ data: Data, originalName: String, for itemId: UUID) async throws -> String {
        let ext = (originalName as NSString).pathExtension
        let filename = "\(itemId.uuidString).\(ext.isEmpty ? "bin" : ext)"
        let url = contentDirectory.appendingPathComponent(filename)
        
        try data.write(to: url)
        
        return filename
    }
    
    /// Load content file
    func loadContent(filename: String) async throws -> Data {
        let url = contentDirectory.appendingPathComponent(filename)
        return try Data(contentsOf: url)
    }
    
    /// Load image
    func loadImage(filename: String) async -> UIImage? {
        let url = contentDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    
    // MARK: - Proof Storage
    
    /// Save .ots proof data
    func saveProof(_ data: Data, for itemId: UUID) async throws {
        let filename = "\(itemId.uuidString).ots"
        let url = proofsDirectory.appendingPathComponent(filename)
        try data.write(to: url)
    }
    
    /// Load .ots proof data
    func loadProof(for itemId: UUID) async -> Data? {
        let filename = "\(itemId.uuidString).ots"
        let url = proofsDirectory.appendingPathComponent(filename)
        return try? Data(contentsOf: url)
    }
    
    /// Get file URL for .ots proof (for sharing)
    func proofFileURL(for itemId: UUID) -> URL {
        let filename = "\(itemId.uuidString).ots"
        return proofsDirectory.appendingPathComponent(filename)
    }
    
    /// Get file URL for content (for sharing)
    func contentFileURL(filename: String) -> URL {
        return contentDirectory.appendingPathComponent(filename)
    }
    
    // MARK: - Thumbnails
    
    private func saveThumbnail(_ image: UIImage, for itemId: UUID) async {
        let size = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        
        guard let data = thumbnail.jpegData(compressionQuality: 0.7) else { return }
        
        let filename = "\(itemId.uuidString).thumb.jpg"
        let url = thumbnailsDirectory.appendingPathComponent(filename)
        
        try? data.write(to: url)
    }
    
    /// Load thumbnail
    func loadThumbnail(for itemId: UUID) async -> UIImage? {
        let filename = "\(itemId.uuidString).thumb.jpg"
        let url = thumbnailsDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    
    // MARK: - Cleanup
    
    /// Delete all files associated with an item
    func deleteFiles(for itemId: UUID, contentFilename: String?) async {
        // Delete content
        if let filename = contentFilename {
            let contentUrl = contentDirectory.appendingPathComponent(filename)
            try? fileManager.removeItem(at: contentUrl)
        }
        
        // Delete proof
        let proofFilename = "\(itemId.uuidString).ots"
        let proofUrl = proofsDirectory.appendingPathComponent(proofFilename)
        try? fileManager.removeItem(at: proofUrl)
        
        // Delete thumbnail
        let thumbFilename = "\(itemId.uuidString).thumb.jpg"
        let thumbUrl = thumbnailsDirectory.appendingPathComponent(thumbFilename)
        try? fileManager.removeItem(at: thumbUrl)
    }
    
    // MARK: - Export
    
    /// Create a shareable bundle with original file and proof
    func createShareBundle(itemId: UUID, contentFileName: String?, hasOtsData: Bool) async throws -> [URL] {
        var urls: [URL] = []
        
        // Add content file if exists
        if let filename = contentFileName {
            let contentUrl = contentFileURL(filename: filename)
            if fileManager.fileExists(atPath: contentUrl.path) {
                urls.append(contentUrl)
            }
        }
        
        // Add proof file if exists
        if hasOtsData {
            let proofUrl = proofFileURL(for: itemId)
            if fileManager.fileExists(atPath: proofUrl.path) {
                urls.append(proofUrl)
            }
        }
        
        return urls
    }
}

// MARK: - Errors

enum StorageError: Error, LocalizedError {
    case compressionFailed
    case fileNotFound
    case writeFailed
    
    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Failed to compress image"
        case .fileNotFound:
            return "File not found"
        case .writeFailed:
            return "Failed to write file"
        }
    }
}
