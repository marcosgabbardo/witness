import Foundation
import SwiftData
import UIKit
import CryptoKit

/// Main coordinator for DataStamp operations
@MainActor
@Observable
final class DataStampManager {
    // MARK: - Services
    private let otsService = OpenTimestampsService()
    private let storageService = StorageService()
    private let pdfService = PDFExportService()
    
    // MARK: - State
    var isProcessing = false
    var processingMessage: String?
    var error: Error?
    
    // MARK: - Sync State
    var isSyncing = false
    var syncProgress: Int = 0
    var syncTotal: Int = 0
    var syncMessage: String?
    
    // MARK: - Create Timestamps
    
    /// Create a timestamp for text content
    func createTextTimestamp(
        text: String,
        title: String?,
        context: ModelContext
    ) async throws -> DataStampItem {
        isProcessing = true
        processingMessage = "Saving text..."
        defer { 
            isProcessing = false 
            processingMessage = nil
        }
        
        // Convert text to UTF-8 data for consistent hashing
        guard let textData = text.data(using: .utf8) else {
            throw DataStampError.hashingFailed
        }
        
        // Compute hash from the file data (not string) for reproducibility
        processingMessage = "Computing hash..."
        let hash = await otsService.sha256(data: textData)
        
        // Create item
        let item = DataStampItem(
            contentType: .text,
            contentHash: hash,
            title: title,
            textContent: text
        )
        
        context.insert(item)
        
        // Save text as .txt file
        processingMessage = "Saving file..."
        let filename = try await storageService.saveText(text, for: item.id)
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
    
    /// Create a timestamp for a photo
    func createPhotoTimestamp(
        image: UIImage,
        title: String?,
        context: ModelContext
    ) async throws -> DataStampItem {
        isProcessing = true
        processingMessage = "Processing image..."
        defer { 
            isProcessing = false 
            processingMessage = nil
        }
        
        // Get image data
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw DataStampError.imageProcessingFailed
        }
        
        // Compute hash
        processingMessage = "Computing hash..."
        let hash = await otsService.sha256(data: imageData)
        
        // Create item
        let item = DataStampItem(
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
    ) async throws -> DataStampItem {
        isProcessing = true
        processingMessage = "Computing hash..."
        defer { 
            isProcessing = false 
            processingMessage = nil
        }
        
        // Compute hash
        let hash = await otsService.sha256(data: data)
        
        // Create item
        let item = DataStampItem(
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
    func upgradeTimestamp(_ item: DataStampItem, context: ModelContext) async {
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
        
        // If original calendar didn't work, try using the pending OTS data
        if upgradedOts == nil, let pendingOts = item.pendingOtsData {
            print("   Trying to upgrade from pending OTS data...")
            upgradedOts = await otsService.upgradeFromPendingOts(
                pendingOtsData: pendingOts,
                originalHash: item.contentHash
            )
            print("   Result: \(upgradedOts != nil ? "got data (\(upgradedOts!.count) bytes)" : "nil")")
        }
        
        // If still nil, try all calendars with original hash
        if upgradedOts == nil {
            print("   Trying all calendars with original hash...")
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
    func checkPendingUpgrades(items: [DataStampItem], context: ModelContext) async {
        let pendingItems = items.filter { $0.status == .submitted }
        
        guard !pendingItems.isEmpty else { return }
        
        // Start sync
        isSyncing = true
        syncProgress = 0
        syncTotal = pendingItems.count
        syncMessage = "Checking \(pendingItems.count) pending..."
        
        defer {
            isSyncing = false
            syncProgress = 0
            syncTotal = 0
            syncMessage = nil
        }
        
        for (index, item) in pendingItems.enumerated() {
            syncProgress = index + 1
            syncMessage = "Checking \(index + 1)/\(pendingItems.count)..."
            await upgradeTimestamp(item, context: context)
        }
    }
    
    /// Debug: Get upgrade info for an item
    func getUpgradeDebugInfo(for item: DataStampItem) async -> String {
        guard let pendingOts = item.pendingOtsData else {
            return "No pending OTS data"
        }
        
        var info = "=== UPGRADE DEBUG ===\n"
        info += "Original hash: \(item.hashHex)\n"
        info += "Calendar: \(item.calendarUrl ?? "none")\n"
        info += "OTS data size: \(pendingOts.count) bytes\n\n"
        
        do {
            let merkleVerifier = MerkleVerifier()
            let proof = try await merkleVerifier.parseOtsFile(pendingOts)
            
            info += "Operations: \(proof.operations.count)\n"
            
            // Compute commitment
            var commitment = item.contentHash
            for (i, op) in proof.operations.enumerated() {
                let before = commitment.hexString
                commitment = applyOp(op, to: commitment)
                info += "\(i+1). \(opName(op)): \(before.prefix(16))... -> \(commitment.hexString.prefix(16))...\n"
            }
            
            info += "\nFinal commitment: \(commitment.hexString)\n"
            
            // Show attestations
            info += "\nAttestations:\n"
            for att in proof.attestations {
                switch att {
                case .pending(let url):
                    info += "- PENDING: \(url)\n"
                    
                    // Try to fetch from calendar
                    let fullUrl = "\(url)/timestamp/\(commitment.hexString)"
                    info += "  URL: \(fullUrl)\n"
                    
                case .bitcoin(let height):
                    info += "- BITCOIN: block \(height)\n"
                default:
                    info += "- OTHER\n"
                }
            }
            
        } catch {
            info += "Parse error: \(error)\n"
        }
        
        return info
    }
    
    private func applyOp(_ op: OTSOperation, to data: Data) -> Data {
        switch op {
        case .sha256:
            return Data(SHA256.hash(data: data))
        case .append(let appendData):
            return data + appendData
        case .prepend(let prependData):
            return prependData + data
        default:
            return data
        }
    }
    
    private func opName(_ op: OTSOperation) -> String {
        switch op {
        case .sha256: return "SHA256"
        case .append(let d): return "Append(\(d.count))"
        case .prepend(let d): return "Prepend(\(d.count))"
        default: return "Other"
        }
    }
    
    /// Verify an item's timestamp
    func verifyTimestamp(_ item: DataStampItem) async throws -> VerificationResult {
        guard let otsData = item.otsData ?? item.pendingOtsData else {
            throw DataStampError.noProofData
        }
        
        return try await otsService.verifyTimestamp(
            otsData: otsData,
            originalHash: item.contentHash
        )
    }
    
    // MARK: - Delete
    
    /// Delete an item and its files
    func deleteItem(_ item: DataStampItem, context: ModelContext) async {
        await storageService.deleteFiles(for: item.id, contentFilename: item.contentFileName)
        context.delete(item)
        try? context.save()
    }
    
    // MARK: - Export
    
    /// Get shareable URLs for an item
    func getShareURLs(for item: DataStampItem) async throws -> [URL] {
        // Extract needed values on MainActor before calling actor
        let itemId = item.id
        var contentFileName = item.contentFileName
        let otsData = item.otsData ?? item.pendingOtsData
        
        // Ensure OTS proof is saved to disk (might have been lost on reinstall)
        if let otsData = otsData {
            try await storageService.saveProof(otsData, for: itemId)
        }
        
        // For text items without a file (legacy), create the .txt file now
        if item.contentType == .text, contentFileName == nil, let text = item.textContent {
            contentFileName = try await storageService.saveText(text, for: itemId)
            // Update the item for future shares
            item.contentFileName = contentFileName
        }
        
        return try await storageService.createShareBundle(
            itemId: itemId,
            contentFileName: contentFileName,
            hasOtsData: otsData != nil
        )
    }
    
    /// Generate PDF certificate for an item
    func generatePDFCertificate(for item: DataStampItem) async throws -> URL {
        // Create snapshot for thread-safe access
        let snapshot = DataStampItemSnapshot(from: item)
        
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
    func getShareURLsWithCertificate(for item: DataStampItem) async throws -> [URL] {
        var urls = try await getShareURLs(for: item)
        
        // Add PDF certificate
        let pdfUrl = try await generatePDFCertificate(for: item)
        urls.insert(pdfUrl, at: 0) // PDF first
        
        return urls
    }
    
    /// Get all share URLs (PDF + original file + .ots)
    func getShareURLsAll(for item: DataStampItem) async throws -> [URL] {
        var urls: [URL] = []
        
        // Add PDF certificate
        let pdfUrl = try await generatePDFCertificate(for: item)
        urls.append(pdfUrl)
        
        // Add original file + .ots
        let proofUrls = try await getShareURLs(for: item)
        urls.append(contentsOf: proofUrls)
        
        return urls
    }
    
    /// Get only .ots file URL
    func getShareURLsOtsOnly(for item: DataStampItem) async throws -> [URL] {
        let itemId = item.id
        let otsData = item.otsData ?? item.pendingOtsData
        
        // Ensure OTS proof is saved to disk
        if let otsData = otsData {
            try await storageService.saveProof(otsData, for: itemId)
        }
        
        let proofUrl = await storageService.proofFileURL(for: itemId)
        
        guard FileManager.default.fileExists(atPath: proofUrl.path) else {
            throw DataStampError.noProofData
        }
        
        return [proofUrl]
    }
    
    /// Load thumbnail for an item
    func loadThumbnail(for item: DataStampItem) async -> UIImage? {
        return await storageService.loadThumbnail(for: item.id)
    }
    
    /// Load full image for an item
    func loadImage(for item: DataStampItem) async -> UIImage? {
        guard let filename = item.contentFileName else { return nil }
        return await storageService.loadImage(filename: filename)
    }
}

// MARK: - Errors

enum DataStampError: Error, LocalizedError {
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
