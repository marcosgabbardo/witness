import Foundation
import SwiftData
import CloudKit
import UIKit
import os.log

/// CloudKit sync service for Witness items with full file sync
@MainActor
final class CloudKitSyncService: ObservableObject {
    
    // MARK: - Constants
    
    private let containerIdentifier = "iCloud.com.makiavel.witness"
    private let recordType = "WitnessItem"
    private let subscriptionID = "witness-changes"
    
    // MARK: - Published State
    
    @Published private(set) var syncState: SyncState = .checking
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var pendingChanges: Int = 0
    @Published private(set) var error: Error?
    @Published private(set) var isAvailable: Bool = false
    @Published var syncProgress: Double = 0
    @Published var syncMessage: String?
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.makiavel.witness", category: "CloudSync")
    private var modelContext: ModelContext?
    private var container: CKContainer?
    private var database: CKDatabase?
    private var storageService: StorageService?
    
    // MARK: - Initialization
    
    init() {
        logger.info("CloudKitSyncService initialized")
    }
    
    // MARK: - Configuration
    
    /// Configure the sync service
    func configure(with modelContext: ModelContext, storage: StorageService) async {
        self.modelContext = modelContext
        self.storageService = storage
        
        // iCloud sync disabled - requires paid Apple Developer account
        // When you have a paid account:
        // 1. Add iCloud capability in Xcode
        // 2. Uncomment the code below
        // 3. Remove this early return
        
        logger.info("iCloud sync disabled - requires paid Apple Developer account")
        syncState = .unavailable
        isAvailable = false
        return
        
        /*
        // Initialize CloudKit
        container = CKContainer(identifier: containerIdentifier)
        database = container?.privateCloudDatabase
        
        // Check account status
        await checkAccountStatus()
        */
    }
    
    private func checkAccountStatus() async {
        guard let container = container else {
            syncState = .unavailable
            isAvailable = false
            return
        }
        
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                logger.info("iCloud account available")
                isAvailable = true
                syncState = .idle
                
                // Setup subscription for remote changes
                await setupSubscription()
                
            case .noAccount:
                logger.warning("No iCloud account")
                isAvailable = false
                syncState = .unavailable
                error = SyncError.noAccount
                
            case .restricted:
                logger.warning("iCloud restricted")
                isAvailable = false
                syncState = .unavailable
                error = SyncError.restricted
                
            case .couldNotDetermine:
                logger.warning("Could not determine iCloud status")
                isAvailable = false
                syncState = .unavailable
                
            case .temporarilyUnavailable:
                logger.warning("iCloud temporarily unavailable")
                isAvailable = false
                syncState = .error
                
            @unknown default:
                isAvailable = false
                syncState = .unavailable
            }
        } catch {
            logger.error("Failed to check account status: \(error.localizedDescription)")
            isAvailable = false
            syncState = .error
            self.error = error
        }
    }
    
    // MARK: - Subscription
    
    private func setupSubscription() async {
        guard let database = database else { return }
        
        let subscription = CKQuerySubscription(
            recordType: recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        
        let notification = CKSubscription.NotificationInfo()
        notification.shouldSendContentAvailable = true
        subscription.notificationInfo = notification
        
        do {
            try await database.save(subscription)
            logger.info("CloudKit subscription created")
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Subscription might already exist
            logger.info("Subscription already exists")
        } catch {
            logger.error("Failed to create subscription: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Sync
    
    /// Perform full sync
    func sync() async {
        guard isAvailable, let database = database, let modelContext = modelContext else {
            logger.info("Sync skipped - not available")
            return
        }
        
        syncState = .syncing
        syncProgress = 0
        syncMessage = "Starting sync..."
        
        do {
            // 1. Upload local changes
            syncMessage = "Uploading changes..."
            try await uploadLocalChanges(to: database, context: modelContext)
            syncProgress = 0.5
            
            // 2. Download remote changes
            syncMessage = "Downloading changes..."
            try await downloadRemoteChanges(from: database, context: modelContext)
            syncProgress = 1.0
            
            // Done
            syncState = .idle
            lastSyncDate = Date()
            syncMessage = nil
            pendingChanges = 0
            error = nil
            
            logger.info("Sync completed successfully")
            
        } catch {
            logger.error("Sync failed: \(error.localizedDescription)")
            syncState = .error
            self.error = error
            syncMessage = nil
        }
    }
    
    // MARK: - Upload
    
    private func uploadLocalChanges(to database: CKDatabase, context: ModelContext) async throws {
        // Fetch all local items
        let descriptor = FetchDescriptor<WitnessItem>()
        let items = try context.fetch(descriptor)
        
        logger.info("Uploading \(items.count) items")
        
        for (index, item) in items.enumerated() {
            syncMessage = "Uploading \(index + 1)/\(items.count)..."
            syncProgress = Double(index) / Double(items.count) * 0.5
            
            do {
                try await uploadItem(item, to: database)
            } catch let error as CKError where error.code == .serverRecordChanged {
                // Conflict - fetch remote and merge
                logger.warning("Conflict for item \(item.id), fetching remote version")
                // For now, remote wins (could implement smarter merge)
            } catch {
                logger.error("Failed to upload item \(item.id): \(error.localizedDescription)")
            }
        }
    }
    
    private func uploadItem(_ item: WitnessItem, to database: CKDatabase) async throws {
        let recordID = CKRecord.ID(recordName: item.id.uuidString)
        
        // Try to fetch existing record or create new
        var record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }
        
        // Set fields
        record["contentType"] = item.contentType.rawValue
        record["contentHash"] = item.contentHash.base64EncodedString()
        record["title"] = item.title
        record["notes"] = item.notes
        record["textContent"] = item.textContent
        record["status"] = item.status.rawValue
        record["statusMessage"] = item.statusMessage
        record["createdAt"] = item.createdAt
        record["lastUpdated"] = item.lastUpdated
        record["calendarUrl"] = item.calendarUrl
        record["submittedAt"] = item.submittedAt
        record["confirmedAt"] = item.confirmedAt
        record["bitcoinBlockHeight"] = item.bitcoinBlockHeight
        record["bitcoinBlockTime"] = item.bitcoinBlockTime
        record["bitcoinTxId"] = item.bitcoinTxId
        
        // Upload content file as CKAsset
        if let filename = item.contentFileName, let storage = storageService {
            let fileURL = await storage.contentFileURL(filename: filename)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                record["contentFile"] = CKAsset(fileURL: fileURL)
                record["contentFileName"] = filename
            }
        }
        
        // Upload OTS proof as CKAsset
        if let otsData = item.otsData ?? item.pendingOtsData, let storage = storageService {
            // Save to temp file for upload
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(item.id.uuidString).ots")
            try otsData.write(to: tempURL)
            record["otsFile"] = CKAsset(fileURL: tempURL)
            record["hasConfirmedProof"] = item.otsData != nil
        }
        
        // Save
        try await database.save(record)
        logger.debug("Uploaded item: \(item.id)")
    }
    
    // MARK: - Download
    
    private func downloadRemoteChanges(from database: CKDatabase, context: ModelContext) async throws {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        
        let (results, _) = try await database.records(matching: query)
        
        logger.info("Downloaded \(results.count) records")
        
        for (index, (_, result)) in results.enumerated() {
            syncMessage = "Processing \(index + 1)/\(results.count)..."
            syncProgress = 0.5 + Double(index) / Double(results.count) * 0.5
            
            switch result {
            case .success(let record):
                try await processRemoteRecord(record, context: context)
            case .failure(let error):
                logger.error("Failed to process record: \(error.localizedDescription)")
            }
        }
        
        try context.save()
    }
    
    private func processRemoteRecord(_ record: CKRecord, context: ModelContext) async throws {
        guard let idString = record.recordID.recordName.components(separatedBy: "-").first,
              let _ = UUID(uuidString: record.recordID.recordName) else {
            return
        }
        
        let itemId = UUID(uuidString: record.recordID.recordName)!
        
        // Check if item exists locally
        let descriptor = FetchDescriptor<WitnessItem>(
            predicate: #Predicate { $0.id == itemId }
        )
        let existing = try context.fetch(descriptor).first
        
        // Parse remote data
        guard let contentTypeRaw = record["contentType"] as? String,
              let contentType = ContentType(rawValue: contentTypeRaw),
              let hashBase64 = record["contentHash"] as? String,
              let contentHash = Data(base64Encoded: hashBase64),
              let statusRaw = record["status"] as? String,
              let status = WitnessStatus(rawValue: statusRaw),
              let createdAt = record["createdAt"] as? Date,
              let lastUpdated = record["lastUpdated"] as? Date else {
            logger.warning("Invalid record data for \(record.recordID.recordName)")
            return
        }
        
        let item: WitnessItem
        
        if let existing = existing {
            // Update existing - remote wins if newer
            if lastUpdated > existing.lastUpdated {
                item = existing
            } else {
                // Local is newer, skip
                return
            }
        } else {
            // Create new
            item = WitnessItem(contentType: contentType, contentHash: contentHash)
            item.id = itemId
            item.createdAt = createdAt
            context.insert(item)
        }
        
        // Update fields
        item.title = record["title"] as? String
        item.notes = record["notes"] as? String
        item.textContent = record["textContent"] as? String
        item.status = status
        item.statusMessage = record["statusMessage"] as? String
        item.lastUpdated = lastUpdated
        item.calendarUrl = record["calendarUrl"] as? String
        item.submittedAt = record["submittedAt"] as? Date
        item.confirmedAt = record["confirmedAt"] as? Date
        item.bitcoinBlockHeight = record["bitcoinBlockHeight"] as? Int
        item.bitcoinBlockTime = record["bitcoinBlockTime"] as? Date
        item.bitcoinTxId = record["bitcoinTxId"] as? String
        
        // Download content file
        if let contentAsset = record["contentFile"] as? CKAsset,
           let assetURL = contentAsset.fileURL,
           let filename = record["contentFileName"] as? String,
           let storage = storageService {
            
            let data = try Data(contentsOf: assetURL)
            
            // Save based on content type
            switch contentType {
            case .photo:
                if let image = UIImage(data: data) {
                    item.contentFileName = try await storage.saveImage(image, for: itemId)
                }
            case .text:
                if let text = String(data: data, encoding: .utf8) {
                    item.contentFileName = try await storage.saveText(text, for: itemId)
                }
            case .file:
                item.contentFileName = try await storage.saveFile(data, originalName: filename, for: itemId)
            }
        }
        
        // Download OTS proof
        if let otsAsset = record["otsFile"] as? CKAsset,
           let assetURL = otsAsset.fileURL,
           let storage = storageService {
            
            let otsData = try Data(contentsOf: assetURL)
            let hasConfirmed = record["hasConfirmedProof"] as? Bool ?? false
            
            if hasConfirmed {
                item.otsData = otsData
            } else {
                item.pendingOtsData = otsData
            }
            
            try await storage.saveProof(otsData, for: itemId)
        }
        
        logger.debug("Processed remote item: \(itemId)")
    }
    
    // MARK: - Delete
    
    /// Delete item from cloud
    func deleteFromCloud(_ itemId: UUID) async {
        guard isAvailable, let database = database else { return }
        
        let recordID = CKRecord.ID(recordName: itemId.uuidString)
        
        do {
            try await database.deleteRecord(withID: recordID)
            logger.info("Deleted item from cloud: \(itemId)")
        } catch {
            logger.error("Failed to delete from cloud: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Notifications
    
    /// Handle remote notification
    func handleRemoteNotification() async {
        logger.info("Remote notification received, syncing...")
        await sync()
    }
}

// MARK: - Sync State

enum SyncState: Equatable {
    case checking
    case idle
    case syncing
    case error
    case unavailable
    
    var description: String {
        switch self {
        case .checking: return "Checking..."
        case .idle: return "Synced"
        case .syncing: return "Syncing..."
        case .error: return "Sync Error"
        case .unavailable: return "iCloud Unavailable"
        }
    }
    
    var icon: String {
        switch self {
        case .checking: return "icloud"
        case .idle: return "checkmark.icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .error: return "exclamationmark.icloud"
        case .unavailable: return "icloud.slash"
        }
    }
}

// MARK: - Errors

enum SyncError: Error, LocalizedError {
    case noAccount
    case restricted
    case networkUnavailable
    case quotaExceeded
    
    var errorDescription: String? {
        switch self {
        case .noAccount:
            return "Please sign in to iCloud in Settings"
        case .restricted:
            return "iCloud access is restricted"
        case .networkUnavailable:
            return "Network unavailable"
        case .quotaExceeded:
            return "iCloud storage full"
        }
    }
}
