import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// GIF → 设备帧编码（160×80 RGB565 大端），与主程序 `OLEDFrameEncoder` 同构。
/// 每帧右下角烤入模式角标（0/1/2 + 强调色），使设备一眼可辨当前工作模式。
enum OLEDUploadEncoder {
    static func frames(fromGIFAt url: URL, mode: Int, maxFrames: Int?) throws -> [Data] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw HelperError.invalidValue("cannot read GIF: \(url.path)")
        }
        let cap = min(maxFrames ?? AhaKeyPacket.oledMaxFrames, AhaKeyPacket.oledMaxFrames)
        let count = min(CGImageSourceGetCount(source), cap)
        guard count > 0 else { throw HelperError.invalidValue("GIF has no frames") }

        var frames: [Data] = []
        frames.reserveCapacity(count)
        for index in 0 ..< count {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(try encodeFrame(image, mode: mode))
        }
        guard !frames.isEmpty else { throw HelperError.invalidValue("no encodable frames") }
        return frames
    }

    private static func encodeFrame(_ image: CGImage, mode: Int) throws -> Data {
        let width = AhaKeyPacket.oledWidth
        let height = AhaKeyPacket.oledHeight
        let bytesPerPixel = 4
        var rgba = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        guard let context = CGContext(
            data: &rgba, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * bytesPerPixel, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw HelperError.invalidValue("cannot create OLED context") }

        context.interpolationQuality = .high
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let scale = min(Double(width) / Double(image.width), Double(height) / Double(image.height))
        let dw = Double(image.width) * scale, dh = Double(image.height) * scale
        context.draw(image, in: CGRect(x: (Double(width) - dw) / 2, y: (Double(height) - dh) / 2, width: dw, height: dh))

        drawModeBadge(in: context, mode: mode, width: width, height: height)

        var data = Data(capacity: width * height * 2)
        for pixel in stride(from: 0, to: rgba.count, by: bytesPerPixel) {
            let r = UInt16(rgba[pixel]), g = UInt16(rgba[pixel + 1]), b = UInt16(rgba[pixel + 2])
            let rgb565 = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
            data.append(UInt8((rgb565 >> 8) & 0xFF))
            data.append(UInt8(rgb565 & 0xFF))
        }
        return data
    }

    // 与主程序 OLEDFrameEncoder 调色板/几何保持一致：蓝0 / 绿1 / 橙2，右下角 24×18。
    private static func accent(_ mode: Int) -> CGColor {
        switch mode {
        case 0: return CGColor(red: 0.20, green: 0.55, blue: 0.96, alpha: 1)
        case 1: return CGColor(red: 0.24, green: 0.76, blue: 0.46, alpha: 1)
        default: return CGColor(red: 0.97, green: 0.55, blue: 0.18, alpha: 1)
        }
    }

    private static func drawModeBadge(in context: CGContext, mode: Int, width: Int, height: Int) {
        let badgeW: CGFloat = 24, badgeH: CGFloat = 18, margin: CGFloat = 3, radius: CGFloat = 3
        let rect = CGRect(x: CGFloat(width) - margin - badgeW, y: margin, width: badgeW, height: badgeH)
        context.saveGState()
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(accent(mode))
        context.fillPath()

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 13, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 1)]
        if let attrString = CFAttributedStringCreate(nil, String(mode) as CFString, attrs as CFDictionary) {
            let line = CTLineCreateWithAttributedString(attrString)
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            context.textPosition = CGPoint(x: rect.midX - bounds.width / 2 - bounds.minX,
                                           y: rect.midY - bounds.height / 2 - bounds.minY)
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }
}
