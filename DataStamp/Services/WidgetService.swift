import Foundation
import WidgetKit
import SwiftData

/// Service to update widget data from main app
@MainActor
final class WidgetService {
    
    static let shared = WidgetService()
    
    private let containerURL: URL?
    
    private init() {
        containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.makiavel.datestamp")
    }
    
    /// Update widget with current data
    func updateWidget(items: [DataStampItem]) {
        guard let containerURL = containerURL else { return }
        
        let pendingCount = items.filter { $0.status == .pending || $0.status == .submitted }.count
        let confirmedCount = items.filter { $0.status == .confirmed || $0.status == .verified }.count
        
        let recentItems = items.prefix(5).map { item in
            WidgetItemData(
                id: item.id.uuidString,
                title: item.displayTitle,
                status: item.status.rawValue.capitalized,
                date: ISO8601DateFormatter().string(from: item.createdAt)
            )
        }
        
        let widgetData = WidgetData(
            pendingCount: pendingCount,
            confirmedCount: confirmedCount,
            recentItems: Array(recentItems)
        )
        
        let dataFile = containerURL.appendingPathComponent("widget-data.json")
        
        do {
            let data = try JSONEncoder().encode(widgetData)
            try data.write(to: dataFile)
            
            // Trigger widget refresh
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("Failed to update widget: \(error)")
        }
    }
}

// MARK: - Shared Data Types

struct WidgetData: Codable {
    let pendingCount: Int
    let confirmedCount: Int
    let recentItems: [WidgetItemData]
}

struct WidgetItemData: Codable {
    let id: String
    let title: String
    let status: String
    let date: String
}
