import SpriteKit
import UIKit

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

    static func ballTexture(number: Int, diameter: CGFloat) -> SKTexture {
        let d = diameter
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: d, height: d), format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(x: 0, y: 0, width: d, height: d)
            let base = baseColor(number)
            let isStripe = number >= 9

            cg.saveGState()
            UIBezierPath(ovalIn: rect).addClip()

            (isStripe ? UIColor.white : base).setFill()
            cg.fill(rect)

            if isStripe {
                base.setFill()
                cg.fill(CGRect(x: 0, y: d * 0.23, width: d, height: d * 0.54))
            }

            if number > 0 {
                let circleRadius = d * 0.26
                let circleRect = CGRect(x: d / 2 - circleRadius, y: d / 2 - circleRadius,
                                        width: circleRadius * 2, height: circleRadius * 2)
                UIColor.white.setFill()
                UIBezierPath(ovalIn: circleRect).fill()

                let fontSize = number >= 10 ? d * 0.26 : d * 0.32
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .heavy),
                    .foregroundColor: UIColor(white: 0.1, alpha: 1),
                    .paragraphStyle: paragraph,
                ]
                let text = NSAttributedString(string: "\(number)", attributes: attributes)
                let textSize = text.size()
                text.draw(in: CGRect(x: 0, y: d / 2 - textSize.height / 2 - d * 0.005, width: d, height: textSize.height))
            }

            let colorSpace = CGColorSpaceCreateDeviceRGB()

            // Edge shading for a rounded look.
            if let shade = CGGradient(colorsSpace: colorSpace,
                                      colors: [UIColor.clear.cgColor,
                                               UIColor.clear.cgColor,
                                               UIColor(white: 0, alpha: 0.45).cgColor] as CFArray,
                                      locations: [0, 0.62, 1]) {
                let center = CGPoint(x: d * 0.42, y: d * 0.40)
                cg.drawRadialGradient(shade, startCenter: center, startRadius: 0,
                                      endCenter: center, endRadius: d * 0.72, options: [.drawsAfterEndLocation])
            }

            // Specular highlight.
            if let highlight = CGGradient(colorsSpace: colorSpace,
                                          colors: [UIColor(white: 1, alpha: 0.85).cgColor,
                                                   UIColor(white: 1, alpha: 0).cgColor] as CFArray,
                                          locations: [0, 1]) {
                let center = CGPoint(x: d * 0.34, y: d * 0.30)
                cg.drawRadialGradient(highlight, startCenter: center, startRadius: 0,
                                      endCenter: center, endRadius: d * 0.30, options: [])
            }

            cg.restoreGState()
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
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
