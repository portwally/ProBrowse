//
//  FocusManager.swift
//  ProBrowse
//
//  Manages which pane is currently active/focused
//

import SwiftUI
import Combine

enum PaneIdentifier {
    case left
    case right
}

enum ClipboardOperation {
    case copy
    case cut
}

class FocusManager: ObservableObject {
    @Published var activePaneId: PaneIdentifier = .left
    
    // Shared clipboard
    var clipboardEntries: [DiskCatalogEntry] = []
    var clipboardOperation: ClipboardOperation = .copy
    var clipboardSourcePath: URL?
    
    static let shared = FocusManager()
    
    private init() {}
    
    func setActivePane(_ paneId: PaneIdentifier) {
        activePaneId = paneId
        print("🎯 Active pane: \(paneId)")
    }
    
    func isActive(_ paneId: PaneIdentifier) -> Bool {
        return activePaneId == paneId
    }
    
    func copyToClipboard(entries: [DiskCatalogEntry], operation: ClipboardOperation, sourcePath: URL) {
        clipboardEntries = entries
        clipboardOperation = operation
        clipboardSourcePath = sourcePath
        print("📋 Clipboard: \(entries.count) items (\(operation))")
    }
    
    func clearClipboard() {
        clipboardEntries.removeAll()
        clipboardSourcePath = nil
        print("🗑️ Clipboard cleared")
    }
    
    func hasClipboard() -> Bool {
        return !clipboardEntries.isEmpty
    }
}
