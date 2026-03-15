import AppKit
import PDFKit
import SwiftUI

struct ContentView: View {
    private enum SidebarMode: String, CaseIterable, Identifiable {
        case contents = "Contents"
        case pages = "Pages"

        var id: String { rawValue }
    }

    @ObservedObject var model: PDFEditorModel
    @State private var sidebarMode: SidebarMode = .contents

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
            navigationSidebar
                .frame(width: 240)

            Divider()

            InteractivePDFCanvas(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var navigationSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Navigation", selection: $sidebarMode) {
                ForEach(SidebarMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)

            Group {
                switch sidebarMode {
                case .contents:
                    TableOfContentsSidebarView(model: model)
                case .pages:
                    ThumbnailSidebarView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .controlBackgroundColor))
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

private struct TableOfContentsSidebarView: View {
    @ObservedObject var model: PDFEditorModel
    @State private var expandedItemIDs: Set<String> = []
    @State private var manuallySelectedItemID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.hasTableOfContents {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(model.tableOfContentsItems) { item in
                                TableOfContentsNodeView(
                                    item: item,
                                    selectedItemID: selectedTableOfContentsItem?.id,
                                    expandedItemIDs: $expandedItemIDs,
                                    onSelect: { selectedItem in
                                        manuallySelectedItemID = selectedItem.id
                                        model.setCurrentPageIndex(selectedItem.pageIndex)
                                    }
                                )
                            }
                        }
                    .padding(8)
                }
                .onAppear {
                    syncManualSelectionForCurrentPage()
                    syncExpandedStateForCurrentPage()
                }
                .onChange(of: model.currentPageIndex) { _, _ in
                    syncManualSelectionForCurrentPage()
                    syncExpandedStateForCurrentPage()
                }
            } else {
                ContentUnavailableView(
                    "No Table of Contents",
                    systemImage: "list.bullet.rectangle",
                    description: Text("This PDF does not include outline entries.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
            }
        }
    }

    private var selectedTableOfContentsItem: PDFEditorModel.TableOfContentsItem? {
        if
            let manuallySelectedItemID,
            let manuallySelectedItem = item(withID: manuallySelectedItemID, in: model.tableOfContentsItems),
            manuallySelectedItem.pageIndex == model.currentPageIndex
        {
            return manuallySelectedItem
        }

        return deepestMatchingItem(in: model.tableOfContentsItems)
    }

    private func item(withID id: String, in items: [PDFEditorModel.TableOfContentsItem]) -> PDFEditorModel.TableOfContentsItem? {
        for candidate in items {
            if candidate.id == id {
                return candidate
            }

            if let child = item(withID: id, in: candidate.children) {
                return child
            }
        }

        return nil
    }

    private func deepestMatchingItem(in items: [PDFEditorModel.TableOfContentsItem]) -> PDFEditorModel.TableOfContentsItem? {
        var candidate: PDFEditorModel.TableOfContentsItem?

        for item in items where item.pageIndex <= model.currentPageIndex {
            candidate = item

            if let deeper = deepestMatchingItem(in: item.children) {
                candidate = deeper
            }
        }

        return candidate
    }

    private func syncExpandedStateForCurrentPage() {
        guard let selectedItem = selectedTableOfContentsItem else {
            return
        }

        expandedItemIDs.formUnion(ancestorIDs(for: selectedItem.id))
    }

    private func syncManualSelectionForCurrentPage() {
        guard
            let manuallySelectedItemID,
            let manuallySelectedItem = item(withID: manuallySelectedItemID, in: model.tableOfContentsItems)
        else {
            return
        }

        if manuallySelectedItem.pageIndex != model.currentPageIndex {
            self.manuallySelectedItemID = nil
        }
    }

    private func ancestorIDs(for id: String) -> [String] {
        let components = id.split(separator: ".").map(String.init)
        guard components.count > 1 else {
            return []
        }

        return (1..<components.count).map { components.prefix($0).joined(separator: ".") }
    }
}

private struct TableOfContentsNodeView: View {
    let item: PDFEditorModel.TableOfContentsItem
    let selectedItemID: String?
    @Binding var expandedItemIDs: Set<String>
    let onSelect: (PDFEditorModel.TableOfContentsItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if hasChildren {
                    Button {
                        toggleExpanded()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(width: 24, height: 24)
                }

                Text(item.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.black)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text("\(item.pageIndex + 1)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.black.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect(item)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.85) : Color.clear)
            )

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.children) { child in
                        TableOfContentsNodeView(
                            item: child,
                            selectedItemID: selectedItemID,
                            expandedItemIDs: $expandedItemIDs,
                            onSelect: onSelect
                        )
                    }
                }
                .padding(.leading, 14)
            }
        }
    }

    private var hasChildren: Bool {
        !item.children.isEmpty
    }

    private var isExpanded: Bool {
        expandedItemIDs.contains(item.id)
    }

    private var isSelected: Bool {
        item.id == selectedItemID
    }

    private func toggleExpanded() {
        if isExpanded {
            expandedItemIDs.remove(item.id)
        } else {
            expandedItemIDs.insert(item.id)
        }
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
