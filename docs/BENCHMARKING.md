# Core Benchmarking

The deterministic core benchmarks measure public `UnicornCore` operations. They do not start `unicorn.app`, InputMethodKit, or the candidate window. They use a separate hostless XCTest target. Thus, correctness tests, sanitizers, and coverage instrumentation do not change the measurements.

## Run the benchmarks

Run this command from the repository root:

```sh
make benchmark
```

The command deletes its benchmark directory before the build. It stops if the result bundle path is still in use. It runs only the `UnicornCorePerformanceTests` test plan.

The command builds production `UnicornCore` in Release configuration for the native host architecture. It disables coverage and parallel testing. The performance target imports the module without `@testable`.

The command hides standard Xcode build output. This keeps the report easy to read. If the build fails, the command shows the captured build output before the failure summary.

`make benchmark-native` runs the reusable execution stage and prints the same summary. Before measurement, this stage records the production keymap identity and the system versions. It stores this data in a provenance sidecar for the result bundle.

`make benchmark-summary` creates the report again from the stored provenance and the result bundle. It does not read the current keymap or run current system-version commands. The command fails if the provenance is missing or malformed.

Do not use `make test` as a benchmark command. The `UnicornCoreTests` plan uses a Debug correctness build with coverage. This plan contains only the correctness target. The performance plan contains only the benchmark target. `make benchmark` does not run the correctness suite.

## Fixtures and workloads

The primary fixture is the exact production [`keymap.json`](../unicorn/keymap.json). The build copies this file from its production source path into the performance-test bundle. Each run records the file byte count and SHA-256 digest.

Setup occurs before XCTest starts measurement. Setup loads the fixture bytes, decodes the setup engines, lists the paths, and warms each workload one time.

Each XCTest measurement has five samples. The tests put small operations into fixed-size batches. This reduces the effect of timer overhead.

| Workload | Measured batch for each sample | Check after measurement | Metrics |
| --- | --- | --- | --- |
| In-memory production-keymap initialization | Decode 10 independent engines from keymap bytes that are in memory | Each decode succeeds. Each root has the expected 79 children. | Wall clock, CPU, memory |
| Every candidate-bearing production path | Traverse all 2,046 paths 50 times. This gives 102,300 path traversals. | The fixture has 3,248 candidates on these paths. Each measured traversal gives the same total. | Wall clock, CPU |
| Common production composition | Run 1,000 cycles. Each cycle uses `\alpha`, `\lambda` plus Enter, `\notin`, and `\Longrightarrow` through `Engine.processKey`. | Warm-up commits are `α`, `λ`, `∉`, and `⇒`. Measured checksums agree. The engine is inactive at the end. | Wall clock, CPU |
| Deterministic mixed composition | Run 500 cycles of 18 public key operations. | The operations give the expected observable actions. They cover commits, invalid-continuation fallback, backspace, row and page navigation, numeric selection, and consecutive symbols. The engine is inactive at the end. | Wall clock, CPU |
| Accumulating soft commit and history | Run 50 cycles. Each cycle contains `\le\alpha` and a chain of 32 `le` soft commits, then `lambda` and Enter. | Commits are `≤α` and 32 `≤` symbols followed by `λ`. Measured checksums agree. The engine is inactive at the end. | Wall clock, CPU, memory |
| Undo and history pressure | Run 500 cycles. Each cycle crosses the 100-entry history boundary and applies 101 backspaces. | History reaches 100 and stays at 100 after one more push. Undo ends with an inactive engine and empty history. | Wall clock, CPU, memory |
| Production candidate navigation and selection | Run 5,000 cycles of 18 public operations after entry of `apl`. | The real `apl` node has 70 candidates. Row movement, paging, direct selection of candidate 70, and Enter give the expected output. The engine is inactive at the end. | Wall clock, CPU |

The expected commits for the mixed workload are `α`, `λ`, `∉`, `⍁`, and `≤α`. The test also checks the invalid continuation after `\lambda`. This continuation emits a commit and then a rejection. This is the fallback that the shell can observe.

The suite uses one synthetic fixture only for the narrow history-cap boundary. Its JSON has 30 bytes. It describes 3 trie nodes, a maximum depth of 2, a maximum branching factor of 1, one candidate-bearing node, and 2 candidates. The initial state has 99 deterministic history snapshots. This is the smallest fixture that can do these operations:

1. Push history to 100.
2. Push one more time past the cap.
3. Drain history through public reduction operations.

Checksums use actions and committed Unicode scalars after each public operation. After measurement, the tests check the checksums, state, and fixture invariants. If an observable result is incorrect, the run fails and does not publish its timing as valid.

## Generated artifacts

All generated files stay in the ignored `build/Benchmark/` directory:

- `Results/UnicornCorePerformanceTests.xcresult` is the fixed Xcode result bundle path.
- `Results/UnicornCorePerformanceTests.xcresult.provenance.json` contains the keymap and system provenance for the measured run.
- `Summary/xcode-test-summary.json` is the supported `xcresulttool get test-results summary` export.
- `Summary/xcode-performance-metrics.json` is the supported `xcresulttool get test-results metrics` export.
- `Summary/benchmark-summary.json` combines the two Xcode exports with benchmark context and calculated sample averages.
- `DerivedData/`, `BuildProducts/`, and `Intermediates/` contain only benchmark build products.

The context contains these captured values:

- production keymap byte count and SHA-256 digest;
- native architecture;
- macOS product version and build version;
- Xcode version and build version;
- Swift version;
- Release configuration;
- measurement iteration count;
- synthetic-fixture dimensions.

The report command prepares exports in temporary files. It publishes the final summary files only after all exports and report generation succeed. If a standalone export fails, the command removes all final summary files. Thus, stale files cannot look like results from the failed attempt.

The concise terminal report shows the average wall-clock and CPU time for each batch. It shows peak memory for selected workloads. It shows the relative standard deviation of wall-clock time as variation.

```text
UNICORN BENCHMARKS  COMPLETE  passed=7 failed=0 skipped=0 total=7
Release · arm64 · 5 iterations

WORKLOAD                                      WALL        CPU   PEAK MEMORY   VARIATION
In-memory initialization                 1.234 ms   1.000 ms      1.00 MiB       1.00%
...

Results: build/Benchmark
Thresholds: not enforced
```

Column widths adjust to the measured values. In an interactive terminal, the passing result is green. Headings and the artifact path are cyan. The no-threshold notice is yellow. Workload names are bold.

Output stays plain and aligned in these conditions:

- output is redirected;
- `CI` is set;
- `NO_COLOR` is present in the environment.

The JSON keeps each raw sample. It also keeps the additional CPU counters that XCTest reports on the current host. Run `make benchmark-report-test` to run the focused tests for the plain and colored formatter.

## Interpret and compare runs

These deterministic feature workloads are not scores that you can compare on all systems. Results include these effects:

- process startup state;
- XCTest overhead that remains after batching;
- host hardware;
- power and thermal state;
- operating-system scheduling;
- compiler and SDK versions;
- background activity.

Memory differences can round to zero. Use peak physical memory and repeated behavior. Do not use one difference sample. Initialization starts with bytes that are already in memory. It does not measure cold file-system startup.

The suite does not measure these items:

- installed-app latency;
- InputMethodKit integration;
- candidate-window rendering;
- Intel runtime performance when the suite runs on Apple silicon;
- the minimum supported macOS version;
- performance comparisons between different computers.

Universal app builds only show that the architecture slices compile. They are not benchmark results.

Use this procedure for a local comparison:

1. Use the same clean git state, host, power mode, Xcode version, and macOS version.
2. Close applications that cause variable system load. Let the host reach a stable thermal state.
3. Run `make benchmark` several times for each revision. Alternate the revisions when this is practical.
4. Save each `build/Benchmark/Summary/benchmark-summary.json` outside `build/` before the next run deletes it.
5. Compare all raw samples and relative standard deviations. Investigate a change that occurs in repeated runs. Do not use one outlier or one result from a shared runner.

The suite has no blocking numeric thresholds. COMPLETE has a specific meaning: all seven workloads passed, and each required metric has five samples.

A failed XCTest run can show metrics that it collected before the failure. However, `make benchmark` fails for each of these conditions:

- compile failure;
- XCTest failure;
- invariant failure;
- incomplete measurement set;
- result-export failure;
- report-generation failure.

Add numeric regression gates only after repeated tests show the variance on a stable, dedicated host. The benchmark does not run in the standard pull-request CI. Do not add it until the required variance evidence and host are available.
