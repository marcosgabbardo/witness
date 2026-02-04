import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var syncService: CloudKitSyncService
    @Query(sort: \DataStampItem.createdAt, order: .reverse) private var items: [DataStampItem]
    
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    
    @State private var datestampManager = DataStampManager()
    @State private var showingCreateSheet = false
    @State private var showingOnboarding = false
    @State private var showingSettings = false
    @State private var showingVerify = false
    @State private var selectedItem: DataStampItem?
    @State private var selectedFilter: ItemFilter = .all
    @State private var searchText = ""
    
    enum ItemFilter: String, CaseIterable {
        case all = "All"
        case pending = "Pending"
        case confirmed = "Confirmed"
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                if items.isEmpty {
                    emptyStateView
                } else {
                    itemListView
                }
                
                // FAB
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        createButton
                            .padding()
                    }
                }
            }
            .navigationTitle("DataStamp")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Text("DataStamp")
                            .font(.headline)
                        
                        if datestampManager.isSyncing {
                            SyncProgressView(
                                progress: datestampManager.syncProgress,
                                total: datestampManager.syncTotal
                            )
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showingVerify = true
                        } label: {
                            Image(systemName: "checkmark.shield")
                        }
                        
                        Menu {
                            ForEach(ItemFilter.allCases, id: \.self) { filter in
                                Button {
                                    selectedFilter = filter
                                } label: {
                                    if selectedFilter == filter {
                                        Label(filter.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(filter.rawValue)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingVerify) {
                VerifyExternalView()
            }
            .refreshable {
                await datestampManager.checkPendingUpgrades(items: items, context: modelContext)
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreateTimestampView(manager: datestampManager)
            }
            .sheet(item: $selectedItem) { item in
                ItemDetailView(item: item, manager: datestampManager)
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(syncService)
            }
            .onAppear {
                if !hasSeenOnboarding {
                    showingOnboarding = true
                }
            }
            .searchable(text: $searchText, prompt: "Search timestamps...")
            .task {
                // Check for upgrades on launch - safely
                await datestampManager.checkPendingUpgrades(items: items, context: modelContext)
            }
            .onChange(of: items) { _, newItems in
                WidgetService.shared.updateWidget(items: newItems)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
            
            Text("No Timestamps Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Create your first timestamp to prove\nsomething existed at a specific time.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                showingCreateSheet = true
            } label: {
                Label("Create Timestamp", systemImage: "plus")
                    .font(.headline)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top)
        }
        .padding()
    }
    
    private var itemListView: some View {
        List {
            ForEach(filteredItems) { item in
                ItemRowCell(item: item, manager: datestampManager)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedItem = item
                    }
            }
            .onDelete(perform: deleteItems)
        }
        .listStyle(.plain)
    }
    
    private var filteredItems: [DataStampItem] {
        var result: [DataStampItem]
        
        // Apply status filter
        switch selectedFilter {
        case .all:
            result = items
        case .pending:
            result = items.filter { $0.status == .pending || $0.status == .submitted }
        case .confirmed:
            result = items.filter { $0.status == .confirmed || $0.status == .verified }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            result = result.filter { item in
                // Search in title
                if let title = item.title, title.lowercased().contains(lowercasedSearch) {
                    return true
                }
                // Search in text content
                if let text = item.textContent, text.lowercased().contains(lowercasedSearch) {
                    return true
                }
                // Search in filename
                if let filename = item.contentFileName, filename.lowercased().contains(lowercasedSearch) {
                    return true
                }
                // Search in notes
                if let notes = item.notes, notes.lowercased().contains(lowercasedSearch) {
                    return true
                }
                // Search in hash (partial match)
                if item.hashHex.lowercased().contains(lowercasedSearch) {
                    return true
                }
                return false
            }
        }
        
        return result
    }
    
    private var createButton: some View {
        Button {
            showingCreateSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(radius: 4, y: 2)
        }
    }
    
    // MARK: - Actions
    
    private func deleteItems(offsets: IndexSet) {
        Task {
            for index in offsets {
                let item = filteredItems[index]
                await datestampManager.deleteItem(item, context: modelContext)
            }
        }
    }
}

// MARK: - Item Row Cell

struct ItemRowCell: View {
    let item: DataStampItem
    let manager: DataStampManager
    
    @State private var thumbnail: UIImage?
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail or icon
            thumbnailView
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Image(systemName: item.statusIcon)
                        .foregroundStyle(statusColor)
                        .font(.caption)
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Date
            VStack(alignment: .trailing, spacing: 4) {
                Text(item.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(item.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .task {
            if item.contentType == .photo {
                thumbnail = await manager.loadThumbnail(for: item)
            }
        }
    }
    
    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.2))
                .overlay {
                    Image(systemName: iconForType)
                        .foregroundStyle(.secondary)
                }
        }
    }
    
    private var iconForType: String {
        switch item.contentType {
        case .text: return "doc.text"
        case .photo: return "photo"
        case .file: return "doc"
        }
    }
    
    private var statusColor: Color {
        switch item.status {
        case .pending: return .gray
        case .submitted: return .orange
        case .confirmed: return .green
        case .verified: return .blue
        case .failed: return .red
        }
    }
    
    private var statusText: String {
        switch item.status {
        case .pending: return "Pending"
        case .submitted: return "Submitted"
        case .confirmed: return "Confirmed"
        case .verified: return "Verified"
        case .failed: return item.statusMessage ?? "Failed"
        }
    }
}

// MARK: - Sync Progress View

struct SyncProgressView: View {
    let progress: Int
    let total: Int
    
    private var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(progress) / Double(total)
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Circular progress indicator
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                    .frame(width: 16, height: 16)
                
                Circle()
                    .trim(from: 0, to: percentage)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: percentage)
            }
            
            Text("\(progress)/\(total)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }
}

#Preview {
    ContentView()
        .environmentObject(CloudKitSyncService())
        .modelContainer(for: DataStampItem.self, inMemory: true)
}

#Preview("Sync Progress") {
    VStack(spacing: 20) {
        SyncProgressView(progress: 1, total: 5)
        SyncProgressView(progress: 3, total: 5)
        SyncProgressView(progress: 5, total: 5)
    }
    .padding()
}
