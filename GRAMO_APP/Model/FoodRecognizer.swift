import Foundation
import CoreML
import UIKit
import CoreVideo

struct RecognitionResult {
    var candidates: [FoodCandidate]
    var requiresConfirmation = true // Own-camera rejection calibration has not yet been collected.
    var note: String
    var elapsedMilliseconds: Double = 0
}
struct ModelLabel: Decodable { var id: String; var rawLabel: String; var name: String }
enum RecognitionError: LocalizedError {
    case missingModel, invalidImage, incompatibleModel
    var errorDescription: String? {
        switch self {
        case .missingModel: return "未安装评估模型。可以先手动输入菜名并记录。"
        case .invalidImage: return "图片或选区无效，请重新拍摄。"
        case .incompatibleModel: return "模型版本、输出或标签不匹配，已停止识别。"
        }
    }
}

/// Serial actor keeps load/compile/inference off the main actor. No network calls.
actor FoodRecognizer {
    static let shared = FoodRecognizer()
    static let revision = "1ce5801e5905f15de1c4e55c89ef2a8cd6d6a97c"
    private var model: MLModel?
    private var labels: [ModelLabel] = []
    private func load() throws -> MLModel {
        if let model { return model }
        var url = Bundle.main.url(forResource: "ChineseFood", withExtension: "mlmodelc")
        #if DEBUG
        if url == nil {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Models")
            let package = directory.appendingPathComponent("ChineseFood.mlpackage")
            if FileManager.default.fileExists(atPath: package.path) {
                let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("ChineseFood-" + Self.revision + ".mlmodelc")
                if !FileManager.default.fileExists(atPath: cache.path) {
                    let compiled = try MLModel.compileModel(at: package)
                    try FileManager.default.copyItem(at: compiled, to: cache)
                }
                url = cache
            }
        }
        #endif
        guard let url else { throw RecognitionError.missingModel }
        let configuration = MLModelConfiguration()
        #if targetEnvironment(simulator)
        configuration.computeUnits = .cpuOnly
        #else
        configuration.computeUnits = .all
        #endif
        let loaded = try MLModel(contentsOf: url, configuration: configuration)
        let metadata = loaded.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
        guard metadata?["model_revision"] == Self.revision,
              let labelJSON = metadata?["labels_json"], let data = labelJSON.data(using: .utf8),
              let labels = try? JSONDecoder().decode([ModelLabel].self, from: data), labels.count == 114,
              labels.enumerated().allSatisfy({ $0.element.id == String($0.offset) }) else { throw RecognitionError.incompatibleModel }
        self.labels = labels; model = loaded
        return loaded
    }
    func warmUp() throws { _ = try load() }
    func recognizeFrame(_ frame: SpoonCameraFrame) throws -> [FoodCandidate] {
        guard let image = UIImage(data: frame.data) else { throw RecognitionError.invalidImage }
        return try recognize(image, source: "勺载相机自动识别", imageID: frame.id.uuidString).candidates
    }
    func preparePhoto(_ image: UIImage, directory: URL) throws -> (image: UIImage, id: String) {
        let upright = Self.upright(image)
        guard let data = upright.jpegData(compressionQuality: 0.9) else { throw RecognitionError.invalidImage }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID().uuidString + ".jpg"
        try data.write(to: directory.appendingPathComponent(id), options: [.atomic, .completeFileProtection])
        return (upright, id)
    }
    func recognize(_ image: UIImage, region: CGRect? = nil, source: String, imageID: String?, diagnosticDirectory: URL? = nil) throws -> RecognitionResult {
        let started = CFAbsoluteTimeGetCurrent()
        let model = try load()
        let pixel = try Self.preprocess(image, region: region)
        let input = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: pixel)])
        let output = try model.prediction(from: input)
        guard let scores = output.featureValue(for: "probabilities")?.multiArrayValue, scores.count == labels.count else { throw RecognitionError.incompatibleModel }
        let indices = (0..<scores.count).sorted { scores[$0].doubleValue == scores[$1].doubleValue ? $0 < $1 : scores[$0].doubleValue > scores[$1].doubleValue }
        guard indices.allSatisfy({ scores[$0].doubleValue.isFinite && (0...1).contains(scores[$0].doubleValue) }) else { throw RecognitionError.incompatibleModel }
        let candidates = indices.prefix(3).map { i in
            FoodCandidate(id: labels[i].id, name: labels[i].name, rawLabel: labels[i].rawLabel,
                          confidence: scores[i].doubleValue, source: source + " · Core ML", modelVersion: Self.revision,
                          imageID: imageID, classID: labels[i].id, region: region.map { [$0.minX, $0.minY, $0.width, $0.height] })
        }
        #if DEBUG
        if let root = diagnosticDirectory, let evidence = try? JSONEncoder().encode(candidates) {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try? evidence.write(to: root.appendingPathComponent("RecognitionEvidence.json"), options: .atomic)
        }
        #endif
        return RecognitionResult(candidates: candidates, note: "同一选区的三个备选名称；请确认一项。尚无本机相机拒识标定，非食物也可能获得高分。", elapsedMilliseconds: (CFAbsoluteTimeGetCurrent() - started) * 1000)
    }
    static func upright(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up, image.scale == 1, image.cgImage != nil { return image }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        // UIImage draw applies all EXIF orientations, including mirrored images.
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }
    static func preprocess(_ image: UIImage, region: CGRect?) throws -> CVPixelBuffer {
        guard image.size.width > 0, image.size.height > 0, let full = upright(image).cgImage else { throw RecognitionError.invalidImage }
        let rect = region ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        guard rect.width > 0, rect.height > 0, rect.minX >= 0, rect.minY >= 0, rect.maxX <= 1.001, rect.maxY <= 1.001,
              let crop = full.cropping(to: CGRect(x: rect.minX * CGFloat(full.width), y: rect.minY * CGFloat(full.height), width: rect.width * CGFloat(full.width), height: rect.height * CGFloat(full.height))) else { throw RecognitionError.invalidImage }
        // ConvNext processor: shortest edge floor(224/.875)=256 then a 224 center crop.
        let ratio = 256.0 / Double(min(crop.width, crop.height))
        let w = Int(Double(crop.width) * ratio), h = Int(Double(crop.height) * ratio)
        let resized = try FoodImagePreprocessor.resize(crop, width: w, height: h)
        guard let center = resized.cropping(to: CGRect(x: (w-224)/2, y: (h-224)/2, width: 224, height: 224)) else { throw RecognitionError.invalidImage }
        var pixel: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 224, 224, kCVPixelFormatType_32BGRA,
                                  [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &pixel) == kCVReturnSuccess, let pixel else { throw RecognitionError.invalidImage }
        CVPixelBufferLockBaseAddress(pixel, []); defer { CVPixelBufferUnlockBaseAddress(pixel, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: 224, height: 224, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue) else { throw RecognitionError.invalidImage }
        context.draw(center, in: CGRect(x: 0, y: 0, width: 224, height: 224))
        return pixel // raw RGB bytes; normalization happens inside the model exactly once
    }
}
