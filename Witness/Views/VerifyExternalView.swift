import SwiftUI
import UniformTypeIdentifiers

struct VerifyExternalView: View {
    @Environment(\.dismiss) private var dismiss
    
    enum ImportMode {
        case ots
        case original
    }
    
    @State private var showingFilePicker = false
    @State private var importMode: ImportMode = .ots
    @State private var isVerifying = false
    @State private var verificationResult: VerificationResult?
    @State private var error: String?
    @State private var selectedFileURL: URL?
    @State private var originalFileURL: URL?
    @State private var showMerkleTree = false
    
    private let otsService = OpenTimestampsService()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                        
                        Text("Verify Timestamp")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Import a .ots proof file to verify when a document was timestamped.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top)
                    
                    // Step 1: Import OTS file
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Step 1: Import .ots Proof", systemImage: "1.circle.fill")
                            .font(.headline)
                        
                        Button {
                            importMode = .ots
                            showingFilePicker = true
                        } label: {
                            HStack {
                                Image(systemName: selectedFileURL != nil ? "checkmark.circle.fill" : "doc.badge.plus")
                                    .foregroundStyle(selectedFileURL != nil ? .green : .blue)
                                Text(selectedFileURL != nil ? "Proof file selected" : "Select .ots file")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        
                        if let url = selectedFileURL {
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Step 2: Import original file (optional)
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Step 2: Original File (Optional)", systemImage: "2.circle.fill")
                            .font(.headline)
                        
                        Text("If you have the original file, import it to verify the hash matches.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Button {
                            importMode = .original
                            showingFilePicker = true
                        } label: {
                            HStack {
                                Image(systemName: originalFileURL != nil ? "checkmark.circle.fill" : "doc.badge.plus")
                                    .foregroundStyle(originalFileURL != nil ? .green : .blue)
                                Text(originalFileURL != nil ? "Original file selected" : "Select original file")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        
                        if let url = originalFileURL {
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Verify Button
                    Button {
                        Task {
                            await verify()
                        }
                    } label: {
                        HStack {
                            if isVerifying {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark.shield")
                            }
                            Text("Verify Timestamp")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedFileURL != nil ? Color.blue : Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(selectedFileURL == nil || isVerifying)
                    .padding(.horizontal)
                    
                    // Results
                    if let result = verificationResult {
                        resultView(result)
                            .padding(.horizontal)
                    }
                    
                    if let error = error {
                        VStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.red)
                            Text("Error")
                                .font(.headline)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                }
            }
            .navigationTitle("Verify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: importMode == .ots ? [.data] : [.item],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .sheet(isPresented: $showMerkleTree) {
                if let result = verificationResult {
                    MerkleTreeView(result: result)
                }
            }
        }
    }
    
    @ViewBuilder
    private func resultView(_ result: VerificationResult) -> some View {
        VStack(spacing: 16) {
            if result.isPending {
                // Pending State - Didactic explanation
                pendingView(result)
            } else if result.isValid {
                // Confirmed State
                confirmedView(result)
            } else {
                // Failed State
                failedView(result)
            }
        }
        .padding()
        .background(backgroundColorFor(result).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private func pendingView(_ result: VerificationResult) -> some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "clock.badge.questionmark")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                
                VStack(alignment: .leading) {
                    Text("Pending Confirmation")
                        .font(.headline)
                    Text("Awaiting Bitcoin block inclusion")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // Explanation
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("What this means")
                        .font(.subheadline.bold())
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                }
                
                Text("Your timestamp has been submitted to an OpenTimestamps calendar server. It will be included in a Bitcoin block within the next few hours.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("Once confirmed, anyone can independently verify that your document existed before the block was mined.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Calendar info
            if !result.pendingCalendars.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Calendar Servers")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    
                    ForEach(result.pendingCalendars, id: \.self) { calendar in
                        HStack {
                            Image(systemName: "server.rack")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text(formatCalendarUrl(calendar))
                                .font(.caption)
                                .fontDesign(.monospaced)
                        }
                    }
                }
            }
            
            // Hash info
            if !result.originalHash.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Document Hash (SHA-256)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(result.originalHash)
                        .font(.caption2)
                        .fontDesign(.monospaced)
                        .lineLimit(2)
                }
            }
            
            // Merkle Tree button
            if !result.operations.isEmpty {
                Button {
                    showMerkleTree = true
                } label: {
                    HStack {
                        Image(systemName: "tree")
                        Text("View Merkle Path")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            
            // Upgrade tip
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Tip")
                        .font(.caption.bold())
                } icon: {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                }
                
                Text("Check back in a few hours, or use the original Witness app to automatically upgrade your timestamp once it's confirmed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    @ViewBuilder
    private func confirmedView(_ result: VerificationResult) -> some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                
                VStack(alignment: .leading) {
                    Text("Verified!")
                        .font(.headline)
                    Text("Anchored in Bitcoin blockchain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // Block details
            VStack(spacing: 8) {
                if let blockHeight = result.blockHeight {
                    HStack {
                        Text("Block Height")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("#\(blockHeight.formatted())")
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                }
                
                if let blockTime = result.blockTime {
                    HStack {
                        Text("Block Time")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(blockTime.formatted(date: .abbreviated, time: .shortened))
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                }
                
                if let txId = result.txId, !txId.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Block Hash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(txId)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            // Merkle Tree button
            if !result.operations.isEmpty {
                Button {
                    showMerkleTree = true
                } label: {
                    HStack {
                        Image(systemName: "tree")
                        Text("View Merkle Path")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    @ViewBuilder
    private func failedView(_ result: VerificationResult) -> some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "xmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                
                VStack(alignment: .leading) {
                    Text("Verification Failed")
                        .font(.headline)
                    Text("Could not verify timestamp")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if let errorMessage = result.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private func backgroundColorFor(_ result: VerificationResult) -> Color {
        if result.isPending {
            return .orange
        } else if result.isValid {
            return .green
        } else {
            return .red
        }
    }
    
    private func formatCalendarUrl(_ url: String) -> String {
        // Extract just the host from URL
        if let urlObj = URL(string: url) {
            return urlObj.host ?? url
        }
        return url
    }
    
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                switch importMode {
                case .ots:
                    selectedFileURL = url
                case .original:
                    originalFileURL = url
                }
            }
        case .failure(let err):
            self.error = err.localizedDescription
        }
    }
    
    private func verify() async {
        guard let otsURL = selectedFileURL else { return }
        
        isVerifying = true
        error = nil
        verificationResult = nil
        
        defer {
            isVerifying = false
        }
        
        do {
            // Copy file to temp location to avoid permission issues
            let tempDir = FileManager.default.temporaryDirectory
            let tempOtsURL = tempDir.appendingPathComponent("verify_\(UUID().uuidString).ots")
            
            // Start accessing and copy
            let accessing = otsURL.startAccessingSecurityScopedResource()
            defer { 
                if accessing { otsURL.stopAccessingSecurityScopedResource() }
                try? FileManager.default.removeItem(at: tempOtsURL)
            }
            
            try FileManager.default.copyItem(at: otsURL, to: tempOtsURL)
            let otsData = try Data(contentsOf: tempOtsURL)
            
            // If we have original file, compute its hash
            var hashData: Data
            if let originalURL = originalFileURL {
                let origAccessing = originalURL.startAccessingSecurityScopedResource()
                defer { if origAccessing { originalURL.stopAccessingSecurityScopedResource() } }
                
                let originalData = try Data(contentsOf: originalURL)
                hashData = await otsService.sha256(data: originalData)
            } else {
                // Extract hash from OTS file (first 32 bytes after header + version + hash type)
                let headerSize = 31 + 1 + 1 // magic + version + hash type
                if otsData.count > headerSize + 32 {
                    hashData = otsData.subdata(in: (headerSize)..<(headerSize + 32))
                } else {
                    throw NSError(domain: "Witness", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid OTS file format"])
                }
            }
            
            verificationResult = try await otsService.verifyTimestamp(otsData: otsData, originalHash: hashData)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Merkle Tree View

struct MerkleTreeView: View {
    @Environment(\.dismiss) private var dismiss
    let result: VerificationResult
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Merkle Path", systemImage: "tree")
                            .font(.title2.bold())
                        
                        Text("The cryptographic operations that link your document to the Bitcoin blockchain.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    
                    // Original Hash
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Document Hash")
                            .font(.headline)
                        
                        Text(result.originalHash)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.horizontal)
                    
                    // Operations
                    if !result.operations.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Operations (\(result.operations.count))")
                                .font(.headline)
                            
                            ForEach(Array(result.operations.enumerated()), id: \.offset) { index, op in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 24, height: 24)
                                        .background(Circle().fill(Color.blue))
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(operationName(op))
                                            .font(.subheadline.bold())
                                        
                                        if let data = operationData(op) {
                                            Text(data)
                                                .font(.caption2)
                                                .fontDesign(.monospaced)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Computed Hash
                    if !result.computedHash.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Computed Hash")
                                .font(.headline)
                            
                            Text(result.computedHash)
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(.horizontal)
                    }
                    
                    // Explanation
                    VStack(alignment: .leading, spacing: 8) {
                        Label("How it works", systemImage: "info.circle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.blue)
                        
                        Text("Each operation transforms the hash. Prepend/Append adds data, SHA256 computes a new hash. The final hash is committed to the Bitcoin blockchain, creating an immutable proof that your document existed at that time.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Merkle Path")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func operationName(_ op: OTSOperation) -> String {
        switch op {
        case .sha256: return "SHA-256"
        case .sha1: return "SHA-1"
        case .ripemd160: return "RIPEMD-160"
        case .append: return "Append"
        case .prepend: return "Prepend"
        case .reverse: return "Reverse"
        case .hexlify: return "Hexlify"
        }
    }
    
    private func operationData(_ op: OTSOperation) -> String? {
        switch op {
        case .append(let data):
            return data.hexString
        case .prepend(let data):
            return data.hexString
        default:
            return nil
        }
    }
}

#Preview {
    VerifyExternalView()
}
