//
//  DiskBrowserPane.swift
//  ProBrowse
//
//  Individual disk browser pane with drag & drop support
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

struct DiskBrowserPane: View {
    @ObservedObject var viewModel: DiskPaneViewModel
    @ObservedObject var targetViewModel: DiskPaneViewModel
    let paneTitle: String
    
    @State private var draggedEntries: [DiskCatalogEntry] = []
    @State private var isTargeted = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(paneTitle)
                    .font(.headline)
                
                Spacer()
                
                if let diskName = viewModel.catalog?.diskName {
                    Text(diskName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if let imagePath = viewModel.diskImagePath {
                    Text(imagePath.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Browser Content
            if let catalog = viewModel.catalog {
                ScrollView {
                    VStack(spacing: 0) {
                        // Control Bar
                        HStack {
                            Button(action: { viewModel.toggleSelectAll() }) {
                                Label(viewModel.isAllSelected ? "Deselect All" : "Select All",
                                      systemImage: viewModel.isAllSelected ? "checkmark.square" : "square")
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { viewModel.expandAll() }) {
                                Label("Expand All", systemImage: "arrow.down.right.and.arrow.up.left")
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                            
                            if !viewModel.selectedEntries.isEmpty {
                                Text("\(viewModel.selectedEntries.count) selected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Button("Export to Finder") {
                                    viewModel.exportSelectedToFinder()
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        
                        Divider()
                        
                        // File List
                        ForEach(catalog.rootEntries) { entry in
                            CatalogEntryRow(
                                entry: entry,
                                isSelected: { viewModel.isSelected($0) },
                                onToggle: { viewModel.toggleSelection($0) },
                                level: 0,
                                expandAllTrigger: viewModel.expandAllTrigger
                            )
                            .onDrag {
                                // Drag from this pane
                                let selectedEntries = viewModel.getSelectedEntries()
                                print("🎯 Starting drag with \(selectedEntries.count) entries")
                                for entry in selectedEntries {
                                    print("   - \(entry.name)")
                                }
                                draggedEntries = selectedEntries
                                return NSItemProvider(object: DraggedEntriesWrapper(entries: selectedEntries))
                            }
                        }
                    }
                }
                .background(
                    Color.clear
                        .onDrop(of: [.fileURL, .data], isTargeted: $isTargeted) { providers in
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
            } else {
                // Empty State
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
                        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                            handleDrop(providers: providers)
                        }
                )
            }
        }
        .fileImporter(
            isPresented: $viewModel.showingFilePicker,
            allowedContentTypes: [.po, .twoimg, .hdv, .woz],
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
    }
    
    // MARK: - Drop Handler
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        print("📥 Drop received with \(providers.count) providers")
        
        // Handle drop from Finder (file URLs)
        for provider in providers {
            print("   Provider has file URL: \(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))")
            print("   Provider has data: \(provider.hasItemConformingToTypeIdentifier("com.probrowse.entries"))")
            
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                print("🗂️ Handling Finder drop")
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
                            if ["po", "2mg", "hdv", "woz"].contains(url.pathExtension.lowercased()) {
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
        }
        
        // Handle drop from other pane
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("com.probrowse.entries") {
                print("🔄 Handling inter-pane drop")
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
