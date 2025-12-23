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
    
    var isAllSelected: Bool {
        guard let catalog = catalog else { return false }
        let allIds = Set(catalog.allEntries.map { $0.id })
        return !allIds.isEmpty && selectedEntries == allIds
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
    
    func toggleSelection(_ entry: DiskCatalogEntry) {
        if selectedEntries.contains(entry.id) {
            selectedEntries.remove(entry.id)
            
            // Deselect children
            if let children = entry.children {
                for child in children {
                    deselectRecursive(child)
                }
            }
        } else {
            selectedEntries.insert(entry.id)
            
            // Select children
            if let children = entry.children {
                for child in children {
                    selectRecursive(child)
                }
            }
        }
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
    
    func getSelectedEntries() -> [DiskCatalogEntry] {
        guard let catalog = catalog else { return [] }
        return catalog.allEntries.filter { selectedEntries.contains($0.id) }
    }
    
    // MARK: - Export to Finder
    
    func exportSelectedToFinder() {
        let entriesToExport = getSelectedEntries().filter { !$0.isDirectory }
        
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
            
            for entry in entriesToExport {
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
                
                let fileURL = exportFolder.appendingPathComponent(filename)
                try entry.data.write(to: fileURL)
                print("✅ Exported: \(filename)")
            }
            
            print("🎉 Export completed: \(entriesToExport.count) files")
            NSWorkspace.shared.activateFileViewerSelecting([exportFolder])
            
        } catch {
            print("❌ Export error: \(error)")
        }
    }
    
    // MARK: - Import Files
    
    func importFile(from url: URL) {
        guard let catalog = catalog,
              let imagePath = diskImagePath else { return }
        
        guard url.startAccessingSecurityScopedResource() else {
            print("Failed to access file")
            return
        }
        
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let data = try Data(contentsOf: url)
            let filename = url.lastPathComponent
            
            // Use Cadius to add file
            CadiusManager.shared.addFile(
                diskImage: imagePath,
                filePath: url,
                fileName: filename
            ) { success in
                if success {
                    // Reload disk image
                    DispatchQueue.main.async {
                        self.loadDiskImage(from: imagePath)
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
        
        // Use Cadius to copy files between images
        for entry in entries where !entry.isDirectory {
            CadiusManager.shared.copyFile(
                from: sourceImagePath,
                to: targetImagePath,
                fileName: entry.name
            ) { success in
                if success {
                    print("Copied \(entry.name)")
                }
            }
        }
        
        // Reload after all copies
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.loadDiskImage(from: targetImagePath)
        }
    }
}
