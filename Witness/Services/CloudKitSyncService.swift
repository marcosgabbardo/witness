import Foundation
import SwiftData
import os.log

// CloudKit import only when available
#if canImport(CloudKit)
import CloudKit
#endif

/// CloudKit sync service for Witness items
/// Safely handles missing iCloud entitlements
@MainActor
final class CloudKitSyncService: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var syncState: SyncState = .unavailable
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var pendingChanges: Int = 0
    @Published private(set) var error: Error?
    @Published private(set) var isAvailable: Bool = false
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.makiavel.witness", category: "CloudSync")
    private var modelContext: ModelContext?
    
    // MARK: - Initialization
    
    init() {
        // Don't touch CloudKit here - it will crash without entitlements
        logger.info("CloudKitSyncService initialized (inactive)")
    }
    
    // MARK: - Public API
    
    /// Configure the sync service with a model context
    /// This is a no-op until iCloud entitlements are configured
    func configure(with modelContext: ModelContext) async {
        self.modelContext = modelContext
        
        // For now, iCloud sync is disabled until entitlements are configured
        // in Apple Developer Portal
        logger.info("CloudKit sync disabled - entitlements not configured")
        self.syncState = .unavailable
        self.isAvailable = false
        
        // To enable CloudKit:
        // 1. Go to Apple Developer Portal
        // 2. Add iCloud capability to your App ID
        // 3. Create iCloud container: iCloud.com.makiavel.witness
        // 4. Uncomment the iCloud entitlements in Witness.entitlements
        // 5. Uncomment the code in this file
    }
    
    /// Trigger a manual sync (no-op when unavailable)
    func sync() async {
        guard isAvailable else {
            logger.info("Sync skipped - CloudKit not available")
            return
        }
        // Sync implementation would go here when enabled
    }
    
    /// Mark an item as needing sync
    func markForSync(_ item: WitnessItem) {
        guard isAvailable else { return }
        pendingChanges += 1
    }
    
    /// Mark an item as deleted
    func markDeleted(_ itemId: UUID) {
        guard isAvailable else { return }
        pendingChanges += 1
    }
}

// MARK: - Sync State

enum SyncState: Equatable {
    case idle
    case syncing
    case error
    case unavailable
    
    var description: String {
        switch self {
        case .idle: return "Synced"
        case .syncing: return "Syncing..."
        case .error: return "Sync Error"
        case .unavailable: return "Not Configured"
        }
    }
    
    var icon: String {
        switch self {
        case .idle: return "checkmark.icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .error: return "exclamationmark.icloud"
        case .unavailable: return "icloud.slash"
        }
    }
}
