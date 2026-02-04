import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var syncService: CloudKitSyncService
    @Query(sort: \DataStampItem.createdAt, order: .reverse) private var items: [DataStampItem]
    
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    
    @State private var datestampManager = DataStampManager()
    @State private var showingCreateSheet = false
    @State private var showingBatchSheet = false
    @State private var showingOnboarding = false
    @State private var showingSettings = false
    @State private var showingVerify = false
    @State private var showingFolders = false
    @State private var selectedItem: DataStampItem?
    @State private var selectedFilter: ItemFilter = .all
    @State private var selectedFolder: Folder?
    @State private var selectedTag: String?
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
                    HStack(spacing: 12) {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        
                        Button {
                            showingFolders = true
                        } label: {
                            Image(systemName: selectedFolder != nil ? "folder.fill" : "folder")
                        }
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
            .sheet(isPresented: $showingBatchSheet) {
                BatchTimestampView(manager: datestampManager)
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
            .sheet(isPresented: $showingFolders) {
                FolderListView(selectedFolder: selectedFolder) { folder in
                    selectedFolder = folder
                }
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
            
            VStack(spacing: 12) {
                Button {
                    showingCreateSheet = true
                } label: {
                    Label("Create Timestamp", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                Button {
                    showingBatchSheet = true
                } label: {
                    Label("Batch Timestamp", systemImage: "square.stack.3d.up")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.top)
            .frame(maxWidth: 250)
        }
        .padding()
    }
    
    private var itemListView: some View {
        List {
            // Active filters section
            if selectedFolder != nil || selectedTag != nil {
                Section {
                    HStack {
                        if let folder = selectedFolder {
                            FilterChip(
                                icon: folder.icon,
                                label: folder.name,
                                color: folder.color
                            ) {
                                selectedFolder = nil
                            }
                        }
                        
                        if let tag = selectedTag {
                            FilterChip(
                                icon: "tag.fill",
                                label: tag,
                                color: .orange
                            ) {
                                selectedTag = nil
                            }
                        }
                        
                        Spacer()
                        
                        Button("Clear All") {
                            selectedFolder = nil
                            selectedTag = nil
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Tags filter row
            if !allTags.isEmpty && selectedTag == nil {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(allTags, id: \.self) { tag in
                                Button {
                                    selectedTag = tag
                                } label: {
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.secondary.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }
            
            // Items
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
        
        // Apply folder filter
        if let folder = selectedFolder {
            result = result.filter { $0.folder?.id == folder.id }
        }
        
        // Apply tag filter
        if let tag = selectedTag {
            result = result.filter { $0.tags.contains(tag) }
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
                // Search in tags
                if item.tags.contains(where: { $0.lowercased().contains(lowercasedSearch) }) {
                    return true
                }
                return false
            }
        }
        
        return result
    }
    
    private var allTags: [String] {
        Array(Set(items.flatMap { $0.tags })).sorted()
    }
    
    private var createButton: some View {
        Menu {
            Button {
                showingCreateSheet = true
            } label: {
                Label("Single Timestamp", systemImage: "plus")
            }
            
            Button {
                showingBatchSheet = true
            } label: {
                Label("Batch Timestamp", systemImage: "square.stack.3d.up")
            }
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

// MARK: - Filter Chip

struct FilterChip: View {
    let icon: String
    let label: String
    let color: Color
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(label)
                .font(.caption)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
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
                    
                    if let folder = item.folder {
                        Image(systemName: folder.icon)
                            .font(.caption2)
                            .foregroundStyle(folder.color)
                    }
                }
                
                // Tags
                if !item.tags.isEmpty {
                    InlineTagsView(tags: item.tags, maxVisible: 2)
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
