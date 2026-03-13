import AppKit
import PDFKit

@MainActor
final class PDFEditorModel: ObservableObject {
    struct TableOfContentsItem: Identifiable, Hashable {
        let id: String
        let title: String
        let pageIndex: Int
        let children: [TableOfContentsItem]
    }

    @Published private(set) var document: PDFDocument?
    @Published private(set) var currentFileURL: URL?
    @Published private(set) var currentPageIndex = 0
    @Published private(set) var selectionRect: CGRect?
    @Published private(set) var tableOfContentsItems: [TableOfContentsItem] = []
    @Published var isShowingPageJumpSheet = false
    @Published var pageJumpInput = ""
    @Published private(set) var errorMessage: String?

    private var launchRequest: LaunchRequest?
    private var didHandleLaunchRequest = false

    init() {
        launchRequest = LaunchRequest.parse(from: CommandLine.arguments.dropFirst())
    }

    var hasDocument: Bool {
        document != nil
    }

    var pageCount: Int {
        document?.pageCount ?? 0
    }

    var canGoPrevious: Bool {
        currentPageIndex > 0
    }

    var canGoNext: Bool {
        currentPageIndex + 1 < pageCount
    }

    var canExport: Bool {
        document != nil && selectionRect != nil
    }

    var hasTableOfContents: Bool {
        !tableOfContentsItems.isEmpty
    }

    var fileDisplayName: String {
        currentFileURL?.lastPathComponent ?? "No PDF loaded"
    }

    var pageStatusText: String {
        guard pageCount > 0 else {
            return "Page 0 / 0"
        }
        return "Page \(currentPageIndex + 1) / \(pageCount)"
    }

    var shortHintText: String {
        selectionRect == nil ? "Drag to select, arrows to browse" : "Arrows move, Shift resizes, Space boosts"
    }

    var selectionSummary: String? {
        guard let selectionRect else {
            return nil
        }

        return "\(Int(selectionRect.width.rounded())) × \(Int(selectionRect.height.rounded())) pt"
    }

    var isShowingError: Bool {
        errorMessage != nil
    }

    func openLaunchRequestIfNeeded() {
        guard !didHandleLaunchRequest else {
            return
        }

        didHandleLaunchRequest = true

        guard let launchRequest else {
            return
        }

        _ = openPDF(at: launchRequest.url, preferredPage: launchRequest.page)
    }

    func dismissError() {
        errorMessage = nil
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        _ = openPDF(at: url, preferredPage: nil)
    }

    @discardableResult
    func openPDF(at url: URL, preferredPage: Int?) -> Bool {
        guard let document = PDFDocument(url: url) else {
            errorMessage = "Could not open \(url.lastPathComponent)."
            return false
        }

        self.document = document
        currentFileURL = url
        selectionRect = nil
        tableOfContentsItems = Self.buildTableOfContents(for: document)

        let targetPage = max(0, min((preferredPage ?? 1) - 1, max(document.pageCount - 1, 0)))
        currentPageIndex = targetPage
        pageJumpInput = "\(targetPage + 1)"
        return true
    }

    func stepPage(by delta: Int) {
        guard pageCount > 0 else {
            return
        }

        setCurrentPageIndex(currentPageIndex + delta)
    }

    func setCurrentPageIndex(_ index: Int) {
        guard pageCount > 0 else {
            currentPageIndex = 0
            return
        }

        let clamped = max(0, min(index, pageCount - 1))
        guard clamped != currentPageIndex else {
            return
        }

        currentPageIndex = clamped
        pageJumpInput = "\(clamped + 1)"
        selectionRect = nil
    }

    func syncCurrentPageFromViewer(_ index: Int) {
        guard pageCount > 0 else {
            return
        }

        let clamped = max(0, min(index, pageCount - 1))
        guard clamped != currentPageIndex else {
            return
        }

        currentPageIndex = clamped
        pageJumpInput = "\(clamped + 1)"
        selectionRect = nil
    }

    func setSelectionRect(_ rect: CGRect?) {
        selectionRect = rect?.standardized
    }

    func clearSelection() {
        selectionRect = nil
    }

    func presentPageJump() {
        guard hasDocument else {
            return
        }

        pageJumpInput = "\(currentPageIndex + 1)"
        isShowingPageJumpSheet = true
    }

    func confirmPageJump() {
        defer { isShowingPageJumpSheet = false }

        guard pageCount > 0 else {
            return
        }

        guard let page = Int(pageJumpInput), (1...pageCount).contains(page) else {
            errorMessage = "Enter a page between 1 and \(pageCount)."
            return
        }

        setCurrentPageIndex(page - 1)
    }

    func exportSelection() {
        guard
            let document,
            let page = document.page(at: currentPageIndex),
            let selectionRect
        else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "cropped_page_\(currentPageIndex + 1).pdf"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try VectorPDFExporter.export(page: page, selectionRect: selectionRect, to: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func buildTableOfContents(for document: PDFDocument) -> [TableOfContentsItem] {
        guard let root = document.outlineRoot else {
            return []
        }

        return outlineChildren(of: root, in: document, path: [])
    }

    private static func outlineChildren(
        of node: PDFOutline,
        in document: PDFDocument,
        path: [Int]
    ) -> [TableOfContentsItem] {
        guard node.numberOfChildren > 0 else {
            return []
        }

        var items: [TableOfContentsItem] = []

        for childIndex in 0..<node.numberOfChildren {
            guard let child = node.child(at: childIndex) else {
                continue
            }

            let childPath = path + [childIndex]
            let children = outlineChildren(of: child, in: document, path: childPath)
            let resolvedPageIndex = resolvedPageIndex(for: child, in: document) ?? children.first?.pageIndex

            if
                let title = child.label?.trimmingCharacters(in: .whitespacesAndNewlines),
                !title.isEmpty,
                let pageIndex = resolvedPageIndex
            {
                items.append(
                    TableOfContentsItem(
                        id: childPath.map(String.init).joined(separator: "."),
                        title: title,
                        pageIndex: pageIndex,
                        children: children
                    )
                )
            }
        }

        return items
    }

    private static func resolvedPageIndex(for outline: PDFOutline, in document: PDFDocument) -> Int? {
        guard
            let destination = outline.destination,
            let page = destination.page
        else {
            return nil
        }

        let pageIndex = document.index(for: page)
        return pageIndex == NSNotFound ? nil : pageIndex
    }
}

private struct LaunchRequest {
    let url: URL
    let page: Int?

    static func parse<S: Sequence>(from arguments: S) -> LaunchRequest? where S.Element == String {
        var iterator = arguments.makeIterator()
        var page: Int?
        var path: String?

        while let argument = iterator.next() {
            switch argument {
            case "--page":
                guard let value = iterator.next(), let parsed = Int(value) else {
                    continue
                }
                page = parsed
            default:
                if path == nil {
                    path = argument
                }
            }
        }

        guard let path else {
            return nil
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let resolved = URL(fileURLWithPath: path, relativeTo: cwd).standardizedFileURL
        return LaunchRequest(url: resolved, page: page)
    }
}
