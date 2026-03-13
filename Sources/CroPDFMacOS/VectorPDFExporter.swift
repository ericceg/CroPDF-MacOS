import CoreGraphics
import Foundation
import PDFKit

enum VectorPDFExporter {
    static func export(page: PDFPage, selectionRect: CGRect, to url: URL) throws {
        let pageBounds = page.bounds(for: .cropBox)
        let clippedSelection = selectionRect.standardized.intersection(pageBounds)

        guard clippedSelection.width > 1, clippedSelection.height > 1 else {
            throw ExportError.invalidSelection
        }

        guard let pageRef = page.pageRef else {
            throw ExportError.missingPageReference
        }

        var mediaBox = CGRect(origin: .zero, size: clippedSelection.size)
        guard
            let consumer = CGDataConsumer(url: url as CFURL),
            let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw ExportError.unableToCreateContext
        }

        context.beginPDFPage([
            kCGPDFContextMediaBox as String: mediaBox,
        ] as CFDictionary)
        context.clip(to: mediaBox)
        context.translateBy(x: -clippedSelection.minX, y: -clippedSelection.minY)
        context.drawPDFPage(pageRef)
        context.endPDFPage()
        context.closePDF()
    }
}

private enum ExportError: LocalizedError {
    case invalidSelection
    case missingPageReference
    case unableToCreateContext

    var errorDescription: String? {
        switch self {
        case .invalidSelection:
            return "Select a larger area before exporting."
        case .missingPageReference:
            return "The current PDF page could not be exported."
        case .unableToCreateContext:
            return "Could not create the destination PDF file."
        }
    }
}
