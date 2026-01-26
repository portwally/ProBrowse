//
//  HexDumpView.swift
//  ProBrowse
//
//  Hex dump view with ASCII sidebar for file inspection
//

import SwiftUI

struct HexDumpView: View {
    let data: Data

    private let bytesPerLine = 16
    private let lineHeight: CGFloat = 18
    private let maxDisplayBytes = 65536  // 64KB limit for performance

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                Text("Offset")
                    .frame(width: 70, alignment: .leading)

                Text("00 01 02 03 04 05 06 07  08 09 0A 0B 0C 0D 0E 0F")
                    .frame(width: 380, alignment: .leading)

                Text("ASCII")
                    .frame(width: 140, alignment: .leading)
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Data rows
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<lineCount, id: \.self) { lineIndex in
                        HexDumpLine(
                            data: data,
                            offset: lineIndex * bytesPerLine,
                            bytesPerLine: bytesPerLine
                        )
                        .frame(height: lineHeight)
                    }
                }
                .padding(.horizontal, 8)
            }

            // Footer with size info
            Divider()

            HStack {
                Text("\(data.count) bytes")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if data.count > maxDisplayBytes {
                    Text("(showing first \(maxDisplayBytes) bytes)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private var lineCount: Int {
        let displayCount = min(data.count, maxDisplayBytes)
        return (displayCount + bytesPerLine - 1) / bytesPerLine
    }
}

struct HexDumpLine: View {
    let data: Data
    let offset: Int
    let bytesPerLine: Int

    var body: some View {
        HStack(spacing: 0) {
            // Offset column
            Text(String(format: "%06X:", offset))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)

            // Hex bytes - first 8
            HStack(spacing: 4) {
                ForEach(0..<8, id: \.self) { i in
                    hexByte(at: i)
                }
            }
            .frame(width: 185, alignment: .leading)

            Text(" ")
                .frame(width: 10)

            // Hex bytes - second 8
            HStack(spacing: 4) {
                ForEach(8..<16, id: \.self) { i in
                    hexByte(at: i)
                }
            }
            .frame(width: 185, alignment: .leading)

            // ASCII column
            Text(asciiString)
                .foregroundColor(.primary)
                .frame(width: 140, alignment: .leading)
        }
        .font(.system(size: 11, design: .monospaced))
    }

    @ViewBuilder
    private func hexByte(at index: Int) -> some View {
        let byteOffset = offset + index
        if byteOffset < data.count {
            let byte = data[byteOffset]
            Text(String(format: "%02X", byte))
                .foregroundColor(byteColor(byte))
        } else {
            Text("  ")
                .foregroundColor(.clear)
        }
    }

    private func byteColor(_ byte: UInt8) -> Color {
        return .blue
    }

    private var asciiString: String {
        var result = ""
        for i in 0..<bytesPerLine {
            let byteOffset = offset + i
            if byteOffset < data.count {
                let byte = data[byteOffset]
                // Handle high-ASCII (Apple II uses high bit set for normal text)
                let lowByte = byte & 0x7F
                if lowByte >= 0x20 && lowByte < 0x7F {
                    result += String(UnicodeScalar(lowByte))
                } else {
                    result += "."
                }
            } else {
                result += " "
            }
        }
        return result
    }
}

#Preview {
    HexDumpView(data: Data(repeating: 0x41, count: 256))
        .frame(width: 600, height: 400)
}
