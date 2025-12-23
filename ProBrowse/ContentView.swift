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
                onInspectLeft: {
                    inspectorPane = .left
                    showingInspectorSheet = true
                },
                onInspectRight: {
                    inspectorPane = .right
                    showingInspectorSheet = true
                }
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
    let onInspectLeft: () -> Void
    let onInspectRight: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Left Pane Controls
            Group {
                Button(action: onOpenLeft) {
                    Label("Open Left", systemImage: "folder.badge.plus")
                }
                .help("Open disk image in left pane (⌘O)")
                
                Button(action: onInspectLeft) {
                    Label("Inspect Left", systemImage: "info.circle")
                }
                .help("Inspect left disk image")
            }
            
            Divider()
                .frame(height: 24)
            
            // Global Controls
            Button(action: onCreate) {
                Label("Create Image", systemImage: "doc.badge.plus")
            }
            .help("Create new disk image (⌘N)")
            
            Divider()
                .frame(height: 24)
            
            // Right Pane Controls
            Group {
                Button(action: onOpenRight) {
                    Label("Open Right", systemImage: "folder.badge.plus")
                }
                .help("Open disk image in right pane (⌘⇧O)")
                
                Button(action: onInspectRight) {
                    Label("Inspect Right", systemImage: "info.circle")
                }
                .help("Inspect right disk image")
            }
            
            Spacer()
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
