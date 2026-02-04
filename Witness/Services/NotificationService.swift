import Foundation
import UserNotifications

/// Manages local notifications for timestamp confirmations
actor NotificationService {
    
    // MARK: - Singleton
    
    static let shared = NotificationService()
    
    // MARK: - Properties
    
    private var isAuthorized = false
    
    // MARK: - Authorization
    
    /// Request notification permission
    func requestAuthorization() async -> Bool {
        do {
            let center = UNUserNotificationCenter.current()
            isAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return isAuthorized
        } catch {
            return false
        }
    }
    
    /// Check current authorization status
    func checkAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
        return isAuthorized
    }
    
    // MARK: - Notifications
    
    /// Schedule notification for when a timestamp is confirmed
    func notifyConfirmation(title: String, itemId: UUID, blockHeight: Int?) async {
        guard await checkAuthorization() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Timestamp Confirmed ✓"
        content.body = "'\(title)' is now anchored in the Bitcoin blockchain"
        content.sound = .default
        content.categoryIdentifier = "TIMESTAMP_CONFIRMED"
        content.userInfo = ["itemId": itemId.uuidString]
        
        // Add Bitcoin block info if available
        if let blockHeight = blockHeight {
            content.subtitle = "Block #\(blockHeight)"
        }
        
        // Send immediately
        let request = UNNotificationRequest(
            identifier: "confirmation-\(itemId.uuidString)",
            content: content,
            trigger: nil
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to schedule notification: \(error)")
        }
    }
    
    /// Schedule notification to remind checking pending timestamps
    func scheduleCheckReminder(in hours: Int = 24) async {
        guard await checkAuthorization() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Pending Timestamps"
        content.body = "You have timestamps waiting for Bitcoin confirmation. Tap to check status."
        content.sound = .default
        content.categoryIdentifier = "CHECK_PENDING"
        
        // Schedule for N hours from now
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(hours * 3600),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "check-pending",
            content: content,
            trigger: trigger
        )
        
        do {
            // Remove existing reminder first
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["check-pending"])
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to schedule reminder: \(error)")
        }
    }
    
    /// Cancel pending check reminder (e.g., when all timestamps confirmed)
    func cancelCheckReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["check-pending"])
    }
    
    // MARK: - Categories
    
    /// Register notification categories and actions
    nonisolated func registerCategories() {
        let viewAction = UNNotificationAction(
            identifier: "VIEW_ACTION",
            title: "View Details",
            options: [.foreground]
        )
        
        let shareAction = UNNotificationAction(
            identifier: "SHARE_ACTION",
            title: "Share Proof",
            options: [.foreground]
        )
        
        let confirmationCategory = UNNotificationCategory(
            identifier: "TIMESTAMP_CONFIRMED",
            actions: [viewAction, shareAction],
            intentIdentifiers: [],
            options: []
        )
        
        let checkAction = UNNotificationAction(
            identifier: "CHECK_ACTION",
            title: "Check Now",
            options: [.foreground]
        )
        
        let pendingCategory = UNNotificationCategory(
            identifier: "CHECK_PENDING",
            actions: [checkAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([
            confirmationCategory,
            pendingCategory
        ])
    }
    
    // MARK: - Badge
    
    /// Update app badge with pending count
    @MainActor
    func updateBadge(pendingCount: Int) {
        UNUserNotificationCenter.current().setBadgeCount(pendingCount)
    }
}
