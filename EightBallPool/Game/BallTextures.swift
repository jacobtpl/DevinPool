import simd
import SpriteKit
import UIKit

/// Balls are drawn as shaded spheres by `sphereShader`: each ball sprite carries an equirectangular
/// "sphere map" texture and a per-node rotation matrix, and the fragment shader projects the visible
/// hemisphere so numbers and stripes roll with the ball.
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

    // MARK: - Sphere shader

    static let rotationAttributes = ["a_c0", "a_c1", "a_c2"]

    /// Orthographic sphere: the sprite quad is the ball's silhouette; `a_c0..2` are the columns of the
    /// ball's local-to-world rotation, so `transpose(R) * normal` looks up the sphere map.
    static let sphereShader: SKShader = {
        let source = """
        void main() {
            vec2 p = (v_tex_coord - 0.5) * 2.0;
            float r2 = min(dot(p, p), 1.0);
            vec3 n = vec3(p.x, p.y, sqrt(1.0 - r2));
            vec3 l = vec3(dot(a_c0, n), dot(a_c1, n), dot(a_c2, n));
            float lon = atan(l.x, l.z);
            float lat = asin(clamp(l.y, -1.0, 1.0));
            vec2 uv = vec2(lon / 6.2831853 + 0.5, 0.5 + lat / 3.1415927);
            vec3 albedo = texture2D(u_texture, uv).rgb;
            vec3 lightDir = normalize(vec3(-0.35, 0.55, 0.75));
            float diffuse = 0.42 + 0.58 * max(dot(n, lightDir), 0.0);
            float spec = pow(max(dot(reflect(-lightDir, n), vec3(0.0, 0.0, 1.0)), 0.0), 48.0) * 0.55;
            vec3 color = albedo * diffuse + vec3(spec);
            float edge = 1.0 - smoothstep(0.90, 1.0, r2);
            gl_FragColor = vec4(color, 1.0) * edge;
        }
        """
        let shader = SKShader(source: source)
        shader.attributes = rotationAttributes.map { SKAttribute(name: $0, type: .vectorFloat3) }
        return shader
    }()

    static func applyRotation(_ rotation: simd_quatf, to node: SKSpriteNode) {
        let m = simd_float3x3(rotation)
        node.setValue(SKAttributeValue(vectorFloat3: m.columns.0), forAttribute: "a_c0")
        node.setValue(SKAttributeValue(vectorFloat3: m.columns.1), forAttribute: "a_c1")
        node.setValue(SKAttributeValue(vectorFloat3: m.columns.2), forAttribute: "a_c2")
    }

    // MARK: - Sphere maps

    private static var sphereMapCache: [Int: SKTexture] = [:]

    /// Equirectangular map (longitude across, latitude down). The stripe is a band around the equator,
    /// the number circles sit on the equator at ±90° so the texture seam (±180°) falls in plain colour.
    static func sphereMap(number: Int) -> SKTexture {
        if let cached = sphereMapCache[number] { return cached }
        let width = 512, height = 256
        let base = baseColor(number)
        let isStripe = number >= 9

        var baseRGB = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0), a: CGFloat(0))
        base.getRed(&baseRGB.r, green: &baseRGB.g, blue: &baseRGB.b, alpha: &baseRGB.a)

        let stripeHalfWidth: CGFloat = 0.62      // radians of latitude
        let circleRadius: CGFloat = 0.44         // angular radius of the number circle
        let softness: CGFloat = 0.012            // antialiasing width in radians

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
            return SKTexture()
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
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        sphereMapCache[number] = texture
        return texture
    }

    /// 0 → 1 across `[-softness, softness]`.
    private static func smooth(_ value: CGFloat, _ softness: CGFloat) -> CGFloat {
        min(max((value + softness) / (2 * softness), 0), 1)
    }

    static func shadowTexture(diameter: CGFloat) -> SKTexture {
        let d = diameter * 1.5
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: d, height: d), format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace,
                                         colors: [UIColor(white: 0, alpha: 0.55).cgColor,
                                                  UIColor(white: 0, alpha: 0.35).cgColor,
                                                  UIColor(white: 0, alpha: 0).cgColor] as CFArray,
                                         locations: [0, 0.55, 1]) {
                let center = CGPoint(x: d / 2, y: d / 2)
                cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                      endCenter: center, endRadius: d / 2, options: [])
            }
        }
        return SKTexture(image: image)
    }
}
