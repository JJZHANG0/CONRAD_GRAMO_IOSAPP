import XCTest
import CoreML
import UIKit
@testable import GRAMO_APP

/// Optional real-photo bench: copy private samples to Documents/ModelBenchSamples.
/// It does not write meal records or include sample images in the repository.
final class LocalModelPerformanceTests: XCTestCase {
    func testLocalModelParityAndLatency() async throws {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = root.appendingPathComponent("ModelBenchSamples")
        guard let url = Bundle.main.url(forResource: "ChineseFood", withExtension: "mlmodelc"),
              let samples = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil),
              samples.contains(where: { $0.pathExtension == "jpg" }) else { throw XCTSkip("Local evaluation model / private bench photos not installed") }
        let config = MLModelConfiguration(); config.computeUnits = .cpuOnly
        let cpu = try MLModel(contentsOf: url, configuration: config)
        var report: [[String: Any]] = []
        for sample in samples.filter({ $0.pathExtension == "jpg" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let image = try XCTUnwrap(UIImage(contentsOfFile: sample.path))
            let prepareStart = CFAbsoluteTimeGetCurrent()
            let pixel = try FoodRecognizer.preprocess(image, region: nil)
            let preprocessing = (CFAbsoluteTimeGetCurrent() - prepareStart) * 1000
            let input = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: pixel)])
            let start = CFAbsoluteTimeGetCurrent()
            let output = try await cpu.prediction(from: input)
            let cpuMS = (CFAbsoluteTimeGetCurrent() - start) * 1000
            let scores = try XCTUnwrap(output.featureValue(for: "probabilities")?.multiArrayValue)
            let top = (0..<scores.count).sorted { scores[$0].doubleValue > scores[$1].doubleValue }.prefix(3).map(String.init)
            var times: [Double] = [], ids: [String] = [], topScores: [Double] = [], maxDelta = 0.0
            for _ in 0..<3 {
                let result = try await FoodRecognizer.shared.recognize(image, source: "Local private benchmark", imageID: nil)
                ids = result.candidates.map(\.id); topScores = result.candidates.compactMap(\.confidence); times.append(result.elapsedMilliseconds)
                XCTAssertEqual(ids, top, "CPU and production path Top 3 changed for \(sample.lastPathComponent)")
                for candidate in result.candidates {
                    let delta = abs((candidate.confidence ?? 0) - scores[Int(candidate.id)!].doubleValue)
                    maxDelta = max(maxDelta, delta)
                    XCTAssertLessThan(delta, 0.01)
                }
                XCTAssertTrue(result.requiresConfirmation)
            }
            report.append(["sample": sample.lastPathComponent, "preprocessingMS": preprocessing,
                           "cpuPredictionMS": cpuMS, "productionTotalMS": times, "top3": ids, "topScores": topScores, "maxScoreDelta": maxDelta])
        }
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("ModelBenchmark.json"), options: .atomic)
        print("LOCAL_MODEL_BENCHMARK " + String(decoding: data, as: UTF8.self))
    }
}
