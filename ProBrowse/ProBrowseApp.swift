//
//  ProBrowseApp.swift
//  ProBrowse
//
//  Created by Walter
//

import SwiftUI

@main
struct ProBrowseApp: App {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onReceive(NotificationCenter.default.publisher(for: .showHelp)) { _ in
                    openWindow(id: "help-window")
                }
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

            CommandGroup(replacing: .help) {
                Button("ProBrowse Help") {
                    NotificationCenter.default.post(
                        name: .showHelp,
                        object: nil
                    )
                }
                .keyboardShortcut("?", modifiers: .command)

                Divider()

                Button("Visit ProBrowse on GitHub") {
                    if let url = URL(string: "https://github.com/portwally/ProBrowse") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

        Window("ProBrowse Help", id: "help-window") {
            HelpWindow()
        }
        .defaultSize(width: 700, height: 500)
    }
}

// Notification Names
extension NSNotification.Name {
    static let createDiskImage = NSNotification.Name("createDiskImage")
    static let openDiskImage = NSNotification.Name("openDiskImage")
    static let showHelp = NSNotification.Name("showHelp")
}
