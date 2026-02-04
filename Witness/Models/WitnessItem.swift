import Foundation
import SwiftData

/// Status of a timestamp in the OpenTimestamps workflow
enum WitnessStatus: String, Codable {
    case pending        // Hash computed, not yet sent
    case submitted      // Sent to calendar, awaiting aggregation
    case confirmed      // Anchored in Bitcoin blockchain
    case verified       // Local verification passed
    case failed         // Something went wrong
}

/// Type of content being timestamped
enum ContentType: String, Codable {
    case text
    case photo
    case file
}

/// Main model representing a timestamped item
@Model
final class WitnessItem {
    // MARK: - Identity
    var id: UUID
    var createdAt: Date
    
    // MARK: - Content
    var contentType: ContentType
    var contentHash: Data          // SHA256 hash
    var contentFileName: String?   // Stored file name (for photos/files)
    var textContent: String?       // For text type
    
    // MARK: - Metadata
    var title: String?
    var notes: String?
    
    // MARK: - Status
    var status: WitnessStatus
    var statusMessage: String?
    var lastUpdated: Date
    
    // MARK: - OpenTimestamps Proof
    var otsData: Data?             // .ots file content
    var pendingOtsData: Data?      // Incomplete .ots before Bitcoin confirmation
    
    // MARK: - Bitcoin Info (populated after confirmation)
    var bitcoinBlockHeight: Int?
    var bitcoinBlockTime: Date?
    var bitcoinTxId: String?
    
    // MARK: - Calendar Info
    var calendarUrl: String?
    var submittedAt: Date?
    
    init(
        contentType: ContentType,
        contentHash: Data,
        title: String? = nil,
        textContent: String? = nil,
        contentFileName: String? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.contentType = contentType
        self.contentHash = contentHash
        self.title = title
        self.textContent = textContent
        self.contentFileName = contentFileName
        self.status = .pending
        self.lastUpdated = Date()
    }
}

// MARK: - Computed Properties
extension WitnessItem {
    var hashHex: String {
        contentHash.map { String(format: "%02x", $0) }.joined()
    }
    
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        switch contentType {
        case .text:
            if let text = textContent {
                return String(text.prefix(50)) + (text.count > 50 ? "..." : "")
            }
            return "Text Note"
        case .photo:
            return "Photo"
        case .file:
            return contentFileName ?? "File"
        }
    }
    
    var statusIcon: String {
        switch status {
        case .pending: return "clock"
        case .submitted: return "arrow.up.circle"
        case .confirmed: return "checkmark.seal.fill"
        case .verified: return "checkmark.shield.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
    
    var statusColor: String {
        switch status {
        case .pending: return "gray"
        case .submitted: return "orange"
        case .confirmed: return "green"
        case .verified: return "blue"
        case .failed: return "red"
        }
    }
    
    var isConfirmed: Bool {
        status == .confirmed || status == .verified
    }
}
