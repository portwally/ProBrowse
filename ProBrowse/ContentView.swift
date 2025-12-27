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
        GeometryReader { geometry in
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
            .overlay(
                // Vertical divider in toolbar aligned with browser divider
                Divider()
                    .frame(width: 1)
                    .offset(x: geometry.size.width / 2, y: 30) // Center, toolbar height/2
                    .frame(height: 60)
                , alignment: .topLeading
            )
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
        HStack(spacing: 0) {
            // Left Pane Controls
            HStack(spacing: 16) {
                ToolbarButton(
                    icon: "folder.badge.plus",
                    label: "Open Left",
                    action: onOpenLeft
                )
                .help("Open disk image in left pane (⌘O)")
                
                ToolbarButton(
                    icon: "trash",
                    label: "Delete",
                    action: onDeleteLeft,
                    disabled: leftSelectionCount == 0,
                    destructive: true
                )
                .help("Delete selected files (⌫)")
                
                ToolbarButton(
                    icon: "square.and.arrow.up",
                    label: "Export",
                    action: onExportLeft,
                    disabled: leftSelectionCount == 0
                )
                .help("Export selected files to Finder")
                
                if leftSelectionCount > 0 {
                    Text("\(leftSelectionCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
            }
            .padding(.leading, 16)
            
            Spacer()
            
            // Global Controls (centered)
            ToolbarButton(
                icon: "doc.badge.plus",
                label: "Create Image",
                action: onCreate
            )
            .help("Create new disk image (⌘N)")
            
            Spacer()
            
            // Right Pane Controls
            HStack(spacing: 16) {
                if rightSelectionCount > 0 {
                    Text("\(rightSelectionCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.trailing, 4)
                }
                
                ToolbarButton(
                    icon: "square.and.arrow.up",
                    label: "Export",
                    action: onExportRight,
                    disabled: rightSelectionCount == 0
                )
                .help("Export selected files to Finder")
                
                ToolbarButton(
                    icon: "trash",
                    label: "Delete",
                    action: onDeleteRight,
                    disabled: rightSelectionCount == 0,
                    destructive: true
                )
                .help("Delete selected files (⌫)")
                
                ToolbarButton(
                    icon: "folder.badge.plus",
                    label: "Open Right",
                    action: onOpenRight
                )
                .help("Open disk image in right pane (⌘⇧O)")
            }
            .padding(.trailing, 16)
        }
        .frame(height: 60) // Compact height
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Toolbar Button Component

struct ToolbarButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    var disabled: Bool = false
    var destructive: Bool = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .frame(height: 20)
                
                Text(label)
                    .font(.system(size: 9))
            }
            .frame(width: 60)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .foregroundColor(
            disabled ? .secondary : (destructive ? .red : .primary)
        )
    }
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
