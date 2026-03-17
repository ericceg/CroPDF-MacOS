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

## Package As .app

There is no dedicated `.app` packaging command anymore. The supported packaging output is the DMG.

## Package As .dmg

```bash
make dmg
```

This builds a temporary app bundle, packages it with `create-dmg`, and leaves you with `dist/CroPDF.dmg`. The intermediate `dist/CroPDF.app` is removed automatically.

`Node.js` and `npm` are required for the DMG step because the script downloads `create-dmg` on demand.

## Releases

GitHub releases are created by pushing a tag that matches `v*.*.*`, for example:

```bash
git tag v1.2.4
git push origin v1.2.4
```

That workflow is the only CI path that builds a DMG. It publishes the release and uploads a versioned asset such as `CroPDF-v1.2.4.dmg`.
