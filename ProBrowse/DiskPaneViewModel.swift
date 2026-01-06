//
//  DiskPaneViewModel.swift
//  ProBrowse
//
//  ViewModel for managing disk pane state and operations
//  Updated to support both ProDOS and DOS 3.3 filesystems
//

import SwiftUI
import Foundation
import Combine

class DiskPaneViewModel: ObservableObject {
    @Published var catalog: DiskCatalog?
    @Published var diskImagePath: URL?
    @Published var selectedEntries: Set<UUID> = []
    @Published var expandAllTrigger = false
    @Published var showingFilePicker = false
    @Published var showingFileInfo = false
    @Published var fileInfoEntry: DiskCatalogEntry?
    
    // Navigation state
    @Published var currentDirectory: DiskCatalogEntry?
    @Published var navigationPath: [DiskCatalogEntry] = []
    
    private var lastSelectedEntry: DiskCatalogEntry?
    
    var isAllSelected: Bool {
        guard let catalog = catalog else { return false }
        let allIds = Set(catalog.allEntries.map { $0.id })
        return !allIds.isEmpty && selectedEntries == allIds
    }
    
    var canGoBack: Bool {
        return !navigationPath.isEmpty
    }
    
    /// Check if the current disk is DOS 3.3 format
    var isDOS33: Bool {
        return catalog?.diskFormat.contains("DOS 3.3") ?? false
    }
    
    // MARK: - Load Disk Image
    
    func loadDiskImage(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("Failed to access security scoped resource")
            return
        }
        
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let originalData = try Data(contentsOf: url)
            self.diskImagePath = url
            
            // Reset navigation
            navigateToRoot()
            
            let isDSK = url.pathExtension.lowercased() == "dsk"
            let isDO = url.pathExtension.lowercased() == "do"
            
            // For .po, .2mg, .hdv, .woz - try directly as ProDOS
            if !isDSK && !isDO {
                if let catalog = try? DiskImageParser.parseProDOS(data: originalData, diskName: url.lastPathComponent) {
                    self.catalog = catalog
                    self.selectedEntries = []
                    return
                }
            }
            
            // For .dsk/.do files - try both filesystems
            if isDSK || isDO {
                print("📀 Loading .dsk file: \(url.lastPathComponent)")
                
                // .dsk can contain either ProDOS or DOS 3.3 filesystem
                // Just try both parsers!
                
                // Try ProDOS first
                if let catalog = try? DiskImageParser.parseProDOS(data: originalData, diskName: url.lastPathComponent) {
                    print("✅ Parsed as ProDOS")
                    self.catalog = catalog
                    self.selectedEntries = []
                    return
                }
                
                // Try DOS 3.3
                if let catalog = try? DiskImageParser.parseDOS33(data: originalData, diskName: url.lastPathComponent) {
                    print("✅ Parsed as DOS 3.3")
                    self.catalog = catalog
                    self.selectedEntries = []
                    return
                }
                
                print("❌ Could not parse .dsk file")
            }
            
            // Fallback: Try as DOS 3.3
            if let catalog = try? DiskImageParser.parseDOS33(data: originalData, diskName: url.lastPathComponent) {
                self.catalog = catalog
                self.selectedEntries = []
                return
            }
            
            print("Unknown disk format")
            
        } catch {
            print("Error loading disk image: \(error)")
        }
    }
    
    // MARK: - Selection
    
    func isSelected(_ entry: DiskCatalogEntry) -> Bool {
        return selectedEntries.contains(entry.id)
    }
    
    func toggleSelection(_ entry: DiskCatalogEntry, commandPressed: Bool = false, shiftPressed: Bool = false) {
        print("🔘 Toggle selection for: \(entry.name)")
        print("   Current selected count: \(selectedEntries.count)")
        print("   Command: \(commandPressed), Shift: \(shiftPressed)")
        
        if shiftPressed {
            // Shift: Range selection from last selected to this one
            handleRangeSelection(entry)
        } else if commandPressed {
            // Command: Toggle individual item
            if selectedEntries.contains(entry.id) {
                selectedEntries.remove(entry.id)
                print("   ➖ Deselected")
            } else {
                selectedEntries.insert(entry.id)
                print("   ➕ Selected")
            }
        } else {
            // No modifier: Replace selection with this item
            selectedEntries.removeAll()
            selectedEntries.insert(entry.id)
            print("   ➕ Selected (cleared others)")
        }
        
        print("   New selected count: \(selectedEntries.count)")
        lastSelectedEntry = entry
    }
    
    private func handleRangeSelection(_ entry: DiskCatalogEntry) {
        guard let catalog = catalog, let lastSelected = lastSelectedEntry else {
            selectedEntries.insert(entry.id)
            return
        }
        
        // Get flat list of all entries
        let allEntries = flattenEntries(catalog.entries)
        
        guard let startIndex = allEntries.firstIndex(where: { $0.id == lastSelected.id }),
              let endIndex = allEntries.firstIndex(where: { $0.id == entry.id }) else {
            return
        }
        
        let range = min(startIndex, endIndex)...max(startIndex, endIndex)
        for i in range {
            selectedEntries.insert(allEntries[i].id)
        }
    }
    
    private func flattenEntries(_ entries: [DiskCatalogEntry]) -> [DiskCatalogEntry] {
        var result: [DiskCatalogEntry] = []
        for entry in entries {
            result.append(entry)
            if let children = entry.children {
                result.append(contentsOf: flattenEntries(children))
            }
        }
        return result
    }
    
    func toggleSelectAll() {
        guard let catalog = catalog else { return }
        
        if isAllSelected {
            selectedEntries = []
        } else {
            selectedEntries = Set(catalog.allEntries.map { $0.id })
        }
    }
    
    func expandAll() {
        expandAllTrigger.toggle()
    }
    
    // MARK: - Directory Navigation
    
    func navigateInto(_ directory: DiskCatalogEntry) {
        guard directory.isDirectory else { return }
        
        // Add current directory to navigation path
        if let current = currentDirectory {
            navigationPath.append(current)
        }
        
        // Set new current directory
        currentDirectory = directory
        
        // Clear selection
        selectedEntries = []
        
        print("📂 Navigated into: \(directory.name)")
    }
    
    func navigateBack() {
        guard !navigationPath.isEmpty else {
            // Already at root
            currentDirectory = nil
            return
        }
        
        // Pop last directory from path
        currentDirectory = navigationPath.popLast()
        
        // Clear selection
        selectedEntries = []
        
        if let current = currentDirectory {
            print("📂 Navigated back to: \(current.name)")
        } else {
            print("📂 Navigated back to root")
        }
    }
    
    func navigateToRoot() {
        navigationPath = []
        currentDirectory = nil
        selectedEntries = []
        print("📂 Navigated to root")
    }
    
    func getSelectedEntries() -> [DiskCatalogEntry] {
        guard let catalog = catalog else {
            print("⚠️ getSelectedEntries: No catalog")
            return []
        }
        
        let result = catalog.allEntries.filter { selectedEntries.contains($0.id) }
        print("📋 getSelectedEntries: \(result.count) of \(selectedEntries.count) IDs")
        for entry in result {
            print("   - \(entry.name)")
        }
        return result
    }
    
    // MARK: - Export to Finder
    
    func exportSelectedToFinder() {
        let entriesToExport = getSelectedEntries()
        
        guard !entriesToExport.isEmpty else { return }
        
        // Use proper Downloads directory
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            print("Could not find Downloads folder")
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        
        let diskName = catalog?.diskName ?? "Disk"
        let exportFolderName = "\(diskName)_export_\(timestamp)"
        let exportFolder = downloadsURL.appendingPathComponent(exportFolderName)
        
        print("📂 Exporting to: \(exportFolder.path)")
        
        do {
            try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
            
            var exportedCount = 0
            for entry in entriesToExport {
                exportedCount += exportEntry(entry, to: exportFolder)
            }
            
            print("🎉 Export completed: \(exportedCount) files")
            NSWorkspace.shared.activateFileViewerSelecting([exportFolder])
            
        } catch {
            print("❌ Export error: \(error)")
        }
    }
    
    // MARK: - Recursive Export Helper
    
    private func exportEntry(_ entry: DiskCatalogEntry, to parentFolder: URL) -> Int {
        var count = 0
        
        if entry.isDirectory {
            // Create subdirectory
            let subfolderURL = parentFolder.appendingPathComponent(entry.name)
            do {
                try FileManager.default.createDirectory(at: subfolderURL, withIntermediateDirectories: true)
                print("📁 Created directory: \(entry.name)")
                
                // Recursively export children
                if let children = entry.children {
                    for child in children {
                        count += exportEntry(child, to: subfolderURL)
                    }
                }
            } catch {
                print("❌ Failed to create directory \(entry.name): \(error)")
            }
        } else {
            // Export file
            var filename = entry.name
            
            // Add extension if missing
            if !filename.contains(".") {
                switch entry.fileType {
                case 0x00, 0x01: filename += ".txt"
                case 0x02: filename += ".bas"
                case 0x04, 0x06: filename += ".bin"
                case 0xFA, 0xFC: filename += ".bas"
                default: filename += ".dat"
                }
            }
            
            let fileURL = parentFolder.appendingPathComponent(filename)
            do {
                try entry.data.write(to: fileURL)
                print("✅ Exported: \(filename)")
                count = 1
            } catch {
                print("❌ Failed to export \(filename): \(error)")
            }
        }
        
        return count
    }
    
    // MARK: - Import Files
    
    func importFile(from url: URL) {
        guard catalog != nil,
              let imagePath = diskImagePath else { return }
        
        guard url.startAccessingSecurityScopedResource() else {
            print("Failed to access file")
            return
        }
        
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let fileData = try Data(contentsOf: url)
            let filename = url.lastPathComponent
            
            print("📋 Importing file: \(filename) (\(fileData.count) bytes)")
            
            // Use appropriate writer based on target filesystem
            if isDOS33 {
                DOS33Writer.shared.addFile(
                    diskImagePath: imagePath,
                    fileName: filename,
                    fileData: fileData,
                    fileType: 0x06,  // BIN
                    auxType: 0x0000
                ) { success, message in
                    if success {
                        print("✅ File imported successfully (DOS 3.3)")
                        DispatchQueue.main.async {
                            self.loadDiskImage(from: imagePath)
                        }
                    } else {
                        print("❌ Failed to import: \(message)")
                    }
                }
            } else {
                ProDOSWriter.shared.addFile(
                    diskImagePath: imagePath,
                    fileName: filename,
                    fileData: fileData,
                    fileType: 0x06,  // BIN
                    auxType: 0x0000
                ) { success, message in
                    if success {
                        print("✅ File imported successfully (ProDOS)")
                        DispatchQueue.main.async {
                            self.loadDiskImage(from: imagePath)
                        }
                    } else {
                        print("❌ Failed to import: \(message)")
                    }
                }
            }
            
        } catch {
            print("Error importing file: \(error)")
        }
    }
    
    func importEntries(_ entries: [DiskCatalogEntry], from sourceVM: DiskPaneViewModel) {
        guard let targetImagePath = diskImagePath,
              let sourceImagePath = sourceVM.diskImagePath else { return }
        
        let targetFormat = isDOS33 ? "DOS 3.3" : "ProDOS"
        let sourceFormat = sourceVM.isDOS33 ? "DOS 3.3" : "ProDOS"
        print("📋 Copying files from \(sourceFormat) to \(targetFormat)...")
        
        // Copy files sequentially to avoid race conditions
        copyNextFile(entries: entries, index: 0, from: sourceImagePath, to: targetImagePath, sourceIsDOS33: sourceVM.isDOS33)
    }
    
    private func copyNextFile(entries: [DiskCatalogEntry], index: Int, from sourceImagePath: URL, to targetImagePath: URL, sourceIsDOS33: Bool) {
        guard index < entries.count else {
            // All files copied - reload
            print("✅ All files copied, reloading...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.loadDiskImage(from: targetImagePath)
            }
            return
        }
        
        let entry = entries[index]
        
        if entry.isDirectory {
            // DOS 3.3 doesn't support directories
            if isDOS33 {
                print("⚠️ Skipping directory '\(entry.name)' - DOS 3.3 doesn't support directories")
                // Copy children as flat files
                if let children = entry.children, !children.isEmpty {
                    // Flatten children into current list
                    var newEntries = Array(entries.dropFirst(index + 1))
                    newEntries.insert(contentsOf: children, at: 0)
                    self.copyNextFile(entries: newEntries, index: 0, from: sourceImagePath, to: targetImagePath, sourceIsDOS33: sourceIsDOS33)
                } else {
                    self.copyNextFile(entries: entries, index: index + 1, from: sourceImagePath, to: targetImagePath, sourceIsDOS33: sourceIsDOS33)
                }
                return
            }
            
            // ProDOS: Create the directory
            print("📁 Processing directory: \(entry.name)")
            
            ProDOSWriter.shared.createDirectory(diskImagePath: targetImagePath, directoryName: entry.name, parentPath: "/") { success, message in
                if success {
                    print("   ✅ Created directory \(entry.name)")
                    
                    // Now copy children INTO this directory
                    if let children = entry.children, !children.isEmpty {
                        print("   📦 Copying \(children.count) children into /\(entry.name)/")
                        let childPath = "/\(entry.name)/"
                        
                        // Recursively copy all children
                        self.copyEntriesRecursively(entries: children, to: targetImagePath, parentPath: childPath, index: 0, sourceIsDOS33: sourceIsDOS33) {
                            // After all children copied, move to next sibling
                            print("   ✅ Finished copying children of \(entry.name)")
                            self.copyNextFile(entries: entries, index: index + 1, from: sourceImagePath, to: targetImagePath, sourceIsDOS33: sourceIsDOS33)
                        }
                    } else {
                        // Empty directory, move to next
                        self.copyNextFile(entries: entries, index: index + 1, from: sourceImagePath, to: targetImagePath, sourceIsDOS33: sourceIsDOS33)
                    }
                } else {
                    print("   ❌ Failed to create directory: \(message)")
                    // Skip this directory and move to next
                    self.copyNextFile(entries: entries, index: index + 1, from: sourceImagePath, to: targetImagePath, sourceIsDOS33: sourceIsDOS33)
                }
            }
            return
        }
        
        // Use data directly from catalog entry (already extracted by DiskImageParser)
        let data = entry.data
        print("✅ Using cached data for \(entry.name) (\(data.count) bytes)")
        
        // Determine file type - convert if source and target have different filesystems
        var fileType = entry.fileType
        var auxType = entry.auxType
        
        if sourceIsDOS33 && !isDOS33 {
            // Converting DOS 3.3 → ProDOS
            let converted = DiskImageParser.convertDOS33ToProDOSFileType(entry.fileType)
            fileType = converted.fileType
            auxType = converted.auxType
            print("   📝 FileType conversion: DOS 3.3 $\(String(format: "%02X", entry.fileType)) → ProDOS $\(String(format: "%02X", fileType))")
        } else if !sourceIsDOS33 && isDOS33 {
            // Converting ProDOS → DOS 3.3 (handled by DOS33Writer internally)
            print("   📝 FileType: ProDOS $\(String(format: "%02X", fileType)) (will be converted by DOS33Writer)")
        }
        
        // Choose writer based on target filesystem
        if isDOS33 {
            DOS33Writer.shared.addFile(
                diskImagePath: targetImagePath,
                fileName: entry.name,
                fileData: data,
                fileType: entry.fileType,  // DOS33Writer converts internally
                auxType: entry.auxType
            ) { addSuccess, message in
                if addSuccess {
                    print("✅ Copied \(entry.name) (DOS 3.3)")
                } else {
                    print("❌ Failed to add \(entry.name): \(message)")
                }
                
                // Continue with next file
                self.copyNextFile(entries: entries, index: index + 1, from: sourceImagePath, to: targetImagePath, sourceIsDOS33: sourceIsDOS33)
            }
        } else {
            ProDOSWriter.shared.addFile(
                diskImagePath: targetImagePath,
                fileName: entry.name,
                fileData: data,
                fileType: fileType,      // Use converted type
                auxType: auxType         // Use converted auxType
            ) { addSuccess, message in
                if addSuccess {
                    print("✅ Copied \(entry.name) (ProDOS)")
                } else {
                    print("❌ Failed to add \(entry.name): \(message)")
                }
                
                // Continue with next file
                self.copyNextFile(entries: entries, index: index + 1, from: sourceImagePath, to: targetImagePath, sourceIsDOS33: sourceIsDOS33)
            }
        }
    }
    
    // MARK: - Copy Directory Contents (With Structure) - ProDOS Only
    
    func copyDirectoryContents(_ entries: [DiskCatalogEntry], from sourceImagePath: URL, to targetImagePath: URL, sourceIsDOS33: Bool = false, completion: @escaping () -> Void) {
        // Copy directory structure recursively
        copyEntriesRecursively(entries: entries, to: targetImagePath, parentPath: "/", index: 0, sourceIsDOS33: sourceIsDOS33, completion: completion)
    }
    
    private func copyEntriesRecursively(entries: [DiskCatalogEntry], to targetImagePath: URL, parentPath: String, index: Int, sourceIsDOS33: Bool, completion: @escaping () -> Void) {
        guard index < entries.count else {
            // All entries copied
            completion()
            return
        }
        
        let entry = entries[index]
        
        if entry.isDirectory {
            // DOS 3.3 doesn't support directories - flatten
            if isDOS33 {
                if let children = entry.children, !children.isEmpty {
                    self.copyEntriesRecursively(entries: children, to: targetImagePath, parentPath: parentPath, index: 0, sourceIsDOS33: sourceIsDOS33) {
                        self.copyEntriesRecursively(entries: entries, to: targetImagePath, parentPath: parentPath, index: index + 1, sourceIsDOS33: sourceIsDOS33, completion: completion)
                    }
                } else {
                    self.copyEntriesRecursively(entries: entries, to: targetImagePath, parentPath: parentPath, index: index + 1, sourceIsDOS33: sourceIsDOS33, completion: completion)
                }
                return
            }
            
            // ProDOS: Create subdirectory
            print("📁 Creating subdirectory: \(entry.name)")
            
            ProDOSWriter.shared.createDirectory(diskImagePath: targetImagePath, directoryName: entry.name, parentPath: parentPath) { success, message in
                if success {
                    print("   ✅ Created directory \(entry.name)")
                    
                    // Copy children into this subdirectory
                    if let children = entry.children, !children.isEmpty {
                        let newPath = parentPath + entry.name + "/"
                        self.copyEntriesRecursively(entries: children, to: targetImagePath, parentPath: newPath, index: 0, sourceIsDOS33: sourceIsDOS33) {
                            // After children copied, move to next sibling
                            self.copyEntriesRecursively(entries: entries, to: targetImagePath, parentPath: parentPath, index: index + 1, sourceIsDOS33: sourceIsDOS33, completion: completion)
                        }
                    } else {
                        self.copyEntriesRecursively(entries: entries, to: targetImagePath, parentPath: parentPath, index: index + 1, sourceIsDOS33: sourceIsDOS33, completion: completion)
                    }
                } else {
                    print("   ❌ Failed to create directory: \(message)")
                    self.copyEntriesRecursively(entries: entries, to: targetImagePath, parentPath: parentPath, index: index + 1, sourceIsDOS33: sourceIsDOS33, completion: completion)
                }
            }
        } else {
            // Copy file
            let data = entry.data
            print("   📄 Copying file: \(entry.name) (\(data.count) bytes)")
            
            // Convert file type if needed
            var fileType = entry.fileType
            var auxType = entry.auxType
            
            if sourceIsDOS33 && !isDOS33 {
                // Converting DOS 3.3 → ProDOS
                let converted = DiskImageParser.convertDOS33ToProDOSFileType(entry.fileType)
                fileType = converted.fileType
                auxType = converted.auxType
                print("   📝 FileType: DOS 3.3 $\(String(format: "%02X", entry.fileType)) → ProDOS $\(String(format: "%02X", fileType))")
            }
            
            if isDOS33 {
                DOS33Writer.shared.addFile(
                    diskImagePath: targetImagePath,
                    fileName: entry.name,
                    fileData: data,
                    fileType: entry.fileType,  // DOS33Writer converts internally
                    auxType: entry.auxType,
                    locked: false
                ) { success, message in
                    if success {
                        print("   ✅ Copied \(entry.name)")
                    } else {
                        print("   ❌ Failed: \(message)")
                    }
                    self.copyEntriesRecursively(entries: entries, to: targetImagePath, parentPath: parentPath, index: index + 1, sourceIsDOS33: sourceIsDOS33, completion: completion)
                }
            } else {
                ProDOSWriter.shared.addFile(
                    diskImagePath: targetImagePath,
                    fileName: entry.name,
                    fileData: data,
                    fileType: fileType,      // Use converted type
                    auxType: auxType,        // Use converted auxType
                    parentPath: parentPath
                ) { success, message in
                    if success {
                        print("   ✅ Copied \(entry.name)")
                    } else {
                        print("   ❌ Failed: \(message)")
                    }
                    self.copyEntriesRecursively(entries: entries, to: targetImagePath, parentPath: parentPath, index: index + 1, sourceIsDOS33: sourceIsDOS33, completion: completion)
                }
            }
        }
    }
    
    // MARK: - Delete Files
    
    func deleteSelected() {
        guard let diskImagePath = diskImagePath else {
            print("❌ No disk image loaded")
            return
        }
        
        let entriesToDelete = getSelectedEntries()
        guard !entriesToDelete.isEmpty else { return }
        
        print("🗑️ Deleting \(entriesToDelete.count) files...")
        
        // Delete files sequentially
        deleteNextFile(entries: entriesToDelete, index: 0, from: diskImagePath)
    }
    
    private func deleteNextFile(entries: [DiskCatalogEntry], index: Int, from diskImagePath: URL) {
        guard index < entries.count else {
            // All files deleted - reload and clear selection
            print("✅ All files deleted, reloading...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.selectedEntries.removeAll()
                self.loadDiskImage(from: diskImagePath)
            }
            return
        }
        
        let entry = entries[index]
        
        // Strip any display suffixes (like lock icon) from filename
        var cleanName = entry.name
        if cleanName.hasSuffix(" 🔒") {
            cleanName = String(cleanName.dropLast(2))
        }
        
        print("🗑️ Attempting to delete: \(cleanName)")
        
        // Check disk format
        guard let diskFormat = catalog?.diskFormat else {
            print("❌ No catalog loaded")
            self.deleteNextFile(entries: entries, index: index + 1, from: diskImagePath)
            return
        }
        
        let isTargetDOS33 = diskFormat.contains("DOS 3.3")
        
        if isTargetDOS33 {
            // Use DOS 3.3 writer
            DOS33Writer.shared.deleteFile(diskImagePath: diskImagePath, fileName: cleanName) { success, message in
                if success {
                    print("✅ Deleted \(cleanName) (DOS 3.3)")
                } else {
                    print("❌ Failed to delete \(cleanName): \(message)")
                }
                
                // Continue with next file
                self.deleteNextFile(entries: entries, index: index + 1, from: diskImagePath)
            }
        } else {
            // Use ProDOS writer
            ProDOSWriter.shared.deleteFile(diskImagePath: diskImagePath, fileName: cleanName) { success, message in
                if success {
                    print("✅ Deleted \(cleanName) (ProDOS)")
                } else {
                    print("❌ Failed to delete \(cleanName): \(message)")
                }
                
                // Continue with next file
                self.deleteNextFile(entries: entries, index: index + 1, from: diskImagePath)
            }
        }
    }
    
    // MARK: - Create Directory
    
    func showCreateDirectoryDialog() {
        guard let diskImagePath = diskImagePath else {
            print("❌ No disk image loaded")
            return
        }
        
        // DOS 3.3 doesn't support directories
        if isDOS33 {
            print("❌ DOS 3.3 doesn't support directories")
            DispatchQueue.main.async {
                let errorAlert = NSAlert()
                errorAlert.messageText = "Cannot Create Directory"
                errorAlert.informativeText = "DOS 3.3 disks do not support subdirectories."
                errorAlert.alertStyle = .warning
                errorAlert.runModal()
            }
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Create New Directory"
        alert.informativeText = "Enter a name for the new directory:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.placeholderString = "Directory name"
        alert.accessoryView = textField
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            let directoryName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !directoryName.isEmpty else {
                print("❌ Directory name cannot be empty")
                return
            }
            
            // Determine parent path
            let parentPath: String
            if let currentDir = currentDirectory {
                // Build path from navigation stack
                var pathComponents = navigationPath.map { $0.name }
                pathComponents.append(currentDir.name)
                parentPath = "/" + pathComponents.joined(separator: "/") + "/"
            } else {
                parentPath = "/"
            }
            
            print("📁 Creating directory '\(directoryName)' in '\(parentPath)'")
            
            ProDOSWriter.shared.createDirectory(
                diskImagePath: diskImagePath,
                directoryName: directoryName,
                parentPath: parentPath
            ) { success, message in
                if success {
                    print("✅ Directory '\(directoryName)' created successfully")
                    // Reload disk image to show new directory
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.loadDiskImage(from: diskImagePath)
                    }
                } else {
                    print("❌ Failed to create directory: \(message)")
                    DispatchQueue.main.async {
                        let errorAlert = NSAlert()
                        errorAlert.messageText = "Failed to Create Directory"
                        errorAlert.informativeText = message
                        errorAlert.alertStyle = .warning
                        errorAlert.runModal()
                    }
                }
            }
        }
    }
    
    // MARK: - Eject Disk
    
    func ejectDisk() {
        print("💿 Ejecting disk image")
        
        // Clear all state
        catalog = nil
        diskImagePath = nil
        selectedEntries.removeAll()
        currentDirectory = nil
        navigationPath.removeAll()
        lastSelectedEntry = nil
        
        print("✅ Disk ejected")
    }
    
    // MARK: - Rename Entry
    
    func renameEntry(_ entry: DiskCatalogEntry) {
        guard let diskImagePath = diskImagePath else {
            print("❌ No disk image loaded")
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Rename \(entry.isDirectory ? "Directory" : "File")"
        alert.informativeText = "Enter a new name:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.placeholderString = "New name"
        textField.stringValue = entry.name
        alert.accessoryView = textField
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !newName.isEmpty else {
                print("❌ Name cannot be empty")
                return
            }
            
            guard newName != entry.name else {
                print("❌ Name unchanged")
                return
            }
            
            print("✏️ Renaming '\(entry.name)' to '\(newName)'")
            
            if isDOS33 {
                DOS33Writer.shared.renameFile(
                    diskImagePath: diskImagePath,
                    oldName: entry.name,
                    newName: newName
                ) { success, message in
                    if success {
                        print("✅ Renamed to '\(newName)' (DOS 3.3)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.loadDiskImage(from: diskImagePath)
                        }
                    } else {
                        print("❌ Failed to rename: \(message)")
                        DispatchQueue.main.async {
                            let errorAlert = NSAlert()
                            errorAlert.messageText = "Failed to Rename"
                            errorAlert.informativeText = message
                            errorAlert.alertStyle = .warning
                            errorAlert.runModal()
                        }
                    }
                }
            } else {
                ProDOSWriter.shared.renameFile(
                    diskImagePath: diskImagePath,
                    oldName: entry.name,
                    newName: newName
                ) { success, message in
                    if success {
                        print("✅ Renamed to '\(newName)' (ProDOS)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.loadDiskImage(from: diskImagePath)
                        }
                    } else {
                        print("❌ Failed to rename: \(message)")
                        DispatchQueue.main.async {
                            let errorAlert = NSAlert()
                            errorAlert.messageText = "Failed to Rename"
                            errorAlert.informativeText = message
                            errorAlert.alertStyle = .warning
                            errorAlert.runModal()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Show File Info
    
    func showFileInfo(_ entry: DiskCatalogEntry) {
        fileInfoEntry = entry
        showingFileInfo = true
    }
    
    // MARK: - Copy/Cut/Paste
    
    func copySelected() {
        let entries = getSelectedEntries()
        guard !entries.isEmpty else {
            print("❌ Nothing selected to copy")
            return
        }
        
        guard let sourcePath = diskImagePath else {
            print("❌ No disk loaded")
            return
        }
        
        FocusManager.shared.copyToClipboard(entries: entries, operation: .copy, sourcePath: sourcePath)
    }
    
    func cutSelected() {
        let entries = getSelectedEntries()
        guard !entries.isEmpty else {
            print("❌ Nothing selected to cut")
            return
        }
        
        guard let sourcePath = diskImagePath else {
            print("❌ No disk loaded")
            return
        }
        
        FocusManager.shared.copyToClipboard(entries: entries, operation: .cut, sourcePath: sourcePath)
    }
    
    func paste(to targetViewModel: DiskPaneViewModel) {
        let clipboard = FocusManager.shared
        
        guard clipboard.hasClipboard() else {
            print("❌ Clipboard is empty")
            return
        }
        
        guard let sourceDiskPath = clipboard.clipboardSourcePath else {
            print("❌ No source disk in clipboard")
            return
        }
        
        guard let targetDiskPath = targetViewModel.diskImagePath else {
            print("❌ No target disk loaded")
            return
        }
        
        print("📋 Pasting \(clipboard.clipboardEntries.count) items...")
        print("   Operation: \(clipboard.clipboardOperation)")
        
        // Get source format to use for file type conversion
        let sourceIsDOS33 = self.catalog?.diskFormat.contains("DOS 3.3") ?? false
        
        // Copy entries using existing mechanism
        targetViewModel.copyDirectoryContents(clipboard.clipboardEntries, from: sourceDiskPath, to: targetDiskPath, sourceIsDOS33: sourceIsDOS33) {
            print("✅ All files pasted")
            
            // If it was a CUT operation, delete from source
            if clipboard.clipboardOperation == .cut {
                print("✂️ Cut operation - deleting from source")
                
                // Delete each entry from source (sourceIsDOS33 already defined above)
                for entry in clipboard.clipboardEntries {
                    if sourceIsDOS33 {
                        DOS33Writer.shared.deleteFile(
                            diskImagePath: sourceDiskPath,
                            fileName: entry.name
                        ) { deleteSuccess, message in
                            if deleteSuccess {
                                print("✅ Deleted \(entry.name) from source (DOS 3.3)")
                            } else {
                                print("❌ Failed to delete \(entry.name): \(message)")
                            }
                        }
                    } else {
                        ProDOSWriter.shared.deleteFile(
                            diskImagePath: sourceDiskPath,
                            fileName: entry.name
                        ) { deleteSuccess, message in
                            if deleteSuccess {
                                print("✅ Deleted \(entry.name) from source (ProDOS)")
                            } else {
                                print("❌ Failed to delete \(entry.name): \(message)")
                            }
                        }
                    }
                }
                
                // Reload source after deletion
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.loadDiskImage(from: sourceDiskPath)
                }
            }
            
            // Clear clipboard after successful paste
            clipboard.clearClipboard()
            
            // Reload target to show new files
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                targetViewModel.loadDiskImage(from: targetDiskPath)
            }
        }
    }
}
