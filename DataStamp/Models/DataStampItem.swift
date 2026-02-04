import Foundation
import SwiftData
import SwiftUI

// MARK: - Folder Model

/// Folder for organizing timestamps
@Model
final class Folder {
    var id: UUID
    var name: String
    var icon: String
    var colorHex: String
    var createdAt: Date
    var sortOrder: Int
    
    @Relationship(deleteRule: .nullify, inverse: \DataStampItem.folder)
    var items: [DataStampItem]?
    
    init(name: String, icon: String = "folder.fill", colorHex: String = "F7931A", sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.createdAt = Date()
        self.sortOrder = sortOrder
    }
    
    var color: Color {
        Color(hex: colorHex) ?? .orange
    }
    
    var itemCount: Int {
        items?.count ?? 0
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
    
    var hexString: String {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return "F7931A"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

// MARK: - Predefined Tags

enum PredefinedTag: String, CaseIterable {
    case important = "Important"
    case work = "Work"
    case personal = "Personal"
    case legal = "Legal"
    case financial = "Financial"
    case creative = "Creative"
    case archive = "Archive"
    
    var icon: String {
        switch self {
        case .important: return "star.fill"
        case .work: return "briefcase.fill"
        case .personal: return "person.fill"
        case .legal: return "building.columns.fill"
        case .financial: return "dollarsign.circle.fill"
        case .creative: return "paintbrush.fill"
        case .archive: return "archivebox.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .important: return .yellow
        case .work: return .blue
        case .personal: return .green
        case .legal: return .purple
        case .financial: return .mint
        case .creative: return .pink
        case .archive: return .gray
        }
    }
}

/// Status of a timestamp in the OpenTimestamps workflow
enum DataStampStatus: String, Codable {
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
final class DataStampItem {
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
    
    // MARK: - Organization
    var tags: [String] = []
    var folder: Folder?
    
    // MARK: - Status
    var status: DataStampStatus
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
    var confirmedAt: Date?
    
    init(
        contentType: ContentType,
        contentHash: Data,
        title: String? = nil,
        textContent: String? = nil,
        contentFileName: String? = nil,
        tags: [String] = [],
        folder: Folder? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.contentType = contentType
        self.contentHash = contentHash
        self.title = title
        self.textContent = textContent
        self.contentFileName = contentFileName
        self.tags = tags
        self.folder = folder
        self.status = .pending
        self.lastUpdated = Date()
    }
}

// MARK: - Computed Properties
extension DataStampItem {
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
