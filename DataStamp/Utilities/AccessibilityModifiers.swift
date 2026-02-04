import SwiftUI

// MARK: - Accessibility Extensions

extension View {
    /// Add standard accessibility for timestamp items
    func timestampAccessibility(
        title: String,
        status: String,
        date: Date
    ) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(status)")
            .accessibilityHint("Timestamp created \(date.formatted(date: .abbreviated, time: .shortened))")
    }
    
    /// Add accessibility for status badge
    func statusBadgeAccessibility(status: String) -> some View {
        self
            .accessibilityLabel("Status: \(status)")
    }
    
    /// Add accessibility for action buttons
    func actionButtonAccessibility(action: String, item: String? = nil) -> some View {
        if let item = item {
            return self.accessibilityLabel("\(action) \(item)")
                .accessibilityAddTraits(.isButton)
        } else {
            return self.accessibilityLabel(action)
                .accessibilityAddTraits(.isButton)
        }
    }
}

// MARK: - Accessibility Labels

enum A11yLabel {
    // Buttons
    static let createTimestamp = "Create new timestamp"
    static let settings = "Settings"
    static let filter = "Filter timestamps"
    static let share = "Share proof"
    static let verify = "Verify proof"
    static let delete = "Delete timestamp"
    
    // Status
    static func status(_ status: String) -> String {
        "Status: \(status)"
    }
    
    // Content types
    static let textNote = "Text note"
    static let photo = "Photo"
    static let file = "File"
    
    // Actions
    static let selectPhoto = "Select photo from library"
    static let takePhoto = "Take photo with camera"
    static let selectFile = "Select file"
    
    // Bitcoin
    static func bitcoinBlock(_ height: Int) -> String {
        "Anchored in Bitcoin block number \(height)"
    }
}
