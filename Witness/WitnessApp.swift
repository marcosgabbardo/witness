import SwiftUI
import SwiftData
import UserNotifications

@main
struct WitnessApp: App {
    @StateObject private var syncService = CloudKitSyncService()
    
    let container: ModelContainer
    
    init() {
        do {
            let schema = Schema([
                WitnessItem.self
            ])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            container = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(syncService)
                .task {
                    await setupNotifications()
                    await syncService.configure(with: container.mainContext)
                }
        }
        .modelContainer(container)
    }
    
    private func setupNotifications() async {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            print("Notifications authorized: \(granted)")
            
            if granted {
                // Register notification categories for actions
                NotificationService.shared.registerCategories()
            }
        } catch {
            print("Notification auth error: \(error)")
        }
    }
}
