# Repository Guidance

This file is the repository-wide operating guide for contributors and coding agents. It points to canonical documentation instead of duplicating product or design rules.

## Canonical Documentation

| Subject | Canonical owner |
| --- | --- |
| User-facing overview, current usage, installation, and essential risk disclosure | [`README.md`](README.md) |
| System architecture and implemented behavior | [`docs/SPECIFICATION.md`](docs/SPECIFICATION.md) and [`docs/specs/`](docs/specs/) |
| Swift coding conventions | [`docs/STYLE_GUIDE.md`](docs/STYLE_GUIDE.md) |
| Technical security, signing, installer, integrity, and distribution behavior | [`docs/specs/security_and_distribution.md`](docs/specs/security_and_distribution.md) |
| Documentation writing and review standards | [`docs/DOCUMENTATION_GUIDE.md`](docs/DOCUMENTATION_GUIDE.md) |
| Build, test, lint, install, and release commands | [`Makefile`](Makefile) |

When documentation conflicts with implementation or automation, verify the current source, project settings, scripts, tests, workflows, and published artifacts before updating the canonical owner. Describe desired but unimplemented behavior as future work, never as current behavior.

## Architecture Constraints

Unicorn uses the three-tier Pure Core, Impure Shell architecture defined in the [system specification](docs/SPECIFICATION.md#architecture):

- Keep state transitions and symbol lookup deterministic in `Engine`.
- Keep presentation calculations as pure transformations on `EngineState`.
- Keep macOS and InputMethodKit effects in `InputController`.

Follow the [Functional Swift style guide](docs/STYLE_GUIDE.md) for code changes. `Engine.state` is the central controlled mutation point; prefer immutable values and pure transformations elsewhere.

## Development Entry Points

The Xcode project is wrapped by the Makefile:

```sh
make test
make lint
make build
make install
make coverage
```

- `make test` runs the hostless `UnicornCoreTests` bundle on the host architecture with coverage enabled, then cross-compiles the production app for the other supported architecture. The cross-compilation checks compilation only; it does not execute that architecture.
- Test diagnostics and coverage data are stored in `build/Test/Results/UnicornCoreTests.xcresult`. All test intermediates stay under the ignored `build/Test/` directory.
- `make coverage` reruns the standard test path and prints a readable report from that `.xcresult` bundle.
- `make build` performs a Release build by default and overrides Xcode signing with the ad-hoc identity `-`.
- `make install` builds, replaces the app in `~/Library/Input Methods/`, and registers it with Launch Services.

The hostless suite uses Swift Testing for engine transitions, trie-backed lookup, candidates, history, limits, and presentation calculations. The legacy functional-operator parity case alone uses XCTest because current Swift SDKs export a conflicting `>>=` declaration across the `UnicornCore` module boundary; the preserved operator delegates to the named implementation exercised by that test.

Core tests exercise the public engine manager seam but do not launch `unicorn.app`, an `IMKServer`, or the candidate panel. InputMethodKit lifecycle, marked-text behavior, candidate UI, and event handling in real clients require installing and enabling the input source and validating it in actual client applications. Cross-compilation and hostless tests do not replace that end-to-end validation or validate the minimum supported macOS version.

Release targets (`release`, `test-release`, `re-release`, and `clean-test-releases`) mutate local and remote Git or GitHub state. Inspect their definitions in the Makefile and use them only with explicit release intent.

Use standard `git` commands for local repository state such as branches, commits, and local tags. Use the GitHub CLI (`gh`) for GitHub-hosted state such as pull requests and releases. The Makefile derives `GITHUB_REPO` from the `origin` remote for release commands; test-tag cleanup in the release workflow uses `gh api` so it does not depend on a local Git checkout.

## Key Paths

- `UnicornCore/Engine.swift`: state transition engine.
- `UnicornCore/EngineTypes.swift`: state, actions, candidate paging, and presentation model.
- `UnicornCore/KeyCode.swift`: macOS event normalization.
- `UnicornCore/Trie.swift`: immutable symbol trie.
- `UnicornCore/FunctionalHelpers.swift`: the project's `|>` and `>>=` operators.
- `UnicornCoreTests/EngineTests.swift`: Swift Testing engine and presentation-model tests.
- `UnicornCoreTests/LegacyFunctionalOperatorTests.swift`: isolated XCTest compatibility case.
- `unicorn/InputController.swift`: InputMethodKit integration.
- `unicorn/keymap.json`: bundled symbol data.
- `.github/workflows/`: pull-request CI and tagged-release automation.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
