//
//  FontPreviewView.swift
//  ProBrowse
//
//  Preview view for Apple IIgs bitmap fonts
//

import SwiftUI

struct FontPreviewView: View {
    let entry: DiskCatalogEntry

    @State private var decodedFont: AppleIIgsFont?
    @State private var sampleImage: CGImage?
    @State private var gridImage: CGImage?
    @State private var scale: Double = 2.0
    @State private var errorMessage: String?

    private let sampleText = "The quick brown fox jumps over the lazy dog. 0123456789"
    private let sampleText2 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz"

    var body: some View {
        VStack(spacing: 0) {
            // Header with font info
            if let font = decodedFont {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.headline)
                        Text("Apple IIgs Font")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(font.fontHeight)pt")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("Chars: \(font.firstChar)-\(font.lastChar)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()
                        .frame(height: 30)
                        .padding(.horizontal, 8)

                    // Scale picker
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .foregroundColor(.secondary)
                            .font(.caption)

                        Picker(selection: $scale) {
                            Text("1x").tag(1.0)
                            Text("2x").tag(2.0)
                            Text("3x").tag(3.0)
                            Text("4x").tag(4.0)
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
            }

            if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "textformat.alt")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Unable to decode font")
                        .font(.headline)
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if decodedFont != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Sample text section
                        GroupBox("Sample Text") {
                            ScrollView(.horizontal, showsIndicators: true) {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let sample = sampleImage {
                                        Image(sample, scale: 1.0 / scale, label: Text("Sample"))
                                            .interpolation(.none)
                                    }

                                    // Render second sample line
                                    if let font = decodedFont,
                                       let sample2 = AppleIIgsFontDecoder.renderText(font: font, text: sampleText2) {
                                        Image(sample2, scale: 1.0 / scale, label: Text("Sample 2"))
                                            .interpolation(.none)
                                    }
                                }
                                .padding(8)
                                .background(Color.white)
                            }
                        }

                        // Character grid section
                        GroupBox("Character Map") {
                            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                                if let grid = gridImage {
                                    Image(grid, scale: 1.0 / scale, label: Text("Character Grid"))
                                        .interpolation(.none)
                                }
                            }
                            .frame(maxHeight: 400)
                        }

                        // Font metrics section
                        if let font = decodedFont {
                            GroupBox("Font Metrics") {
                                VStack(alignment: .leading, spacing: 4) {
                                    MetricRow(label: "Height", value: "\(font.fontHeight) pixels")
                                    MetricRow(label: "Ascent", value: "\(font.ascent) pixels")
                                    MetricRow(label: "Descent", value: "\(font.descent) pixels")
                                    MetricRow(label: "Leading", value: "\(font.leading) pixels")
                                    MetricRow(label: "Max Width", value: "\(font.maxWidth) pixels")
                                    MetricRow(label: "Characters", value: "\(font.firstChar) - \(font.lastChar) (\(font.characterCount) chars)")
                                    MetricRow(label: "Font Type", value: String(format: "$%04X", font.fontType))
                                }
                                .padding(4)
                            }
                        }
                    }
                    .padding()
                }
            } else {
                ProgressView("Decoding font...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            decodeFont()
        }
        .onChange(of: scale) { _, _ in
            // Images already rendered, just re-scaling
        }
    }

    private func decodeFont() {
        guard entry.data.count > 0 else {
            errorMessage = "No font data"
            return
        }

        if let font = AppleIIgsFontDecoder.decode(data: entry.data) {
            decodedFont = font

            // Render sample text
            sampleImage = AppleIIgsFontDecoder.renderText(font: font, text: sampleText)

            // Render character grid
            gridImage = AppleIIgsFontDecoder.renderCharacterGrid(font: font, columns: 16, cellPadding: 3)

            if sampleImage == nil && gridImage == nil {
                errorMessage = "Could not render font glyphs"
            }
        } else {
            // Provide more diagnostic info
            let hexDump = entry.data.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " ")
            errorMessage = "Invalid or unsupported font format\n\nFile size: \(entry.data.count) bytes\nFirst 32 bytes: \(hexDump)"
        }
    }
}

// MARK: - Metric Row Helper

private struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(.body, design: .monospaced))
            Spacer()
        }
        .font(.system(size: 12))
    }
}

#Preview {
    FontPreviewView(entry: DiskCatalogEntry(
        name: "SHASTON.8",
        fileType: 0xC8,
        fileTypeString: "FNT",
        auxType: 0,
        size: 1024,
        blocks: 2,
        loadAddress: nil,
        length: 1024,
        data: Data(),
        isImage: false,
        isDirectory: false,
        children: nil
    ))
    .frame(width: 600, height: 500)
}
