import AppKit
import PDFKit
import SwiftUI

struct InteractivePDFCanvas: NSViewRepresentable {
    @ObservedObject var model: PDFEditorModel

    func makeNSView(context: Context) -> PDFCanvasContainerView {
        let view = PDFCanvasContainerView()
        view.onSelectionChange = { rect in
            Task { @MainActor in
                model.setSelectionRect(rect)
            }
        }
        view.onPageStep = { delta in
            Task { @MainActor in
                model.stepPage(by: delta)
            }
        }
        view.onClearSelection = {
            Task { @MainActor in
                model.clearSelection()
            }
        }
        view.onPageChange = { pageIndex in
            Task { @MainActor in
                model.syncCurrentPageFromViewer(pageIndex)
            }
        }
        return view
    }

    func updateNSView(_ nsView: PDFCanvasContainerView, context: Context) {
        nsView.update(document: model.document, pageIndex: model.currentPageIndex, selectionRect: model.selectionRect)
    }
}

final class PDFCanvasContainerView: NSView {
    let pdfView = PDFView()
    private let stageView = NSView()
    let overlayView = SelectionOverlayView()

    var onSelectionChange: ((CGRect?) -> Void)? {
        didSet { overlayView.onSelectionChange = onSelectionChange }
    }

    var onPageStep: ((Int) -> Void)? {
        didSet { overlayView.onPageStep = onPageStep }
    }

    var onClearSelection: (() -> Void)? {
        didSet { overlayView.onClearSelection = onClearSelection }
    }

    var onPageChange: ((Int) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor

        stageView.translatesAutoresizingMaskIntoConstraints = false
        stageView.wantsLayer = true
        stageView.layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.displayBox = .cropBox
        pdfView.backgroundColor = .underPageBackgroundColor

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.pdfView = pdfView

        addSubview(stageView)
        stageView.addSubview(pdfView)
        stageView.addSubview(overlayView)

        NSLayoutConstraint.activate([
            stageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stageView.topAnchor.constraint(equalTo: topAnchor),
            stageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            pdfView.leadingAnchor.constraint(equalTo: stageView.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: stageView.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: stageView.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: stageView.bottomAnchor),

            overlayView.leadingAnchor.constraint(equalTo: stageView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: stageView.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: stageView.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: stageView.bottomAnchor),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePDFPageChanged),
            name: .PDFViewPageChanged,
            object: pdfView
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func update(document: PDFDocument?, pageIndex: Int, selectionRect: CGRect?) {
        if pdfView.document !== document {
            pdfView.document = document
        }

        if
            let document,
            let page = document.page(at: pageIndex),
            pdfView.currentPage !== page
        {
            pdfView.go(to: page)
        }

        overlayView.sync(selectionRect: selectionRect)
        overlayView.needsDisplay = true
    }

    @objc
    private func handlePDFPageChanged() {
        guard
            let document = pdfView.document,
            let currentPage = pdfView.currentPage
        else {
            return
        }

        let pageIndex = document.index(for: currentPage)
        if pageIndex != NSNotFound {
            onPageChange?(pageIndex)
        }
    }
}

final class SelectionOverlayView: NSView {
    weak var pdfView: PDFView?
    var onSelectionChange: ((CGRect?) -> Void)?
    var onPageStep: ((Int) -> Void)?
    var onClearSelection: (() -> Void)?

    private var selectionRectInPage: CGRect?
    private var dragAnchor: CGPoint?
    private var isSpaceHeld = false

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    func sync(selectionRect: CGRect?) {
        let standardized = selectionRect?.standardized
        if selectionRectInPage != standardized {
            selectionRectInPage = standardized
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        guard let pageFrame = currentPageFrame else {
            return
        }

        dragAnchor = clamp(point: convert(event.locationInWindow, from: nil), to: pageFrame)
        selectionRectInPage = nil
        onSelectionChange?(nil)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        updateSelection(with: event, finalize: false)
    }

    override func mouseUp(with event: NSEvent) {
        updateSelection(with: event, finalize: true)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            isSpaceHeld = true
            return
        }

        if event.keyCode == 53 {
            selectionRectInPage = nil
            onClearSelection?()
            onSelectionChange?(nil)
            needsDisplay = true
            return
        }

        guard let selectionViewRect = currentSelectionFrame else {
            handleNavigationKey(event)
            return
        }

        guard let pageFrame = currentPageFrame else {
            return
        }

        let delta = isSpaceHeld ? CGFloat(25) : CGFloat(1)
        let shiftHeld = event.modifierFlags.contains(.shift)
        var rect = selectionViewRect

        switch event.keyCode {
        case 123:
            if shiftHeld {
                rect.size.width = max(2, rect.width - delta)
            } else {
                rect.origin.x -= delta
            }
        case 124:
            if shiftHeld {
                rect.size.width += delta
            } else {
                rect.origin.x += delta
            }
        case 125:
            if shiftHeld {
                rect.size.height += delta
            } else {
                rect.origin.y += delta
            }
        case 126:
            if shiftHeld {
                rect.size.height = max(2, rect.height - delta)
            } else {
                rect.origin.y -= delta
            }
        default:
            super.keyDown(with: event)
            return
        }

        rect = clamp(selectionRect: rect.standardized, to: pageFrame)
        selectionRectInPage = convertSelectionToPage(rect)
        onSelectionChange?(selectionRectInPage)
        needsDisplay = true
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            isSpaceHeld = false
            return
        }

        super.keyUp(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let rect = currentSelectionFrame?.integral else {
            return
        }

        let fillPath = NSBezierPath(rect: rect)
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        fillPath.fill()

        let strokePath = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        strokePath.lineWidth = 1
        NSColor.controlAccentColor.setStroke()
        strokePath.stroke()
    }

    private func updateSelection(with event: NSEvent, finalize: Bool) {
        guard let dragAnchor, let pageFrame = currentPageFrame else {
            return
        }

        let point = clamp(point: convert(event.locationInWindow, from: nil), to: pageFrame)
        let rect = CGRect(
            x: min(dragAnchor.x, point.x),
            y: min(dragAnchor.y, point.y),
            width: abs(point.x - dragAnchor.x),
            height: abs(point.y - dragAnchor.y)
        )

        if finalize, (rect.width < 3 || rect.height < 3) {
            selectionRectInPage = nil
            onSelectionChange?(nil)
        } else {
            selectionRectInPage = convertSelectionToPage(rect)
            onSelectionChange?(selectionRectInPage)
        }

        if finalize {
            self.dragAnchor = nil
        }

        needsDisplay = true
    }

    private func handleNavigationKey(_ event: NSEvent) {
        switch event.keyCode {
        case 123:
            onPageStep?(-1)
        case 124:
            onPageStep?(1)
        default:
            super.keyDown(with: event)
        }
    }

    private var currentPageFrame: CGRect? {
        guard let pdfView, let page = pdfView.currentPage else {
            return nil
        }

        let pageBounds = page.bounds(for: pdfView.displayBox)
        let inPDFView = pdfView.convert(pageBounds, from: page)
        let frame = convert(inPDFView, from: pdfView).standardized
        return frame.isNull ? nil : frame
    }

    private var currentSelectionFrame: CGRect? {
        guard
            let pdfView,
            let page = pdfView.currentPage,
            let selectionRectInPage
        else {
            return nil
        }

        let inPDFView = pdfView.convert(selectionRectInPage, from: page)
        let frame = convert(inPDFView, from: pdfView).standardized
        return frame.isNull ? nil : frame
    }

    private func convertSelectionToPage(_ rect: CGRect) -> CGRect? {
        guard let pdfView, let page = pdfView.currentPage else {
            return nil
        }

        let inPDFView = convert(rect, to: pdfView)
        let inPage = pdfView.convert(inPDFView, to: page).standardized
        let pageBounds = page.bounds(for: pdfView.displayBox)
        let clipped = inPage.intersection(pageBounds)
        guard clipped.width > 1, clipped.height > 1 else {
            return nil
        }
        return clipped
    }

    private func clamp(point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func clamp(selectionRect: CGRect, to pageFrame: CGRect) -> CGRect {
        var rect = selectionRect

        rect.size.width = min(rect.width, pageFrame.width)
        rect.size.height = min(rect.height, pageFrame.height)
        rect.origin.x = min(max(rect.origin.x, pageFrame.minX), pageFrame.maxX - rect.width)
        rect.origin.y = min(max(rect.origin.y, pageFrame.minY), pageFrame.maxY - rect.height)

        return rect
    }
}
