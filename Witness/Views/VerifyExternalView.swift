import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var openTimestampsProof: UTType {
        UTType(importedAs: "org.opentimestamps.ots")
    }
}

struct VerifyExternalView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var isImporting = false
    @State private var isVerifying = false
    @State private var verificationResult: VerificationDisplayResult?
    @State private var error: String?
    @State private var selectedFileURL: URL?
    @State private var originalFileURL: URL?
    @State private var hashToVerify: Data?
    @State private var isImportingOriginal = false
    
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
                            isImporting = true
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
                            isImportingOriginal = true
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
                            Text("Verification Failed")
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
                isPresented: $isImporting,
                allowedContentTypes: [.openTimestampsProof, .data],
                allowsMultipleSelection: false
            ) { result in
                handleOTSImport(result)
            }
            .fileImporter(
                isPresented: $isImportingOriginal,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                handleOriginalImport(result)
            }
        }
    }
    
    @ViewBuilder
    private func resultView(_ result: VerificationDisplayResult) -> some View {
        VStack(spacing: 16) {
            // Status
            HStack {
                Image(systemName: result.isValid ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(result.isValid ? .green : .red)
                
                VStack(alignment: .leading) {
                    Text(result.isValid ? "Verified!" : "Invalid")
                        .font(.headline)
                    Text(result.isValid ? "This timestamp is anchored in Bitcoin" : "Could not verify timestamp")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // Details
            if result.isValid {
                VStack(spacing: 8) {
                    if let blockHeight = result.blockHeight {
                        HStack {
                            Text("Block Height")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("#\(blockHeight)")
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
                            Text("Transaction")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(txId)
                                .font(.caption)
                                .fontDesign(.monospaced)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding()
        .background(result.isValid ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func handleOTSImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                // Store the URL - we'll handle security scope when verifying
                selectedFileURL = url
            }
        case .failure(let error):
            self.error = error.localizedDescription
        }
    }
    
    private func handleOriginalImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                originalFileURL = url
            }
        case .failure(let error):
            self.error = error.localizedDescription
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
            
            let result = try await otsService.verifyTimestamp(otsData: otsData, originalHash: hashData)
            
            verificationResult = VerificationDisplayResult(
                isValid: result.isValid,
                blockHeight: result.blockHeight,
                blockTime: result.blockTime,
                txId: result.txId
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct VerificationDisplayResult {
    let isValid: Bool
    let blockHeight: Int?
    let blockTime: Date?
    let txId: String?
}

#Preview {
    VerifyExternalView()
}
