//
//  IconPreviewView.swift
//  ProBrowse
//
//  Preview view for Apple IIgs icon files ($CA/ICN)
//

import SwiftUI

struct IconPreviewView: View {
    let entry: DiskCatalogEntry

    @State private var iconFile: AppleIIgsIconFile?
    @State private var scale: Double = 4.0
    @State private var errorMessage: String?
    @State private var showTransparency: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.headline)
                    Text("Apple IIgs Icon File")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let iconFile = iconFile {
                    Text("\(iconFile.entries.count) icon\(iconFile.entries.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.blue)

                    Divider()
                        .frame(height: 30)
                        .padding(.horizontal, 8)
                }

                // Transparency toggle
                Toggle(isOn: $showTransparency) {
                    Image(systemName: "checkerboard.rectangle")
                        .foregroundColor(.secondary)
                }
                .toggleStyle(.checkbox)
                .help("Show transparency checkerboard")

                Divider()
                    .frame(height: 30)
                    .padding(.horizontal, 8)

                // Scale picker
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    Picker(selection: $scale) {
                        Text("2x").tag(2.0)
                        Text("4x").tag(4.0)
                        Text("6x").tag(6.0)
                        Text("8x").tag(8.0)
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Content
            if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Unable to decode icons")
                        .font(.headline)
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let iconFile = iconFile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(iconFile.entries.enumerated()), id: \.offset) { index, iconEntry in
                            IconEntryView(
                                entry: iconEntry,
                                index: index,
                                scale: Int(scale),
                                showTransparency: showTransparency
                            )
                        }
                    }
                    .padding()
                }
            } else {
                ProgressView("Decoding icons...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            decodeIcons()
        }
    }

    private func decodeIcons() {
        guard entry.data.count > 0 else {
            errorMessage = "No icon data"
            return
        }

        if let decoded = AppleIIgsIconDecoder.decode(data: entry.data) {
            iconFile = decoded
        } else {
            let hexDump = entry.data.prefix(64).map { String(format: "%02X", $0) }.joined(separator: " ")
            errorMessage = "Invalid or unsupported icon format\n\nFile size: \(entry.data.count) bytes\nFirst 64 bytes:\n\(hexDump)"
        }
    }
}

// MARK: - Icon Entry View

private struct IconEntryView: View {
    let entry: AppleIIgsIconEntry
    let index: Int
    let scale: Int
    let showTransparency: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Pathname
                HStack {
                    Image(systemName: "folder")
                        .foregroundColor(.secondary)
                    Text(entry.pathname)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }

                HStack(alignment: .top, spacing: 24) {
                    // Large icon
                    if let largeIcon = entry.largeIcon {
                        VStack(spacing: 4) {
                            Text("Large")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            IconImageView(icon: largeIcon, scale: scale, showTransparency: showTransparency)

                            Text("\(largeIcon.width)×\(largeIcon.height)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Small icon
                    if let smallIcon = entry.smallIcon {
                        VStack(spacing: 4) {
                            Text("Small")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            IconImageView(icon: smallIcon, scale: scale, showTransparency: showTransparency)

                            Text("\(smallIcon.width)×\(smallIcon.height)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
            }
            .padding(8)
        } label: {
            Text("Icon \(index + 1)")
        }
    }
}

// MARK: - Icon Image View

private struct IconImageView: View {
    let icon: AppleIIgsIconImage
    let scale: Int
    let showTransparency: Bool

    var body: some View {
        if let image = renderImage() {
            Image(image, scale: 1.0, label: Text("Icon"))
                .interpolation(.none)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: CGFloat(icon.width * scale), height: CGFloat(icon.height * scale))
                .overlay(
                    Text("?")
                        .foregroundColor(.secondary)
                )
        }
    }

    private func renderImage() -> CGImage? {
        if showTransparency {
            return AppleIIgsIconDecoder.renderIconWithBackground(icon, scale: scale, checkerSize: max(2, scale))
        } else {
            return AppleIIgsIconDecoder.renderIcon(icon, scale: scale)
        }
    }
}

#Preview {
    IconPreviewView(entry: DiskCatalogEntry(
        name: "FINDER.ICONS",
        fileType: 0xCA,
        fileTypeString: "ICN",
        auxType: 0,
        size: 4096,
        blocks: 8,
        loadAddress: nil,
        length: 4096,
        data: Data(),
        isImage: false,
        isDirectory: false,
        children: nil
    ))
    .frame(width: 600, height: 500)
}
