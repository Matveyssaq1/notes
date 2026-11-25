import AppKit
import PencilKit

// Run with swiftc Polya/StrokeEraser.swift Tests/StrokeEraserChecks.swift -o /tmp/stroke-eraser-checks
@main
struct StrokeEraserChecks {
    static func main() {
        let ink = PKInk(.pen, color: .black)
        let path = PKStrokePath(controlPoints: [0.0, 100.0].map { x in
            PKStrokePoint(location: CGPoint(x: x, y: 20), timeOffset: x / 100,
                          size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: .now)
        let stroke = PKStroke(ink: ink, path: path)
        let nearby = CGPoint(x: 52, y: 27)
        precondition(!hit(stroke, [nearby], width: 4))
        precondition(hit(stroke, [nearby], width: 16))
        precondition(hit(stroke, [CGPoint(x: 50, y: 4), CGPoint(x: 50, y: 34)], width: 4))
        precondition(!hit(stroke, [CGPoint(x: 50, y: 4), CGPoint(x: 50, y: 12)], width: 4))

        let translated = PKStroke(ink: ink, path: path, transform: CGAffineTransform(translationX: 100, y: 60))
        precondition(!hit(translated, [nearby], width: 16))
        precondition(hit(translated, [CGPoint(x: 152, y: 87)], width: 16))

        let visible = NSBezierPath(rect: CGRect(x: -10, y: 0, width: 120, height: 40))
        visible.appendRect(CGRect(x: 40, y: 10, width: 20, height: 20))
        visible.windingRule = .evenOdd
        let masked = PKStroke(ink: ink, path: path, mask: visible)
        precondition(!hit(masked, [CGPoint(x: 50, y: 20)], width: 8))
        precondition(hit(masked, [CGPoint(x: 25, y: 20)], width: 8))
        print("Stroke eraser checks passed")
    }

    static func hit(_ stroke: PKStroke, _ points: [CGPoint], width: CGFloat) -> Bool {
        let sweep = eraserSweep(points: points, width: width)
        return stroke.isHit(by: sweep, bounds: sweep.boundingBoxOfPath)
    }
}
