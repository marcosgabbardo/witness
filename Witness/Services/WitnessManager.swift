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
    private let pdfService = PDFExportService()
    
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
        guard item.status == .submitted else { 
            print("⏭️ Skipping \(item.displayTitle) - status is \(item.status)")
            return 
        }
        
        print("🔄 Checking upgrade for: \(item.displayTitle)")
        print("   Hash: \(item.hashHex)")
        print("   Calendar: \(item.calendarUrl ?? "none")")
        
        // Try original calendar first, then all calendars
        var upgradedOts: Data?
        
        if let calendarUrl = item.calendarUrl {
            print("   Trying original calendar: \(calendarUrl)")
            upgradedOts = try? await otsService.upgradeTimestamp(
                hash: item.contentHash,
                calendarUrl: calendarUrl
            )
            print("   Result: \(upgradedOts != nil ? "got data (\(upgradedOts!.count) bytes)" : "nil")")
        }
        
        // If original calendar didn't work, try all calendars
        if upgradedOts == nil {
            print("   Trying all calendars...")
            upgradedOts = await otsService.upgradeTimestampFromAnyCalendar(hash: item.contentHash)
            print("   Result: \(upgradedOts != nil ? "got data (\(upgradedOts!.count) bytes)" : "nil")")
        }
        
        guard let finalOts = upgradedOts else {
            print("❌ No upgrade available yet for \(item.displayTitle)")
            return
        }
        
        print("✅ Got upgraded proof for \(item.displayTitle)!")
        
        // Update item with confirmed proof
        item.otsData = finalOts
        item.status = .confirmed
        item.confirmedAt = Date()
        item.lastUpdated = Date()
        
        // Try to extract block info
        do {
            let verificationResult = try await otsService.verifyTimestamp(
                otsData: finalOts,
                originalHash: item.contentHash
            )
            
            if verificationResult.isValid {
                item.bitcoinBlockHeight = verificationResult.blockHeight
                item.bitcoinBlockTime = verificationResult.blockTime
                item.bitcoinTxId = verificationResult.txId
            }
        } catch {
            print("Could not extract block info: \(error)")
        }
        
        // Save updated proof
        try? await storageService.saveProof(finalOts, for: item.id)
        try? context.save()
        
        // Send notification and haptic
        let displayTitle = item.displayTitle
        let itemId = item.id
        let blockHeight = item.bitcoinBlockHeight
        await NotificationService.shared.notifyConfirmation(
            title: displayTitle,
            itemId: itemId,
            blockHeight: blockHeight
        )
        HapticManager.shared.timestampConfirmed()
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
        let otsData = item.otsData ?? item.pendingOtsData
        
        // Ensure OTS proof is saved to disk (might have been lost on reinstall)
        if let otsData = otsData {
            try await storageService.saveProof(otsData, for: itemId)
        }
        
        return try await storageService.createShareBundle(
            itemId: itemId,
            contentFileName: contentFileName,
            hasOtsData: otsData != nil
        )
    }
    
    /// Generate PDF certificate for an item
    func generatePDFCertificate(for item: WitnessItem) async throws -> URL {
        // Create snapshot for thread-safe access
        let snapshot = WitnessItemSnapshot(from: item)
        
        // Load image if it's a photo
        var contentImage: UIImage?
        if item.contentType == .photo {
            contentImage = await loadImage(for: item)
        }
        
        // Generate PDF
        let pdfData = try await pdfService.generateCertificate(for: snapshot, contentImage: contentImage)
        
        // Save to temp file
        let url = try await pdfService.saveCertificateToFile(data: pdfData, itemId: item.id)
        
        return url
    }
    
    /// Get share URLs including PDF certificate
    func getShareURLsWithCertificate(for item: WitnessItem) async throws -> [URL] {
        var urls = try await getShareURLs(for: item)
        
        // Add PDF certificate
        let pdfUrl = try await generatePDFCertificate(for: item)
        urls.insert(pdfUrl, at: 0) // PDF first
        
        return urls
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
