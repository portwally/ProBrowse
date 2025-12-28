//
//  DiskPaneViewModel.swift
//  ProBrowse
//
//  ViewModel for managing disk pane state and operations
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
    
    // MARK: - Load Disk Image
    
    func loadDiskImage(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("Failed to access security scoped resource")
            return
        }
        
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let data = try Data(contentsOf: url)
            self.diskImagePath = url
            
            // Reset navigation
            navigateToRoot()
            
            // Try to parse as ProDOS
            if let catalog = try? DiskImageParser.parseProDOS(data: data, diskName: url.lastPathComponent) {
                self.catalog = catalog
                self.selectedEntries = []
                return
            }
            
            // Try to parse as DOS 3.3
            if let catalog = try? DiskImageParser.parseDOS33(data: data, diskName: url.lastPathComponent) {
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
    
    private func selectRecursive(_ entry: DiskCatalogEntry) {
        selectedEntries.insert(entry.id)
        if let children = entry.children {
            for child in children {
                selectRecursive(child)
            }
        }
    }
    
    private func deselectRecursive(_ entry: DiskCatalogEntry) {
        selectedEntries.remove(entry.id)
        if let children = entry.children {
            for child in children {
                deselectRecursive(child)
            }
        }
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
        let entriesToExport = getSelectedEntries()  // Include directories!
        
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
            
            // Use native ProDOS writer to add file
            // Default to BIN ($06) file type with aux 0x0000
            ProDOSWriter.shared.addFile(
                diskImagePath: imagePath,
                fileName: filename,
                fileData: fileData,
                fileType: 0x06,  // BIN
                auxType: 0x0000
            ) { success, message in
                if success {
                    print("✅ File imported successfully")
                    // Reload disk image
                    DispatchQueue.main.async {
                        self.loadDiskImage(from: imagePath)
                    }
                } else {
                    print("❌ Failed to import: \(message)")
                }
            }
            
        } catch {
            print("Error importing file: \(error)")
        }
    }
    
    func importEntries(_ entries: [DiskCatalogEntry], from sourceVM: DiskPaneViewModel) {
        guard let targetImagePath = diskImagePath,
              let sourceImagePath = sourceVM.diskImagePath else { return }
        
        print("📋 Copying files using native ProDOS writer...")
        
        // Copy files sequentially to avoid race conditions
        copyNextFile(entries: entries, index: 0, from: sourceImagePath, to: targetImagePath)
    }
    
    private func copyNextFile(entries: [DiskCatalogEntry], index: Int, from sourceImagePath: URL, to targetImagePath: URL) {
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
            // Create the directory itself first!
            print("📁 Processing directory: \(entry.name)")
            
            ProDOSWriter.shared.createDirectory(diskImagePath: targetImagePath, directoryName: entry.name, parentPath: "/") { success, message in
                if success {
                    print("   ✅ Created directory \(entry.name)")
                    
                    // Now copy children INTO this directory
                    if let children = entry.children, !children.isEmpty {
                        print("   📦 Copying \(children.count) children into /\(entry.name)/")
                        let childPath = "/\(entry.name)/"
                        
                        // Recursively copy all children
                        self.copyEntriesRecursively(entries: children, to: targetImagePath, parentPath: childPath, index: 0) {
                            // After all children copied, move to next sibling
                            print("   ✅ Finished copying children of \(entry.name)")
                            self.copyNextFile(entries: entries, index: index + 1, from: sourceImagePath, to: targetImagePath)
                        }
                    } else {
                        // Empty directory, move to next
                        self.copyNextFile(entries: entries, index: index + 1, from: sourceImagePath, to: targetImagePath)
                    }
                } else {
                    print("   ❌ Failed to create directory: \(message)")
                    // Skip this directory and move to next
                    self.copyNextFile(entries: entries, index: index + 1, from: sourceImagePath, to: targetImagePath)
                }
            }
            return
        }
        
        // Use data directly from catalog entry (already extracted by DiskImageParser)
        let data = entry.data
        print("✅ Using cached data for \(entry.name) (\(data.count) bytes)")
        
        // Add to target
        ProDOSWriter.shared.addFile(
            diskImagePath: targetImagePath,
            fileName: entry.name,
            fileData: data,
            fileType: entry.fileType,
            auxType: entry.auxType
        ) { addSuccess, message in
            if addSuccess {
                print("✅ Copied \(entry.name)")
            } else {
                print("❌ Failed to add \(entry.name): \(message)")
            }
            
            // Continue with next file
            self.copyNextFile(entries: entries, index: index + 1, from: sourceImagePath, to: targetImagePath)
        }
    }
    
    // MARK: - Copy Directory Contents (With Structure)
    
    private func copyDirectoryContents(_ entries: [DiskCatalogEntry], from sourceImagePath: URL, to targetImagePath: URL, completion: @escaping () -> Void) {
        // Copy directory structure recursively
        copyEntriesRecursively(entries: entries, to: targetImagePath, parentPath: "/", index: 0, completion: completion)
    }
    
    private func copyEntriesRecursively(entries: [DiskCatalogEntry], to targetImagePath: URL, parentPath: String, index: Int, completion: @escaping () -> Void) {
        guard index < entries.count else {
            // All entries copied
            completion()
            return
        }
        
        let entry = entries[index]
        
        if entry.isDirectory {
            // Create subdirectory first
            print("📁 Creating subdirectory: \(entry.name)")
            
            ProDOSWriter.shared.createDirectory(diskImagePath: targetImagePath, directoryName: entry.name, parentPath: parentPath) { success, message in
                if success {
                    print("   ✅ Created directory \(entry.name)")
                    
                    // Copy children into this subdirectory
                    if let children = entry.children, !children.isEmpty {
                        let newPath = parentPath + entry.name + "/"
                        self.copyEntriesRecursively(entries: children, to: targetImagePath, parentPath: newPath, index: 0) {
                            // After children copied, move to next sibling
                            self.copyEntriesRecursively(entries: entries, to: targetImagePath, parentPath: parentPath, index: index + 1, completion: completion)
                        }
                    } else {
                        // Empty directory, move to next
                        self.copyEntriesRecursively(entries: entries, to: targetImagePath, parentPath: parentPath, index: index + 1, completion: completion)
                    }
                } else {
                    print("   ❌ Failed to create directory: \(message)")
                    // Skip this directory and move to next
                    self.copyEntriesRecursively(entries: entries, to: targetImagePath, parentPath: parentPath, index: index + 1, completion: completion)
                }
            }
        } else {
            // Copy file to parent directory
            print("   Copying file: \(entry.name) to \(parentPath)")
            
            ProDOSWriter.shared.addFile(
                diskImagePath: targetImagePath,
                fileName: entry.name,
                fileData: entry.data,
                fileType: entry.fileType,
                auxType: entry.auxType,
                parentPath: parentPath  // NEW: specify parent directory!
            ) { addSuccess, message in
                if addSuccess {
                    print("   ✅ Copied \(entry.name) to \(parentPath)")
                } else {
                    print("   ❌ Failed: \(message)")
                }
                
                // Continue with next entry
                self.copyEntriesRecursively(entries: entries, to: targetImagePath, parentPath: parentPath, index: index + 1, completion: completion)
            }
        }
    }
    
    private func copyNextFileFromList(files: [DiskCatalogEntry], index: Int, from sourceImagePath: URL, to targetImagePath: URL, completion: @escaping () -> Void) {
        guard index < files.count else {
            // All files from directory copied
            completion()
            return
        }
        
        let entry = files[index]
        let data = entry.data
        
        print("   Copying \(entry.name) from directory...")
        
        ProDOSWriter.shared.addFile(
            diskImagePath: targetImagePath,
            fileName: entry.name,
            fileData: data,
            fileType: entry.fileType,
            auxType: entry.auxType
        ) { addSuccess, message in
            if addSuccess {
                print("   ✅ Copied \(entry.name)")
            } else {
                print("   ❌ Failed: \(message)")
            }
            
            // Continue with next file
            self.copyNextFileFromList(files: files, index: index + 1, from: sourceImagePath, to: targetImagePath, completion: completion)
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
        
        // Delete file or directory
        ProDOSWriter.shared.deleteFile(diskImagePath: diskImagePath, fileName: entry.name) { success, message in
            if success {
                print("✅ Deleted \(entry.name)")
            } else {
                print("❌ Failed to delete \(entry.name): \(message)")
            }
            
            // Continue with next file
            self.deleteNextFile(entries: entries, index: index + 1, from: diskImagePath)
        }
    }
}
