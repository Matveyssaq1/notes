import CoreGraphics

// Run with swiftc Polya/ShapeGeometry.swift Tests/ShapeGeometryChecks.swift -o /tmp/shape-checks
@main
struct ShapeGeometryChecks {
    static func main() {
        let circle = (0...60).map { index -> CGPoint in
            let angle = CGFloat(index) / 60 * .pi * 2
            let radius = 45 + 2 * sin(angle * 5)
            return CGPoint(x: 62 + radius * cos(angle), y: 54 + radius * sin(angle))
        }
        let correctedCircle = shapeOutline(circle)!
        let circleBounds = pointBounds(correctedCircle)
        precondition(correctedCircle.count == 65 && abs(circleBounds.width - circleBounds.height) < 0.01)
        precondition(shapeOutline(Array(circle.prefix(40))) == nil)
        precondition(shapeOutline(circle + circle.dropFirst()) == nil)

        let ellipse = circle.map { CGPoint(x: $0.x * 1.8, y: $0.y) }
        let correctedEllipse = shapeOutline(ellipse)!
        let ellipseBounds = pointBounds(correctedEllipse)
        precondition(correctedEllipse.count == 65 && ellipseBounds.width > ellipseBounds.height * 1.6)

        let triangle = [CGPoint(x: 8, y: 90), CGPoint(x: 59, y: 4), CGPoint(x: 111, y: 91)]
        precondition(shapeOutline(trail(around: triangle))?.count == 13)
        let rectangle = [CGPoint(x: 57, y: 8), CGPoint(x: 106, y: 13), CGPoint(x: 101, y: 75),
                         CGPoint(x: 5, y: 70), CGPoint(x: 8, y: 4)]
        let correctedRectangle = shapeOutline(trail(around: rectangle))!
        precondition(correctedRectangle.count == 17)
        let a = correctedRectangle[0], b = correctedRectangle[4], c = correctedRectangle[8]
        precondition(abs((b.x - a.x) * (c.x - b.x) + (b.y - a.y) * (c.y - b.y)) < 0.01)

        let line = (0...10).map { CGPoint(x: $0 * 10, y: $0 % 2) }
        precondition(shapeOutline(line)?.allSatisfy { $0.y == 0 } == true)
        let scratch = (0...20).map { CGPoint(x: $0.isMultiple(of: 2) ? 0 : 90, y: $0 * 3) }
        precondition(shapeOutline(scratch) == nil && shapeOutline([.zero]) == nil)
        print("Shape geometry checks passed")
    }

    static func trail(around vertices: [CGPoint]) -> [CGPoint] {
        var points = [vertices[0]]
        for index in vertices.indices {
            let start = vertices[index], end = vertices[(index + 1) % vertices.count]
            for step in 1...12 {
                let offset = CGFloat(step) / 12
                let wobble = sin(offset * .pi * 2) * 1.5
                points.append(CGPoint(x: start.x + (end.x - start.x) * offset + wobble,
                                      y: start.y + (end.y - start.y) * offset - wobble))
            }
        }
        return points
    }
}
