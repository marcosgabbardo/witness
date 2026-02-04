import UIKit

/// Centralized haptic feedback manager
@MainActor
final class HapticManager {
    
    static let shared = HapticManager()
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()
    
    private init() {
        // Prepare generators
        impactLight.prepare()
        impactMedium.prepare()
        notification.prepare()
        selection.prepare()
    }
    
    // MARK: - Impact
    
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        switch style {
        case .light:
            impactLight.impactOccurred()
        case .medium:
            impactMedium.impactOccurred()
        case .heavy:
            impactHeavy.impactOccurred()
        case .soft:
            impactLight.impactOccurred(intensity: 0.5)
        case .rigid:
            impactHeavy.impactOccurred(intensity: 0.8)
        @unknown default:
            impactMedium.impactOccurred()
        }
    }
    
    // MARK: - Notification
    
    func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notification.notificationOccurred(type)
    }
    
    /// Success feedback - use when timestamp is confirmed
    func success() {
        notification.notificationOccurred(.success)
    }
    
    /// Warning feedback - use for pending states
    func warning() {
        notification.notificationOccurred(.warning)
    }
    
    /// Error feedback - use when something fails
    func error() {
        notification.notificationOccurred(.error)
    }
    
    // MARK: - Selection
    
    func selectionChanged() {
        selection.selectionChanged()
    }
    
    // MARK: - Compound Patterns
    
    /// Timestamp created pattern
    func timestampCreated() {
        impact(.medium)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.success()
        }
    }
    
    /// Timestamp confirmed pattern (celebratory)
    func timestampConfirmed() {
        success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.impact(.heavy)
        }
    }
    
    /// Button tap
    func buttonTap() {
        impact(.light)
    }
    
    /// Pull to refresh
    func refresh() {
        impact(.medium)
    }
}
