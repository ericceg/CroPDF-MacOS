# CroPDF Native

Native macOS rebuild of [CroPDF](https://github.com/ericceg/CroPDF): fast PDF figure cropping with native rendering, keyboard-precise selection, and vector-preserving export.

## What changed from the original

- SwiftUI + AppKit shell instead of Tkinter
- PDFKit rendering for a more responsive native page viewer
- Quartz-based PDF export that keeps the cropped result in PDF/vector form
- Glass-forward macOS interface with translucent controls and ambient lighting

## Features

- Open a PDF and browse pages quickly
- Drag a crop rectangle directly on the current page
- Use `Cmd + 0` to open a PDF
- Use `Cmd + S` to crop and save
- Use `Cmd + G` to jump to a page
- Use arrow keys to move the selection
- Use `Shift + Arrow` to resize the selection
- Hold `Space` while using arrows to move or resize in 25-point jumps
- Press `Escape` to clear the selection
- Save the crop as a new PDF without rasterizing it

## Build

```bash
swift build
```

## Run

```bash
swift run CroPDFMacOS
```

Optional launch arguments:

```bash
swift run CroPDFMacOS /path/to/file.pdf --page 12
```

You can also open the package directly in Xcode and run it as a macOS app target.
