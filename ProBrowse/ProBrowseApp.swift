//
//  ProBrowseApp.swift
//  ProBrowse
//
//  Created by Walter
//

import SwiftUI

@main
struct ProBrowseApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Disk Image...") {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("createDiskImage"), 
                        object: nil
                    )
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

// Notification Names
extension NSNotification.Name {
    static let createDiskImage = NSNotification.Name("createDiskImage")
    static let openDiskImage = NSNotification.Name("openDiskImage")
}
