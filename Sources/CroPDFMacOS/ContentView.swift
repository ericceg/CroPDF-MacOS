import AppKit
import PDFKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: PDFEditorModel

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Divider()

                if model.hasDocument {
                    workspace
                } else {
                    EmptyStateView(openAction: model.openPanel)
                }

                Divider()
                statusBar
            }
        }
        .sheet(isPresented: $model.isShowingPageJumpSheet) {
            PageJumpSheet(model: model)
        }
        .alert("CroPDF", isPresented: Binding(
            get: { model.isShowingError },
            set: { if !$0 { model.dismissError() } }
        )) {
            Button("OK", role: .cancel) {
                model.dismissError()
            }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
        .task {
            model.openLaunchRequestIfNeeded()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                model.openPanel()
            } label: {
                Label("Open", systemImage: "folder")
            }

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.fileDisplayName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                Text(model.hasDocument ? "Lossless PDF cropper" : "Open a PDF to begin")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            pageNavigation

            Button("Go to Page") {
                model.presentPageJump()
            }
            .disabled(!model.hasDocument)

            Button {
                model.exportSelection()
            } label: {
                Label("Crop and Save", systemImage: "square.on.square")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canExport)
        }
        .controlSize(.regular)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var pageNavigation: some View {
        HStack(spacing: 10) {
            ControlGroup {
                Button {
                    model.stepPage(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!model.canGoPrevious)

                Button {
                    model.stepPage(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!model.canGoNext)
            }

            Text(model.pageStatusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        }
    }

    private var workspace: some View {
        HStack(spacing: 0) {
            ThumbnailSidebarView(model: model)
                .frame(width: 168)

            Divider()

            InteractivePDFCanvas(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Text(model.shortHintText)
                .foregroundStyle(.secondary)

            Spacer()

            if let selectionSummary = model.selectionSummary {
                Text("Selection: \(selectionSummary)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct ThumbnailSidebarView: View {
    @ObservedObject var model: PDFEditorModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0..<model.pageCount, id: \.self) { index in
                    ThumbnailCell(
                        image: thumbnail(for: index),
                        pageNumber: index + 1,
                        isSelected: index == model.currentPageIndex
                    )
                    .onTapGesture {
                        model.setCurrentPageIndex(index)
                    }
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func thumbnail(for index: Int) -> NSImage {
        guard let page = model.document?.page(at: index) else {
            return NSImage(size: NSSize(width: 120, height: 160))
        }

        return page.thumbnail(of: NSSize(width: 120, height: 160), for: .cropBox)
    }
}

private struct ThumbnailCell: View {
    let image: NSImage
    let pageNumber: Int
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 116)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)

            Text("\(pageNumber)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }
}

private struct EmptyStateView: View {
    let openAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Open a PDF")
                    .font(.system(size: 22, weight: .semibold))

                Text("Drag to create a crop, use the arrow keys for fine adjustment, then export a cropped PDF without rasterizing it.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button {
                openAction()
            } label: {
                Label("Choose PDF", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct PageJumpSheet: View {
    @ObservedObject var model: PDFEditorModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Go to Page")
                .font(.system(size: 20, weight: .semibold))

            Text("Enter a page from 1 to \(max(model.pageCount, 1)).")
                .foregroundStyle(.secondary)

            TextField("Page number", text: $model.pageJumpInput)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    submit()
                }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Go") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 320)
        .background(.regularMaterial)
        .task {
            isFocused = true
        }
    }

    private func submit() {
        model.confirmPageJump()
        dismiss()
    }
}
