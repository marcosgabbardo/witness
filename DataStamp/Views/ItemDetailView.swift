import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let item: DataStampItem
    let manager: DataStampManager
    
    @State private var fullImage: UIImage?
    @State private var isVerifying = false
    @State private var verificationResult: VerificationResult?
    @State private var showingShareSheet = false
    @State private var shareURLs: [URL] = []
    @State private var showingDeleteConfirmation = false
    @State private var showingShareOptions = false
    @State private var isGeneratingPDF = false
    @State private var error: Error?
    @State private var showingError = false
    @State private var merkleTreeData: MerkleTreeData?
    @State private var showingImportProof = false
    @State private var showingTagsEditor = false
    @State private var showingFolderPicker = false
    @State private var isFetchingBlockInfo = false
    
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]
    
    private let merkleVerifier = MerkleVerifier()
    private let otsService = OpenTimestampsService()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Content Preview
                    contentPreviewSection
                    
                    // Status Section
                    statusSection
                    
                    // Details Section
                    detailsSection
                    
                    // Organization Section
                    organizationSection
                    
                    // Actions Section
                    actionsSection
                }
                .padding()
            }
            .navigationTitle("Timestamp Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingShareOptions = true
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        
                        Button {
                            Task { await exportPDF() }
                        } label: {
                            Label("Export PDF Certificate", systemImage: "doc.richtext")
                        }
                        .disabled(isGeneratingPDF)
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(urls: shareURLs)
            }
            .confirmationDialog("Delete Timestamp?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        await manager.deleteItem(item, context: modelContext)
                        dismiss()
                    }
                }
            } message: {
                Text("This will permanently delete the timestamp and its proof.")
            }
            .confirmationDialog("Share Options", isPresented: $showingShareOptions, titleVisibility: .visible) {
                Button("Share All (PDF + File + .ots)") {
                    Task { await shareAll() }
                }
                Button("Share with PDF Certificate") {
                    Task { await shareWithCertificate() }
                }
                Button("Share Original File + .ots") {
                    Task { await share() }
                }
                Button("Share .ots Only") {
                    Task { await shareOtsOnly() }
                }
            } message: {
                Text("Choose what to include in the share.")
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(error?.localizedDescription ?? "Unknown error")
            }
            .sheet(item: $merkleTreeData) { data in
                MerkleTreeView(
                    originalHash: data.originalHash,
                    computedHash: data.computedHash,
                    operations: data.operations,
                    pendingCalendars: data.pendingCalendars,
                    blockHeight: item.bitcoinBlockHeight,
                    blockTime: item.bitcoinBlockTime
                )
            }
            .fileImporter(
                isPresented: $showingImportProof,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                Task { await handleImportProof(result) }
            }
            .task {
                if item.contentType == .photo {
                    fullImage = await manager.loadImage(for: item)
                }
            }
        }
    }
    
    // MARK: - Content Preview
    
    @ViewBuilder
    private var contentPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Content")
                .font(.headline)
            
            switch item.contentType {
            case .text:
                if let text = item.textContent {
                    Text(text)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
            case .photo:
                if let image = fullImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .frame(height: 200)
                        .overlay {
                            ProgressView()
                        }
                }
                
            case .file:
                HStack {
                    Image(systemName: "doc.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading) {
                        Text(item.contentFileName ?? "File")
                            .font(.headline)
                    }
                    
                    Spacer()
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    // MARK: - Status Section
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status")
                .font(.headline)
            
            HStack(spacing: 16) {
                // Status Icon
                ZStack {
                    Circle()
                        .fill(statusBackgroundColor)
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: item.statusIcon)
                        .font(.title)
                        .foregroundStyle(statusForegroundColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text(statusDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Bitcoin blockchain info if confirmed
            if item.isConfirmed {
                VStack(alignment: .leading, spacing: 12) {
                    // Header
                    HStack {
                        Image(systemName: "bitcoinsign.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        
                        Text("Bitcoin Blockchain")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        
                        Spacer()
                        
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                    
                    Divider()
                    
                    if let blockHeight = item.bitcoinBlockHeight {
                        // Block Height - clickable
                        Link(destination: URL(string: "https://blockstream.info/block-height/\(blockHeight)")!) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Block Height")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("#\(formatBlockHeight(blockHeight))")
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.semibold)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .foregroundStyle(.primary)
                        
                        // Block Time
                        if let blockTime = item.bitcoinBlockTime {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Block Time")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(blockTime.formatted(date: .abbreviated, time: .shortened))
                                        .font(.subheadline)
                                }
                                Spacer()
                            }
                        }
                        
                        // Transaction ID - clickable
                        if let txId = item.bitcoinTxId, !txId.isEmpty {
                            Link(destination: URL(string: "https://blockstream.info/tx/\(txId)")!) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Transaction")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(txId.prefix(16))...\(txId.suffix(8))")
                                            .font(.system(.caption, design: .monospaced))
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                        .foregroundStyle(.orange)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    } else {
                        // Block info not available - fetch button
                        VStack(spacing: 8) {
                            Text("Block details not available")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Button {
                                Task {
                                    await fetchBlockInfo()
                                }
                            } label: {
                                HStack {
                                    if isFetchingBlockInfo {
                                        ProgressView()
                                            .tint(.orange)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text("Fetch Block Info")
                                }
                                .font(.subheadline.bold())
                                .foregroundStyle(.orange)
                            }
                            .disabled(isFetchingBlockInfo)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private var statusBackgroundColor: Color {
        switch item.status {
        case .pending: return .gray.opacity(0.2)
        case .submitted: return .orange.opacity(0.2)
        case .confirmed: return .green.opacity(0.2)
        case .verified: return .blue.opacity(0.2)
        case .failed: return .red.opacity(0.2)
        }
    }
    
    private var statusForegroundColor: Color {
        switch item.status {
        case .pending: return .gray
        case .submitted: return .orange
        case .confirmed: return .green
        case .verified: return .blue
        case .failed: return .red
        }
    }
    
    private var statusTitle: String {
        switch item.status {
        case .pending: return "Pending"
        case .submitted: return "Submitted"
        case .confirmed: return "Confirmed"
        case .verified: return "Verified"
        case .failed: return "Failed"
        }
    }
    
    private var statusDescription: String {
        switch item.status {
        case .pending:
            return "Waiting to submit to OpenTimestamps"
        case .submitted:
            return "Waiting for Bitcoin confirmation (~1-24 hours)"
        case .confirmed:
            return "Anchored in the Bitcoin blockchain"
        case .verified:
            return "Proof verified successfully"
        case .failed:
            return item.statusMessage ?? "Something went wrong"
        }
    }
    
    // MARK: - Details Section
    
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
            
            VStack(spacing: 0) {
                detailRow(label: "Created", value: item.createdAt.formatted(date: .long, time: .shortened))
                
                Divider()
                
                detailRow(label: "Hash (SHA256)", value: item.hashHex, isMonospace: true)
                
                if item.calendarUrl != nil {
                    Divider()
                    if item.status == .submitted {
                        // Show multi-calendar info for pending timestamps
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Calendars")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Label("alice.btc.calendar.opentimestamps.org", systemImage: "checkmark.circle.fill")
                                Label("bob.btc.calendar.opentimestamps.org", systemImage: "checkmark.circle.fill")
                                Label("finney.calendar.eternitywall.com", systemImage: "checkmark.circle.fill")
                            }
                            .font(.caption2)
                            .foregroundStyle(.green)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    } else if let calendarUrl = item.calendarUrl {
                        // Show confirmed calendar for completed timestamps
                        detailRow(label: "Confirmed via", value: calendarUrl)
                    }
                }
                
                if let submittedAt = item.submittedAt {
                    Divider()
                    detailRow(label: "Submitted", value: submittedAt.formatted(date: .long, time: .shortened))
                }
                
                if let blockTime = item.bitcoinBlockTime {
                    Divider()
                    detailRow(label: "Bitcoin Time", value: blockTime.formatted(date: .long, time: .shortened))
                }
            }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private func detailRow(label: String, value: String, isMonospace: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(isMonospace ? .system(.caption, design: .monospaced) : .subheadline)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
    
    // MARK: - Organization Section
    
    private var organizationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Organization")
                .font(.headline)
            
            VStack(spacing: 0) {
                // Folder
                Button {
                    showingFolderPicker = true
                } label: {
                    HStack {
                        Image(systemName: item.folder?.icon ?? "folder")
                            .foregroundStyle(item.folder?.color ?? .secondary)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Folder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.folder?.name ?? "None")
                                .font(.subheadline)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                }
                .foregroundStyle(.primary)
                
                Divider()
                
                // Tags
                Button {
                    showingTagsEditor = true
                } label: {
                    HStack {
                        Image(systemName: "tag")
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tags")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            if item.tags.isEmpty {
                                Text("None")
                                    .font(.subheadline)
                            } else {
                                InlineTagsView(tags: item.tags, maxVisible: 4)
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                }
                .foregroundStyle(.primary)
            }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .sheet(isPresented: $showingTagsEditor) {
            TagsEditorView(item: item)
        }
        .sheet(isPresented: $showingFolderPicker) {
            FolderPickerView(item: item, folders: folders)
        }
    }
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Verify button (if confirmed)
            // Refresh button (if pending/submitted)
            if item.status == .submitted {
                Button {
                    Task {
                        await manager.upgradeTimestamp(item, context: modelContext)
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Check for Confirmation")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
            }
            
            // Share button
            Button {
                showingShareOptions = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share Proof")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // Export PDF button
            Button {
                Task { await exportPDF() }
            } label: {
                HStack {
                    if isGeneratingPDF {
                        ProgressView()
                            .tint(.primary)
                    } else {
                        Image(systemName: "doc.richtext")
                    }
                    Text("Export PDF Certificate")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isGeneratingPDF)
            
            // View Merkle Tree button (if has OTS data)
            if item.otsData != nil || item.pendingOtsData != nil {
                Button {
                    Task { await loadMerkleTree() }
                } label: {
                    HStack {
                        Image(systemName: "tree")
                        Text("View Merkle Path")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func fetchBlockInfo() async {
        isFetchingBlockInfo = true
        defer { isFetchingBlockInfo = false }
        
        // Try to extract block info directly from OTS data (fast path)
        let extracted = await manager.extractBlockInfo(for: item, context: modelContext)
        
        if extracted {
            HapticManager.shared.success()
            return
        }
        
        // If direct extraction failed, try upgrading first (maybe OTS needs upgrade)
        if item.status == .submitted {
            await manager.upgradeTimestamp(item, context: modelContext)
            
            // Try extraction again after upgrade
            let extractedAfterUpgrade = await manager.extractBlockInfo(for: item, context: modelContext)
            if extractedAfterUpgrade {
                HapticManager.shared.success()
                return
            }
        }
        
        // If still no block info, show error
        self.error = NSError(
            domain: "DataStamp",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Could not extract block info. The timestamp may still be pending Bitcoin confirmation."]
        )
        showingError = true
    }
    
    private func formatBlockHeight(_ height: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: height)) ?? "\(height)"
    }
    
    // MARK: - Actions
    
    private func verify() async {
        isVerifying = true
        defer { isVerifying = false }
        
        do {
            verificationResult = try await manager.verifyTimestamp(item)
            // Could show a success message or update UI
        } catch {
            self.error = error
            showingError = true
        }
    }
    
    private func share() async {
        do {
            let urls = try await manager.getShareURLs(for: item)
            if !urls.isEmpty {
                // Use imperative presentation to avoid SwiftUI timing issues
                presentShareSheet(urls: urls)
            } else {
                let hasOts = item.otsData != nil
                let hasPendingOts = item.pendingOtsData != nil
                let otsSize = item.otsData?.count ?? item.pendingOtsData?.count ?? 0
                self.error = NSError(domain: "DataStamp", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "No proof files found.\n\nDebug: otsData=\(hasOts), pendingOtsData=\(hasPendingOts), size=\(otsSize) bytes"
                ])
                showingError = true
            }
        } catch {
            self.error = error
            showingError = true
        }
    }
    
    private func shareWithCertificate() async {
        isGeneratingPDF = true
        defer { isGeneratingPDF = false }
        
        do {
            let urls = try await manager.getShareURLsWithCertificate(for: item)
            if !urls.isEmpty {
                presentShareSheet(urls: urls)
            }
        } catch {
            self.error = error
            showingError = true
        }
    }
    
    private func shareAll() async {
        isGeneratingPDF = true
        defer { isGeneratingPDF = false }
        
        do {
            let urls = try await manager.getShareURLsAll(for: item)
            if !urls.isEmpty {
                presentShareSheet(urls: urls)
            }
        } catch {
            self.error = error
            showingError = true
        }
    }
    
    private func shareOtsOnly() async {
        do {
            let urls = try await manager.getShareURLsOtsOnly(for: item)
            if !urls.isEmpty {
                presentShareSheet(urls: urls)
            }
        } catch {
            self.error = error
            showingError = true
        }
    }
    
    private func exportPDF() async {
        isGeneratingPDF = true
        defer { isGeneratingPDF = false }
        
        do {
            let pdfUrl = try await manager.generatePDFCertificate(for: item)
            presentShareSheet(urls: [pdfUrl])
        } catch {
            self.error = error
            showingError = true
        }
    }
    
    private func loadMerkleTree() async {
        guard let otsData = item.otsData ?? item.pendingOtsData else { return }
        
        do {
            let proof = try await merkleVerifier.parseOtsFile(otsData)
            
            // Extract pending calendars
            let pendingCalendars = proof.attestations.compactMap { attestation -> String? in
                if case .pending(let url) = attestation { return url }
                return nil
            }
            
            merkleTreeData = MerkleTreeData(
                originalHash: proof.originalHash.hexString,
                computedHash: "",  // Would need to compute this
                operations: proof.operations,
                pendingCalendars: pendingCalendars
            )
        } catch {
            self.error = error
            showingError = true
        }
    }
    
    private func handleImportProof(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            // Start security access
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            
            do {
                let otsData = try Data(contentsOf: url)
                
                // Verify it's valid OTS format
                let proof = try await merkleVerifier.parseOtsFile(otsData)
                
                // Check if it has Bitcoin attestation
                let hasBitcoin = proof.attestations.contains { attestation in
                    if case .bitcoin = attestation { return true }
                    return false
                }
                
                guard hasBitcoin else {
                    self.error = NSError(domain: "DataStamp", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "This proof file is still pending. Please download an upgraded proof from opentimestamps.org"
                    ])
                    showingError = true
                    return
                }
                
                // Verify the hash matches
                guard proof.originalHash == item.contentHash else {
                    self.error = NSError(domain: "DataStamp", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "This proof file is for a different document (hash mismatch)"
                    ])
                    showingError = true
                    return
                }
                
                // Update the item
                item.otsData = otsData
                item.status = .confirmed
                item.confirmedAt = Date()
                item.lastUpdated = Date()
                
                // Try to extract block info
                let verificationResult = try await otsService.verifyTimestamp(
                    otsData: otsData,
                    originalHash: item.contentHash
                )
                
                if verificationResult.isValid {
                    item.bitcoinBlockHeight = verificationResult.blockHeight
                    item.bitcoinBlockTime = verificationResult.blockTime
                    item.bitcoinTxId = verificationResult.txId
                }
                
                try modelContext.save()
                
                // Haptic feedback
                HapticManager.shared.timestampConfirmed()
                
            } catch {
                self.error = error
                showingError = true
            }
            
        case .failure(let err):
            self.error = err
            showingError = true
        }
    }
}

// MARK: - Supporting Types

struct MerkleTreeData: Identifiable {
    let id = UUID()
    let originalHash: String
    let computedHash: String
    let operations: [OTSOperation]
    let pendingCalendars: [String]
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Pre-load file data to ensure system has them ready
        let items: [Any] = urls.compactMap { url -> Any? in
            // Read file data and create a proper activity item
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }
        
        let controller = UIActivityViewController(
            activityItems: items.isEmpty ? urls : items,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// Alternative: Present share sheet imperatively to avoid SwiftUI timing issues
extension View {
    func presentShareSheet(urls: [URL]) {
        guard !urls.isEmpty else { return }
        
        // Ensure we're on main thread and files exist
        let validUrls = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !validUrls.isEmpty else { return }
        
        DispatchQueue.main.async {
            let activityVC = UIActivityViewController(activityItems: validUrls, applicationActivities: nil)
            
            // Find the top-most view controller
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               var topController = window.rootViewController {
                while let presented = topController.presentedViewController {
                    topController = presented
                }
                
                // iPad popover support
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = topController.view
                    popover.sourceRect = CGRect(x: topController.view.bounds.midX, y: topController.view.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                
                topController.present(activityVC, animated: true)
            }
        }
    }
}

#Preview {
    let item = DataStampItem(
        contentType: .text,
        contentHash: Data(repeating: 0xAB, count: 32),
        title: "Sample Note",
        textContent: "This is a sample text that has been timestamped."
    )
    item.status = .confirmed
    item.bitcoinBlockHeight = 830000
    
    return ItemDetailView(item: item, manager: DataStampManager())
        .modelContainer(for: DataStampItem.self, inMemory: true)
}
