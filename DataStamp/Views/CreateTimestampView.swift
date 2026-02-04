import SwiftUI
import SwiftData
import PhotosUI

struct CreateTimestampView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let manager: DataStampManager
    
    @State private var selectedTab: CreateTab = .text
    @State private var textContent = ""
    @State private var title = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var selectedFileData: Data?
    @State private var selectedFileName: String?
    @State private var isProcessing = false
    @State private var showingCamera = false
    @State private var showingFilePicker = false
    @State private var error: Error?
    @State private var showingError = false
    
    enum CreateTab: String, CaseIterable {
        case text = "Text"
        case photo = "Photo"
        case file = "File"
        
        var icon: String {
            switch self {
            case .text: return "doc.text"
            case .photo: return "photo"
            case .file: return "doc"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                Picker("Type", selection: $selectedTab) {
                    ForEach(CreateTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                Divider()
                
                // Content based on tab
                ScrollView {
                    VStack(spacing: 20) {
                        // Title field (optional)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title (optional)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            TextField("Enter a title", text: $title)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        // Tab-specific content
                        switch selectedTab {
                        case .text:
                            textInputView
                        case .photo:
                            photoInputView
                        case .file:
                            fileInputView
                        }
                    }
                    .padding()
                }
                
                Divider()
                
                // Create button
                createButtonView
                    .padding()
            }
            .navigationTitle("Create Timestamp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedPhotoItem) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImage = image
                    }
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraView(image: $selectedImage)
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        loadFile(from: url)
                    }
                case .failure(let error):
                    self.error = error
                    showingError = true
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(error?.localizedDescription ?? "Unknown error")
            }
            .overlay {
                if isProcessing {
                    processingOverlay
                }
            }
        }
    }
    
    // MARK: - Tab Content Views
    
    private var textInputView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            TextEditor(text: $textContent)
                .frame(minHeight: 200)
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Text("This text will be hashed and timestamped.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var photoInputView: some View {
        VStack(spacing: 16) {
            if let image = selectedImage {
                // Show selected image
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Button("Change Photo") {
                    selectedImage = nil
                }
                .font(.subheadline)
            } else {
                // Photo selection options
                VStack(spacing: 16) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            
            Text("The photo will be hashed and timestamped.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var fileInputView: some View {
        VStack(spacing: 16) {
            if let fileName = selectedFileName {
                // Show selected file
                HStack {
                    Image(systemName: "doc.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading) {
                        Text(fileName)
                            .font(.headline)
                        
                        if let data = selectedFileData {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button {
                        selectedFileData = nil
                        selectedFileName = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Button {
                    showingFilePicker = true
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.badge.plus")
                            .font(.largeTitle)
                        Text("Select File")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            
            Text("The file will be hashed and timestamped.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Create Button
    
    private var createButtonView: some View {
        Button {
            HapticManager.shared.buttonTap()
            Task {
                await createTimestamp()
            }
        } label: {
            HStack {
                Image(systemName: "checkmark.seal")
                Text("Create Timestamp")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(canCreate ? Color.accentColor : Color.gray)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!canCreate || isProcessing)
    }
    
    private var canCreate: Bool {
        switch selectedTab {
        case .text:
            return !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .photo:
            return selectedImage != nil
        case .file:
            return selectedFileData != nil
        }
    }
    
    // MARK: - Processing Overlay
    
    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                
                Text(manager.processingMessage ?? "Processing...")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    // MARK: - Actions
    
    private func createTimestamp() async {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            let titleToUse = title.isEmpty ? nil : title
            
            switch selectedTab {
            case .text:
                _ = try await manager.createTextTimestamp(
                    text: textContent,
                    title: titleToUse,
                    context: modelContext
                )
                
            case .photo:
                guard let image = selectedImage else { return }
                _ = try await manager.createPhotoTimestamp(
                    image: image,
                    title: titleToUse,
                    context: modelContext
                )
                
            case .file:
                guard let data = selectedFileData,
                      let fileName = selectedFileName else { return }
                _ = try await manager.createFileTimestamp(
                    data: data,
                    filename: fileName,
                    title: titleToUse,
                    context: modelContext
                )
            }
            
            // Success haptic
            HapticManager.shared.timestampCreated()
            dismiss()
        } catch {
            self.error = error
            showingError = true
        }
    }
    
    private func loadFile(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            selectedFileData = try Data(contentsOf: url)
            selectedFileName = url.lastPathComponent
        } catch {
            self.error = error
            showingError = true
        }
    }
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    CreateTimestampView(manager: DataStampManager())
        .modelContainer(for: DataStampItem.self, inMemory: true)
}
