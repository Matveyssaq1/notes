import PencilKit

func eraserSweep(points: [CGPoint], width: CGFloat) -> CGPath {
    guard let start = points.first else { return CGMutablePath() }
    if points.allSatisfy({ $0 == start }) {
        let radius = width / 2
        return CGPath(ellipseIn: CGRect(x: start.x - radius, y: start.y - radius, width: width, height: width), transform: nil)
    }
    let path = CGMutablePath()
    path.addLines(between: points)
    return path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1)
}

extension PKStroke {
    func isHit(by sweep: CGPath, bounds: CGRect) -> Bool {
        guard bounds.intersects(renderBounds) else { return false }
        var inverse = transform.inverted()
        guard let localSweep = sweep.copy(using: &inverse) else { return false }
        let area = mask.map { mask in
            #if canImport(UIKit)
            let evenOdd = mask.usesEvenOddFillRule
            #else
            let evenOdd = mask.windingRule == .evenOdd
            #endif
            let visible = evenOdd ? mask.cgPath.normalized(using: .evenOdd) : mask.cgPath
            return localSweep.intersection(visible, using: .winding)
        } ?? localSweep
        guard !area.isEmpty else { return false }
        let areaBounds = area.boundingBoxOfPath
        let scale = max(1, hypot(transform.a, transform.b), hypot(transform.c, transform.d))
        let samples = path.interpolatedPoints(by: .distance(2 / scale))
        return samples.contains(where: touches) || path.last.map(touches) == true

        func touches(_ sample: PKStrokePoint) -> Bool {
            let point = sample.location
            let footprint = CGRect(x: point.x - sample.size.width / 2, y: point.y - sample.size.height / 2,
                                   width: sample.size.width, height: sample.size.height)
            return areaBounds.intersects(footprint)
                && area.intersects(CGPath(ellipseIn: footprint, transform: nil), using: .winding)
        }
    }
}
