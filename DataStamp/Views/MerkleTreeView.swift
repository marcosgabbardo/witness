import SwiftUI

/// View to display the Merkle path operations from an OTS proof
struct MerkleTreeView: View {
    @Environment(\.dismiss) private var dismiss
    
    let originalHash: String
    let computedHash: String
    let operations: [OTSOperation]
    let pendingCalendars: [String]
    let blockHeight: Int?
    let blockTime: Date?
    
    init(result: VerificationResult) {
        self.originalHash = result.originalHash
        self.computedHash = result.computedHash
        self.operations = result.operations
        self.pendingCalendars = result.pendingCalendars
        self.blockHeight = result.blockHeight
        self.blockTime = result.blockTime
    }
    
    init(originalHash: String, computedHash: String, operations: [OTSOperation], pendingCalendars: [String] = [], blockHeight: Int? = nil, blockTime: Date? = nil) {
        self.originalHash = originalHash
        self.computedHash = computedHash
        self.operations = operations
        self.pendingCalendars = pendingCalendars
        self.blockHeight = blockHeight
        self.blockTime = blockTime
    }
    
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
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(.blue)
                            Text("Document Hash (SHA-256)")
                                .font(.headline)
                        }
                        
                        Text(originalHash.isEmpty ? "N/A" : originalHash)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.horizontal)
                    
                    // Operations
                    if !operations.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "arrow.triangle.branch")
                                    .foregroundStyle(.orange)
                                Text("Operations (\(operations.count))")
                                    .font(.headline)
                            }
                            
                            ForEach(Array(operations.enumerated()), id: \.offset) { index, op in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 24, height: 24)
                                        .background(Circle().fill(Color.orange))
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(operationName(op))
                                                .font(.subheadline.bold())
                                            
                                            Spacer()
                                            
                                            Image(systemName: operationIcon(op))
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        if let data = operationData(op) {
                                            Text(data)
                                                .font(.caption2)
                                                .fontDesign(.monospaced)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                                .textSelection(.enabled)
                                        }
                                        
                                        Text(operationDescription(op))
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "questionmark.circle")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No operations found")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                    
                    // Computed Hash
                    if !computedHash.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Computed Hash")
                                    .font(.headline)
                            }
                            
                            Text(computedHash)
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .textSelection(.enabled)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(.horizontal)
                    }
                    
                    // Bitcoin info if available
                    if let height = blockHeight {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "bitcoinsign.circle.fill")
                                    .foregroundStyle(.orange)
                                Text("Bitcoin Anchor")
                                    .font(.headline)
                            }
                            
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Block Height")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("#\(height.formatted())")
                                        .fontWeight(.medium)
                                }
                                
                                if let time = blockTime {
                                    HStack {
                                        Text("Block Time")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(time.formatted(date: .abbreviated, time: .shortened))
                                            .fontWeight(.medium)
                                    }
                                }
                            }
                            .font(.subheadline)
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(.horizontal)
                    }
                    
                    // Pending calendars
                    if !pendingCalendars.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "clock.badge.questionmark")
                                    .foregroundStyle(.orange)
                                Text("Pending Calendars")
                                    .font(.headline)
                            }
                            
                            ForEach(pendingCalendars, id: \.self) { calendar in
                                HStack {
                                    Image(systemName: "server.rack")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                    Text(formatCalendarUrl(calendar))
                                        .font(.caption)
                                        .fontDesign(.monospaced)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(.horizontal)
                    }
                    
                    // Explanation
                    VStack(alignment: .leading, spacing: 8) {
                        Label("How it works", systemImage: "info.circle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.blue)
                        
                        Text("Each operation transforms the hash step by step:\n\n• **Prepend/Append** adds data before or after the current hash\n• **SHA-256** computes a new cryptographic hash\n\nThe final computed hash is committed to the Bitcoin blockchain through a transaction, creating an immutable, publicly verifiable proof that your document existed at that time.")
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
    
    private func operationIcon(_ op: OTSOperation) -> String {
        switch op {
        case .sha256, .sha1, .ripemd160: return "number"
        case .append: return "plus.circle"
        case .prepend: return "arrow.left.circle"
        case .reverse: return "arrow.left.arrow.right"
        case .hexlify: return "textformat"
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
    
    private func operationDescription(_ op: OTSOperation) -> String {
        switch op {
        case .sha256: return "Compute SHA-256 hash"
        case .sha1: return "Compute SHA-1 hash"
        case .ripemd160: return "Compute RIPEMD-160 hash"
        case .append: return "Append bytes to the end"
        case .prepend: return "Prepend bytes to the beginning"
        case .reverse: return "Reverse byte order"
        case .hexlify: return "Convert to hex string"
        }
    }
    
    private func formatCalendarUrl(_ url: String) -> String {
        if let urlObj = URL(string: url) {
            return urlObj.host ?? url
        }
        return url
    }
}

#Preview {
    MerkleTreeView(
        originalHash: "abc123def456789...",
        computedHash: "final789xyz...",
        operations: [.prepend(Data([0x01, 0x02])), .sha256, .append(Data([0x03, 0x04])), .sha256],
        pendingCalendars: ["https://alice.btc.calendar.opentimestamps.org"],
        blockHeight: 830000,
        blockTime: Date()
    )
}
