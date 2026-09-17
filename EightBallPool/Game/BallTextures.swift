import UIKit

/// Ball colours and the equirectangular "sphere map" textures wrapped onto the 3-D balls.
enum BallTextures {
    static func baseColor(_ number: Int) -> UIColor {
        switch number {
        case 0: return .white
        case 8: return UIColor(white: 0.08, alpha: 1)
        default:
            switch (number - 1) % 8 {
            case 0: return UIColor(red: 0.98, green: 0.80, blue: 0.10, alpha: 1)
            case 1: return UIColor(red: 0.12, green: 0.36, blue: 0.86, alpha: 1)
            case 2: return UIColor(red: 0.86, green: 0.16, blue: 0.16, alpha: 1)
            case 3: return UIColor(red: 0.45, green: 0.20, blue: 0.66, alpha: 1)
            case 4: return UIColor(red: 0.96, green: 0.50, blue: 0.10, alpha: 1)
            case 5: return UIColor(red: 0.10, green: 0.56, blue: 0.30, alpha: 1)
            default: return UIColor(red: 0.55, green: 0.12, blue: 0.16, alpha: 1)
            }
        }
    }

    private static var sphereMapCache: [Int: UIImage] = [:]

    /// Equirectangular map (longitude across, latitude down, matching SceneKit's sphere UVs). The stripe
    /// is a band around the equator; the number circles sit on the equator at ±90° so the texture seam
    /// (±180°) falls in plain colour.
    static func sphereMap(number: Int) -> UIImage {
        if let cached = sphereMapCache[number] { return cached }
        let width = 1024, height = 512
        let base = baseColor(number)
        let isStripe = number >= 9

        var baseRGB = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0), a: CGFloat(0))
        base.getRed(&baseRGB.r, green: &baseRGB.g, blue: &baseRGB.b, alpha: &baseRGB.a)

        let stripeHalfWidth: CGFloat = 0.62      // radians of latitude
        let circleRadius: CGFloat = 0.44         // angular radius of the number circle
        let softness: CGFloat = 0.006            // antialiasing width in radians

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let lat = (0.5 - (CGFloat(y) + 0.5) / CGFloat(height)) * .pi
            let cosLat = cos(lat)
            for x in 0..<width {
                let lon = ((CGFloat(x) + 0.5) / CGFloat(width) - 0.5) * 2 * .pi
                var colorMix: CGFloat = isStripe ? smooth(stripeHalfWidth - abs(lat), softness) : 1
                if number > 0 {
                    // Angular distance to the nearest number-circle centre (lat 0, lon ±90°).
                    let d1 = acos(min(1, max(-1, cosLat * cos(lon - .pi / 2))))
                    let d2 = acos(min(1, max(-1, cosLat * cos(lon + .pi / 2))))
                    let inCircle = smooth(circleRadius - min(d1, d2), softness)
                    colorMix *= 1 - inCircle
                }
                let i = (y * width + x) * 4
                pixels[i] = UInt8(clamping: Int((baseRGB.r * colorMix + (1 - colorMix)) * 255))
                pixels[i + 1] = UInt8(clamping: Int((baseRGB.g * colorMix + (1 - colorMix)) * 255))
                pixels[i + 2] = UInt8(clamping: Int((baseRGB.b * colorMix + (1 - colorMix)) * 255))
                pixels[i + 3] = 255
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let baseImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                      bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo,
                                      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            return UIImage()
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { ctx in
            UIImage(cgImage: baseImage).draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            guard number > 0 else { return }
            // Near the equator the equirectangular projection is nearly conformal, so the number can be
            // drawn flat inside the circle. Circle radius in pixels along the equator:
            let pixelRadius = circleRadius / (2 * .pi) * CGFloat(width)
            let fontSize = pixelRadius * (number >= 10 ? 1.15 : 1.45)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .heavy),
                .foregroundColor: UIColor(white: 0.08, alpha: 1),
                .paragraphStyle: paragraph,
            ]
            let text = NSAttributedString(string: "\(number)", attributes: attributes)
            let textSize = text.size()
            for u in [0.25, 0.75] {
                let cx = CGFloat(u) * CGFloat(width)
                text.draw(in: CGRect(x: cx - pixelRadius, y: CGFloat(height) / 2 - textSize.height / 2,
                                     width: pixelRadius * 2, height: textSize.height))
            }
        }
        sphereMapCache[number] = image
        return image
    }

    /// 0 → 1 across `[-softness, softness]`.
    private static func smooth(_ value: CGFloat, _ softness: CGFloat) -> CGFloat {
        min(max((value + softness) / (2 * softness), 0), 1)
    }
}
