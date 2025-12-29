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

class FocusManager: ObservableObject {
    @Published var activePaneId: PaneIdentifier = .left
    
    static let shared = FocusManager()
    
    private init() {}
    
    func setActivePane(_ paneId: PaneIdentifier) {
        activePaneId = paneId
        print("🎯 Active pane: \(paneId)")
    }
    
    func isActive(_ paneId: PaneIdentifier) -> Bool {
        return activePaneId == paneId
    }
}
