import SwiftUI
import SwiftData
import PhotosUI

/// View for creating timestamps for multiple files/photos at once
struct BatchTimestampView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let manager: DataStampManager
    
    // MARK: - State
    @State private var selectedTab: BatchTab = .photos
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var loadedImages: [LoadedImage] = []
    @State private var selectedFiles: [SelectedFile] = []
    @State private var isLoadingImages = false
    @State private var isProcessing = false
    @State private var processedCount = 0
    @State private var totalCount = 0
    @State private var currentItemName = ""
    @State private var results: [BatchResult] = []
    @State private var showingResults = false
    @State private var showingFilePicker = false
    @State private var error: String?
    
    // MARK: - Models
    
    struct LoadedImage: Identifiable {
        let id = UUID()
        let image: UIImage
        let photoItem: PhotosPickerItem
        var title: String
        var isSelected: Bool = true
    }
    
    struct SelectedFile: Identifiable {
        let id = UUID()
        let data: Data
        let filename: String
        var title: String
        var isSelected: Bool = true
    }
    
    struct BatchResult: Identifiable {
        let id = UUID()
        let name: String
        let success: Bool
        let error: String?
    }
    
    enum BatchTab: String, CaseIterable {
        case photos = "Photos"
        case files = "Files"
        
        var icon: String {
            switch self {
            case .photos: return "photo.on.rectangle.angled"
            case .files: return "doc.on.doc"
            }
        }
    }
    
    // MARK: - Computed
    
    private var selectedItemsCount: Int {
        switch selectedTab {
        case .photos:
            return loadedImages.filter(\.isSelected).count
        case .files:
            return selectedFiles.filter(\.isSelected).count
        }
    }
    
    private var canProcess: Bool {
        selectedItemsCount > 0 && !isProcessing
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                Picker("Type", selection: $selectedTab) {
                    ForEach(BatchTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                Divider()
                
                // Content
                if isProcessing {
                    processingView
                } else if showingResults {
                    resultsView
                } else {
                    selectionView
                }
            }
            .navigationTitle("Batch Timestamp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                Task {
                    await loadImages(from: newItems)
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleFileSelection(result)
            }
        }
    }
    
    // MARK: - Selection View
    
    @ViewBuilder
    private var selectionView: some View {
        VStack(spacing: 0) {
            switch selectedTab {
            case .photos:
                photosSelectionView
            case .files:
                filesSelectionView
            }
            
            Divider()
            
            // Process button
            VStack(spacing: 12) {
                if selectedItemsCount > 0 {
                    Text("\(selectedItemsCount) items selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Button {
                    Task {
                        await processItems()
                    }
                } label: {
                    HStack {
                        Image(systemName: "bolt.fill")
                        Text("Timestamp \(selectedItemsCount) Items")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!canProcess)
            }
            .padding()
        }
    }
    
    // MARK: - Photos Selection
    
    @ViewBuilder
    private var photosSelectionView: some View {
        VStack(spacing: 16) {
            // Photo picker
            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: 50,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HStack {
                    Image(systemName: "photo.badge.plus")
                    Text(loadedImages.isEmpty ? "Select Photos" : "Add More Photos")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
            .padding(.top)
            
            if isLoadingImages {
                ProgressView("Loading photos...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loadedImages.isEmpty {
                ContentUnavailableView(
                    "No Photos Selected",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Select multiple photos to timestamp them all at once")
                )
            } else {
                // Photo grid
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                        ForEach($loadedImages) { $item in
                            PhotoItemView(item: $item) {
                                if let index = loadedImages.firstIndex(where: { $0.id == item.id }) {
                                    loadedImages.remove(at: index)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Files Selection
    
    @ViewBuilder
    private var filesSelectionView: some View {
        VStack(spacing: 16) {
            // File picker button
            Button {
                showingFilePicker = true
            } label: {
                HStack {
                    Image(systemName: "doc.badge.plus")
                    Text(selectedFiles.isEmpty ? "Select Files" : "Add More Files")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
            .padding(.top)
            
            if selectedFiles.isEmpty {
                ContentUnavailableView(
                    "No Files Selected",
                    systemImage: "doc.on.doc",
                    description: Text("Select multiple files to timestamp them all at once")
                )
            } else {
                // File list
                List {
                    ForEach($selectedFiles) { $file in
                        FileItemRow(file: $file)
                    }
                    .onDelete { indexSet in
                        selectedFiles.remove(atOffsets: indexSet)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    // MARK: - Processing View
    
    @ViewBuilder
    private var processingView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ProgressView(value: Double(processedCount), total: Double(totalCount))
                .progressViewStyle(.linear)
                .padding(.horizontal, 40)
            
            VStack(spacing: 8) {
                Text("Processing \(processedCount)/\(totalCount)")
                    .font(.headline)
                
                Text(currentItemName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Results View
    
    @ViewBuilder
    private var resultsView: some View {
        VStack(spacing: 0) {
            // Summary
            let successCount = results.filter(\.success).count
            let failCount = results.count - successCount
            
            VStack(spacing: 12) {
                Image(systemName: failCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(failCount == 0 ? .green : .orange)
                
                Text(failCount == 0 ? "All Done!" : "Completed with Issues")
                    .font(.title2.bold())
                
                HStack(spacing: 20) {
                    Label("\(successCount) succeeded", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                    
                    if failCount > 0 {
                        Label("\(failCount) failed", systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                    }
                }
                .font(.subheadline)
            }
            .padding(.vertical, 24)
            
            Divider()
            
            // Results list
            List(results) { result in
                HStack {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.success ? .green : .red)
                    
                    VStack(alignment: .leading) {
                        Text(result.name)
                            .lineLimit(1)
                        
                        if let error = result.error {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .listStyle(.plain)
            
            Divider()
            
            // Done button
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .padding()
        }
    }
    
    // MARK: - Actions
    
    private func loadImages(from items: [PhotosPickerItem]) async {
        isLoadingImages = true
        defer { isLoadingImages = false }
        
        var newImages: [LoadedImage] = []
        
        for item in items {
            // Skip if already loaded
            if loadedImages.contains(where: { $0.photoItem == item }) {
                continue
            }
            
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                let loadedImage = LoadedImage(
                    image: image,
                    photoItem: item,
                    title: ""
                )
                newImages.append(loadedImage)
            }
        }
        
        // Keep existing + add new
        let existingItems = loadedImages.filter { existing in
            items.contains { $0 == existing.photoItem }
        }
        loadedImages = existingItems + newImages
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                
                if let data = try? Data(contentsOf: url) {
                    let file = SelectedFile(
                        data: data,
                        filename: url.lastPathComponent,
                        title: ""
                    )
                    selectedFiles.append(file)
                }
            }
        case .failure(let error):
            self.error = error.localizedDescription
        }
    }
    
    private func processItems() async {
        isProcessing = true
        results = []
        
        switch selectedTab {
        case .photos:
            let itemsToProcess = loadedImages.filter(\.isSelected)
            totalCount = itemsToProcess.count
            processedCount = 0
            
            for item in itemsToProcess {
                currentItemName = item.title.isEmpty ? "Photo \(processedCount + 1)" : item.title
                
                do {
                    _ = try await manager.createPhotoTimestamp(
                        image: item.image,
                        title: item.title.isEmpty ? nil : item.title,
                        context: modelContext
                    )
                    results.append(BatchResult(name: currentItemName, success: true, error: nil))
                } catch {
                    results.append(BatchResult(name: currentItemName, success: false, error: error.localizedDescription))
                }
                
                processedCount += 1
            }
            
        case .files:
            let itemsToProcess = selectedFiles.filter(\.isSelected)
            totalCount = itemsToProcess.count
            processedCount = 0
            
            for item in itemsToProcess {
                currentItemName = item.title.isEmpty ? item.filename : item.title
                
                do {
                    _ = try await manager.createFileTimestamp(
                        data: item.data,
                        filename: item.filename,
                        title: item.title.isEmpty ? nil : item.title,
                        context: modelContext
                    )
                    results.append(BatchResult(name: currentItemName, success: true, error: nil))
                } catch {
                    results.append(BatchResult(name: currentItemName, success: false, error: error.localizedDescription))
                }
                
                processedCount += 1
            }
        }
        
        isProcessing = false
        showingResults = true
        HapticManager.shared.success()
    }
}

// MARK: - Photo Item View

struct PhotoItemView: View {
    @Binding var item: BatchTimestampView.LoadedImage
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: item.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(item.isSelected ? Color.orange : Color.clear, lineWidth: 3)
                    )
                    .opacity(item.isSelected ? 1.0 : 0.5)
                
                // Selection toggle
                Button {
                    item.isSelected.toggle()
                } label: {
                    Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(item.isSelected ? .orange : .gray)
                        .background(Circle().fill(.white).padding(2))
                }
                .offset(x: 4, y: -4)
                
                // Delete button
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, .red)
                }
                .offset(x: 4, y: 80)
            }
        }
    }
}

// MARK: - File Item Row

struct FileItemRow: View {
    @Binding var file: BatchTimestampView.SelectedFile
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection toggle
            Button {
                file.isSelected.toggle()
            } label: {
                Image(systemName: file.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(file.isSelected ? .orange : .gray)
            }
            .buttonStyle(.plain)
            
            // File icon
            Image(systemName: iconForFile(file.filename))
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 32)
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename)
                    .lineLimit(1)
                
                Text(formatFileSize(file.data.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .opacity(file.isSelected ? 1.0 : 0.5)
    }
    
    private func iconForFile(_ filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "jpg", "jpeg", "png", "gif", "heic": return "photo"
        case "mp4", "mov", "avi": return "video"
        case "mp3", "wav", "m4a": return "music.note"
        case "zip", "rar", "7z": return "archivebox"
        case "doc", "docx": return "doc.text"
        case "xls", "xlsx": return "tablecells"
        default: return "doc"
        }
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Preview

#Preview {
    BatchTimestampView(manager: DataStampManager())
        .modelContainer(for: DataStampItem.self, inMemory: true)
}
