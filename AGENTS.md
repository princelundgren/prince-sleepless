# PrinceSleepless: agent instructions

Everything in this repository is public: code, docs, commit messages, issues and pull requests.

- **Nothing personal or employer-specific.** No machine names, host names, account IDs or
  organisation names, in code, tests, fixtures, docs or commits. Use placeholders.
- **The design is the authority:** `docs/superpowers/specs/2026-11-24-princesleepless-design.md`.
  A change that makes it untrue updates it in the same commit.
- **Privacy is a product feature.** No telemetry, analytics, crash reporting or SDK that collects
  any of them. Logs go through `os.Logger` with the subsystem `com.princelundgren.princesleepless`
  only. Neither the app nor the helper has entitlements.
- **Nothing runs through a shell string.** Run `pmset` and every other tool as an executable plus an
  argument list.
- **Never install or run a build on a Mac whose sleep is disabled on purpose.** The helper clears the
  flag at every boot.
- **Changes land through a pull request**, with signed commits.
- **CI runs on GitHub's `xcode-27` runner.** Every action is pinned by full commit SHA, except the
  Claude review: it calls the shared reusable workflow at its moving `v1` tag, since only that
  repository's maintainer can move its `v*` tags.
- **Build and test** from the repository root:
  - `swift test --package-path PrinceSleeplessCore`
  - `scripts/install-xcodegen.sh`, then in `PrinceSleepless/`:
    `../build/tools/xcodegen/bin/xcodegen generate` and
    `xcodebuild -scheme PrinceSleepless -configuration Debug -derivedDataPath ../build/DerivedData CODE_SIGNING_ALLOWED=NO build`.
    The `.xcodeproj` is generated from `PrinceSleepless/project.yml` and not committed.
- **Dependencies:** Dependabot covers GitHub Actions and the core package. XcodeGen, pinned with its
  checksum in `scripts/install-xcodegen.sh`, and Sparkle, pinned by commit in
  `PrinceSleepless/project.yml`, are checked against their latest releases, with the release notes
  read, before each release.
