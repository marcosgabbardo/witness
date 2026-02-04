import Foundation
import SwiftData
import UIKit

/// Main coordinator for Witness operations
@MainActor
@Observable
final class WitnessManager {
    // MARK: - Services
    private let otsService = OpenTimestampsService()
    private let storageService = StorageService()
    
    // MARK: - State
    var isProcessing = false
    var processingMessage: String?
    var error: Error?
    
    // MARK: - Create Timestamps
    
    /// Create a timestamp for text content
    func createTextTimestamp(
        text: String,
        title: String?,
        context: ModelContext
    ) async throws -> WitnessItem {
        isProcessing = true
        processingMessage = "Computing hash..."
        defer { 
            isProcessing = false 
            processingMessage = nil
        }
        
        // Compute hash
        guard let hash = await otsService.sha256(string: text) else {
            throw WitnessError.hashingFailed
        }
        
        // Create item
        let item = WitnessItem(
            contentType: .text,
            contentHash: hash,
            title: title,
            textContent: text
        )
        
        context.insert(item)
        
        // Submit to calendar
        processingMessage = "Submitting to OpenTimestamps..."
        do {
            let (otsData, calendarUrl) = try await otsService.submitHash(hash)
            item.pendingOtsData = otsData
            item.calendarUrl = calendarUrl
            item.submittedAt = Date()
            item.status = .submitted
            item.lastUpdated = Date()
            
            // Save proof
            try await storageService.saveProof(otsData, for: item.id)
        } catch {
            item.status = .failed
            item.statusMessage = error.localizedDescription
            item.lastUpdated = Date()
        }
        
        try context.save()
        return item
    }
    
    /// Create a timestamp for a photo
    func createPhotoTimestamp(
        image: UIImage,
        title: String?,
        context: ModelContext
    ) async throws -> WitnessItem {
        isProcessing = true
        processingMessage = "Processing image..."
        defer { 
            isProcessing = false 
            processingMessage = nil
        }
        
        // Get image data
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw WitnessError.imageProcessingFailed
        }
        
        // Compute hash
        processingMessage = "Computing hash..."
        let hash = await otsService.sha256(data: imageData)
        
        // Create item
        let item = WitnessItem(
            contentType: .photo,
            contentHash: hash,
            title: title
        )
        
        context.insert(item)
        
        // Save image
        processingMessage = "Saving image..."
        let filename = try await storageService.saveImage(image, for: item.id)
        item.contentFileName = filename
        
        // Submit to calendar
        processingMessage = "Submitting to OpenTimestamps..."
        do {
            let (otsData, calendarUrl) = try await otsService.submitHash(hash)
            item.pendingOtsData = otsData
            item.calendarUrl = calendarUrl
            item.submittedAt = Date()
            item.status = .submitted
            item.lastUpdated = Date()
            
            // Save proof
            try await storageService.saveProof(otsData, for: item.id)
        } catch {
            item.status = .failed
            item.statusMessage = error.localizedDescription
            item.lastUpdated = Date()
        }
        
        try context.save()
        return item
    }
    
    /// Create a timestamp for a file
    func createFileTimestamp(
        data: Data,
        filename: String,
        title: String?,
        context: ModelContext
    ) async throws -> WitnessItem {
        isProcessing = true
        processingMessage = "Computing hash..."
        defer { 
            isProcessing = false 
            processingMessage = nil
        }
        
        // Compute hash
        let hash = await otsService.sha256(data: data)
        
        // Create item
        let item = WitnessItem(
            contentType: .file,
            contentHash: hash,
            title: title,
            contentFileName: filename
        )
        
        context.insert(item)
        
        // Save file
        processingMessage = "Saving file..."
        let savedFilename = try await storageService.saveFile(data, originalName: filename, for: item.id)
        item.contentFileName = savedFilename
        
        // Submit to calendar
        processingMessage = "Submitting to OpenTimestamps..."
        do {
            let (otsData, calendarUrl) = try await otsService.submitHash(hash)
            item.pendingOtsData = otsData
            item.calendarUrl = calendarUrl
            item.submittedAt = Date()
            item.status = .submitted
            item.lastUpdated = Date()
            
            // Save proof
            try await storageService.saveProof(otsData, for: item.id)
        } catch {
            item.status = .failed
            item.statusMessage = error.localizedDescription
            item.lastUpdated = Date()
        }
        
        try context.save()
        return item
    }
    
    // MARK: - Upgrade & Verification
    
    /// Try to upgrade a pending timestamp to confirmed
    func upgradeTimestamp(_ item: WitnessItem, context: ModelContext) async {
        guard item.status == .submitted,
              let calendarUrl = item.calendarUrl else { return }
        
        do {
            if let upgradedOts = try await otsService.upgradeTimestamp(
                hash: item.contentHash,
                calendarUrl: calendarUrl
            ) {
                item.otsData = upgradedOts
                item.status = .confirmed
                item.lastUpdated = Date()
                
                // Extract block info if possible
                // For now, just mark as confirmed
                
                // Save updated proof
                try await storageService.saveProof(upgradedOts, for: item.id)
                try context.save()
            }
        } catch {
            // Don't mark as failed - might just not be ready yet
            print("Upgrade check failed: \(error)")
        }
    }
    
    /// Check all pending items for upgrades
    func checkPendingUpgrades(items: [WitnessItem], context: ModelContext) async {
        let pendingItems = items.filter { $0.status == .submitted }
        
        for item in pendingItems {
            await upgradeTimestamp(item, context: context)
        }
    }
    
    /// Verify an item's timestamp
    func verifyTimestamp(_ item: WitnessItem) async throws -> VerificationResult {
        guard let otsData = item.otsData ?? item.pendingOtsData else {
            throw WitnessError.noProofData
        }
        
        return try await otsService.verifyTimestamp(
            otsData: otsData,
            originalHash: item.contentHash
        )
    }
    
    // MARK: - Delete
    
    /// Delete an item and its files
    func deleteItem(_ item: WitnessItem, context: ModelContext) async {
        await storageService.deleteFiles(for: item.id, contentFilename: item.contentFileName)
        context.delete(item)
        try? context.save()
    }
    
    // MARK: - Export
    
    /// Get shareable URLs for an item
    func getShareURLs(for item: WitnessItem) async throws -> [URL] {
        // Extract needed values on MainActor before calling actor
        let itemId = item.id
        let contentFileName = item.contentFileName
        let hasOtsData = item.otsData != nil
        
        return try await storageService.createShareBundle(
            itemId: itemId,
            contentFileName: contentFileName,
            hasOtsData: hasOtsData
        )
    }
    
    /// Load thumbnail for an item
    func loadThumbnail(for item: WitnessItem) async -> UIImage? {
        return await storageService.loadThumbnail(for: item.id)
    }
    
    /// Load full image for an item
    func loadImage(for item: WitnessItem) async -> UIImage? {
        guard let filename = item.contentFileName else { return nil }
        return await storageService.loadImage(filename: filename)
    }
}

// MARK: - Errors

enum WitnessError: Error, LocalizedError {
    case hashingFailed
    case imageProcessingFailed
    case noProofData
    case saveFailed
    
    var errorDescription: String? {
        switch self {
        case .hashingFailed:
            return "Failed to compute hash"
        case .imageProcessingFailed:
            return "Failed to process image"
        case .noProofData:
            return "No proof data available"
        case .saveFailed:
            return "Failed to save data"
        }
    }
}
