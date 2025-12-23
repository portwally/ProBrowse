//
//  CatalogEntryRow.swift
//  ProBrowse
//
//  Row view for catalog entries with checkbox and hierarchy support
//

import SwiftUI

struct CatalogEntryRow: View {
    let entry: DiskCatalogEntry
    let isSelected: (DiskCatalogEntry) -> Bool
    let onToggle: (DiskCatalogEntry) -> Void
    let level: Int
    let expandAllTrigger: Bool
    
    @State private var isExpanded: Bool
    
    init(entry: DiskCatalogEntry, isSelected: @escaping (DiskCatalogEntry) -> Bool, onToggle: @escaping (DiskCatalogEntry) -> Void, level: Int, expandAllTrigger: Bool) {
        self.entry = entry
        self.isSelected = isSelected
        self.onToggle = onToggle
        self.level = level
        self.expandAllTrigger = expandAllTrigger
        _isExpanded = State(initialValue: expandAllTrigger)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main Row
            HStack(spacing: 8) {
                // Indentation for hierarchy
                if level > 0 {
                    ForEach(0..<level, id: \.self) { _ in
                        Text("  ")
                    }
                    Text("└─")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Checkbox
                Button(action: {
                    onToggle(entry)
                }) {
                    Image(systemName: isSelected(entry) ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected(entry) ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 30)
                
                // Expand/Collapse for folders
                if entry.isDirectory && entry.children != nil && !entry.children!.isEmpty {
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else if entry.isDirectory {
                    Spacer()
                        .frame(width: 20)
                }
                
                Text(entry.icon)
                    .font(.title3)
                
                Text(entry.name)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fontWeight(entry.isDirectory ? .semibold : .regular)
                
                Text(entry.typeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)
                
                Text(entry.sizeString)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .trailing)
                
                if let loadAddr = entry.loadAddress {
                    Text(String(format: "$%04X", loadAddr))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)
                } else {
                    Text("-")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isSelected(entry) ? Color.blue.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                onToggle(entry)
            }
            
            // Show children when expanded
            if entry.isDirectory && isExpanded, let children = entry.children {
                ForEach(children) { child in
                    CatalogEntryRowRecursive(
                        entry: child,
                        isSelected: isSelected,
                        onToggle: onToggle,
                        level: level + 1,
                        expandAllTrigger: expandAllTrigger
                    )
                }
            }
        }
        .onChange(of: expandAllTrigger) { newValue in
            isExpanded = newValue
        }
    }
}

// Recursive wrapper
struct CatalogEntryRowRecursive: View {
    let entry: DiskCatalogEntry
    let isSelected: (DiskCatalogEntry) -> Bool
    let onToggle: (DiskCatalogEntry) -> Void
    let level: Int
    let expandAllTrigger: Bool
    
    var body: some View {
        CatalogEntryRow(
            entry: entry,
            isSelected: isSelected,
            onToggle: onToggle,
            level: level,
            expandAllTrigger: expandAllTrigger
        )
    }
}
