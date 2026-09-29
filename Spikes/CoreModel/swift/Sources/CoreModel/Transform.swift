// The only platform difference in the Core: which C library provides cos and sin.
#if canImport(Darwin)
import Darwin
#elseif canImport(ucrt)
import ucrt
#elseif canImport(Glibc)
import Glibc
#endif

/// A 2-D point in document pixels.
public struct Point: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// An affine transform, mapping (x, y) to (a·x + c·y + tx, b·x + d·y + ty) — the same layout as CGAffineTransform,
/// written out so the Core needs no CoreGraphics.
public struct Transform: Equatable, Hashable, Sendable {
    public var a, b, c, d, tx, ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }

    public static let identity = Transform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public static func translation(_ x: Double, _ y: Double) -> Transform {
        Transform(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
    }

    public static func scale(_ sx: Double, _ sy: Double) -> Transform {
        Transform(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0)
    }

    /// Clockwise on screen, where y points down.
    public static func rotation(_ radians: Double) -> Transform {
        let cosine = cos(radians), sine = sin(radians)
        return Transform(a: cosine, b: sine, c: -sine, d: cosine, tx: 0, ty: 0)
    }

    /// This transform, then `next`.
    public func concatenating(_ next: Transform) -> Transform {
        Transform(a: a * next.a + b * next.c, b: a * next.b + b * next.d,
                  c: c * next.a + d * next.c, d: c * next.b + d * next.d,
                  tx: tx * next.a + ty * next.c + next.tx, ty: tx * next.b + ty * next.d + next.ty)
    }

    public func apply(to p: Point) -> Point {
        Point(x: a * p.x + c * p.y + tx, y: b * p.x + d * p.y + ty)
    }

    /// Nil when the transform flattens everything onto a line.
    public var inverted: Transform? {
        let determinant = a * d - b * c
        guard determinant != 0, determinant.isFinite else { return nil }
        return Transform(a: d / determinant, b: -b / determinant, c: -c / determinant, d: a / determinant,
                         tx: (c * ty - d * tx) / determinant, ty: (b * tx - a * ty) / determinant)
    }
}
