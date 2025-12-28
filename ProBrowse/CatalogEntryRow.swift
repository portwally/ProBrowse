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
    let onToggle: (DiskCatalogEntry, Bool, Bool) -> Void  // entry, command, shift
    let onDoubleClick: ((DiskCatalogEntry) -> Void)?  // NEW: double-click navigation
    let level: Int
    let expandAllTrigger: Bool
    @ObservedObject var columnWidths: ColumnWidths
    
    @State private var isExpanded: Bool
    
    init(entry: DiskCatalogEntry, isSelected: @escaping (DiskCatalogEntry) -> Bool, onToggle: @escaping (DiskCatalogEntry, Bool, Bool) -> Void, onDoubleClick: ((DiskCatalogEntry) -> Void)? = nil, level: Int, expandAllTrigger: Bool, columnWidths: ColumnWidths) {
        self.entry = entry
        self.isSelected = isSelected
        self.onToggle = onToggle
        self.onDoubleClick = onDoubleClick
        self.level = level
        self.expandAllTrigger = expandAllTrigger
        self.columnWidths = columnWidths
        _isExpanded = State(initialValue: expandAllTrigger)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main Row with columns
            CatalogEntryRowContent(
                entry: entry,
                isSelected: isSelected(entry),
                isExpanded: $isExpanded,
                level: level,
                onToggle: onToggle,
                onDoubleClick: onDoubleClick,
                columnWidths: columnWidths
            )
            
            // Children (if expanded)
            if isExpanded, let children = entry.children, !children.isEmpty {
                ForEach(children) { child in
                    CatalogEntryRow(
                        entry: child,
                        isSelected: isSelected,
                        onToggle: onToggle,
                        onDoubleClick: onDoubleClick,
                        level: level + 1,
                        expandAllTrigger: expandAllTrigger,
                        columnWidths: columnWidths
                    )
                }
            }
        }
        .onChange(of: expandAllTrigger) { oldValue, newValue in
            if entry.isDirectory && entry.children != nil && !entry.children!.isEmpty {
                isExpanded = newValue
            }
        }
    }
}

// MARK: - Catalog Entry Row Content

struct CatalogEntryRowContent: View {
    let entry: DiskCatalogEntry
    let isSelected: Bool
    @Binding var isExpanded: Bool
    let level: Int
    let onToggle: (DiskCatalogEntry, Bool, Bool) -> Void
    let onDoubleClick: ((DiskCatalogEntry) -> Void)?
    @ObservedObject var columnWidths: ColumnWidths
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                (isSelected ? Color.accentColor.opacity(0.3) : Color.clear)
                
                HStack(spacing: 0) {
                    // Name Column (with indentation and expand button)
                    HStack(spacing: 4) {
                        // Padding at start
                        Spacer().frame(width: 8)
                        
                        // Indentation
                        if level > 0 {
                            Spacer()
                                .frame(width: CGFloat(level * 16))
                        }
                        
                        // Expand/Collapse for ALL directories (even empty ones)
                        if entry.isDirectory {
                            Button(action: { isExpanded.toggle() }) {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .frame(width: 16, height: 16)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Spacer().frame(width: 16)
                        }
                        
                        Text(entry.icon)
                            .font(.body)
                        
                        Text(entry.name)
                            .lineLimit(1)
                            .fontWeight(entry.isDirectory ? .semibold : .regular)
                        
                        Spacer(minLength: 0)
                    }
                    .frame(width: columnWidths.nameWidth, alignment: .leading)
                    
                    Divider().frame(width: 1).opacity(0.3)
                    
                    // Type Column
                    HStack(spacing: 0) {
                        Spacer().frame(width: 8)
                        Text(entry.fileTypeString)
                            .font(.caption)
                        Spacer(minLength: 0)
                    }
                    .frame(width: columnWidths.typeWidth, alignment: .leading)
                    
                    Divider().frame(width: 1).opacity(0.3)
                    
                    // Aux Column
                    HStack(spacing: 0) {
                        Spacer().frame(width: 8)
                        Text(String(format: "$%04X", entry.auxType))
                            .font(.caption)
                            .monospacedDigit()
                        Spacer(minLength: 0)
                    }
                    .frame(width: columnWidths.auxWidth, alignment: .leading)
                    
                    Divider().frame(width: 1).opacity(0.3)
                    
                    // Size Column (in bytes)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Text("\(entry.size)")
                            .font(.caption)
                            .monospacedDigit()
                        Spacer().frame(width: 8)
                    }
                    .frame(width: columnWidths.sizeWidth, alignment: .trailing)
                    
                    Divider().frame(width: 1).opacity(0.3)
                    
                    // Modified Column
                    HStack(spacing: 0) {
                        Spacer().frame(width: 8)
                        Text(entry.modificationDate ?? "—")
                            .font(.caption)
                        Spacer(minLength: 0)
                    }
                    .frame(width: columnWidths.modifiedWidth, alignment: .leading)
                    
                    Divider().frame(width: 1).opacity(0.3)
                    
                    // Created Column
                    HStack(spacing: 0) {
                        Spacer().frame(width: 8)
                        Text(entry.creationDate ?? "—")
                            .font(.caption)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(height: 22)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            // Double-click: navigate into directory
            if entry.isDirectory, let onDoubleClick = onDoubleClick {
                print("🖱️ Double-click on directory: \(entry.name)")
                onDoubleClick(entry)
            }
        }
        .onTapGesture {
            let event = NSApp.currentEvent
            let commandPressed = event?.modifierFlags.contains(.command) ?? false
            let shiftPressed = event?.modifierFlags.contains(.shift) ?? false
            
            print("🔘 Toggle selection for: \(entry.name)")
            print("   Current selected count: \(isSelected ? 1 : 0)")
            print("   Command: \(commandPressed), Shift: \(shiftPressed)")
            
            onToggle(entry, commandPressed, shiftPressed)
        }
    }
}
