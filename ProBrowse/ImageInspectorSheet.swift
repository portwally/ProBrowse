//
//  ImageInspectorSheet.swift
//  ProBrowse
//
//  Sheet for inspecting disk image properties
//

import SwiftUI
import Combine

struct ImageInspectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: DiskPaneViewModel
    
    @State private var verificationResult: String?
    @State private var isVerifying = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Disk Image Inspector")
                .font(.title2)
                .fontWeight(.semibold)
            
            if let catalog = viewModel.catalog, let imagePath = viewModel.diskImagePath {
                VStack(alignment: .leading, spacing: 16) {
                    // Image Info
                    Group {
                        InfoRow(label: "Volume Name", value: catalog.diskName)
                        InfoRow(label: "Format", value: catalog.diskFormat)
                        InfoRow(label: "File", value: imagePath.lastPathComponent)
                        InfoRow(label: "Path", value: imagePath.path)
                        InfoRow(label: "Size", value: formatBytes(catalog.diskSize))
                    }
                    
                    Divider()
                    
                    // Statistics
                    Group {
                        InfoRow(label: "Total Files", value: "\(catalog.totalFiles)")
                        InfoRow(label: "Image Files", value: "\(catalog.imageFiles)")
                        InfoRow(label: "Root Entries", value: "\(catalog.entries.count)")
                    }
                    
                    Divider()
                    
                    // Actions
                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: verifyImage) {
                            HStack {
                                if isVerifying {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "checkmark.shield")
                                }
                                Text("Verify Image Integrity")
                            }
                        }
                        .disabled(isVerifying)
                        
                        if let result = verificationResult {
                            Text(result)
                                .font(.caption)
                                .foregroundColor(result.contains("✅") ? .green : .red)
                                .padding(.leading, 24)
                        }
                        
                        Button(action: {
                            NSWorkspace.shared.activateFileViewerSelecting([imagePath])
                        }) {
                            HStack {
                                Image(systemName: "folder")
                                Text("Show in Finder")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No disk image loaded")
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack {
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500, height: 500)
    }
    
    private func verifyImage() {
        guard let imagePath = viewModel.diskImagePath else { return }
        
        isVerifying = true
        verificationResult = nil
        
        CadiusManager.shared.verifyVolume(diskImage: imagePath) { success, message in
            isVerifying = false
            
            if success {
                verificationResult = "✅ Image verified successfully"
            } else {
                verificationResult = "❌ Verification failed: \(message)"
            }
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.body, design: .monospaced))
    }
}

#Preview {
    ImageInspectorSheet(viewModel: DiskPaneViewModel())
}
