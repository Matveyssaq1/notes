import CoreGraphics

func pointBounds(_ points: [CGPoint]) -> CGRect {
    guard let first = points.first else { return .null }
    var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
    for point in points.dropFirst() {
        minX = min(minX, point.x)
        maxX = max(maxX, point.x)
        minY = min(minY, point.y)
        maxY = max(maxY, point.y)
    }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

func shapeOutline(_ points: [CGPoint]) -> [CGPoint]? {
    guard points.count >= 5, let first = points.first, let last = points.last else { return nil }
    let dx = last.x - first.x, dy = last.y - first.y
    let length = hypot(dx, dy)
    if lineCandidate(points, from: first, along: CGPoint(x: dx, y: dy), length: length) {
        return (0...8).map { index in
            let fraction = CGFloat(index) / 8
            return CGPoint(x: first.x + dx * fraction, y: first.y + dy * fraction)
        }
    }

    let bounds = pointBounds(points)
    let shortSide = min(bounds.width, bounds.height)
    guard shortSide >= 24, length < shortSide * 0.28 else { return nil }
    if let polygon = polygonCorners(points, tolerance: shortSide * 0.065) {
        let fractions: [CGFloat] = [0, 0.04, 0.5, 0.96]
        var outline: [CGPoint] = []
        for (start, end) in zip(polygon, Array(polygon.dropFirst()) + [polygon[0]]) {
            for fraction in fractions {
                let x = start.x + (end.x - start.x) * fraction
                let y = start.y + (end.y - start.y) * fraction
                outline.append(CGPoint(x: x, y: y))
            }
        }
        return outline + [polygon[0]]
    }

    let xRadius = bounds.width / 2, yRadius = bounds.height / 2
    let normalized = points.map { CGPoint(x: ($0.x - bounds.midX) / xRadius, y: ($0.y - bounds.midY) / yRadius) }
    guard normalized.filter({ abs(hypot($0.x, $0.y) - 1) > 0.24 }).count * 8 < points.count else { return nil }
    let angles = normalized.map { atan2($0.y, $0.x) }
    let travel = zip(angles, angles.dropFirst()).map { start, end in
        atan2(sin(end - start), cos(end - start))
    }
    let turn = travel.reduce(0, +)
    guard abs(turn) > .pi * 1.7, abs(turn) < .pi * 2.3,
          travel.reduce(0, { $0 + abs($1) }) < .pi * 2.6 else { return nil }
    let circular = max(xRadius, yRadius) / min(xRadius, yRadius) < 1.22
    let radius = (xRadius + yRadius) / 2
    return (0...64).map { index in
        let angle = CGFloat(index) / 64 * .pi * 2
        return CGPoint(x: bounds.midX + (circular ? radius : xRadius) * cos(angle),
                       y: bounds.midY + (circular ? radius : yRadius) * sin(angle))
    }
}

private func polygonCorners(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint]? {
    let first = points[0]
    guard let far = points.indices.max(by: { distance(points[$0], first) < distance(points[$1], first) }),
          let opposite = points.indices.max(by: { distance(points[$0], points[far]) < distance(points[$1], points[far]) }) else { return nil }
    let start = min(far, opposite), end = max(far, opposite)
    guard start < end else { return nil }
    let wrap = Array(points[end...]) + Array(points[...start])
    let corners = simplify(points[start...end], tolerance: tolerance).dropLast()
        + simplify(wrap[...], tolerance: tolerance).dropLast()
    guard corners.count == 3 || corners.count == 4 else { return nil }
    let vertices = Array(corners)
    let edges = vertices.indices.map { index in
        let start = vertices[index], end = vertices[(index + 1) % vertices.count]
        return CGPoint(x: end.x - start.x, y: end.y - start.y)
    }
    let lengths = edges.map { hypot($0.x, $0.y) }
    guard lengths.allSatisfy({ $0 > tolerance * 5 }) else { return nil }
    let angleCosines = edges.indices.map { index in
        let next = (index + 1) % edges.count
        return abs(edges[index].x * edges[next].x + edges[index].y * edges[next].y) / (lengths[index] * lengths[next])
    }
    if vertices.count == 3 { return angleCosines.allSatisfy { $0 < 0.95 } ? vertices : nil }
    guard angleCosines.allSatisfy({ $0 < 0.30 }) else { return nil }

    let axis = edges[0]
    let u = CGPoint(x: axis.x / lengths[0], y: axis.y / lengths[0])
    let projected = vertices.map { CGPoint(x: $0.x * u.x + $0.y * u.y, y: -$0.x * u.y + $0.y * u.x) }
    let bounds = pointBounds(projected)
    return projected.map { point in
        let x = point.x < bounds.midX ? bounds.minX : bounds.maxX
        let y = point.y < bounds.midY ? bounds.minY : bounds.maxY
        return CGPoint(x: x * u.x - y * u.y, y: x * u.y + y * u.x)
    }
}

private func simplify(_ points: ArraySlice<CGPoint>, tolerance: CGFloat) -> [CGPoint] {
    guard let start = points.first, let end = points.last else { return [] }
    let dx = end.x - start.x, dy = end.y - start.y
    let length = max(hypot(dx, dy), 0.001)
    var furthest = points.startIndex
    var deviation = tolerance
    for index in points.indices.dropFirst().dropLast() {
        let point = points[index]
        let offset = abs((point.x - start.x) * dy - (point.y - start.y) * dx) / length
        if offset > deviation {
            deviation = offset
            furthest = index
        }
    }
    guard furthest != points.startIndex else { return [start, end] }
    return simplify(points[...furthest], tolerance: tolerance).dropLast()
        + simplify(points[furthest...], tolerance: tolerance)
}

private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
    hypot(first.x - second.x, first.y - second.y)
}

func lineCandidate(_ points: some Sequence<CGPoint>, from start: CGPoint, along vector: CGPoint, length: CGFloat) -> Bool {
    guard length >= 65 else { return false }
    let tolerance = min(12, length * 0.07)
    var traveled: CGFloat = 0
    var previous = start
    for point in points {
        let dx = point.x - start.x
        let dy = point.y - start.y
        let deviation = abs(dx * vector.y - dy * vector.x) / length
        guard deviation <= tolerance else { return false }
        traveled += hypot(point.x - previous.x, point.y - previous.y)
        previous = point
    }
    return traveled < 1.18 * length
}
