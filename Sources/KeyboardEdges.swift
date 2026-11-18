// Adapted from TheseusTabBar.edgeImages at pinned upstream revision.
// Apache-2.0; see Vendor/Theseus/LICENSE and NOTICE.
// Change: rectangular distance field; original shade/glow profiles retained.
import UIKit

enum KeyboardEdges {
    static let darkEdgeGlow = TheseusTabBar.darkEdgeGlow
    static let lightEdgeGlow = TheseusTabBar.lightEdgeGlow
    static func images(size: CGSize, scale: CGFloat, dark isDark: Bool) -> (shade: CGImage?, glow: CGImage?) {
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return (nil, nil) }
        var shade = [UInt8](repeating: 0, count: width * height * 4)
        var glow = [UInt8](repeating: 0, count: width * height * 4)
        let glowProfile = isDark ? darkEdgeGlow : lightEdgeGlow
        func profile(_ values: [CGFloat], at depth: CGFloat) -> CGFloat {
            let position = depth - 0.5
            guard position < CGFloat(values.count - 1) else { return 0 }
            if position <= 0 { return values[0] }
            let index = Int(position)
            let fraction = position - CGFloat(index)
            return values[index] + (values[index + 1] - values[index]) * fraction
        }
        for y in 0..<height {
            for x in 0..<width {
                let px = CGFloat(x) + 0.5, py = CGFloat(y) + 0.5
                let horizontalDepth = min(px, CGFloat(width) - px)
                let verticalDepth = min(py, CGFloat(height) - py)
                let normalX: CGFloat = horizontalDepth < verticalDepth ? 1 : 0
                let normalY: CGFloat = horizontalDepth < verticalDepth ? 0 : (py < CGFloat(height) / 2 ? -1 : 1)
                let distance = -min(horizontalDepth, verticalDepth)
                let side = pow(normalX * normalX, 3)
                let vertical = pow(normalY * normalY, 0.8)
                var shadeAlpha: CGFloat = 0
                var glowLevel: CGFloat = 0
                if distance >= 0 {
                    if distance < 1 {
                        shadeAlpha = isDark ? 0.70 * side : 0.12 + 0.23 * side
                    } else if distance < 2 {
                        shadeAlpha = isDark ? 0.34 * side : 0.06 + 0.11 * side
                    }
                } else {
                    let depth = -distance
                    glowLevel = profile(glowProfile, at: depth) * vertical
                    if normalY < 0 {
                        shadeAlpha = 0.016 * exp(-pow((depth - 33) / 18, 2)) * normalY * normalY
                    }
                    shadeAlpha += 0.021 * exp(-pow(depth / 35, 2)) * normalX * normalX
                }
                let offset = (y * width + x) * 4
                let shadeByte = UInt8(min(max(shadeAlpha, 0), 1) * 255)
                shade[offset + 3] = shadeByte
                let glowByte = UInt8(min(max(glowLevel, 0), 255))
                glow[offset] = glowByte
                glow[offset + 1] = glowByte
                glow[offset + 2] = glowByte
                glow[offset + 3] = glowByte
            }
        }
        func image(_ bytes: inout [UInt8]) -> CGImage? {
            bytes.withUnsafeMutableBytes { buffer -> CGImage? in
                CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                          space: space, bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)?.makeImage()
            }
        }
        return (image(&shade), image(&glow))
    }

}
