import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var syncService: CloudKitSyncService
    
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    @State private var showingResetConfirmation = false
    
    var body: some View {
        NavigationStack {
            List {
                // iCloud Section
                Section {
                    Toggle(isOn: $iCloudSyncEnabled) {
                        HStack {
                            Image(systemName: syncService.syncState.icon)
                                .foregroundStyle(syncStateColor)
                            Text("iCloud Sync")
                        }
                    }
                    .disabled(!syncService.isAvailable)
                    .onChange(of: iCloudSyncEnabled) { _, newValue in
                        if newValue && syncService.isAvailable {
                            Task {
                                await syncService.sync()
                            }
                        }
                    }
                    
                    if iCloudSyncEnabled {
                        HStack {
                            Text("Status")
                            Spacer()
                            if syncService.syncState == .syncing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(syncService.syncState.description)
                                .foregroundStyle(.secondary)
                        }
                        
                        if let lastSync = syncService.lastSyncDate {
                            LabeledContent("Last Synced", value: lastSync.formatted(date: .abbreviated, time: .shortened))
                        }
                        
                        if syncService.pendingChanges > 0 {
                            LabeledContent("Pending Changes", value: "\(syncService.pendingChanges)")
                        }
                        
                        Button {
                            Task {
                                await syncService.sync()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Sync Now")
                            }
                        }
                        .disabled(syncService.syncState == .syncing || syncService.syncState == .unavailable)
                    }
                } header: {
                    Text("iCloud")
                } footer: {
                    if syncService.syncState == .unavailable {
                        Text("iCloud is not available. Please sign in to iCloud in Settings.")
                    } else if let error = syncService.error {
                        Text("Sync error: \(error.localizedDescription)")
                            .foregroundStyle(.red)
                    } else {
                        Text("Sync your timestamps, proofs, and files across all your devices via iCloud.")
                    }
                }
                
                // About Section
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                    
                    Link(destination: URL(string: "https://opentimestamps.org")!) {
                        HStack {
                            Text("OpenTimestamps")
                            Spacer()
                            Image(systemName: "arrow.up.forward.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Data Section
                Section {
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Text("Delete All Data")
                    }
                } footer: {
                    Text("This will permanently delete all timestamps and proofs from this device.")
                }
                
                // Privacy Section
                Section("Privacy") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Local First", systemImage: "iphone")
                        Text("Your files and content never leave your device. Only cryptographic hashes are sent to timestamp servers.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No Account Required", systemImage: "person.slash")
                        Text("DataStamp works without any signup or tracking. Your privacy is preserved.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Bitcoin Anchored", systemImage: "bitcoinsign.circle")
                        Text("Timestamps are anchored in the Bitcoin blockchain, providing mathematical proof of existence.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Delete All Data?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) {
                    deleteAllData()
                }
            } message: {
                Text("This will permanently delete all your timestamps and proofs. This cannot be undone.")
            }
        }
    }
    
    private var syncStateColor: Color {
        switch syncService.syncState {
        case .checking: return .orange
        case .idle: return .green
        case .syncing: return .blue
        case .error: return .red
        case .unavailable: return .gray
        }
    }
    
    private func deleteAllData() {
        do {
            try modelContext.delete(model: DataStampItem.self)
            try modelContext.save()
        } catch {
            print("Failed to delete data: \(error)")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(CloudKitSyncService())
        .modelContainer(for: DataStampItem.self, inMemory: true)
}
