# Core Benchmarking

Unicorn's deterministic core benchmarks measure public `UnicornCore` operations without launching `unicorn.app`, InputMethodKit, or the candidate window. They run in a separate hostless XCTest target so correctness tests, sanitizers, and coverage instrumentation do not execute or distort them.

## Running the benchmarks

From the repository root, run:

```sh
make benchmark
```

The command deletes its dedicated benchmark directory before building, refuses to proceed if the result bundle path is still occupied, and runs only the `UnicornCorePerformanceTests` test plan. It compiles production `UnicornCore` in Release on the host's native architecture with coverage and parallel testing disabled. The performance target imports the module normally, without `@testable`. `make benchmark-native` and `make benchmark-summary` expose the reusable execution and reporting stages behind the canonical command.

Do not use `make test` as a benchmark command. The ordinary `UnicornCoreTests` plan uses a Debug correctness build with coverage and contains only the correctness target. Conversely, the dedicated performance plan contains only the benchmark target, and `make benchmark` does not run the correctness suite.

## Fixtures and workloads

The primary fixture is the exact production [`keymap.json`](../unicorn/keymap.json), copied into the performance-test bundle from its production source path. Each run records its byte count and SHA-256 digest. Setup, including loading fixture bytes, decoding setup engines, enumerating paths, and warming each workload once, occurs before XCTest starts measuring.

Each XCTest measurement contains five samples. Tiny operations are batched at a fixed size so timer overhead does not dominate.

| Workload | Measured batch per sample | Post-measurement invariant | Metrics |
| --- | --- | --- | --- |
| In-memory production-keymap initialization | Decode 10 independent engines from already loaded keymap bytes | Every decode succeeds and each root has the expected 79 children | Wall clock, CPU, memory |
| Every candidate-bearing production path | Traverse all 2,046 paths 50 times, or 102,300 path traversals | The fixture has 3,248 candidates across those paths and every measured traversal reproduces that total | Wall clock, CPU |
| Common production composition | Run 1,000 cycles covering `\alpha`, `\lambda` plus Enter, `\notin`, and `\Longrightarrow` through `Engine.processKey` | Warm-up commits are `α`, `λ`, `∉`, and `⇒`; measured checksums match and the engine ends inactive | Wall clock, CPU |
| Deterministic mixed composition | Run 500 cycles of 18 public key operations | Commits, invalid-continuation fallback, backspace, row and page navigation, numeric selection, and consecutive symbols produce the expected observable actions; the engine ends inactive | Wall clock, CPU |
| Accumulating soft commit and history | Run 50 cycles containing `\le\alpha` and a chain of 32 `le` soft commits followed by `lambda` and Enter | Commits are `≤α` and 32 `≤` symbols followed by `λ`; checksums match and the engine ends inactive | Wall clock, CPU, memory |
| Undo and history pressure | Run 500 cycles crossing the 100-entry history boundary and applying 101 backspaces | History reaches 100, remains capped at 100 after another push, and undo finishes inactive with empty history | Wall clock, CPU, memory |
| Production candidate navigation and selection | Run 5,000 cycles of 18 public operations after entering `apl` | The real `apl` node has 70 candidates; row movement, paging, direct selection of candidate 70, and Enter complete with matching observable output and an inactive engine | Wall clock, CPU |

The mixed workload's expected commits are `α`, `λ`, `∉`, `⍁`, and `≤α`. It verifies that the invalid continuation after `\lambda` emits a commit followed by rejection, which is the fallback observable to the shell.

The sole synthetic fixture is used only for the otherwise narrow history-cap boundary. Its JSON is 30 bytes and describes 3 trie nodes, maximum depth 2, maximum branching factor 1, one candidate-bearing node, and 2 candidates. The starting state contains 99 deterministic history snapshots. This is the smallest fixture needed to push once to 100, push once past the cap, and then drain history through public reduction operations.

Checksums consume actions and committed Unicode scalars after every public operation. They are asserted after measurement, along with state and fixture invariants, so a run with an incorrect observable result fails instead of publishing timing from invalid work.

## Generated artifacts

All generated files stay under the ignored `build/Benchmark/` directory:

- `Results/UnicornCorePerformanceTests.xcresult`: the deterministic, dedicated Xcode result bundle path;
- `Summary/xcode-test-summary.json`: the supported `xcresulttool get test-results summary` export;
- `Summary/xcode-performance-metrics.json`: the supported `xcresulttool get test-results metrics` export;
- `Summary/benchmark-summary.json`: the two Xcode exports combined with benchmark context and computed sample averages;
- `DerivedData/`, `BuildProducts/`, and `Intermediates/`: benchmark-only build products.

The context records production keymap byte count and SHA-256, native architecture, macOS product and build versions, Xcode version and build, Swift version, Release configuration, measurement iterations, and synthetic-fixture dimensions. The concise terminal report shows batch-average wall-clock and CPU time, plus peak memory for selected workloads. The JSON retains every raw sample and additional CPU counters that XCTest reports on the current host.

## Interpreting and comparing runs

These are deterministic feature workloads, not universally comparable scores. Results include process startup state, XCTest overhead that remains after batching, host hardware, power and thermal state, OS scheduling, compiler and SDK versions, and background activity. Memory deltas can quantize to zero; use peak physical memory and repeated behavior rather than a single delta sample. Initialization starts from bytes already in memory, so it does not claim cold filesystem startup.

The suite does not measure installed-app latency, InputMethodKit integration, candidate-window rendering, Intel runtime performance when run on Apple silicon, the minimum supported macOS version, or cross-machine performance. Universal app builds establish compilation for their architecture slices only and are not benchmark results.

For a local comparison:

1. Use the same clean git state, host, power mode, Xcode, and macOS version.
2. Close noisy applications and allow the host to reach a stable thermal state.
3. Run `make benchmark` several times for each revision, alternating revisions when practical.
4. Save each `build/Benchmark/Summary/benchmark-summary.json` outside `build/` before the next run deletes it.
5. Compare all raw samples and relative standard deviations. Investigate a consistent shift across repeated runs, not one outlier or one shared-runner result.

There are no blocking numeric thresholds in this suite. A compile failure, XCTest failure, invariant failure, result-export failure, or report-generation failure makes `make benchmark` fail. Numeric regression gates should be added only after repeated variance evidence exists on a stable dedicated host. The benchmark is intentionally absent from ordinary pull-request CI until that evidence and host exist.
