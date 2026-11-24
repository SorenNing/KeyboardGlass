import Foundation
import CoreGraphics

// Exercise the same three-point affine mapping used for App-content rendering.
var checked = 0
for scale: CGFloat in [1, 2, 3] {
    for rootOrigin in [CGPoint.zero, CGPoint(x: 17, y: 61), CGPoint(x: -23, y: 91)] {
        for angle: CGFloat in [0, .pi/2, -.pi/2] {
            let expected = CGAffineTransform(translationX: rootOrigin.x, y: rootOrigin.y).rotated(by: angle)
            let origin = CGPoint.zero.applying(expected)
            let x = CGPoint(x: 1, y: 0).applying(expected)
            let y = CGPoint(x: 0, y: 1).applying(expected)
            let map = CGAffineTransform(a: x.x-origin.x, b: x.y-origin.y, c: y.x-origin.x, d: y.y-origin.y, tx: origin.x, ty: origin.y)
            for keyboardPoint in [CGPoint(x: 0, y: 596), CGPoint(x: 215, y: 800), CGPoint(x: 430, y: 932)] {
                let local = keyboardPoint.applying(expected.inverted())
                let result = local.applying(map)
                // Capture context translates by -region.origin and flips to bitmap rows.
                let pixelX = (result.x - 0) * scale
                let pixelY = (932 - result.y) * scale
                precondition(abs(pixelX - keyboardPoint.x * scale) < 0.0001)
                precondition(abs(pixelY - (932-keyboardPoint.y) * scale) < 0.0001)
                checked += 1
            }
        }
    }
}
print("Capture geometry passed: \(checked) point mappings")
