//
//  FileInspectorSheet.swift
//  ProBrowse
//
//  File inspector with tabbed interface for viewing file contents
//

import SwiftUI

struct FileInspectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entry: DiskCatalogEntry

    enum InspectorTab: String, CaseIterable {
        case content = "Content"
        case hex = "Hex"
        case info = "Info"
    }

    @State private var selectedTab: InspectorTab = .content

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(entry.name)
                    .font(.headline)

                Spacer()

                // Placeholder for symmetry
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.clear)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Tab Picker
            Picker(selection: $selectedTab) {
                ForEach(InspectorTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Tab Content
            switch selectedTab {
            case .content:
                FileContentView(entry: entry)
            case .hex:
                HexDumpView(data: entry.data)
            case .info:
                FileInfoView(entry: entry)
            }

            Divider()

            // Footer
            HStack {
                Text("\(entry.data.count) bytes")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
        }
        .frame(width: 700, height: 800)
    }
}

// MARK: - File Content View

struct FileContentView: View {
    let entry: DiskCatalogEntry

    var body: some View {
        Group {
            switch detectContentType() {
            case .text:
                TextContentView(data: entry.data)
            case .applesoftBasic:
                BasicListingView(data: entry.data, isApplesoft: true)
            case .integerBasic:
                BasicListingView(data: entry.data, isApplesoft: false)
            case .graphics:
                GraphicsPreviewView(entry: entry)
            case .font:
                FontPreviewView(entry: entry)
            case .icon:
                IconPreviewView(entry: entry)
            case .binary:
                HexDumpView(data: entry.data)
            }
        }
    }

    enum FileContentType {
        case text
        case applesoftBasic
        case integerBasic
        case graphics
        case font
        case icon
        case binary
    }

    private func detectContentType() -> FileContentType {
        // Check by ProDOS file type
        switch entry.fileType {
        case 0x04:  // TXT
            return .text
        case 0xFC:  // BAS (Applesoft)
            return .applesoftBasic
        case 0xFA:  // INT (Integer BASIC)
            return .integerBasic
        case 0x06:  // BIN - check if graphics by size
            if isLikelyGraphics() {
                return .graphics
            }
            return .binary
        case 0x08:  // FOT (Apple II Graphics)
            return .graphics
        case 0xC0:  // PNT (Packed SHR)
            return .graphics
        case 0xC1:  // PIC (SHR)
            return .graphics
        case 0xC8:  // FNT (Apple IIgs Font)
            return .font
        case 0xCA:  // ICN (Apple IIgs Icons)
            return .icon
        case 0xB3:  // APP - Some SHR files use this type
            if isLikelyGraphics() {
                return .graphics
            }
            return .binary
        default:
            // Check if it looks like text
            if isLikelyText() {
                return .text
            }
            return .binary
        }
    }

    private func isLikelyGraphics() -> Bool {
        let size = entry.data.count
        let auxType = entry.auxType

        // Check aux type hints for graphics load addresses
        if auxType == 0x2000 || auxType == 0x4000 {
            // HGR load addresses - accept HGR size range
            if size >= 8184 && size <= 8200 {
                return true
            }
        }

        // Common Apple II graphics sizes
        return (size >= 8184 && size <= 8200) ||  // HGR (8192 typical, 8184 common)
               size == 16384 ||                    // DHGR
               (size >= 32000 && size <= 32768) || // SHR
               (size >= 38400 && size <= 39000)    // 3200-color SHR
    }

    private func isLikelyText() -> Bool {
        guard entry.data.count > 0 else { return false }

        // Sample first 256 bytes
        let sampleSize = min(256, entry.data.count)
        var printableCount = 0

        for i in 0..<sampleSize {
            let byte = entry.data[i]
            let lowByte = byte & 0x7F  // Handle high-ASCII
            if (lowByte >= 0x20 && lowByte < 0x7F) || lowByte == 0x0D || lowByte == 0x0A {
                printableCount += 1
            }
        }

        // If more than 80% is printable, treat as text
        return Double(printableCount) / Double(sampleSize) > 0.8
    }
}

// MARK: - Text Content View

struct TextContentView: View {
    let data: Data

    var body: some View {
        ScrollView {
            Text(convertToText())
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
    }

    private func convertToText() -> String {
        var result = ""
        for byte in data {
            // Handle Apple II high-ASCII (high bit set for normal text)
            let lowByte = byte & 0x7F
            if lowByte >= 0x20 && lowByte < 0x7F {
                result += String(UnicodeScalar(lowByte))
            } else if lowByte == 0x0D {
                result += "\n"
            } else if lowByte == 0x0A {
                // Skip LF if it follows CR
            } else if lowByte == 0x00 {
                // End of text in some formats
                break
            } else {
                result += "."
            }
        }
        return result
    }
}

// MARK: - BASIC Listing View

struct BasicListingView: View {
    let data: Data
    let isApplesoft: Bool

    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(getLines().enumerated()), id: \.offset) { index, line in
                    BasicLineView(line: line, isApplesoft: isApplesoft, isEvenRow: index % 2 == 0)
                }
            }
            .padding(.vertical, 4)
        }
        .textSelection(.enabled)
    }

    private func getLines() -> [String] {
        let listing = isApplesoft
            ? ApplesoftDetokenizer.detokenize(data)
            : IntegerBasicDetokenizer.detokenize(data)
        return listing.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
}

struct BasicLineView: View {
    let line: String
    let isApplesoft: Bool
    let isEvenRow: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            // Line number (first part before space)
            if let spaceIndex = line.firstIndex(of: " ") {
                let lineNum = String(line[..<spaceIndex])
                let code = String(line[line.index(after: spaceIndex)...])

                // Line number column - compact, fixed width
                Text(lineNum)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.yellow)
                    .frame(width: 45, alignment: .trailing)

                // Code - single line, no wrap
                Text(attributedCode(code))
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.leading, 8)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                Text(line)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.leading, 53)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func highlightedCode(_ code: String) -> some View {
        Text(attributedCode(code))
            .font(.system(size: 13, design: .monospaced))
    }

    private func attributedCode(_ code: String) -> AttributedString {
        var result = AttributedString(code)

        // Highlight strings (text between quotes)
        let stringPattern = "\"[^\"]*\""
        if let regex = try? NSRegularExpression(pattern: stringPattern) {
            let range = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: range) {
                if let swiftRange = Range(match.range, in: code),
                   let attrRange = Range(swiftRange, in: result) {
                    result[attrRange].foregroundColor = .green
                }
            }
        }

        // Highlight REM comments (everything after REM)
        if let remRange = code.range(of: "REM") {
            let commentStart = remRange.lowerBound
            if let attrRange = Range(commentStart..<code.endIndex, in: result) {
                result[attrRange].foregroundColor = .gray
                result[attrRange].inlinePresentationIntent = .emphasized
            }
        }

        // Highlight keywords
        let keywords = [
            "GOTO", "GOSUB", "RETURN", "IF", "THEN", "FOR", "TO", "STEP", "NEXT",
            "PRINT", "INPUT", "LET", "DIM", "READ", "DATA", "END", "STOP",
            "ON", "POKE", "PEEK", "CALL", "HOME", "HTAB", "VTAB", "TEXT", "GR", "HGR",
            "HCOLOR=", "COLOR=", "PLOT", "HPLOT", "HLIN", "VLIN", "DRAW", "XDRAW",
            "GET", "DEF", "FN", "AND", "OR", "NOT", "ONERR", "RESUME"
        ]

        for keyword in keywords {
            var searchStart = code.startIndex
            while let range = code.range(of: keyword, range: searchStart..<code.endIndex) {
                // Only highlight if it's a whole word (not part of a variable name)
                let beforeOK = range.lowerBound == code.startIndex ||
                    !code[code.index(before: range.lowerBound)].isLetter
                let afterOK = range.upperBound == code.endIndex ||
                    !code[range.upperBound].isLetter

                if beforeOK && afterOK {
                    if let attrRange = Range(range, in: result) {
                        result[attrRange].foregroundColor = .cyan
                    }
                }
                searchStart = range.upperBound
            }
        }

        return result
    }
}

// MARK: - Graphics Preview View

struct GraphicsPreviewView: View {
    let entry: DiskCatalogEntry

    @State private var decodedImage: CGImage?
    @State private var imageType: AppleIIImageType = .Unknown
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var scale: Double = 2.0

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                if imageType != .Unknown {
                    Text(imageType.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    let res = imageType.resolution
                    Text("\(res.width)x\(res.height)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .foregroundColor(.secondary)
                    .font(.caption)

                Picker(selection: $scale) {
                    Text("1x").tag(1.0)
                    Text("2x").tag(2.0)
                    Text("3x").tag(3.0)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Image display
            ScrollView([.horizontal, .vertical]) {
                if isLoading {
                    ProgressView("Decoding...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let image = decodedImage {
                    Image(decorative: image, scale: 1.0)
                        .interpolation(.none)
                        .scaleEffect(scale)
                        .frame(
                            width: CGFloat(image.width) * scale,
                            height: CGFloat(image.height) * scale
                        )
                        .background(Color.black)
                } else if let error = errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("Unable to decode image")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            decodeImage()
        }
    }

    private func decodeImage() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            let result = AppleIIDecoder.detectAndDecode(
                data: entry.data,
                fileType: entry.fileType,
                auxType: entry.auxType
            )

            DispatchQueue.main.async {
                self.decodedImage = result.image
                self.imageType = result.type
                self.isLoading = false

                if result.image == nil && result.type == .Unknown {
                    self.errorMessage = "Unknown or unsupported graphics format"
                }
            }
        }
    }
}

// MARK: - File Info View

struct FileInfoView: View {
    let entry: DiskCatalogEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // File Section
                GroupBox("File") {
                    VStack(alignment: .leading, spacing: 6) {
                        FileInfoRow(label: "File name", value: entry.name)
                        FileInfoRow(label: "File type", value: String(format: "$%02X (%@)", entry.fileType, entry.fileTypeString))
                        FileInfoHexRow(label: "EOF", hex: entry.size, width: 6)
                        if let blocks = entry.blocks {
                            FileInfoHexRow(label: "Blocks used", hex: blocks, width: 4)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Catalog Entry Section
                GroupBox("Catalog Entry") {
                    VStack(alignment: .leading, spacing: 6) {
                        if let storageType = entry.storageType {
                            FileInfoHexRow(label: "Storage type", hex: Int(storageType), width: 2, suffix: entry.storageTypeDescription)
                        }
                        FileInfoHexRow(label: "File type", hex: Int(entry.fileType), width: 2, suffix: entry.fileTypeString)
                        if let keyPtr = entry.keyPointer {
                            FileInfoHexRow(label: "Key ptr", hex: keyPtr, width: 4)
                        }
                        if let blocks = entry.blocks {
                            FileInfoHexRow(label: "Blocks used", hex: blocks, width: 4)
                        }
                        FileInfoHexRow(label: "EOF", hex: entry.size, width: 6)
                        FileInfoHexRow(label: "Auxtype", hex: Int(entry.auxType), width: 4)

                        if let access = entry.accessFlags {
                            FileInfoHexRow(label: "Access", hex: Int(access), width: 2, suffix: entry.accessFlagsDescription)
                        }
                        if let version = entry.version {
                            FileInfoHexRow(label: "Version", hex: Int(version), width: 2)
                        }
                        if let minVersion = entry.minVersion {
                            FileInfoHexRow(label: "Min version", hex: Int(minVersion), width: 2)
                        }
                        if let headerPtr = entry.headerPointer, headerPtr > 0 {
                            FileInfoHexRow(label: "Header ptr", hex: headerPtr, width: 4)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Dates Section
                if entry.creationDate != nil || entry.modificationDate != nil {
                    GroupBox("Dates") {
                        VStack(alignment: .leading, spacing: 6) {
                            if let created = entry.creationDate {
                                FileInfoRow(label: "Created", value: created)
                            }
                            if let modified = entry.modificationDate {
                                FileInfoRow(label: "Modified", value: modified)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Data Statistics
                GroupBox("Data") {
                    VStack(alignment: .leading, spacing: 6) {
                        FileInfoHexRow(label: "Data size", hex: entry.data.count, width: 6)
                        if entry.data.count > 0 {
                            FileInfoRow(label: "First byte", value: String(format: "$%02X", entry.data[0]))
                            if entry.data.count >= 2 {
                                let lastByte = entry.data[entry.data.count - 1]
                                FileInfoRow(label: "Last byte", value: String(format: "$%02X", lastByte))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
    }
}

// MARK: - File Info Row Helpers

struct FileInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer()
        }
        .font(.system(size: 12, design: .monospaced))
    }
}

/// Displays a value in hex and decimal format, similar to DiskBrowser2
struct FileInfoHexRow: View {
    let label: String
    let hex: Int
    let width: Int  // Number of hex digits (2, 4, or 6)
    var suffix: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)

            // Hex value
            Text(hexString)
                .foregroundColor(.blue)
                .frame(width: 60, alignment: .trailing)

            // Decimal value
            Text(decimalString)
                .frame(width: 70, alignment: .trailing)

            // Optional suffix (description)
            if let suffix = suffix {
                Text(suffix)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .font(.system(size: 12, design: .monospaced))
        .textSelection(.enabled)
    }

    private var hexString: String {
        switch width {
        case 2: return String(format: "%02X", hex & 0xFF)
        case 4: return String(format: "%04X", hex & 0xFFFF)
        case 6: return String(format: "%06X", hex & 0xFFFFFF)
        default: return String(format: "%X", hex)
        }
    }

    private var decimalString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: hex)) ?? "\(hex)"
    }
}

#Preview {
    FileInspectorSheet(entry: DiskCatalogEntry(
        name: "TEST.BAS",
        fileType: 0xFC,
        fileTypeString: "BAS",
        auxType: 0x0801,
        size: 256,
        blocks: 2,
        loadAddress: 0x0801,
        length: 256,
        data: Data(repeating: 0x00, count: 256),
        isImage: false,
        isDirectory: false,
        children: nil,
        modificationDate: "01-Jan-25",
        creationDate: "01-Jan-25"
    ))
}
