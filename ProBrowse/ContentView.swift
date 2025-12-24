//
//  ContentView.swift
//  ProBrowse
//
//  Apple IIgs Disk Image Browser with Dual Pane View
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

struct ContentView: View {
    @StateObject private var leftPaneVM = DiskPaneViewModel()
    @StateObject private var rightPaneVM = DiskPaneViewModel()
    @State private var showingCreateImageSheet = false
    @State private var showingInspectorSheet = false
    @State private var inspectorPane: PaneLocation? = nil
    
    enum PaneLocation {
        case left, right
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            ToolbarView(
                onOpenLeft: { leftPaneVM.showingFilePicker = true },
                onOpenRight: { rightPaneVM.showingFilePicker = true },
                onCreate: { showingCreateImageSheet = true },
                onDeleteLeft: { leftPaneVM.deleteSelected() },
                onDeleteRight: { rightPaneVM.deleteSelected() },
                onExportLeft: { leftPaneVM.exportSelectedToFinder() },
                onExportRight: { rightPaneVM.exportSelectedToFinder() },
                leftSelectionCount: leftPaneVM.selectedEntries.count,
                rightSelectionCount: rightPaneVM.selectedEntries.count
            )
            
            Divider()
            
            // Dual Pane Browser
            HStack(spacing: 0) {
                // Left Pane
                DiskBrowserPane(viewModel: leftPaneVM, targetViewModel: rightPaneVM, paneTitle: "Left Disk")
                    .frame(minWidth: 400)
                
                Divider()
                
                // Right Pane
                DiskBrowserPane(viewModel: rightPaneVM, targetViewModel: leftPaneVM, paneTitle: "Right Disk")
                    .frame(minWidth: 400)
            }
        }
        .sheet(isPresented: $showingCreateImageSheet) {
            CreateImageSheet()
        }
        .sheet(isPresented: $showingInspectorSheet) {
            if let pane = inspectorPane {
                let vm = pane == .left ? leftPaneVM : rightPaneVM
                ImageInspectorSheet(viewModel: vm)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.createDiskImage)) { _ in
            showingCreateImageSheet = true
        }
    }
}

// MARK: - Toolbar View

struct ToolbarView: View {
    let onOpenLeft: () -> Void
    let onOpenRight: () -> Void
    let onCreate: () -> Void
    let onDeleteLeft: () -> Void
    let onDeleteRight: () -> Void
    let onExportLeft: () -> Void
    let onExportRight: () -> Void
    let leftSelectionCount: Int
    let rightSelectionCount: Int
    
    var body: some View {
        HStack(spacing: 16) {
            // Left Pane Controls
            HStack(spacing: 12) {
                Button(action: onOpenLeft) {
                    Label("Open Left", systemImage: "folder.badge.plus")
                }
                .help("Open disk image in left pane (⌘O)")
                
                Button(action: onDeleteLeft) {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(leftSelectionCount == 0)
                .foregroundColor(leftSelectionCount > 0 ? .red : .secondary)
                .help("Delete selected files (⌫)")
                
                Button(action: onExportLeft) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(leftSelectionCount == 0)
                .help("Export selected files to Finder")
                
                if leftSelectionCount > 0 {
                    Text("\(leftSelectionCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
                .frame(height: 24)
            
            // Global Controls
            Button(action: onCreate) {
                Label("Create Image", systemImage: "doc.badge.plus")
            }
            .help("Create new disk image (⌘N)")
            
            Spacer()
            
            // Vertical separator matching browser divider
            Divider()
                .frame(width: 1)
            
            Spacer()
            
            // Right Pane Controls
            HStack(spacing: 12) {
                if rightSelectionCount > 0 {
                    Text("\(rightSelectionCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Button(action: onExportRight) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(rightSelectionCount == 0)
                .help("Export selected files to Finder")
                
                Button(action: onDeleteRight) {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(rightSelectionCount == 0)
                .foregroundColor(rightSelectionCount > 0 ? .red : .secondary)
                .help("Delete selected files (⌫)")
                
                Button(action: onOpenRight) {
                    Label("Open Right", systemImage: "folder.badge.plus")
                }
                .help("Open disk image in right pane (⌘⇧O)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
