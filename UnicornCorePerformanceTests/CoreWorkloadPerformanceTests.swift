import Foundation
import XCTest
import UnicornCore

private enum BenchmarkFixture {
    static let productionKeymapByteCount = 240_703
    static let candidateBearingPathCount = 2_046
    static let productionCandidateCount = 3_248
    static let largestCandidateListCount = 70

    static let initializationBatchSize = 10
    static let traversalBatchSize = 50
    static let commonCompositionBatchSize = 1_000
    static let mixedCompositionBatchSize = 500
    static let accumulatingCompositionBatchSize = 50
    static let historyPressureBatchSize = 500
    static let candidateNavigationBatchSize = 5_000

    static let syntheticHistoryJSON = #"{"a":{"b":{">>":["B1","B2"]}}}"#
    static let syntheticHistoryByteCount = 30
    static let syntheticHistoryBranchingFactor = 1
    static let syntheticHistoryCandidateCount = 2

    static func productionKeymapData(testCase: XCTestCase) throws -> Data {
        let bundle = Bundle(for: type(of: testCase))
        let url = try XCTUnwrap(
            bundle.url(forResource: "keymap", withExtension: "json"),
            "The performance-test bundle must contain the production keymap"
        )
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, productionKeymapByteCount)
        return data
    }

    static func productionEngine(testCase: XCTestCase) throws -> Engine {
        return try Engine(jsonData: productionKeymapData(testCase: testCase))
    }

    static func syntheticHistoryEngine() throws -> Engine {
        let data = try XCTUnwrap(syntheticHistoryJSON.data(using: .utf8))
        XCTAssertEqual(data.count, syntheticHistoryByteCount)
        return try Engine(jsonData: data)
    }
}

private struct CandidatePath {
    let characters: [Character]
    let candidateCount: Int
}

private func candidateBearingPaths(root: Trie) -> [CandidatePath] {
    func visit(node: Trie, path: [Character]) -> [CandidatePath] {
        let current = node.candidates.map {
            [CandidatePath(characters: path, candidateCount: $0.count)]
        } ?? []
        let descendants = node.children.keys.sorted().flatMap { character in
            visit(node: node.children[character]!, path: path + [character])
        }
        return current + descendants
    }

    return visit(node: root, path: [])
}

private func actionChecksum(_ actions: [EngineAction]) -> UInt64 {
    return actions.reduce(0) { checksum, action in
        switch action {
        case .reject:
            return checksum &+ 3
        case .sync:
            return checksum &+ 5
        case .navigate(.up):
            return checksum &+ 7
        case .navigate(.down):
            return checksum &+ 11
        case .navigate(.pageUp):
            return checksum &+ 13
        case .navigate(.pageDown):
            return checksum &+ 17
        case .commit(let text):
            return text.unicodeScalars.reduce(checksum &+ 19) {
                $0 &+ UInt64($1.value)
            }
        }
    }
}

private func processActions(_ keyCodes: [KeyCode], with engine: Engine) -> [EngineAction] {
    return keyCodes.flatMap { engine.processKey(keyCode: $0) }
}

private func process(_ keyCodes: [KeyCode], with engine: Engine) -> UInt64 {
    return keyCodes.reduce(0) { checksum, keyCode in
        checksum &+ actionChecksum(engine.processKey(keyCode: keyCode))
    }
}

private func committedTexts(in actions: [EngineAction]) -> [String] {
    return actions.compactMap { action in
        guard case .commit(let text) = action else { return nil }
        return text
    }
}

private let commonCompositionKeys: [KeyCode] = [
    .chars("\\"), .chars("alpha"),
    .chars("\\"), .chars("lambda"), .enter,
    .chars("\\"), .chars("notin"),
    .chars("\\"), .chars("Longrightarrow")
]

private func runCommonComposition(engine: Engine, batchSize: Int) -> UInt64 {
    return (0..<batchSize).reduce(0) { checksum, _ in
        checksum &+ process(commonCompositionKeys, with: engine)
    }
}

private let mixedCompositionKeys: [KeyCode] = [
    .chars("\\"), .chars("alpha"),
    .chars("\\"), .chars("lambda"), .chars("!"),
    .chars("\\"), .chars("not"), .backspace, .chars("tin"),
    .chars("\\"), .chars("apl"), .down, .right, .chars("3"),
    .chars("\\"), .chars("le"), .chars("\\"), .chars("alpha")
]

private func runMixedComposition(engine: Engine, batchSize: Int) -> UInt64 {
    return (0..<batchSize).reduce(0) { checksum, _ in
        checksum &+ process(mixedCompositionKeys, with: engine)
    }
}

private let accumulatingCompositionKeys: [KeyCode] = {
    let representative: [KeyCode] = [
        .chars("\\"), .chars("le"), .chars("\\"), .chars("alpha")
    ]
    let chainStart: [KeyCode] = [.chars("\\")]
    let chainBody = (0..<32).flatMap { _ in
        [KeyCode.chars("le"), KeyCode.chars("\\")]
    }
    let chainEnd: [KeyCode] = [.chars("lambda"), .enter]
    return representative + chainStart + chainBody + chainEnd
}()

private func runAccumulatingComposition(engine: Engine, batchSize: Int) -> UInt64 {
    return (0..<batchSize).reduce(0) { checksum, _ in
        checksum &+ process(accumulatingCompositionKeys, with: engine)
    }
}

private func historyPressureSeed(engine: Engine) -> EngineState {
    let snapshot = EngineState(
        path: [engine.root],
        buffer: "\\",
        active: true,
        candidateWindow: .empty()
    )
    return snapshot.updating(history: Array(repeating: snapshot, count: 99))
}

private func runHistoryPressure(engine: Engine, seed: EngineState, batchSize: Int) -> UInt64 {
    return (0..<batchSize).reduce(0) { checksum, _ in
        let (atCap, atCapActions) = engine.reduce(state: seed, keyCode: .chars("a"))
        let (pastCap, pastCapActions) = engine.reduce(state: atCap, keyCode: .chars("b"))
        let final = (0..<101).reduce(pastCap) { state, _ in
            engine.reduce(state: state, keyCode: .backspace).0
        }
        let observed = UInt64(atCap.history.count + pastCap.history.count)
            &+ actionChecksum(atCapActions)
            &+ actionChecksum(pastCapActions)
            &+ UInt64(final.active ? 1 : 0)
        return checksum &+ observed
    }
}

private func runCandidateNavigation(engine: Engine, batchSize: Int) -> UInt64 {
    return (0..<batchSize).reduce(0) { checksum, _ in
        var cycle = process([.chars("\\"), .chars("apl")], with: engine)
        for _ in 0..<8 {
            cycle &+= actionChecksum(engine.processKey(keyCode: .down))
        }
        for _ in 0..<3 {
            cycle &+= actionChecksum(engine.processKey(keyCode: .up))
        }
        cycle &+= process([.right, .right, .left], with: engine)
        engine.selectCandidate(index: 69)
        cycle &+= actionChecksum(engine.processKey(keyCode: .enter))
        return checksum &+ cycle
    }
}

final class CoreWorkloadPerformanceTests: XCTestCase {
    private let standardMetrics: [XCTMetric] = [XCTClockMetric(), XCTCPUMetric()]
    private let memoryMetrics: [XCTMetric] = [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]

    private func options() -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        return options
    }

    func testInMemoryInitializationFromProductionKeymap() throws {
        let data = try BenchmarkFixture.productionKeymapData(testCase: self)
        let warmEngine = try Engine(jsonData: data)
        XCTAssertEqual(warmEngine.root.children.count, 79)

        var measuredError: Error?
        var observedRootChildCount = 0
        measure(metrics: memoryMetrics, options: options()) {
            var childCount = 0
            for _ in 0..<BenchmarkFixture.initializationBatchSize {
                do {
                    let engine = try Engine(jsonData: data)
                    childCount += engine.root.children.count
                } catch {
                    measuredError = error
                    return
                }
            }
            observedRootChildCount = childCount
        }

        XCTAssertNil(measuredError)
        XCTAssertEqual(observedRootChildCount, 79 * BenchmarkFixture.initializationBatchSize)
    }

    func testTraversalOfEveryCandidateBearingProductionPath() throws {
        let engine = try BenchmarkFixture.productionEngine(testCase: self)
        let paths = candidateBearingPaths(root: engine.root)
        XCTAssertEqual(paths.count, BenchmarkFixture.candidateBearingPathCount)
        XCTAssertEqual(
            paths.reduce(0) { $0 + $1.candidateCount },
            BenchmarkFixture.productionCandidateCount
        )
        XCTAssertEqual(traverse(paths: paths, root: engine.root, batchSize: 1), 3_248)

        var checksum = 0
        measure(metrics: standardMetrics, options: options()) {
            checksum = self.traverse(
                paths: paths,
                root: engine.root,
                batchSize: BenchmarkFixture.traversalBatchSize
            )
        }

        XCTAssertEqual(
            checksum,
            BenchmarkFixture.productionCandidateCount * BenchmarkFixture.traversalBatchSize
        )
    }

    func testCommonProductionComposition() throws {
        let warmEngine = try BenchmarkFixture.productionEngine(testCase: self)
        let warmActions = processActions(commonCompositionKeys, with: warmEngine)
        XCTAssertEqual(committedTexts(in: warmActions), ["α", "λ", "∉", "⇒"])
        let expected = actionChecksum(warmActions)
        XCTAssertFalse(warmEngine.state.active)

        let engine = try BenchmarkFixture.productionEngine(testCase: self)
        var checksum: UInt64 = 0
        measure(metrics: standardMetrics, options: options()) {
            checksum = runCommonComposition(
                engine: engine,
                batchSize: BenchmarkFixture.commonCompositionBatchSize
            )
        }

        XCTAssertFalse(engine.state.active)
        XCTAssertEqual(checksum, expected * UInt64(BenchmarkFixture.commonCompositionBatchSize))
    }

    func testDeterministicMixedComposition() throws {
        let warmEngine = try BenchmarkFixture.productionEngine(testCase: self)
        let warmActions = processActions(mixedCompositionKeys, with: warmEngine)
        XCTAssertEqual(committedTexts(in: warmActions), ["α", "λ", "∉", "⍁", "≤α"])
        XCTAssertTrue(
            zip(warmActions, warmActions.dropFirst()).contains {
                $0.0 == .commit("λ") && $0.1 == .reject
            }
        )
        let expected = actionChecksum(warmActions)
        XCTAssertFalse(warmEngine.state.active)

        let engine = try BenchmarkFixture.productionEngine(testCase: self)
        var checksum: UInt64 = 0
        measure(metrics: standardMetrics, options: options()) {
            checksum = runMixedComposition(
                engine: engine,
                batchSize: BenchmarkFixture.mixedCompositionBatchSize
            )
        }

        XCTAssertFalse(engine.state.active)
        XCTAssertEqual(checksum, expected * UInt64(BenchmarkFixture.mixedCompositionBatchSize))
    }

    func testAccumulatingSoftCommitAndHistory() throws {
        let warmEngine = try BenchmarkFixture.productionEngine(testCase: self)
        let warmActions = processActions(accumulatingCompositionKeys, with: warmEngine)
        XCTAssertEqual(
            committedTexts(in: warmActions),
            ["≤α", String(repeating: "≤", count: 32) + "λ"]
        )
        let expected = actionChecksum(warmActions)
        XCTAssertFalse(warmEngine.state.active)

        let engine = try BenchmarkFixture.productionEngine(testCase: self)
        var checksum: UInt64 = 0
        measure(metrics: memoryMetrics, options: options()) {
            checksum = runAccumulatingComposition(
                engine: engine,
                batchSize: BenchmarkFixture.accumulatingCompositionBatchSize
            )
        }

        XCTAssertFalse(engine.state.active)
        XCTAssertEqual(
            checksum,
            expected * UInt64(BenchmarkFixture.accumulatingCompositionBatchSize)
        )
    }

    func testUndoAndHistoryPressureAtCap() throws {
        let engine = try BenchmarkFixture.syntheticHistoryEngine()
        XCTAssertEqual(engine.root.children.count, BenchmarkFixture.syntheticHistoryBranchingFactor)
        let firstNode = try XCTUnwrap(engine.root.children["a"])
        XCTAssertEqual(firstNode.children.count, BenchmarkFixture.syntheticHistoryBranchingFactor)
        let candidateNode = try XCTUnwrap(firstNode.children["b"])
        XCTAssertTrue(candidateNode.children.isEmpty)
        XCTAssertEqual(
            candidateNode.candidates?.count,
            BenchmarkFixture.syntheticHistoryCandidateCount
        )
        let seed = historyPressureSeed(engine: engine)
        let atCap = engine.reduce(state: seed, keyCode: .chars("a")).0
        let pastCap = engine.reduce(state: atCap, keyCode: .chars("b")).0
        let afterUndo = (0..<101).reduce(pastCap) { state, _ in
            engine.reduce(state: state, keyCode: .backspace).0
        }
        XCTAssertEqual(atCap.history.count, 100)
        XCTAssertEqual(pastCap.history.count, 100)
        XCTAssertFalse(afterUndo.active)
        XCTAssertTrue(afterUndo.history.isEmpty)
        let expected = runHistoryPressure(engine: engine, seed: seed, batchSize: 1)

        var checksum: UInt64 = 0
        measure(metrics: memoryMetrics, options: options()) {
            checksum = runHistoryPressure(
                engine: engine,
                seed: seed,
                batchSize: BenchmarkFixture.historyPressureBatchSize
            )
        }

        XCTAssertEqual(checksum, expected * UInt64(BenchmarkFixture.historyPressureBatchSize))
    }

    func testProductionCandidateNavigationAndSelection() throws {
        let warmEngine = try BenchmarkFixture.productionEngine(testCase: self)
        _ = process([.chars("\\"), .chars("apl")], with: warmEngine)
        XCTAssertEqual(
            warmEngine.state.candidateWindow.candidates.count,
            BenchmarkFixture.largestCandidateListCount
        )
        XCTAssertEqual(
            candidateBearingPaths(root: warmEngine.root).map(\.candidateCount).max(),
            BenchmarkFixture.largestCandidateListCount
        )
        for _ in 0..<8 {
            _ = warmEngine.processKey(keyCode: .down)
        }
        for _ in 0..<3 {
            _ = warmEngine.processKey(keyCode: .up)
        }
        _ = process([.right, .right, .left], with: warmEngine)
        XCTAssertEqual(warmEngine.state.candidateWindow.firstVisibleIndex, 9)
        XCTAssertEqual(warmEngine.state.candidateWindow.selectedIndex, 9)
        warmEngine.selectCandidate(index: 69)
        XCTAssertEqual(warmEngine.state.candidateWindow.selectedCandidate, "⎕")
        XCTAssertEqual(warmEngine.processKey(keyCode: .enter), [.commit("⎕")])
        XCTAssertFalse(warmEngine.state.active)
        let expected = runCandidateNavigation(engine: warmEngine, batchSize: 1)
        XCTAssertFalse(warmEngine.state.active)

        let engine = try BenchmarkFixture.productionEngine(testCase: self)
        var checksum: UInt64 = 0
        measure(metrics: standardMetrics, options: options()) {
            checksum = runCandidateNavigation(
                engine: engine,
                batchSize: BenchmarkFixture.candidateNavigationBatchSize
            )
        }

        XCTAssertFalse(engine.state.active)
        XCTAssertEqual(checksum, expected * UInt64(BenchmarkFixture.candidateNavigationBatchSize))
    }

    private func traverse(paths: [CandidatePath], root: Trie, batchSize: Int) -> Int {
        return (0..<batchSize).reduce(0) { checksum, _ in
            checksum + paths.reduce(0) { pathChecksum, path in
                let terminal = path.characters.reduce(Optional(root)) { node, character in
                    node?.children[character]
                }
                return pathChecksum + (terminal?.candidates?.count ?? -path.candidateCount)
            }
        }
    }
}
