//
//  FileInfoSheet.swift
//  ProBrowse
//
//  Sheet for inspecting individual file/directory properties
//

import SwiftUI

struct FileInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entry: DiskCatalogEntry
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(entry.isDirectory ? "📂 Directory Info" : "📄 File Info")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Basic Info
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Basic Information")
                        
                        InfoRow(label: "Name", value: entry.name)
                        InfoRow(label: "Type", value: entry.isDirectory ? "Directory" : entry.fileTypeString)
                        InfoRow(label: "Size", value: formatBytes(entry.size))
                        
                        if !entry.isDirectory {
                            InfoRow(label: "Blocks Used", value: "\(entry.blocksUsed)")
                        }
                    }
                    
                    Divider()
                    
                    // Technical Details
                    if !entry.isDirectory {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Technical Details")
                            
                            InfoRow(label: "File Type", value: String(format: "$%02X", entry.fileType))
                            InfoRow(label: "Aux Type", value: String(format: "$%04X", entry.auxType))
                            InfoRow(label: "Storage Type", value: storageTypeName(entry.storageType))
                            
                            if let description = fileTypeDescription {
                                InfoRow(label: "Description", value: description)
                            }
                        }
                        
                        Divider()
                    }
                    
                    // Dates
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Dates")
                        
                        if let created = entry.creationDate {
                            InfoRow(label: "Created", value: formatDate(created))
                        } else {
                            InfoRow(label: "Created", value: "—")
                        }
                        
                        if let modified = entry.modificationDate {
                            InfoRow(label: "Modified", value: formatDate(modified))
                        } else {
                            InfoRow(label: "Modified", value: "—")
                        }
                    }
                    
                    // Directory Info
                    if entry.isDirectory {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Directory Contents")
                            
                            let childCount = entry.children?.count ?? 0
                            InfoRow(label: "Items", value: "\(childCount)")
                            
                            if let children = entry.children, !children.isEmpty {
                                let files = children.filter { !$0.isDirectory }.count
                                let dirs = children.filter { $0.isDirectory }.count
                                
                                InfoRow(label: "Files", value: "\(files)")
                                InfoRow(label: "Subdirectories", value: "\(dirs)")
                                
                                let totalSize = children.reduce(0) { $0 + $1.size }
                                InfoRow(label: "Total Size", value: formatBytes(totalSize))
                            }
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
    }
    
    private var fileTypeDescription: String? {
        // Get human-readable description for common file types
        switch entry.fileType {
        case 0x04: return "Text File"
        case 0x06: return "Binary File"
        case 0x0F: return "Directory"
        case 0x19: return "AppleWorks Database"
        case 0x1A: return "AppleWorks Word Processor"
        case 0x1B: return "AppleWorks Spreadsheet"
        case 0xB0: return "QuickDraw Image"
        case 0xC0: return "Picture (PIC)"
        case 0xC1: return "Packed Picture (PNT)"
        case 0xEF: return "Pascal Area"
        case 0xF0: return "Command File"
        case 0xFA: return "Integer BASIC"
        case 0xFC: return "Applesoft BASIC"
        case 0xFD: return "Variables File"
        case 0xFE: return "Relocatable Code"
        case 0xFF: return "System File (SYS)"
        default: return nil
        }
    }
    
    private func storageTypeName(_ type: UInt8) -> String {
        switch type {
        case 0: return "Deleted"
        case 1: return "Seedling (1 block)"
        case 2: return "Sapling (index + data)"
        case 3: return "Tree (master + indices + data)"
        case 0xD: return "Subdirectory"
        case 0xE: return "Subdirectory Header"
        case 0xF: return "Volume Directory Header"
        default: return "Unknown (\(type))"
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) bytes"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Views

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.primary)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)
            
            Text(value)
                .font(.body)
                .foregroundColor(.primary)
                .textSelection(.enabled)
            
            Spacer()
        }
    }
}

#Preview {
    FileInfoSheet(entry: DiskCatalogEntry(
        name: "EXAMPLE.TXT",
        fileType: 0x04,
        auxType: 0x0000,
        size: 2048,
        blocksUsed: 4,
        creationDate: Date(),
        modificationDate: Date(),
        storageType: 1,
        isDirectory: false
    ))
}
