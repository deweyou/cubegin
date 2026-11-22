import Foundation
#if canImport(Cubegin)
import Cubegin
#endif

struct Scramble: Sendable {
    let algorithm: String
    let svg: String

    var diagramAspectRatio: Double? {
        guard let viewBox = svg.range(of: "viewBox=\""),
              let end = svg[viewBox.upperBound...].firstIndex(of: "\"") else { return nil }
        let dimensions = svg[viewBox.upperBound..<end]
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
        guard dimensions.count == 4,
              let width = Double(dimensions[2]), let height = Double(dimensions[3]),
              width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        return width / height
    }
}
enum AssistMethod: String, Identifiable, Sendable {
    case cross, xcross, eoline, eofc
    case rouxFirst = "roux-s1", rouxStages = "roux-s2"
    case petrusFirst = "petrus-s1", petrusStages = "petrus-s2"
    case cfopF2L = "cfop-f2l", zzF2L = "zz-f2l", block = "block-222", eoDr = "eo-dr"
    case cubeFace = "222-face", cubeLayer = "222-layer"
    case shapeFTM = "sq1-shape-ftm", shapeTwist = "sq1-shape-twist"
    case pyraminxV = "pyraminx-v", skewbFace = "skewb-face"

    var id: String { rawValue }

    static func solverEvent(for event: String) -> String {
        let puzzle = event.split(separator: ".").first.map(String.init) ?? event
        switch puzzle {
        case "333bld", "333fm", "333oh", "333mbld": return "333"
        case "444bld": return "444"
        default: return puzzle
        }
    }

    static func available(for event: String) -> [Self] {
        if event.contains(".") {
            switch event {
            case "333.easy_cross": return [.cross]
            case "333.easy_xcross": return [.xcross]
            case "333.f2l": return [.cfopF2L]
            default: return []
            }
        }
        return switch solverEvent(for: event) {
        case "333":
            [.cross, .xcross, .eoline, .eofc, .rouxFirst, .rouxStages, .petrusFirst, .petrusStages,
             .cfopF2L, .zzF2L, .block, .eoDr]
        case "222": [.cubeFace, .cubeLayer]
        case "sq1": [.shapeFTM, .shapeTwist]
        case "pyram": [.pyraminxV]
        case "skewb": [.skewbFace]
        default: []
        }
    }

    var isStaged: Bool {
        switch self {
        case .rouxStages, .petrusStages, .cfopF2L, .zzF2L, .eoDr: true
        default: false
        }
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .cross: "Cross"
        case .xcross: "XCross"
        case .eoline: "EOLine"
        case .eofc: "EOFC"
        case .rouxFirst: language.text("Roux 第一块", "Roux First Block")
        case .rouxStages: language.text("Roux 分阶段", "Roux Stages")
        case .petrusFirst: language.text("Petrus 第一块", "Petrus First Block")
        case .petrusStages: language.text("Petrus 分阶段", "Petrus Stages")
        case .cfopF2L: "CFOP F2L"
        case .zzF2L: "ZZ F2L"
        case .block: language.text("2×2×2 块", "2×2×2 Block")
        case .eoDr: "EO → DR"
        case .cubeFace, .skewbFace: language.text("一面", "Face")
        case .cubeLayer: language.text("一层", "Layer")
        case .shapeFTM: language.text("复形 FTM", "Shape FTM")
        case .shapeTwist: language.text("复形 Twist", "Shape Twist")
        case .pyraminxV: language.text("V 形", "V Shape")
        }
    }
}

struct AssistSolution: Decodable, Identifiable, Sendable {
    struct Metric: Decodable, Sendable {
        let ftm: Int
    }

    let target: String
    let targetLabel: String
    let setupRotation: String
    let solution: String
    let metric: Metric?

    var id: String { target }
}

enum Engine {
    static func assistSolutions(event: String, method: AssistMethod, algorithm: String) async throws -> [AssistSolution] {
        try Task.checkCancellation()
        return try await Task.detached(priority: .userInitiated) {
#if canImport(Cubegin)
            let solverEvent = AssistMethod.solverEvent(for: event)
            struct AssistResult: Decodable { let solutions: [AssistSolution] }
            struct SearchOptions: Encodable {
                let targets: [String]?
                let maxSolutionsPerTarget = 1
            }
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            // Training scrambles generated without orientation options use the D face.
            let targets: [String]? = switch event {
            case "333.easy_cross", "333.easy_xcross": ["D"]
            default: nil
            }
            let options = try encoder.encode(SearchOptions(targets: targets))
            let methods = try JSONEncoder().encode([method.rawValue])
            let json = try solveAssist(
                event: solverEvent, methodsJson: String(decoding: methods, as: UTF8.self),
                algorithm: algorithm, optionsJson: String(decoding: options, as: UTF8.self)
            )
            let solutions = try JSONDecoder().decode([AssistResult].self, from: Data(json.utf8))
                .flatMap(\.solutions)
            if event == "333.f2l", let cross = solutions.first, cross.target == "Cross",
               cross.solution.isEmpty, cross.setupRotation.isEmpty {
                return Array(solutions.dropFirst())
            }
            return solutions
#else
            throw EngineError.sdkMissing
#endif
        }.value
    }

    static func diagram(event: String, algorithm: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
#if canImport(Cubegin)
            let baseEvent = String(event.split(separator: ".")[0])
            return try evaluateEvent(event: baseEvent, algorithm: algorithm).svg
#else
            throw EngineError.sdkMissing
#endif
        }.value
    }

    // Called from the import worker. The engine validates the scramble for its base puzzle.
    static func acceptsImportedScramble(event: String, algorithm: String) throws -> Bool {
#if canImport(Cubegin)
        let baseEvent = String(event.split(separator: ".")[0])
        do {
            _ = try evaluateEvent(event: baseEvent, algorithm: algorithm)
            return true
        } catch CubeginError.InvalidInput {
            return false
        }
#else
        throw EngineError.sdkMissing
#endif
    }

    static func scramble(event: String) async throws -> Scramble {
        try await Task.detached(priority: .userInitiated) {
#if canImport(Cubegin)
            let seed = UInt32.random(in: .min ... .max)
            let algorithm: String
            if event.contains(".") {
                struct TrainingResult: Decodable { let algorithm: String }
                let json = try generateTraining(id: event, seed: seed, optionsJson: "{}")
                algorithm = try JSONDecoder().decode(TrainingResult.self, from: Data(json.utf8)).algorithm
            } else {
                algorithm = try generateEvent(event: event, seed: seed).algorithm
            }
            let baseEvent = String(event.split(separator: ".")[0])
            let state = try evaluateEvent(event: baseEvent, algorithm: algorithm)
            return Scramble(algorithm: algorithm, svg: state.svg)
#else
            throw EngineError.sdkMissing
#endif
        }.value
    }
    enum EngineError: LocalizedError {
        case sdkMissing
        var errorDescription: String? { "尚未链接 Cubegin SDK。请构建 本仓库的 iOS XCFramework，然后打开 Cubegin.xcodeproj 使用 CubeginApp scheme。" }
    }
}
