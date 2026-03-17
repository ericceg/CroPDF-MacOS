import AppKit
import SwiftUI

final class CroPDFAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconImage = appIconImage() {
            NSApp.applicationIconImage = iconImage
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    private func appIconImage() -> NSImage? {
        let candidates = [
            ("CroPDF", "icns"),
            ("CroPDFIcon", "png"),
        ]

        for (name, ext) in candidates {
            if let iconURL = Bundle.module.url(forResource: name, withExtension: ext),
               let iconImage = NSImage(contentsOf: iconURL) {
                return iconImage
            }
        }

        return nil
    }
}

@main
struct CroPDFMacOSApp: App {
    @NSApplicationDelegateAdaptor(CroPDFAppDelegate.self) private var appDelegate
    @StateObject private var model = PDFEditorModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 800, minHeight: 400)
        }
        .defaultSize(width: 1240, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open PDF") {
                    model.openPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("CroPDF") {
                Button("Open PDF") {
                    model.openPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Crop and Save") {
                    model.exportSelection()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.canExport)

                Button("Go to Page") {
                    model.presentPageJump()
                }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(!model.hasDocument)
            }
        }
    }
}
