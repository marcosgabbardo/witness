import AppIntents
import SwiftUI
import SwiftData

// MARK: - Shared Container

@MainActor
enum DataStampIntentContainer {
    static let shared: ModelContainer = {
        do {
            let schema = Schema([DataStampItem.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}

// MARK: - Timestamp Text Intent

struct TimestampTextIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Timestamp Text"
    nonisolated static let description = IntentDescription("Create a timestamp proof for text content")
    
    @Parameter(title: "Text Content")
    var text: String
    
    @Parameter(title: "Title")
    var title: String?
    
    static var parameterSummary: some ParameterSummary {
        Summary("Timestamp \(\.$text)") {
            \.$title
        }
    }
    
    nonisolated static let openAppWhenRun: Bool = false
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = DataStampIntentContainer.shared
        let manager = DataStampManager()
        
        do {
            let item = try await manager.createTextTimestamp(
                text: text,
                title: title,
                context: container.mainContext
            )
            
            return .result(dialog: "✓ Timestamp created for '\(item.displayTitle)'. It will be confirmed in the Bitcoin blockchain within 24 hours.")
        } catch {
            return .result(dialog: "Failed to create timestamp: \(error.localizedDescription)")
        }
    }
}

// MARK: - Get Pending Count Intent

struct GetPendingCountIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Get Pending Timestamps"
    nonisolated static let description = IntentDescription("Get the count of timestamps waiting for confirmation")
    
    nonisolated static let openAppWhenRun: Bool = false
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let container = DataStampIntentContainer.shared
        
        // Fetch all items and filter in memory (simpler than complex predicates)
        let descriptor = FetchDescriptor<DataStampItem>()
        let allItems = (try? container.mainContext.fetch(descriptor)) ?? []
        let count = allItems.filter { $0.status == .submitted || $0.status == .pending }.count
        
        if count == 0 {
            return .result(value: count, dialog: "All timestamps are confirmed! ✓")
        } else if count == 1 {
            return .result(value: count, dialog: "You have 1 timestamp waiting for confirmation.")
        } else {
            return .result(value: count, dialog: "You have \(count) timestamps waiting for confirmation.")
        }
    }
}

// MARK: - Get Confirmed Count Intent

struct GetConfirmedCountIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Get Confirmed Timestamps"
    nonisolated static let description = IntentDescription("Get the count of confirmed timestamps")
    
    nonisolated static let openAppWhenRun: Bool = false
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let container = DataStampIntentContainer.shared
        
        // Fetch all items and filter in memory
        let descriptor = FetchDescriptor<DataStampItem>()
        let allItems = (try? container.mainContext.fetch(descriptor)) ?? []
        let count = allItems.filter { $0.status == .confirmed || $0.status == .verified }.count
        
        return .result(value: count, dialog: "You have \(count) confirmed timestamps.")
    }
}

// MARK: - Open App Intent

struct OpenDataStampIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Open DataStamp"
    nonisolated static let description = IntentDescription("Open the DataStamp app")
    
    nonisolated static let openAppWhenRun: Bool = true
    
    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - App Shortcuts Provider

struct DataStampShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TimestampTextIntent(),
            phrases: [
                "Timestamp text in \(.applicationName)",
                "Create timestamp in \(.applicationName)",
                "DataStamp text in \(.applicationName)",
                "Prove text in \(.applicationName)"
            ],
            shortTitle: "Timestamp Text",
            systemImageName: "checkmark.seal"
        )
        
        AppShortcut(
            intent: GetPendingCountIntent(),
            phrases: [
                "How many pending in \(.applicationName)",
                "Check pending in \(.applicationName)",
                "Pending count in \(.applicationName)"
            ],
            shortTitle: "Pending Count",
            systemImageName: "clock"
        )
        
        AppShortcut(
            intent: GetConfirmedCountIntent(),
            phrases: [
                "How many confirmed in \(.applicationName)",
                "Check confirmed in \(.applicationName)",
                "Confirmed count in \(.applicationName)"
            ],
            shortTitle: "Confirmed Count",
            systemImageName: "checkmark.circle"
        )
        
        AppShortcut(
            intent: OpenDataStampIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Show \(.applicationName)"
            ],
            shortTitle: "Open App",
            systemImageName: "app"
        )
    }
}
