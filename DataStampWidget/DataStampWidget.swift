import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct DataStampEntry: TimelineEntry {
    let date: Date
    let pendingCount: Int
    let confirmedCount: Int
    let recentItems: [WidgetItem]
}

struct WidgetItem: Identifiable {
    let id: UUID
    let title: String
    let status: String
    let statusColor: Color
    let date: Date
}

// MARK: - Timeline Provider

struct DataStampTimelineProvider: TimelineProvider {
    
    func placeholder(in context: Context) -> DataStampEntry {
        DataStampEntry(
            date: Date(),
            pendingCount: 2,
            confirmedCount: 5,
            recentItems: [
                WidgetItem(id: UUID(), title: "Sample Note", status: "Confirmed", statusColor: .green, date: Date()),
                WidgetItem(id: UUID(), title: "Photo", status: "Pending", statusColor: .orange, date: Date().addingTimeInterval(-3600))
            ]
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (DataStampEntry) -> Void) {
        let entry = loadEntry()
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<DataStampEntry>) -> Void) {
        let entry = loadEntry()
        
        // Update every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func loadEntry() -> DataStampEntry {
        // Load from shared container
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.makiavel.datestamp") else {
            return DataStampEntry(date: Date(), pendingCount: 0, confirmedCount: 0, recentItems: [])
        }
        
        let dataFile = containerURL.appendingPathComponent("widget-data.json")
        
        guard let data = try? Data(contentsOf: dataFile),
              let widgetData = try? JSONDecoder().decode(WidgetData.self, from: data) else {
            return DataStampEntry(date: Date(), pendingCount: 0, confirmedCount: 0, recentItems: [])
        }
        
        let items = widgetData.recentItems.map { item in
            WidgetItem(
                id: UUID(uuidString: item.id) ?? UUID(),
                title: item.title,
                status: item.status,
                statusColor: statusColor(for: item.status),
                date: ISO8601DateFormatter().date(from: item.date) ?? Date()
            )
        }
        
        return DataStampEntry(
            date: Date(),
            pendingCount: widgetData.pendingCount,
            confirmedCount: widgetData.confirmedCount,
            recentItems: items
        )
    }
    
    private func statusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "pending": return .gray
        case "submitted": return .orange
        case "confirmed": return .green
        case "verified": return .blue
        default: return .red
        }
    }
}

// MARK: - Widget Data (from main app)

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

// MARK: - Widget Views

struct DataStampWidgetEntryView: View {
    var entry: DataStampEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }
    
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.orange)
                Text("DataStamp")
                    .font(.headline)
            }
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("\(entry.confirmedCount) confirmed")
                        .font(.caption)
                }
                
                if entry.pendingCount > 0 {
                    HStack {
                        Circle()
                            .fill(.orange)
                            .frame(width: 8, height: 8)
                        Text("\(entry.pendingCount) pending")
                            .font(.caption)
                    }
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
    
    private var mediumView: some View {
        HStack(spacing: 16) {
            // Stats
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.orange)
                    Text("DataStamp")
                        .font(.headline)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("\(entry.confirmedCount)")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("confirmed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Circle()
                            .fill(.orange)
                            .frame(width: 8, height: 8)
                        Text("\(entry.pendingCount)")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("pending")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // Recent items
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if entry.recentItems.isEmpty {
                    Text("No timestamps yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(entry.recentItems.prefix(3)) { item in
                        HStack {
                            Circle()
                                .fill(item.statusColor)
                                .frame(width: 6, height: 6)
                            Text(item.title)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget Configuration

struct DataStampWidget: Widget {
    let kind: String = "DataStampWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DataStampTimelineProvider()) { entry in
            DataStampWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("DataStamp")
        .description("Track your timestamp proofs")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Widget Bundle

@main
struct DataStampWidgetBundle: WidgetBundle {
    var body: some Widget {
        DataStampWidget()
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    DataStampWidget()
} timeline: {
    DataStampEntry(date: Date(), pendingCount: 2, confirmedCount: 5, recentItems: [])
}

#Preview(as: .systemMedium) {
    DataStampWidget()
} timeline: {
    DataStampEntry(
        date: Date(),
        pendingCount: 2,
        confirmedCount: 5,
        recentItems: [
            WidgetItem(id: UUID(), title: "My Note", status: "Confirmed", statusColor: .green, date: Date()),
            WidgetItem(id: UUID(), title: "Photo.jpg", status: "Pending", statusColor: .orange, date: Date())
        ]
    )
}
