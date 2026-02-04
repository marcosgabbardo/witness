import SwiftUI
import SwiftData

/// View for editing tags on a DataStampItem
struct TagsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: DataStampItem
    
    @State private var newTag = ""
    @State private var showingSuggestions = false
    
    // Get all unique tags used across items
    @Query private var allItems: [DataStampItem]
    
    private var existingTags: [String] {
        Array(Set(allItems.flatMap { $0.tags })).sorted()
    }
    
    private var suggestedTags: [String] {
        let predefined = PredefinedTag.allCases.map { $0.rawValue }
        let existing = existingTags
        let all = Set(predefined + existing)
        let current = Set(item.tags)
        return Array(all.subtracting(current)).sorted()
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Current tags
                Section {
                    if item.tags.isEmpty {
                        Text("No tags")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(item.tags, id: \.self) { tag in
                            TagRow(tag: tag, color: colorForTag(tag))
                        }
                        .onDelete(perform: removeTags)
                    }
                } header: {
                    Text("Current Tags")
                } footer: {
                    Text("Swipe to remove tags")
                }
                
                // Add new tag
                Section("Add Tag") {
                    HStack {
                        TextField("New tag name", text: $newTag)
                            .textInputAutocapitalization(.words)
                            .onSubmit {
                                addTag(newTag)
                            }
                        
                        Button {
                            addTag(newTag)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.orange)
                        }
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                
                // Suggestions
                if !suggestedTags.isEmpty {
                    Section("Suggestions") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                            ForEach(Array(suggestedTags.prefix(12).enumerated()), id: \.offset) { index, tag in
                                SuggestionTagButton(tag: tag, onAdd: {
                                    addSingleTag(tag)
                                })
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Tags")
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
    
    private func addTag(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !item.tags.contains(trimmed) else { return }
        var newTags = item.tags
        newTags.append(trimmed)
        item.tags = newTags
        newTag = ""
    }
    
    private func addSingleTag(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !item.tags.contains(trimmed) else { return }
        var newTags = item.tags
        newTags.append(trimmed)
        item.tags = newTags
    }
    
    private func removeTags(at offsets: IndexSet) {
        item.tags.remove(atOffsets: offsets)
    }
    
    private func colorForTag(_ tag: String) -> Color {
        if let predefined = PredefinedTag(rawValue: tag) {
            return predefined.color
        }
        // Generate consistent color from tag name
        let hash = abs(tag.hashValue)
        let colors: [Color] = [.blue, .green, .purple, .pink, .orange, .mint, .teal, .indigo]
        return colors[hash % colors.count]
    }
}

// MARK: - Suggestion Tag Button

struct SuggestionTagButton: View {
    let tag: String
    let onAdd: () -> Void
    
    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 4) {
                if let predefined = PredefinedTag(rawValue: tag) {
                    Image(systemName: predefined.icon)
                        .font(.caption)
                }
                Text(tag)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(colorForTag(tag).opacity(0.15))
            .foregroundStyle(colorForTag(tag))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    private func colorForTag(_ tag: String) -> Color {
        if let predefined = PredefinedTag(rawValue: tag) {
            return predefined.color
        }
        let hash = abs(tag.hashValue)
        let colors: [Color] = [.blue, .green, .purple, .pink, .orange, .mint, .teal, .indigo]
        return colors[hash % colors.count]
    }
}

// MARK: - Tag Row

struct TagRow: View {
    let tag: String
    let color: Color
    
    var body: some View {
        HStack {
            if let predefined = PredefinedTag(rawValue: tag) {
                Image(systemName: predefined.icon)
                    .foregroundStyle(color)
                    .frame(width: 24)
            } else {
                Image(systemName: "tag.fill")
                    .foregroundStyle(color)
                    .frame(width: 24)
            }
            Text(tag)
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                
                self.size.width = max(self.size.width, x)
            }
            
            self.size.height = y + rowHeight
        }
    }
}

// MARK: - Inline Tags View (for ContentView)

struct InlineTagsView: View {
    let tags: [String]
    let maxVisible: Int
    
    init(tags: [String], maxVisible: Int = 3) {
        self.tags = tags
        self.maxVisible = maxVisible
    }
    
    var body: some View {
        if tags.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                ForEach(tags.prefix(maxVisible), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(colorForTag(tag).opacity(0.15))
                        .foregroundStyle(colorForTag(tag))
                        .clipShape(Capsule())
                }
                if tags.count > maxVisible {
                    Text("+\(tags.count - maxVisible)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func colorForTag(_ tag: String) -> Color {
        if let predefined = PredefinedTag(rawValue: tag) {
            return predefined.color
        }
        let hash = abs(tag.hashValue)
        let colors: [Color] = [.blue, .green, .purple, .pink, .orange, .mint, .teal, .indigo]
        return colors[hash % colors.count]
    }
}

#Preview {
    let item = DataStampItem(contentType: .text, contentHash: Data(), title: "Test", tags: ["Important", "Work"])
    return TagsEditorView(item: item)
        .modelContainer(for: [DataStampItem.self], inMemory: true)
}
