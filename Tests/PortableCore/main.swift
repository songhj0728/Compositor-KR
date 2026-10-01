// Compile with Compositor/Core/*.swift. This harness uses only the Swift standard library.
let locks: [Int: (locked: Bool, parent: Int?)] = [
    1: (true, nil), 2: (false, 1), 3: (false, 2), 4: (false, nil)
]
precondition(LayerLockRules.isLocked(3) { locks[$0] })
precondition(!LayerLockRules.isLocked(4) { locks[$0] })
precondition(LayerLockRules.isLocked(1) { id in (false, id) })
precondition(LayerLockRules.toggledValue([false, true]))
precondition(!LayerLockRules.toggledValue([true, true]))
precondition(BevelGeometry.clampedSize(250, width: 24, height: 24) == 6)
precondition(BevelGeometry.clampedSize(0, width: 24, height: 24) == 0)
precondition(BevelGeometry.clampedSize(2, width: 24, height: 24) == 2)
let square: [Float] = [
    0, 0, 0, 0, 0,
    0, 1, 1, 1, 0,
    0, 1, 1, 1, 0,
    0, 1, 1, 1, 0,
    0, 0, 0, 0, 0
]
let distances = BevelGeometry.edgeDistances(square, width: 5, height: 5)
precondition(distances[12] == 1.5)
precondition(distances[6] == 0.5 && abs(distances[0] - (Float(2).squareRoot() - 0.5)) < 0.00001)
for y in 0..<5 {
    for x in 0..<5 {
        precondition(distances[y * 5 + x] == distances[y * 5 + 4 - x])
        precondition(distances[y * 5 + x] == distances[(4 - y) * 5 + x])
    }
}
print("Portable core tests passed: inherited locks, cycles, toggles, bevel limits and silhouette symmetry")

// Compare against a brute-force Euclidean oracle, including a circular hole.
let side = 41
let disk: [Float] = (0..<(side * side)).map { i in
    let x = i % side - 20, y = i / side - 20
    return x * x + y * y <= 144 ? 0 : 1
}
let circular = BevelGeometry.edgeDistances(disk, width: side, height: side)
for i in disk.indices {
    var nearest = Float.infinity
    for j in disk.indices where disk[j] != disk[i] {
        let dx = i % side - j % side, dy = i / side - j / side
        nearest = min(nearest, Float(dx * dx + dy * dy).squareRoot())
    }
    precondition(abs(circular[i] - (nearest - 0.5)) < 0.00001,
                 "Circular bevel distances must be Euclidean at every angle")
}
print("Circular hole Euclidean oracle passed")

// Interrupted obsolete requests must stop before both complete transforms finish.
var cancellationChecks = 0
do {
    _ = try BevelGeometry.edgeDistances(disk, width: side, height: side, isCancelled: {
        cancellationChecks += 1
        return cancellationChecks == 5
    })
    preconditionFailure("An obsolete distance calculation completed")
} catch BevelGeometry.CalculationError.cancelled {
    precondition(cancellationChecks == 5)
} catch { preconditionFailure("Unexpected cancellation error") }
let narrow = BevelGeometry.edgeDistances([0, 1, 1, 0], width: 1, height: 4)
precondition(narrow == [0.5, 0.5, 0.5, 0.5])
print("Cooperative cancellation and single-column geometry passed")

precondition(BevelGeometry.height(distance: -2, size: 4, profile: .inner) == 0)
precondition(BevelGeometry.height(distance: 2, size: 4, profile: .inner) == 0.5)
precondition(BevelGeometry.height(distance: 8, size: 4, profile: .inner) == 1)
precondition(BevelGeometry.height(distance: -2, size: 4, profile: .outer) == 0.5)
precondition(BevelGeometry.height(distance: 0, size: 4, profile: .emboss) == 0.5)
precondition(BevelGeometry.height(distance: -2, size: 4, profile: .pillow)
    == BevelGeometry.height(distance: 2, size: 4, profile: .pillow))
precondition(BevelGeometry.lighting(slopeX: 0, slopeY: 0, light: SIMD3(0, 0, 1)) == 1)
print("Shared bevel profiles and flat-surface lighting passed")
