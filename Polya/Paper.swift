import PencilKit
import UIKit.UIGestureRecognizerSubclass
import PDFKit
import SwiftUI
import Vision

enum Paper {
    static let lightPaper = UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1)
    static let size = CGSize(width: 768, height: 1024)
    static let boardSize = CGSize(width: 4096, height: 4096)
    static var bounds: CGRect { CGRect(origin: .zero, size: size) }

    static func paint(_ context: CGContext, dark: Bool, rect: CGRect = bounds, style: PaperStyle = .grid) {
        let background = dark ? UIColor(white: 0.11, alpha: 1) : lightPaper
        let grid = dark ? UIColor(white: 0.26, alpha: 1) : UIColor(white: 0.86, alpha: 1)
        context.setFillColor(background.cgColor)
        context.fill(rect)
        let xs = stride(from: Int(rect.minX / 24) * 24, to: Int(rect.maxX), by: 24)
        let ys = stride(from: Int(rect.minY / 24) * 24, to: Int(rect.maxY), by: 24)
        if style == .dots {
            context.setFillColor(grid.cgColor)
            for x in xs {
                for y in ys { context.fillEllipse(in: CGRect(x: x, y: y, width: 2, height: 2)) }
            }
        } else if style == .music {
            context.setStrokeColor(grid.cgColor)
            context.setLineWidth(0.8)
            for block in stride(from: 96, to: rect.maxY, by: 120) {
                for line in 0..<5 {
                    let y = CGFloat(block) + CGFloat(line) * 12
                    context.move(to: CGPoint(x: rect.minX, y: y))
                    context.addLine(to: CGPoint(x: rect.maxX, y: y))
                }
            }
            context.strokePath()
        } else if style != .plain {
            context.setStrokeColor(grid.cgColor)
            context.setLineWidth(0.6)
            if style == .grid {
                for x in xs {
                    context.move(to: CGPoint(x: CGFloat(x), y: rect.minY))
                    context.addLine(to: CGPoint(x: CGFloat(x), y: rect.maxY))
                }
            }
            for y in ys {
                context.move(to: CGPoint(x: rect.minX, y: CGFloat(y)))
                context.addLine(to: CGPoint(x: rect.maxX, y: CGFloat(y)))
            }
            context.strokePath()
            if style == .cornell {
                let summaryY = size.height - 220
                context.setLineWidth(1.4)
                context.move(to: CGPoint(x: 216, y: rect.minY))
                context.addLine(to: CGPoint(x: 216, y: min(rect.maxY, summaryY)))
                context.move(to: CGPoint(x: rect.minX, y: summaryY))
                context.addLine(to: CGPoint(x: rect.maxX, y: summaryY))
                context.strokePath()
            }
        }
    }

    static func textFits(_ text: String) -> Bool {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: size.width - 96, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.systemFont(ofSize: 20)], context: nil)
        return bounds.height <= size.height - 96
    }

    static func drawText(_ text: String, dark: Bool) {
        (text as NSString).draw(in: CGRect(x: 48, y: 48, width: size.width - 96, height: size.height - 96),
                               withAttributes: [.font: UIFont.systemFont(ofSize: 20),
                                                .foregroundColor: dark ? UIColor.white : UIColor.black])
    }

    static func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            let supported = try request.supportedRecognitionLanguages()
            request.recognitionLanguages = ["ru-RU", "en-US"].filter { supported.contains($0) }
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }

    static func drawPDFPage(_ page: PDFPage, in context: CGContext) {
        let source = page.bounds(for: .cropBox)
        guard source.width > 0, source.height > 0 else { return }
        let scale = min(size.width / source.width, size.height / source.height)
        context.saveGState()
        context.translateBy(x: (size.width - source.width * scale) / 2,
                            y: (size.height + source.height * scale) / 2)
        context.scaleBy(x: scale, y: -scale)
        page.draw(with: .cropBox, to: context)
        context.restoreGState()
    }

    static func pdf(_ drawings: [PKDrawing], dark: Bool, board: Bool = false, style: PaperStyle = .grid, backgrounds: [PDFPage?] = [], texts: [String] = []) -> Data {
        let content = drawings.first?.bounds ?? .null
        let region = board && !content.isEmpty && !content.isNull
            ? content.insetBy(dx: -48, dy: -48).integral : bounds
        let page = CGRect(origin: .zero, size: region.size)
        let appearance = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { pdf in
            appearance.performAsCurrent {
                for (index, drawing) in drawings.enumerated() {
                    pdf.beginPage()
                    let background = backgrounds.indices.contains(index) ? backgrounds[index] : nil
                    paint(pdf.cgContext, dark: dark && background == nil, rect: page, style: background == nil ? style : .plain)
                    if let background { drawPDFPage(background, in: pdf.cgContext) }
                    if texts.indices.contains(index) { drawText(texts[index], dark: dark && background == nil) }
                    if !drawing.strokes.isEmpty {
                        let inkAppearance = background == nil ? appearance : UITraitCollection(userInterfaceStyle: .light)
                        inkAppearance.performAsCurrent {
                            drawing.image(from: region, scale: board ? 1 : 2).draw(in: page)
                        }
                    }
                }
            }
        }
    }
}

enum EraserMode: String, CaseIterable {
    case strokes, pixel

    var title: String { self == .strokes ? "Штрихи" : "Пиксельный" }
    var widths: [CGFloat] {
        if self == .strokes { return [4, 8, 16, 32, 48] }
        let range = PKEraserTool.EraserType.fixedWidthBitmap.validWidthRange
        return [range.lowerBound, 24, 36, 54, range.upperBound]
    }
    var defaultWidth: CGFloat { self == .strokes ? 16 : widths[0] }
}

enum WritingTool: String, CaseIterable {
    case pen, highlighter, eraser, lasso, pencil, monoline, line, ruler

    var icon: String {
        switch self {
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .eraser: "eraser"
        case .lasso: "lasso"
        case .pencil: "pencil"
        case .monoline: "scribble.variable"
        case .line: "line.diagonal"
        case .ruler: "ruler"
        }
    }

    var title: String {
        switch self {
        case .pen: "Перо"
        case .highlighter: "Маркер"
        case .eraser: "Ластик"
        case .lasso: "Выделение"
        case .pencil: "Карандаш"
        case .monoline: "Моноширинное перо"
        case .line: "Отрезок"
        case .ruler: "Линейка"
        }
    }

    static let defaults: [Self] = [.pen, .highlighter, .eraser, .lasso, .ruler, .line]

    var drawsInk: Bool { inkType != nil }

    private var inkType: PKInkingTool.InkType? {
        switch self {
        case .pen, .line: .pen
        case .highlighter: .marker
        case .pencil: .pencil
        case .monoline: .monoline
        case .eraser, .lasso, .ruler: nil
        }
    }

    var inkWidths: [CGFloat] {
        guard let inkType else { return [] }
        let range = inkType.validWidthRange
        let widths: [CGFloat] = switch self {
        case .highlighter: [7.5, 15, 22.5, 30, 45]
        case .pencil: [2.5, 3, 5, 8, 12]
        case .monoline: [0.5, 1, 2, 3, 4]
        default: [1.5, 3, 4.5, 6, 9]
        }
        return Set(widths.map { min(range.upperBound, max(range.lowerBound, $0)) }).sorted()
    }

    func inkColor(_ color: UIColor) -> UIColor {
        self == .highlighter && color == .black ? .systemOrange : color
    }

    func pencilTool(color: UIColor, width: CGFloat, eraserMode: EraserMode) -> PKTool {
        switch self {
        case .eraser: eraserMode == .strokes ? PKEraserTool(.vector) : PKEraserTool(.fixedWidthBitmap, width: width)
        case .lasso: PKLassoTool()
        default: PKInkingTool(inkType ?? .pen, color: inkColor(color), width: width)
        }
    }
}

final class WritingCanvas: PKCanvasView {
    private let history = UndoManager()
    override var undoManager: UndoManager? { history }

    func replaceDrawing(_ next: PKDrawing, undoDrawing: PKDrawing? = nil) {
        registerDrawingUndo(undoDrawing ?? drawing)
        drawing = next
    }

    func registerDrawingUndo(_ previous: PKDrawing) {
        history.registerUndo(withTarget: self) { $0.replaceDrawing(previous) }
    }
}

private final class StrokeEraserGesture: UIGestureRecognizer {
    var width: CGFloat = 16
    var didErase: ((PKDrawing) -> Void)?
    private var original: PKDrawing?
    private var remaining: [PKStroke] = []
    private var previous = CGPoint.zero
    var isErasing: Bool { original != nil }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard original == nil, let canvas = view as? WritingCanvas, let touch = touches.first else { return }
        original = canvas.drawing
        remaining = canvas.drawing.strokes
        previous = touch.preciseLocation(in: canvas)
        state = .began
        erase([previous], on: canvas)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard isErasing, let canvas = view as? WritingCanvas, let touch = touches.first else { return }
        let positions = (event.coalescedTouches(for: touch) ?? [touch]).map { $0.preciseLocation(in: canvas) }
        erase([previous] + positions, on: canvas)
        previous = positions.last ?? previous
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let canvas = view as? WritingCanvas, let original, let touch = touches.first else { return }
        erase([previous, touch.preciseLocation(in: canvas)], on: canvas)
        if remaining.count < original.strokes.count {
            canvas.registerDrawingUndo(original)
            didErase?(canvas.drawing)
        }
        self.original = nil
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }

    override func reset() {
        if let original, let canvas = view as? WritingCanvas { canvas.drawing = original }
        original = nil
        remaining.removeAll()
        super.reset()
    }

    private func erase(_ positions: [CGPoint], on canvas: WritingCanvas) {
        let sweep = eraserSweep(points: positions, width: width)
        let bounds = sweep.boundingBoxOfPath
        let count = remaining.count
        remaining.removeAll { $0.isHit(by: sweep, bounds: bounds) }
        if remaining.count != count { canvas.drawing = PKDrawing(strokes: remaining) }
    }
}

private final class PencilHold: UIGestureRecognizer {
    var tracksShapes = true
    var didLift: (() -> Void)?
    private(set) var shape: PKStroke?
    private(set) var isTouching = false
    private var points: [CGPoint] = []
    private var anchor = CGPoint.zero
    private var original = PKDrawing()
    private var hold: Task<Void, Never>?
    private let preview = UIImageView()

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        clearPreview()
        guard tracksShapes, let canvas = view as? WritingCanvas, let touch = touches.first else {
            state = .failed
            return
        }
        isTouching = true
        original = canvas.drawing
        anchor = touch.preciseLocation(in: canvas)
        points = [anchor]
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard isTouching, let canvas = view as? WritingCanvas, let touch = touches.first else { return }
        let zoom = (canvas.superview?.superview as? UIScrollView)?.zoomScale ?? 1
        let location = touch.preciseLocation(in: canvas)
        for sample in event.coalescedTouches(for: touch) ?? [touch] {
            let point = sample.preciseLocation(in: canvas)
            if let previous = points.last, hypot(point.x - previous.x, point.y - previous.y) * zoom >= 1.5 {
                points.append(point)
            }
        }

        let movement = hypot(location.x - anchor.x, location.y - anchor.y) * zoom
        guard movement >= (shape == nil ? 4 : 12) else { return }
        anchor = location
        clearPreview()
        hold?.cancel()
        hold = Task { @MainActor [weak self, weak canvas] in
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled, let self, let canvas, isTouching else { return }
            showPreview(on: canvas, zoom: zoom)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        isTouching = false
        hold?.cancel()
        state = .ended
        didLift?()
        if let image = preview.image {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, preview.image === image else { return }
                clearPreview()
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        isTouching = false
        hold?.cancel()
        clearPreview()
        state = .cancelled
        didLift?()
    }

    override func reset() {
        isTouching = false
        hold?.cancel()
        points.removeAll(keepingCapacity: true)
        original = PKDrawing()
        super.reset()
    }

    func clearPreview() {
        guard shape != nil else { return }
        shape = nil
        preview.removeFromSuperview()
        preview.image = nil
        view?.layer.mask = nil
    }

    private func showPreview(on canvas: WritingCanvas, zoom: CGFloat) {
        guard let sheet = canvas.superview, let tool = canvas.tool as? PKInkingTool,
              let outline = shapeOutline(points) else { return }
        let ink = PKInk(tool.inkType, color: tool.color)
        let size = CGSize(width: tool.width, height: tool.width)
        let path = PKStrokePath(controlPoints: outline.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) / 120, size: size,
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: .now)
        let stroke = PKStroke(ink: ink, path: path)
        let trailBounds = pointBounds(points)
        let region = trailBounds.union(stroke.renderBounds)
            .insetBy(dx: -tool.width * 3 - 12 / zoom, dy: -tool.width * 3 - 12 / zoom)
            .intersection(canvas.bounds).integral
        guard !region.isEmpty else { return }

        // Replace only the preview area so other ink and the paper beneath it stay visible.
        let drawing = PKDrawing(strokes: original.strokes.filter { $0.renderBounds.intersects(region) } + [stroke])
        let scale = min(canvas.traitCollection.displayScale * zoom, 2048 / max(region.width, region.height))
        canvas.traitCollection.performAsCurrent { preview.image = drawing.image(from: region, scale: scale) }
        preview.frame = canvas.convert(region, to: sheet)
        preview.isUserInteractionEnabled = false
        preview.accessibilityElementsHidden = true
        sheet.addSubview(preview)

        let mask = CAShapeLayer()
        mask.frame = canvas.bounds
        let cutout = UIBezierPath(rect: canvas.bounds)
        cutout.append(UIBezierPath(rect: region))
        mask.path = cutout.cgPath
        mask.fillRule = .evenOdd
        canvas.layer.mask = mask
        shape = stroke
    }
}

class GridView: UIView {
    var text = "" { didSet { if oldValue != text { setNeedsDisplay() } } }
    var style: PaperStyle = .grid { didSet { if oldValue != style { setNeedsDisplay() } } }
    var backgroundPage: PDFPage? { didSet { if oldValue !== backgroundPage { setNeedsDisplay() } } }
    var dark = false { didSet { if oldValue != dark { setNeedsDisplay() } } }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        Paper.paint(context, dark: dark, rect: rect, style: backgroundPage == nil ? style : .plain)
        if let backgroundPage { Paper.drawPDFPage(backgroundPage, in: context) }
        Paper.drawText(text, dark: dark)
    }
}

final class BoardGridView: GridView {
    override class var layerClass: AnyClass { CATiledLayer.self }
}

final class PaperScrollView: UIScrollView, UIScrollViewDelegate {
    let sheet: UIView
    let grid: GridView
    let canvas: WritingCanvas
    private let paperSize: CGSize
    private let board: Bool
    private var previousSize = CGSize.zero

    init(board: Bool) {
        self.board = board
        let size = board ? Paper.boardSize : Paper.size
        paperSize = size
        let frame = CGRect(origin: .zero, size: size)
        sheet = UIView(frame: frame)
        grid = board ? BoardGridView(frame: frame) : GridView(frame: frame)
        canvas = WritingCanvas(frame: frame)
        super.init(frame: .zero)
        backgroundColor = .clear
        delegate = self
        maximumZoomScale = 3
        panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        if !board { panGestureRecognizer.minimumNumberOfTouches = 2 }
        delaysContentTouches = false
        contentInsetAdjustmentBehavior = .never
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = .pencilOnly
        canvas.accessibilityLabel = "Лист для рукописного ввода"
        grid.isUserInteractionEnabled = false
        sheet.clipsToBounds = true
        sheet.addSubview(grid)
        sheet.addSubview(canvas)
        addSubview(sheet)
        contentSize = paperSize
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        if bounds.size != previousSize {
            let fit = min(bounds.width / paperSize.width, bounds.height / paperSize.height)
            let wasFitted = previousSize == .zero || abs(zoomScale - minimumZoomScale) < 0.001
            let initial = previousSize == .zero
            previousSize = bounds.size
            maximumZoomScale = max(3, fit)
            minimumZoomScale = fit
            if board && initial {
                zoomScale = max(fit, 0.6)
                contentOffset = CGPoint(x: max(0, (contentSize.width - bounds.width) / 2),
                                        y: max(0, (contentSize.height - bounds.height) / 2))
            } else if wasFitted || zoomScale < fit { zoomScale = fit }
        }
        centerPaper()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { sheet }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPaper() }

    private func centerPaper() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        let insets = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != insets { contentInset = insets }
    }
}

struct PaperEditor: UIViewRepresentable {
    let drawing: PKDrawing
    var text = ""
    let tool: WritingTool
    let eraserMode: EraserMode
    let dark: Bool
    let style: PaperStyle
    let ink: UIColor
    let width: CGFloat
    let ruler: Bool
    let straighten: Bool
    let scratchErase: Bool
    var board = false
    var backgroundPage: PDFPage?
    let toggleTabs: (() -> Void)?
    let didChange: (PKDrawing) -> Void
    let registerCanvas: (WritingCanvas) -> Void

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        var didChange: (PKDrawing) -> Void
        var toggleTabs: (() -> Void)?
        fileprivate let pencilHold = PencilHold(target: nil, action: nil)
        fileprivate let strokeEraser = StrokeEraserGesture(target: nil, action: nil)
        var selectedTool: WritingTool?
        var eraserMode: EraserMode?
        var ink: UIColor?
        var width: CGFloat?
        var straighten = false
        var scratchErase = true
        var ruler = false
        private var pendingStroke: (count: Int, tool: WritingTool)?
        private var isReplacing = false
        private var renderingShape = false

        init(didChange: @escaping (PKDrawing) -> Void) { self.didChange = didChange }

        @objc func paperTapped() { toggleTabs?() }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            pendingStroke = nil
            guard let selectedTool, selectedTool.drawsInk else { return }
            pendingStroke = (canvasView.drawing.strokes.count, selectedTool)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isReplacing, !strokeEraser.isErasing else { return }
            let strokes = canvasView.drawing.strokes
            if let pendingStroke, strokes.count > pendingStroke.count {
                guard !pencilHold.isTouching else { return }
                self.pendingStroke = nil
                if let canvas = canvasView as? WritingCanvas,
                   strokes.count == pendingStroke.count + 1, let last = strokes.last {
                    let older = strokes.dropLast()
                    let tool = pendingStroke.tool
                    if let shape = pencilHold.shape {
                        renderingShape = true
                        replace(canvas, with: Array(older) + [shape])
                    } else if scratchErase && !ruler && tool != .line && tool != .highlighter,
                       let remaining = last.erasingStrokes(in: older) {
                        replace(canvas, with: remaining, undo: PKDrawing(strokes: Array(older)))
                    } else if tool == .line || (straighten && tool != .highlighter),
                              let straight = last.straightened(forced: tool == .line) {
                        replace(canvas, with: Array(older) + [straight])
                    }
                }
            }
            didChange(canvasView.drawing)
        }

        func canvasViewDidFinishRendering(_ canvasView: PKCanvasView) {
            if renderingShape {
                renderingShape = false
                pencilHold.clearPreview()
            }
        }

        fileprivate func finishHeldShape(on canvas: WritingCanvas) {
            if let pendingStroke, canvas.drawing.strokes.count > pendingStroke.count {
                canvasViewDrawingDidChange(canvas)
            }
        }

        private func replace(_ canvas: WritingCanvas, with strokes: [PKStroke], undo: PKDrawing? = nil) {
            isReplacing = true
            defer { isReplacing = false }
            canvas.replaceDrawing(PKDrawing(strokes: strokes), undoDrawing: undo)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(didChange: didChange) }

    func makeUIView(context: Context) -> PaperScrollView {
        let view = PaperScrollView(board: board)
        view.canvas.drawing = drawing
        view.canvas.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.paperTapped))
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        tap.cancelsTouchesInView = false
        view.sheet.addGestureRecognizer(tap)
        view.canvas.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Показать или скрыть вкладки") { [weak coordinator = context.coordinator] _ in
            guard let toggleTabs = coordinator?.toggleTabs else { return false }
            toggleTabs()
            return true
        }]
        let strokeEraser = context.coordinator.strokeEraser
        strokeEraser.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        strokeEraser.isEnabled = false
        strokeEraser.didErase = { [weak coordinator = context.coordinator] in coordinator?.didChange($0) }
        view.canvas.addGestureRecognizer(strokeEraser)
        let hold = context.coordinator.pencilHold
        hold.delegate = context.coordinator
        hold.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        hold.cancelsTouchesInView = false
        view.canvas.addGestureRecognizer(hold)
        hold.didLift = { [weak coordinator = context.coordinator, weak canvas = view.canvas] in
            DispatchQueue.main.async {
                if let canvas { coordinator?.finishHeldShape(on: canvas) }
            }
        }
        DispatchQueue.main.async { [weak canvas = view.canvas] in
            if let canvas { registerCanvas(canvas) }
        }
        return view
    }

    func updateUIView(_ view: PaperScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.didChange = didChange
        coordinator.toggleTabs = toggleTabs
        coordinator.straighten = straighten
        coordinator.scratchErase = scratchErase
        coordinator.ruler = ruler
        view.canvas.isRulerActive = ruler
        let erasesStrokes = tool == .eraser && eraserMode == .strokes
        if coordinator.strokeEraser.isEnabled != erasesStrokes {
            coordinator.strokeEraser.isEnabled = erasesStrokes
        }
        coordinator.strokeEraser.width = width
        coordinator.pencilHold.tracksShapes = !ruler && tool.drawsInk && tool != .line && tool != .highlighter
        if coordinator.selectedTool != tool || coordinator.ink != ink || coordinator.width != width || coordinator.eraserMode != eraserMode {
            view.canvas.tool = tool.pencilTool(color: ink, width: width, eraserMode: eraserMode)
            coordinator.selectedTool = tool
            coordinator.ink = ink
            coordinator.width = width
            coordinator.eraserMode = eraserMode
        }
        if view.canvas.drawingGestureRecognizer.isEnabled == erasesStrokes {
            view.canvas.drawingGestureRecognizer.isEnabled = !erasesStrokes
        }
        let darkInk = dark && backgroundPage == nil
        view.overrideUserInterfaceStyle = darkInk ? .dark : .light
        view.grid.dark = darkInk
        view.grid.style = style
        view.grid.text = text
        view.grid.backgroundPage = backgroundPage
    }
}


extension PKStroke {
    func erasingStrokes(in older: ArraySlice<PKStroke>) -> [PKStroke]? {
        guard !older.isEmpty else { return nil }
        let trail = pageSamples()
        guard scratchCandidate(trail) else { return nil }

        let region = renderBounds.insetBy(dx: -6, dy: -6)
        let remaining = older.filter { stroke in
            guard stroke.mask == nil, region.intersects(stroke.renderBounds) else { return true }
            return !scratchCovers(stroke.pageSamples(), trail: trail, region: region)
        }
        return remaining.count < older.count ? remaining : nil
    }

    private func pageSamples() -> [CGPoint] {
        let points = path.interpolatedPoints(by: .distance(4))
        let samples = points.map { $0.location.applying(transform) }
        guard let last = path.last?.location.applying(transform) else { return samples }
        return samples.last == last ? samples : samples + [last]
    }

    func straightened(forced: Bool) -> PKStroke? {
        guard mask == nil, let first = path.first, let last = path.last else { return nil }
        let vector = CGPoint(x: last.location.x - first.location.x, y: last.location.y - first.location.y)
        let length = hypot(vector.x, vector.y)
        guard length >= (forced ? 6 : 65) else { return nil }
        if !forced && !lineCandidate(path.lazy.map(\.location), from: first.location, along: vector, length: length) {
            return nil
        }

        let middle = path[path.count / 2]
        let samples = (0...8).map { index in
            let fraction = CGFloat(index) / 8
            let location = CGPoint(x: first.location.x + vector.x * fraction,
                                   y: first.location.y + vector.y * fraction)
            return PKStrokePoint(location: location, timeOffset: last.timeOffset * Double(fraction),
                                 size: middle.size, opacity: middle.opacity, force: middle.force,
                                 azimuth: middle.azimuth, altitude: middle.altitude)
        }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: samples, creationDate: path.creationDate),
                        transform: transform, mask: nil, randomSeed: randomSeed)
    }
}


func scratchCandidate(_ points: [CGPoint]) -> Bool {
    guard let first = points.first, points.count >= 8,
          let lowX = points.map(\.x).min(), let highX = points.map(\.x).max(),
          let lowY = points.map(\.y).min(), let highY = points.map(\.y).max() else { return false }
    let horizontal = highX - lowX >= highY - lowY
    let span = max(highX - lowX, highY - lowY)
    guard span >= 22 else { return false }
    let threshold = span * 0.46
    var extreme = horizontal ? first.x : first.y
    var direction: CGFloat = 0
    var turns = 0
    for point in points.dropFirst() {
        let coordinate = horizontal ? point.x : point.y
        let delta = coordinate - extreme
        if direction == 0 {
            if abs(delta) < threshold { continue }
            direction = delta > 0 ? 1 : -1
            extreme = coordinate
        } else if delta * direction >= 0 {
            extreme = coordinate
        } else if abs(delta) >= threshold {
            turns += 1
            direction = -direction
            extreme = coordinate
        }
    }
    return turns >= 2
}

func scratchCovers(_ target: [CGPoint], trail: [CGPoint], region: CGRect) -> Bool {
    guard !target.isEmpty else { return false }
    let inside = target.filter { region.contains($0) }
    guard inside.count * 5 >= target.count * 3 else { return false }
    var hits = 0
    for point in inside {
        if trail.contains(where: { sample in
            let dx = point.x - sample.x
            let dy = point.y - sample.y
            return dx * dx + dy * dy <= 64
        }) {
            hits += 1
            if hits >= min(2, target.count) { return true }
        }
    }
    return false
}
