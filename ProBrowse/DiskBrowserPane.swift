//
//  DiskBrowserPane.swift
//  ProBrowse
//
//  Individual disk browser pane with drag & drop support
//

import SwiftUI
import UniformTypeIdentifiers
import Combine
import AppKit

struct DiskBrowserPane: View {
    @ObservedObject var viewModel: DiskPaneViewModel
    @ObservedObject var targetViewModel: DiskPaneViewModel
    @ObservedObject var columnWidths: ColumnWidths
    let paneTitle: String
    let paneId: PaneIdentifier
    var hideHeader: Bool = false
    
    @State private var draggedEntries: [DiskCatalogEntry] = []
    @State private var isTargeted = false
    @StateObject private var focusManager = FocusManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            if !hideHeader {
                headerView
            }
            
            // Browser Content
            if let catalog = viewModel.catalog {
                browserContentView(catalog: catalog)
            } else {
                emptyStateView
            }
        }
        .onTapGesture {
            // Set this pane as active when clicked
            focusManager.setActivePane(paneId)
        }
        .onChange(of: focusManager.activePaneId) { oldValue, newValue in
            // Clear selection when this pane loses focus
            if newValue != paneId && !viewModel.selectedEntries.isEmpty {
                print("🔄 Clearing selection in inactive \(paneId) pane")
                viewModel.selectedEntries.removeAll()
            }
        }
        .fileImporter(
            isPresented: $viewModel.showingFilePicker,
            allowedContentTypes: [.po, .twoimg, .hdv, .dsk, .do],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.loadDiskImage(from: url)
                }
            case .failure(let error):
                print("Error selecting file: \(error)")
            }
        }
        .sheet(isPresented: $viewModel.showingFileInfo) {
            if let entry = viewModel.fileInfoEntry {
                FileInfoSheet(entry: entry)
            }
        }
        .sheet(isPresented: $viewModel.showingChangeFileType) {
            if let entry = viewModel.changeFileTypeEntry {
                ChangeFileTypeSheet(
                    entry: entry,
                    onSave: { newFileType, newAuxType in
                        viewModel.changeFileType(entry: entry, newFileType: newFileType, newAuxType: newAuxType)
                    }
                )
            }
        }
        .sheet(isPresented: $viewModel.showingInspector) {
            if let entry = viewModel.inspectorEntry {
                FileInspectorSheet(entry: entry)
            }
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Volume Name
                HStack(spacing: 4) {
                    Text("Volume:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let diskName = viewModel.catalog?.diskName {
                        Text(diskName)
                            .font(.caption)
                            .fontWeight(.medium)
                    } else {
                        Text("—")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Filesystem Type
                HStack(spacing: 4) {
                    Text("Filesystem:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let diskFormat = viewModel.catalog?.diskFormat {
                        Text(diskFormat)
                            .font(.caption)
                            .fontWeight(.medium)
                    } else {
                        Text("—")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Volume Size
                HStack(spacing: 4) {
                    Text("Size:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let imageData = viewModel.diskImagePath.flatMap({ try? Data(contentsOf: $0) }) {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(imageData.count), countStyle: .file))
                            .font(.caption)
                            .fontWeight(.medium)
                    } else {
                        Text("—")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Back button and current path
                HStack(spacing: 8) {
                    Button(action: {
                        viewModel.navigateBack()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canGoBack && viewModel.currentDirectory == nil)
                    .opacity((viewModel.canGoBack || viewModel.currentDirectory != nil) ? 1.0 : 0.3)
                    
                    if let currentDir = viewModel.currentDirectory {
                        Text("📂 \(currentDir.name)")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                
                Spacer()
                
                // Filename
                HStack(spacing: 4) {
                    Text("Filename:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let imagePath = viewModel.diskImagePath {
                        Text(imagePath.lastPathComponent)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("—")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
        }
    }
    
    // MARK: - Browser Content View
    
    private func browserContentView(catalog: DiskCatalog) -> some View {
        VStack(spacing: 0) {
            // Column Headers
            ColumnHeadersView(columnWidths: columnWidths)
            
            Divider()
            
            // File List
            fileListView(catalog: catalog)
        }
        .background(
            Color.clear
                .onDrop(of: [.fileURL, .plainText], isTargeted: $isTargeted) { providers in
                    handleDrop(providers: providers)
                }
        )
        .overlay(
            Group {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue, lineWidth: 2)
                        .padding(4)
                }
            }
        )
    }
    
    // MARK: - File List View
    
    private func fileListView(catalog: DiskCatalog) -> some View {
        let entriesToShow: [DiskCatalogEntry] = {
            if let currentDir = viewModel.currentDirectory {
                // Show children of current directory
                return currentDir.children ?? []
            } else {
                // Show root entries
                return catalog.rootEntries
            }
        }()
        
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(entriesToShow) { entry in
                    catalogEntryRowWithDrag(entry: entry)
                }
            }
        }
    }
    
    // MARK: - Catalog Entry Row with Drag
    
    private func catalogEntryRowWithDrag(entry: DiskCatalogEntry) -> some View {
        CatalogEntryRow(
            entry: entry,
            isSelected: { viewModel.isSelected($0) },
            onToggle: { entry, cmd, shift in
                // Set this pane as active when selecting entries
                focusManager.setActivePane(paneId)
                viewModel.toggleSelection(entry, commandPressed: cmd, shiftPressed: shift)
            },
            onDoubleClick: { entry in
                viewModel.navigateInto(entry)
            },
            onRename: { entry in
                viewModel.renameEntry(entry)
            },
            onGetInfo: { entry in
                viewModel.showFileInfo(entry)
            },
            onChangeFileType: { entry in
                viewModel.showChangeFileType(entry)
            },
            onInspect: { entry in
                viewModel.showInspector(entry)
            },
            onCopy: { entry in
                focusManager.setActivePane(paneId)
                if !viewModel.isSelected(entry) {
                    viewModel.selectedEntries.removeAll()
                    viewModel.selectedEntries.insert(entry.id)
                }
                viewModel.copySelected()
            },
            onCut: { entry in
                focusManager.setActivePane(paneId)
                if !viewModel.isSelected(entry) {
                    viewModel.selectedEntries.removeAll()
                    viewModel.selectedEntries.insert(entry.id)
                }
                viewModel.cutSelected()
            },
            onPaste: {
                focusManager.setActivePane(paneId)
                // Paste into THIS pane (not target!)
                let clipboard = FocusManager.shared
                guard clipboard.hasClipboard() else {
                    print("❌ Clipboard is empty")
                    return
                }
                guard let sourcePath = clipboard.clipboardSourcePath else {
                    print("❌ No source in clipboard")
                    return
                }
                guard let targetPath = viewModel.diskImagePath else {
                    print("❌ No disk loaded in this pane")
                    return
                }
                
                print("📋 Pasting into CURRENT pane (\(paneId))")
                
                viewModel.copyDirectoryContents(clipboard.clipboardEntries, from: sourcePath, to: targetPath) {
                    print("✅ Pasted into \(paneId) pane")
                    
                    // If CUT, delete from source
                    if clipboard.clipboardOperation == .cut {
                        print("✂️ Cut operation - deleting from source")
                        for entry in clipboard.clipboardEntries {
                            ProDOSWriter.shared.deleteFile(diskImagePath: sourcePath, fileName: entry.name) { _, _ in }
                        }
                    }
                    
                    clipboard.clearClipboard()
                    
                    // Reload THIS pane
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.loadDiskImage(from: targetPath)
                    }
                }
            },
            onExport: { entry in
                focusManager.setActivePane(paneId)
                if !viewModel.isSelected(entry) {
                    viewModel.selectedEntries.removeAll()
                    viewModel.selectedEntries.insert(entry.id)
                }
                viewModel.exportSelectedToFinder()
            },
            onDelete: { entry in
                focusManager.setActivePane(paneId)
                if !viewModel.isSelected(entry) {
                    viewModel.selectedEntries.removeAll()
                    viewModel.selectedEntries.insert(entry.id)
                }
                viewModel.deleteSelected()
            },
            level: 0,
            expandAllTrigger: viewModel.expandAllTrigger,
            columnWidths: columnWidths
        )
        .onDrag {
            createDragProvider()
        }
    }
    
    // MARK: - Drag Provider
    
    private func createDragProvider() -> NSItemProvider {
        let selectedEntries = viewModel.getSelectedEntries()
        print("🎯 Starting drag with \(selectedEntries.count) entries")
        for entry in selectedEntries {
            print("   - \(entry.name)")
        }
        draggedEntries = selectedEntries
        
        // Encode to JSON string
        do {
            let jsonData = try JSONEncoder().encode(selectedEntries)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("📦 Encoded JSON (\(jsonString.count) chars)")
                print("   First 100 chars: \(String(jsonString.prefix(100)))")
                let provider = NSItemProvider(object: jsonString as NSString)
                provider.suggestedName = "probrowse-entries"
                return provider
            } else {
                print("❌ Failed to create string from JSON data")
            }
        } catch {
            print("❌ JSON Encoding error: \(error)")
        }
        
        return NSItemProvider()
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "opticaldiscdrive")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Disk Image Loaded")
                .font(.title3)
                .foregroundColor(.secondary)
            
            Button("Open Disk Image") {
                viewModel.showingFilePicker = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.clear
                .onDrop(of: [.fileURL, .item, .data], isTargeted: $isTargeted) { providers in
                    handleDrop(providers: providers)
                }
        )
    }
    
    // MARK: - Drop Handler

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        print("📥 Drop received with \(providers.count) providers")

        // Handle drop from Finder (file URLs)
        for provider in providers {
            print("   Provider has file URL: \(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))")
            print("   Provider has data: \(provider.hasItemConformingToTypeIdentifier("com.probrowse.entries"))")
            print("   Registered types: \(provider.registeredTypeIdentifiers)")

            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                print("🗂️ Handling Finder drop (fileURL type)")
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (urlData, error) in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("❌ Error loading URL: \(error)")
                            return
                        }

                        if let data = urlData as? Data,
                           let url = URL(dataRepresentation: data, relativeTo: nil) {

                            print("📂 File URL: \(url.path)")

                            // Check if it's a disk image to open
                            if ["po", "2mg", "hdv", "dsk", "do"].contains(url.pathExtension.lowercased()) {
                                print("💿 Opening disk image")
                                viewModel.loadDiskImage(from: url)
                            } else {
                                // Import file to disk
                                print("📄 Importing file to disk")
                                viewModel.importFile(from: url)
                            }
                        }
                    }
                }
                return true
            }

            // Handle files dropped by content type (e.g., public.assembly-source, public.source-code)
            // These don't have fileURL type but can be loaded via loadFileRepresentation
            let contentTypes = provider.registeredTypeIdentifiers
            let isSourceFile = contentTypes.contains { typeId in
                typeId.contains("source") || typeId.contains("text") || typeId.contains("plain")
            }

            if isSourceFile, let firstType = contentTypes.first {
                print("🗂️ Handling Finder drop via content type: \(firstType)")

                // Use loadFileRepresentation to get the actual file URL
                // IMPORTANT: The temporary file is deleted when callback returns, so read data BEFORE dispatching
                provider.loadFileRepresentation(forTypeIdentifier: firstType) { url, error in
                    if let error = error {
                        print("❌ Error loading file representation: \(error)")
                        return
                    }

                    guard let url = url else {
                        print("❌ No URL from file representation")
                        return
                    }

                    print("📂 File URL from representation: \(url.path)")
                    let filename = url.lastPathComponent
                    let ext = url.pathExtension.lowercased()
                    print("📄 Original filename: \(filename)")

                    // Read the file data IMMEDIATELY (before temp file is deleted)
                    let data: Data
                    do {
                        data = try Data(contentsOf: url)
                        print("📄 Read \(data.count) bytes from file")
                    } catch {
                        print("❌ Error reading file: \(error)")
                        return
                    }

                    // Now dispatch to main queue with the data we've already read
                    DispatchQueue.main.async {
                        // Check if it's a disk image
                        if ["po", "2mg", "hdv", "dsk", "do"].contains(ext) {
                            print("💿 Opening disk image")
                            // Copy to temp location since the file representation is temporary
                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                            do {
                                try data.write(to: tempURL)
                                self.viewModel.loadDiskImage(from: tempURL)
                            } catch {
                                print("❌ Error writing temp file: \(error)")
                            }
                        } else {
                            // Import file to disk with original filename
                            let sanitized = self.sanitizeFilenameForProDOS(filename)
                            print("📄 Importing as: \(sanitized)")

                            // Determine file type based on extension
                            let fileType: UInt8
                            switch ext {
                            case "s", "asm", "src":
                                fileType = 0x04  // TXT - source code as text
                            case "txt", "text":
                                fileType = 0x04  // TXT
                            case "bas":
                                fileType = 0x04  // TXT for BASIC source (not tokenized)
                            default:
                                fileType = 0x04  // Default to TXT
                            }

                            self.viewModel.importRawData(data, filename: sanitized, fileType: fileType, auxType: 0)
                        }
                    }
                }
                return true
            }
        }

        // Handle drop from other pane (String-based transfer via Data)
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                // Check if this might be an inter-pane transfer by checking suggestedName
                let suggestedName = provider.suggestedName
                if suggestedName == "probrowse-entries" {
                    print("🔄 Handling inter-pane drop (plaintext with probrowse marker)")
                } else {
                    print("🔄 Handling plainText drop - suggestedName: \(suggestedName ?? "nil")")
                }

                provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { (data, error) in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("❌ Error loading data: \(error)")
                            return
                        }

                        guard let data = data else {
                            print("❌ No data received")
                            return
                        }

                        print("✅ Got data (\(data.count) bytes)")

                        if let jsonString = String(data: data, encoding: .utf8) {
                            print("✅ Converted to string (\(jsonString.count) chars)")
                            print("   First 100 chars: \(String(jsonString.prefix(100)))")

                            // First try to decode as inter-pane transfer (JSON)
                            do {
                                let entries = try JSONDecoder().decode([DiskCatalogEntry].self, from: data)
                                print("✅ Decoded \(entries.count) entries - inter-pane transfer")
                                for entry in entries {
                                    print("   - \(entry.name)")
                                }
                                viewModel.importEntries(entries, from: targetViewModel)
                            } catch {
                                // Not JSON - this is probably a text file being dropped from Finder
                                // But we should have already handled this via loadFileRepresentation above
                                print("⚠️ Not JSON and not handled by file representation")
                                print("   This may be pasted text - importing as PASTED.TXT")

                                let sanitized = "PASTED.TXT"
                                viewModel.importRawData(data, filename: sanitized, fileType: 0x04, auxType: 0)
                            }
                        } else {
                            print("❌ Failed to convert data to string")
                        }
                    }
                }
                return true
            }
        }
        
        // Old method - keep for backward compatibility
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("com.probrowse.entries") {
                print("🔄 Handling inter-pane drop (legacy)")
                provider.loadDataRepresentation(forTypeIdentifier: "com.probrowse.entries") { data, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("❌ Error loading entries: \(error)")
                            return
                        }
                        
                        if let data = data,
                           let wrapper = try? JSONDecoder().decode(DraggedEntriesWrapper.self, from: data) {
                            print("✅ Decoded \(wrapper.entries.count) entries")
                            for entry in wrapper.entries {
                                print("   - \(entry.name)")
                            }
                            viewModel.importEntries(wrapper.entries, from: targetViewModel)
                        } else {
                            print("❌ Failed to decode entries")
                        }
                    }
                }
                return true
            }
        }
        
        print("❌ No valid drop data found")
        return false
    }

    /// Convert a filename to ProDOS-compatible format
    private func sanitizeFilenameForProDOS(_ filename: String) -> String {
        // Get base name and extension
        let url = URL(fileURLWithPath: filename)
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        // Convert to uppercase and filter valid characters
        var sanitized = baseName.uppercased()
            .replacingOccurrences(of: " ", with: ".")
            .replacingOccurrences(of: "_", with: ".")
            .replacingOccurrences(of: "-", with: ".")
            .filter { $0.isLetter || $0.isNumber || $0 == "." }

        // Add extension if present
        if !ext.isEmpty {
            let sanitizedExt = ext.uppercased()
                .filter { $0.isLetter || $0.isNumber }
            if !sanitizedExt.isEmpty {
                sanitized += "." + sanitizedExt
            }
        }

        // Ensure not empty
        if sanitized.isEmpty {
            sanitized = "IMPORTED"
        }

        // ProDOS max filename is 15 characters
        return String(sanitized.prefix(15))
    }
}

// MARK: - Dragged Entries Wrapper

class DraggedEntriesWrapper: NSObject, NSItemProviderWriting, Codable {
    let entries: [DiskCatalogEntry]
    
    init(entries: [DiskCatalogEntry]) {
        self.entries = entries
    }
    
    static var writableTypeIdentifiersForItemProvider: [String] {
        ["com.probrowse.entries"]
    }
    
    func loadData(withTypeIdentifier typeIdentifier: String, forItemProviderCompletionHandler completionHandler: @escaping (Data?, Error?) -> Void) -> Progress? {
        if typeIdentifier == "com.probrowse.entries" {
            do {
                let data = try JSONEncoder().encode(self)
                completionHandler(data, nil)
            } catch {
                completionHandler(nil, error)
            }
        }
        return nil
    }
}

// MARK: - Column Headers View

struct ColumnHeadersView: View {
    @ObservedObject var columnWidths: ColumnWidths
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Color(NSColor.controlBackgroundColor)
                
                HStack(spacing: 0) {
                    // Name Column
                    ColumnHeader(title: "Name", width: $columnWidths.nameWidth)
                    
                    // Divider resizes NAME column (to the left)
                    ColumnDivider(leftWidth: $columnWidths.nameWidth, minLeftWidth: 100, maxLeftWidth: 400)
                    
                    // Type Column
                    ColumnHeader(title: "Type", width: $columnWidths.typeWidth)
                    
                    // Divider resizes TYPE column (to the left)
                    ColumnDivider(leftWidth: $columnWidths.typeWidth, minLeftWidth: 40, maxLeftWidth: 150)
                    
                    // Aux Column
                    ColumnHeader(title: "Aux", width: $columnWidths.auxWidth)
                    
                    // Divider resizes AUX column (to the left)
                    ColumnDivider(leftWidth: $columnWidths.auxWidth, minLeftWidth: 60, maxLeftWidth: 150)
                    
                    // Size Column
                    ColumnHeader(title: "Size", width: $columnWidths.sizeWidth)
                    
                    // Divider resizes SIZE column (to the left)
                    ColumnDivider(leftWidth: $columnWidths.sizeWidth, minLeftWidth: 80, maxLeftWidth: 200)
                    
                    // Modified Column
                    ColumnHeader(title: "Modified", width: $columnWidths.modifiedWidth)
                    
                    // Divider resizes MODIFIED column (to the left)
                    ColumnDivider(leftWidth: $columnWidths.modifiedWidth, minLeftWidth: 100, maxLeftWidth: 200)
                    
                    // Created Column (fills remaining space)
                    HStack(spacing: 0) {
                        Spacer().frame(width: 8)
                        Text("Created")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(height: 24)
    }
}

// MARK: - Column Header Component

struct ColumnHeader: View {
    let title: String
    @Binding var width: Double
    
    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 8)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
    }
}

// MARK: - Column Divider (Resizable)

struct ColumnDivider: View {
    @Binding var leftWidth: Double
    let minLeftWidth: Double
    let maxLeftWidth: Double
    
    @State private var isDragging = false
    @State private var dragStartWidth: Double = 0
    @State private var previewWidth: Double = 0
    
    var body: some View {
        Divider()
            .frame(width: 1)
            .background(isDragging ? Color.accentColor : Color.secondary.opacity(0.3))
            .overlay(
                // Invisible drag area
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    dragStartWidth = leftWidth
                                }
                                // Calculate preview width but don't update binding yet
                                let newWidth = dragStartWidth + value.translation.width
                                previewWidth = min(max(newWidth, minLeftWidth), maxLeftWidth)
                            }
                            .onEnded { value in
                                // Only update the actual width at the end
                                let newWidth = dragStartWidth + value.translation.width
                                leftWidth = min(max(newWidth, minLeftWidth), maxLeftWidth)
                                isDragging = false
                            }
                    )
            )
    }
}
