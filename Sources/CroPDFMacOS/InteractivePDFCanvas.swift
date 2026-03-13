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
    let pdfView = PreviewLikePDFView()
    let overlayView = SelectionOverlayView()
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var magnifyMonitor: Any?
    private var smartMagnifyMonitor: Any?

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

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.displayBox = .cropBox
        pdfView.backgroundColor = .underPageBackgroundColor
        pdfView.isInMarkupMode = true

        overlayView.pdfView = pdfView
        overlayView.frame = .zero
        overlayView.autoresizingMask = [.width, .height]

        addSubview(pdfView)

        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePDFPageChanged),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePDFViewGeometryChanged),
            name: .PDFViewScaleChanged,
            object: pdfView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePDFViewGeometryChanged),
            name: .PDFViewVisiblePagesChanged,
            object: pdfView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePDFViewGeometryChanged),
            name: .PDFViewDisplayBoxChanged,
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeEventMonitors()
        } else {
            installEventMonitorsIfNeeded()
            attachOverlayIfNeeded()
        }
    }

    override func layout() {
        super.layout()
        attachOverlayIfNeeded()
    }

    func update(document: PDFDocument?, pageIndex: Int, selectionRect: CGRect?) {
        if pdfView.document !== document {
            pdfView.document = document
            pdfView.refreshZoomBounds()
            attachOverlayIfNeeded()
        }

        if
            let document,
            let page = document.page(at: pageIndex),
            pdfView.currentPage !== page
        {
            pdfView.go(to: page)
        }

        attachOverlayIfNeeded()
        overlayView.sync(selectionRect: selectionRect)
        overlayView.needsDisplay = true
    }

    @objc
    private func handlePDFPageChanged() {
        overlayView.needsDisplay = true

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

    @objc
    private func handlePDFViewGeometryChanged() {
        attachOverlayIfNeeded()
        overlayView.needsDisplay = true
    }

    private func shouldHandleKeyboardEvent(_ event: NSEvent) -> Bool {
        guard
            let window,
            event.window === window,
            window.attachedSheet == nil
        else {
            return false
        }

        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            return false
        }

        if window.firstResponder is NSTextView {
            return false
        }

        return true
    }

    private func shouldHandleGestureEvent(_ event: NSEvent) -> Bool {
        guard
            let window,
            event.window === window,
            window.attachedSheet == nil
        else {
            return false
        }

        let locationInView = convert(event.locationInWindow, from: nil)
        return bounds.contains(locationInView)
    }

    private func installEventMonitorsIfNeeded() {
        if keyDownMonitor == nil {
            keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else {
                    return event
                }

                guard shouldHandleKeyboardEvent(event) else {
                    return event
                }

                return overlayView.handleKeyDownEvent(event) ? nil : event
            }
        }

        if keyUpMonitor == nil {
            keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                guard let self else {
                    return event
                }

                guard shouldHandleKeyboardEvent(event) else {
                    return event
                }

                return overlayView.handleKeyUpEvent(event) ? nil : event
            }
        }

        if magnifyMonitor == nil {
            magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
                guard let self else {
                    return event
                }

                guard shouldHandleGestureEvent(event) else {
                    return event
                }

                pdfView.handleMagnifyEvent(event, in: self)
                overlayView.needsDisplay = true
                return nil
            }
        }

        if smartMagnifyMonitor == nil {
            smartMagnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .smartMagnify) { [weak self] event in
                guard let self else {
                    return event
                }

                guard shouldHandleGestureEvent(event) else {
                    return event
                }

                pdfView.smartMagnify(with: event)
                overlayView.needsDisplay = true
                return nil
            }
        }
    }

    private func removeEventMonitors() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }

        if let keyUpMonitor {
            NSEvent.removeMonitor(keyUpMonitor)
            self.keyUpMonitor = nil
        }

        if let magnifyMonitor {
            NSEvent.removeMonitor(magnifyMonitor)
            self.magnifyMonitor = nil
        }

        if let smartMagnifyMonitor {
            NSEvent.removeMonitor(smartMagnifyMonitor)
            self.smartMagnifyMonitor = nil
        }
    }

    private func attachOverlayIfNeeded() {
        guard let documentView = pdfView.documentView else {
            overlayView.removeFromSuperview()
            return
        }

        if overlayView.superview !== documentView {
            overlayView.removeFromSuperview()
            overlayView.frame = documentView.bounds
            documentView.addSubview(overlayView)
        } else if overlayView.frame.size != documentView.bounds.size {
            overlayView.frame = documentView.bounds
        }
    }
}

final class PreviewLikePDFView: PDFView {
    private let minimumZoomRatio: CGFloat = 0.1
    private var pinchAnchorPage: PDFPage?
    private var pinchAnchorPointOnPage: CGPoint?
    private var isAdjustingScrollBounds = false

    override func layout() {
        super.layout()
        refreshZoomBounds()
        enforceCropBoxScrollBounds()
    }

    override func magnify(with event: NSEvent) {
        refreshZoomBounds()

        if autoScales {
            autoScales = false
            scaleFactor = scaleFactorForSizeToFit
        }

        super.magnify(with: event)
        clampScaleFactor()
        enforceCropBoxScrollBounds()
    }

    override func smartMagnify(with event: NSEvent) {
        refreshZoomBounds()
        super.smartMagnify(with: event)
        clampScaleFactor()
        enforceCropBoxScrollBounds()
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        enforceCropBoxScrollBounds()
    }

    func refreshZoomBounds() {
        guard document != nil else {
            return
        }

        let fitScale = scaleFactorForSizeToFit
        guard fitScale.isFinite, fitScale > 0 else {
            return
        }

        minScaleFactor = fitScale * minimumZoomRatio
        maxScaleFactor = max(fitScale * 8, fitScale + 4)

        if autoScales {
            scaleFactor = fitScale
            enforceCropBoxScrollBounds()
            return
        }

        clampScaleFactor()
        enforceCropBoxScrollBounds()
    }

    func handleMagnifyEvent(_ event: NSEvent, in sourceView: NSView) {
        guard document != nil else {
            return
        }

        refreshZoomBounds()

        let locationInSourceView = sourceView.convert(event.locationInWindow, from: nil)
        let locationInView = convert(locationInSourceView, from: sourceView)

        switch event.phase {
        case .began:
            if autoScales {
                autoScales = false
                scaleFactor = scaleFactorForSizeToFit
            }

            if let page = page(for: locationInView, nearest: true) {
                pinchAnchorPage = page
                pinchAnchorPointOnPage = convert(locationInView, to: page)
            } else {
                pinchAnchorPage = nil
                pinchAnchorPointOnPage = nil
            }

            fallthrough

        case .changed:
            let targetScale = min(
                max(scaleFactor * (1 + event.magnification), minScaleFactor),
                maxScaleFactor
            )

            scaleFactor = targetScale
            alignPinchAnchor(to: locationInView)
            enforceCropBoxScrollBounds()

        case .ended, .cancelled:
            pinchAnchorPage = nil
            pinchAnchorPointOnPage = nil
            enforceCropBoxScrollBounds()

        default:
            break
        }
    }

    private func clampScaleFactor() {
        guard scaleFactor.isFinite else {
            return
        }

        scaleFactor = min(max(scaleFactor, minScaleFactor), maxScaleFactor)
    }

    private func alignPinchAnchor(to locationInView: CGPoint) {
        guard
            let pinchAnchorPage,
            let pinchAnchorPointOnPage,
            let documentView,
            let clipView = documentView.enclosingScrollView?.contentView
        else {
            return
        }

        let anchorInView = convert(pinchAnchorPointOnPage, from: pinchAnchorPage)
        let anchorInDocument = documentView.convert(anchorInView, from: self)
        let targetInDocument = documentView.convert(locationInView, from: self)
        var nextOrigin = clipView.bounds.origin

        nextOrigin.x += anchorInDocument.x - targetInDocument.x
        nextOrigin.y += anchorInDocument.y - targetInDocument.y

        let constrainedBounds = clipView.constrainBoundsRect(
            NSRect(origin: nextOrigin, size: clipView.bounds.size)
        )

        clipView.scroll(to: constrainedBounds.origin)
        documentView.enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    private func enforceCropBoxScrollBounds() {
        guard
            !isAdjustingScrollBounds,
            let document,
            let documentView,
            let clipView = documentView.enclosingScrollView?.contentView,
            let currentPage
        else {
            return
        }

        let verticalContentBounds = document.pageContentBounds(
            for: displayBox,
            in: self,
            documentView: documentView
        )
        let horizontalContentBounds = currentPage.contentBounds(
            for: displayBox,
            in: self,
            documentView: documentView
        )

        guard !verticalContentBounds.isNull, !horizontalContentBounds.isNull else {
            return
        }

        let clipBounds = clipView.bounds
        let nextOrigin = CGPoint(
            x: constrainedOrigin(
                current: clipBounds.origin.x,
                visibleLength: clipBounds.width,
                contentMin: horizontalContentBounds.minX,
                contentMax: horizontalContentBounds.maxX
            ),
            y: constrainedOrigin(
                current: clipBounds.origin.y,
                visibleLength: clipBounds.height,
                contentMin: verticalContentBounds.minY,
                contentMax: verticalContentBounds.maxY
            )
        )

        guard nextOrigin != clipBounds.origin else {
            return
        }

        isAdjustingScrollBounds = true
        clipView.scroll(to: nextOrigin)
        documentView.enclosingScrollView?.reflectScrolledClipView(clipView)
        isAdjustingScrollBounds = false
    }

    private func constrainedOrigin(
        current: CGFloat,
        visibleLength: CGFloat,
        contentMin: CGFloat,
        contentMax: CGFloat
    ) -> CGFloat {
        let contentLength = contentMax - contentMin

        if contentLength <= visibleLength {
            return contentMin - ((visibleLength - contentLength) * 0.5)
        }

        let lowerBound = contentMin
        let upperBound = contentMax - visibleLength
        return min(max(current, lowerBound), upperBound)
    }
}

@MainActor
private extension PDFPage {
    func contentBounds(for displayBox: PDFDisplayBox, in pdfView: PDFView, documentView: NSView) -> CGRect {
        let boundsInPDFView = pdfView.convert(bounds(for: displayBox), from: self)
        return documentView.convert(boundsInPDFView, from: pdfView).standardized
    }
}

@MainActor
private extension PDFDocument {
    func pageContentBounds(for displayBox: PDFDisplayBox, in pdfView: PDFView, documentView: NSView) -> CGRect {
        var aggregateBounds = CGRect.null

        for pageIndex in 0..<pageCount {
            guard let page = page(at: pageIndex) else {
                continue
            }

            aggregateBounds = aggregateBounds.union(
                page.contentBounds(for: displayBox, in: pdfView, documentView: documentView)
            )
        }

        return aggregateBounds.standardized
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

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleKeyDownEvent(event) {
            return
        }

        super.keyDown(with: event)
    }

    @discardableResult
    func handleKeyDownEvent(_ event: NSEvent) -> Bool {
        if event.keyCode == 49 {
            isSpaceHeld = true
            return true
        }

        if event.keyCode == 53 {
            selectionRectInPage = nil
            onClearSelection?()
            onSelectionChange?(nil)
            needsDisplay = true
            return true
        }

        guard let selectionViewRect = currentSelectionFrame else {
            return handleNavigationKey(event)
        }

        guard let pageFrame = currentPageFrame else {
            return false
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
            return false
        }

        rect = clamp(selectionRect: rect.standardized, to: pageFrame)
        selectionRectInPage = convertSelectionToPage(rect)
        onSelectionChange?(selectionRectInPage)
        needsDisplay = true
        return true
    }

    override func keyUp(with event: NSEvent) {
        if handleKeyUpEvent(event) {
            return
        }

        super.keyUp(with: event)
    }

    @discardableResult
    func handleKeyUpEvent(_ event: NSEvent) -> Bool {
        if event.keyCode == 49 {
            isSpaceHeld = false
            return true
        }

        return false
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

    private func handleNavigationKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123:
            onPageStep?(-1)
            return true
        case 124:
            onPageStep?(1)
            return true
        default:
            return false
        }
    }

    private var currentPageFrame: CGRect? {
        guard
            let pdfView,
            let page = pdfView.currentPage,
            let documentView = pdfView.documentView
        else {
            return nil
        }

        let frame = convertPageRect(page.bounds(for: pdfView.displayBox), on: page, via: documentView)
        return frame.isNull ? nil : frame
    }

    private var currentSelectionFrame: CGRect? {
        guard
            let pdfView,
            let page = pdfView.currentPage,
            let selectionRectInPage,
            let documentView = pdfView.documentView
        else {
            return nil
        }

        let frame = convertPageRect(selectionRectInPage, on: page, via: documentView)
        return frame.isNull ? nil : frame
    }

    private func convertSelectionToPage(_ rect: CGRect) -> CGRect? {
        guard
            let pdfView,
            let page = pdfView.currentPage,
            let documentView = pdfView.documentView
        else {
            return nil
        }

        let inDocumentView = documentView.convert(rect, from: self)
        let inPDFView = pdfView.convert(inDocumentView, from: documentView)
        let inPage = pdfView.convert(inPDFView, to: page).standardized
        let pageBounds = page.bounds(for: pdfView.displayBox)
        let clipped = inPage.intersection(pageBounds)
        guard clipped.width > 1, clipped.height > 1 else {
            return nil
        }
        return clipped
    }

    private func convertPageRect(_ rect: CGRect, on page: PDFPage, via documentView: NSView) -> CGRect {
        guard let pdfView else {
            return .null
        }

        let inPDFView = pdfView.convert(rect, from: page)
        let inDocumentView = documentView.convert(inPDFView, from: pdfView)
        return convert(inDocumentView, from: documentView).standardized
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
