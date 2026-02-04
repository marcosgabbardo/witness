import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WitnessItem.createdAt, order: .reverse) private var items: [WitnessItem]
    
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    
    @State private var witnessManager = WitnessManager()
    @State private var showingCreateSheet = false
    @State private var showingOnboarding = false
    @State private var selectedItem: WitnessItem?
    @State private var selectedFilter: ItemFilter = .all
    
    enum ItemFilter: String, CaseIterable {
        case all = "All"
        case pending = "Pending"
        case confirmed = "Confirmed"
    }
    
    var filteredItems: [WitnessItem] {
        switch selectedFilter {
        case .all:
            return items
        case .pending:
            return items.filter { $0.status == .pending || $0.status == .submitted }
        case .confirmed:
            return items.filter { $0.status == .confirmed || $0.status == .verified }
        }
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
            .navigationTitle("Witness")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
            .sheet(isPresented: $showingCreateSheet) {
                CreateTimestampView(manager: witnessManager)
            }
            .sheet(item: $selectedItem) { item in
                ItemDetailView(item: item, manager: witnessManager)
            }
            .task {
                // Check for upgrades on launch
                await witnessManager.checkPendingUpgrades(items: items, context: modelContext)
            }
            .refreshable {
                await witnessManager.checkPendingUpgrades(items: items, context: modelContext)
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingView()
            }
            .onAppear {
                if !hasSeenOnboarding {
                    showingOnboarding = true
                }
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
                ItemRowCell(item: item, manager: witnessManager)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedItem = item
                    }
            }
            .onDelete(perform: deleteItems)
        }
        .listStyle(.plain)
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
                await witnessManager.deleteItem(item, context: modelContext)
            }
        }
    }
}

// MARK: - Item Row Cell

struct ItemRowCell: View {
    let item: WitnessItem
    let manager: WitnessManager
    
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

#Preview {
    ContentView()
        .modelContainer(for: WitnessItem.self, inMemory: true)
}
