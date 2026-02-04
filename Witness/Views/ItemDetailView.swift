import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let item: WitnessItem
    let manager: WitnessManager
    
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
                Button("Share with PDF Certificate") {
                    Task { await shareWithCertificate() }
                }
                Button("Share Proof Files Only") {
                    Task { await share() }
                }
            } message: {
                Text("Choose what to include in the share.")
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(error?.localizedDescription ?? "Unknown error")
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
            
            // Bitcoin info if confirmed
            if item.isConfirmed, let blockHeight = item.bitcoinBlockHeight {
                HStack {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .foregroundStyle(.orange)
                    
                    Text("Block #\(blockHeight)")
                        .font(.subheadline)
                    
                    Spacer()
                    
                    if let txId = item.bitcoinTxId, !txId.isEmpty {
                        Link(destination: URL(string: "https://blockstream.info/tx/\(txId)")!) {
                            Text("View on Blockchain")
                                .font(.caption)
                        }
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
                
                if let calendarUrl = item.calendarUrl {
                    Divider()
                    detailRow(label: "Calendar", value: calendarUrl)
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
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Verify button (if confirmed)
            if item.status == .confirmed {
                Button {
                    Task { await verify() }
                } label: {
                    HStack {
                        if isVerifying {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.shield")
                        }
                        Text("Verify Proof")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isVerifying)
            }
            
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
        }
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
            // Debug info
            let hasOts = item.otsData != nil
            let hasPendingOts = item.pendingOtsData != nil
            let otsSize = item.otsData?.count ?? item.pendingOtsData?.count ?? 0
            
            shareURLs = try await manager.getShareURLs(for: item)
            if !shareURLs.isEmpty {
                showingShareSheet = true
            } else {
                self.error = NSError(domain: "Witness", code: 0, userInfo: [
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
            shareURLs = try await manager.getShareURLsWithCertificate(for: item)
            if !shareURLs.isEmpty {
                showingShareSheet = true
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
            shareURLs = [pdfUrl]
            showingShareSheet = true
        } catch {
            self.error = error
            showingError = true
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    let item = WitnessItem(
        contentType: .text,
        contentHash: Data(repeating: 0xAB, count: 32),
        title: "Sample Note",
        textContent: "This is a sample text that has been timestamped."
    )
    item.status = .confirmed
    item.bitcoinBlockHeight = 830000
    
    return ItemDetailView(item: item, manager: WitnessManager())
        .modelContainer(for: WitnessItem.self, inMemory: true)
}
