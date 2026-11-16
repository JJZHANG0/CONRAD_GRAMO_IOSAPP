import UIKit

/// RGB bicubic resampling with widened filter for downsampling, matching the model's
/// ConvNext/Pillow preprocessing (a = -0.5). No neural-network normalization here.
enum FoodImagePreprocessor {
    private static func cubic(_ value: Double) -> Double {
        let x = abs(value)
        if x < 1 { return 1 + x*x*(1.5*x - 2.5) }
        if x < 2 { return 2 - 4*x + 2.5*x*x - 0.5*x*x*x }
        return 0
    }
    private static func weights(input: Int, output: Int) -> [[(Int, Double)]] {
        let scale = Double(input)/Double(output), filterScale = max(1,scale)
        return (0..<output).map { destination in
            let center = (Double(destination)+0.5)*scale
            let lower = max(0,Int(center-2*filterScale+0.5))
            let upper = min(input,Int(center+2*filterScale+0.5))
            let values = (lower..<upper).map { ($0,cubic((Double($0)+0.5-center)/filterScale)) }
            let total = values.reduce(0) { $0+$1.1 }
            return values.map { ($0.0,$0.1/total) }
        }
    }
    static func resize(_ source: CGImage, width: Int, height: Int) throws -> CGImage {
        let sw = source.width, sh = source.height
        guard sw > 0, sh > 0, sw*sh <= 50_000_000, width > 0, height > 0, width*height <= 10_000_000 else { throw RecognitionError.invalidImage }
        var pixels = [UInt8](repeating: 0, count: sw*sh*4)
        try pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: sw*4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw RecognitionError.invalidImage }
            context.draw(source, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        }
        let horizontal = weights(input: sw, output: width), vertical = weights(input: sh, output: height)
        var intermediate = [UInt8](repeating: 255, count: width*sh*4)
        // Match the 8-bit intermediate rounding of an RGB PIL image.
        for y in 0..<sh { for x in 0..<width { for channel in 0..<3 {
            let value = horizontal[x].reduce(0.0) { $0 + Double(pixels[(y*sw+$1.0)*4+channel])*$1.1 }
            intermediate[(y*width+x)*4+channel] = UInt8(min(255,max(0,Int(value.rounded()))))
        } } }
        var output = [UInt8](repeating: 255, count: width*height*4)
        for y in 0..<height { for x in 0..<width { for channel in 0..<3 {
            let value = vertical[y].reduce(0.0) { $0 + Double(intermediate[($1.0*width+x)*4+channel])*$1.1 }
            output[(y*width+x)*4+channel] = UInt8(min(255,max(0,Int(value.rounded()))))
        } } }
        guard let provider = CGDataProvider(data: Data(output) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width*4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw RecognitionError.invalidImage }
        return image
    }
}
