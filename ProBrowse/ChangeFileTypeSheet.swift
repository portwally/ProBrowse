//
//  ChangeFileTypeSheet.swift
//  ProBrowse
//
//  Sheet for changing file type and aux type of ProDOS files
//

import SwiftUI

struct ChangeFileTypeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entry: DiskCatalogEntry
    let onSave: (UInt8, UInt16) -> Void

    @State private var fileTypeHex: String
    @State private var auxTypeHex: String
    @State private var errorMessage: String?

    init(entry: DiskCatalogEntry, onSave: @escaping (UInt8, UInt16) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _fileTypeHex = State(initialValue: String(format: "%02X", entry.fileType))
        _auxTypeHex = State(initialValue: String(format: "%04X", entry.auxType))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Change File Type")
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
            VStack(alignment: .leading, spacing: 20) {
                // File name (read-only)
                VStack(alignment: .leading, spacing: 8) {
                    Text("File Name")
                        .font(.headline)
                    Text(entry.name)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Divider()

                // File Type
                VStack(alignment: .leading, spacing: 8) {
                    Text("File Type")
                        .font(.headline)

                    HStack {
                        Text("$")
                            .font(.body.monospaced())
                            .foregroundColor(.secondary)

                        TextField("00", text: $fileTypeHex)
                            .font(.body.monospaced())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .onChange(of: fileTypeHex) { _, newValue in
                                // Filter to hex characters and limit to 2
                                let filtered = newValue.uppercased().filter { "0123456789ABCDEF".contains($0) }
                                if filtered.count > 2 {
                                    fileTypeHex = String(filtered.prefix(2))
                                } else {
                                    fileTypeHex = filtered
                                }
                                updateDescription()
                            }

                        if let info = currentFileTypeInfo {
                            Text("(\(info.shortName))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Common file types
                    Text("Common types:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        FileTypeButton(label: "TXT", type: 0x04, currentType: $fileTypeHex)
                        FileTypeButton(label: "BIN", type: 0x06, currentType: $fileTypeHex)
                        FileTypeButton(label: "SYS", type: 0xFF, currentType: $fileTypeHex)
                        FileTypeButton(label: "BAS", type: 0xFC, currentType: $fileTypeHex)
                        FileTypeButton(label: "AWP", type: 0x1A, currentType: $fileTypeHex)
                    }
                }

                Divider()

                // Aux Type
                VStack(alignment: .leading, spacing: 8) {
                    Text("Aux Type")
                        .font(.headline)

                    HStack {
                        Text("$")
                            .font(.body.monospaced())
                            .foregroundColor(.secondary)

                        TextField("0000", text: $auxTypeHex)
                            .font(.body.monospaced())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onChange(of: auxTypeHex) { _, newValue in
                                // Filter to hex characters and limit to 4
                                let filtered = newValue.uppercased().filter { "0123456789ABCDEF".contains($0) }
                                if filtered.count > 4 {
                                    auxTypeHex = String(filtered.prefix(4))
                                } else {
                                    auxTypeHex = filtered
                                }
                            }

                        Text("(Load address for BIN)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Common aux types
                    Text("Common values:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        AuxTypeButton(label: "$0000", type: 0x0000, currentType: $auxTypeHex)
                        AuxTypeButton(label: "$0800", type: 0x0800, currentType: $auxTypeHex)
                        AuxTypeButton(label: "$2000", type: 0x2000, currentType: $auxTypeHex)
                        AuxTypeButton(label: "$4000", type: 0x4000, currentType: $auxTypeHex)
                    }
                }

                // Description
                if let info = currentFileTypeInfo {
                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.headline)
                        Text("\(info.icon) \(info.description)")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding()

            Divider()

            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 400, height: 520)
    }

    private var currentFileTypeInfo: ProDOSFileTypeInfo? {
        guard let fileType = UInt8(fileTypeHex, radix: 16) else { return nil }
        let auxType = UInt16(auxTypeHex, radix: 16) ?? 0
        return ProDOSFileTypeInfo.getFileTypeInfo(fileType: fileType, auxType: auxType)
    }

    private var isValid: Bool {
        guard !fileTypeHex.isEmpty else { return false }
        guard UInt8(fileTypeHex, radix: 16) != nil else { return false }
        guard auxTypeHex.isEmpty || UInt16(auxTypeHex, radix: 16) != nil else { return false }
        return true
    }

    private func updateDescription() {
        errorMessage = nil
    }

    private func save() {
        guard let fileType = UInt8(fileTypeHex, radix: 16) else {
            errorMessage = "Invalid file type"
            return
        }

        let auxType = UInt16(auxTypeHex, radix: 16) ?? 0

        onSave(fileType, auxType)
        dismiss()
    }
}

// MARK: - File Type Button

struct FileTypeButton: View {
    let label: String
    let type: UInt8
    @Binding var currentType: String

    var body: some View {
        Button(label) {
            currentType = String(format: "%02X", type)
        }
        .buttonStyle(.bordered)
        .font(.caption)
    }
}

// MARK: - Aux Type Button

struct AuxTypeButton: View {
    let label: String
    let type: UInt16
    @Binding var currentType: String

    var body: some View {
        Button(label) {
            currentType = String(format: "%04X", type)
        }
        .buttonStyle(.bordered)
        .font(.caption)
    }
}

#Preview {
    ChangeFileTypeSheet(
        entry: DiskCatalogEntry(
            name: "EXAMPLE.BIN",
            fileType: 0x06,
            fileTypeString: "BIN",
            auxType: 0x2000,
            size: 2048,
            blocks: 4,
            loadAddress: nil,
            length: nil,
            data: Data(),
            isImage: false,
            isDirectory: false,
            children: nil
        ),
        onSave: { _, _ in }
    )
}
