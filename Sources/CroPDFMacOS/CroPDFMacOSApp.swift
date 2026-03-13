import SwiftUI

@main
struct CroPDFMacOSApp: App {
    @StateObject private var model = PDFEditorModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1040, minHeight: 760)
        }
        .defaultSize(width: 1240, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) { }
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
