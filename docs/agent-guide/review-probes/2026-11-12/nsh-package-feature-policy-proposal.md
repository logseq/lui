# NSH package feature-policy proposal

Status: the minimal CLI correction is published on the authorized `fork/logseq`
branch as `adc186db7213f3ccd1eacaa836cc721e9779fd14` and selected by LUI's immutable
NSH dependency pin. The focused regressions, 218 CLI unit tests and strict
all-target Clippy passed; three unrelated Web/benchmark cases remain intentionally
ignored. A fresh macOS package now passes the complete wrapper and strict
generated-manifest/lock guards. Outside-checkout launch, upgrades and other
desktop targets remain unqualified at this checkpoint.

## Observed failures

The last published LUI checkpoint `7dccfb65a9274fa0ff8651b9e91b9c364efb339a`
failed its [NSH desktop workflow](https://github.com/logseq/lui/actions/runs/43161886990):

- [macOS package job](https://github.com/logseq/lui/actions/runs/43161886990/job/130994784923):
  generated runner lock changed during packaging. Upgrade qualification was
  skipped after that rejection.
- [Windows package job](https://github.com/logseq/lui/actions/runs/43161886990/job/130994785290):
  the same generated-lock rejection, before outside-checkout launch.
- [Linux package job](https://github.com/logseq/lui/actions/runs/43161886990/job/130994785417):
  `javascriptcore6-sys` could not find `javascriptcoregtk-6.0 >= 2.40.0` through
  pkg-config while packaging a Rust-root application.

These logs belong to the earlier published NSH pin. The relevant CLI policy and
workspace-generation sources were unchanged between that pin
`ea23ae9cd5f56426145ea225f1a220e1eca0d3a2` and the pre-correction dependency
`2635333e4cc0d3be8032c97f3a5e08d3685179c6`.

## Source cause and narrow correction

The pinned CLI's `main.rs` enables `RustApp::unify_features` for a package
targeting the host OS, whereas `nsh build` leaves it off. The generated
`hack/Cargo.toml` therefore changes between the wrapper's build and package
commands. `rust_app.rs` explicitly documents that package commands should leave
this development feature-unification crate empty.

The package-mode unification uses workspace metadata that includes development
hosts. Linux's host enables WebKit, which in turn requests JavaScriptCore's
system library. The generated Rust-only release runner itself explicitly
disables default features and does not request WebView or JS. Installing WebKit
to satisfy this unintended development feature union would obscure the Rust-only
shipping boundary. This is not evidence that the standalone CLI executable or
the intended Rust runner needs an additional JavaScriptCore dependency.

Correction `adc186d` removes only the package-specific unification exception. Public `nsh build`
and `nsh package` then select the same existing empty-hack generation policy.
Test, run and development-command policy remains unchanged. Regression source
checks the actual parsed command policy for Rust-root and mixed entries across
all desktop targets, plus generation stability after clearing a cached
development hack. No new CLI flag, manifest generator, Cargo interception shim,
dependency tree or package-lock bypass is added.

The LUI wrapper independently retains its generated-lock equality check and adds
manifest equality checks before publishing final archives. Expected lock or
manifest hashes are never refreshed after the package command. Existing pinned
CLI receipts remain authoritative. The published correction was reviewed against
`2635333`, tested in isolation and added to the authorized fork; no extra public
API or application-specific SDK behavior was introduced.

## Required verification

- Run the focused CLI policy and empty-hack regeneration tests, then the required
  NSH checks at the proposal revision.
- Verify a fresh CLI build/package pair leaves the complete generated manifest
  set and lock unchanged, using the wrapper's existing strict checks.
- Requalify real native macOS, Windows and Linux packages, followed by the
  outside-checkout launch and whole-app upgrade gates. The three failed remote
  jobs above remain failed historical results until fresh native jobs pass.
- On Linux, confirm the intended Rust runner's resolved features exclude the
  development-only WebView/JavaScriptCore path rather than accepting an extra
  application runtime requirement.

## Fresh macOS package result

On 2026-11-12, the actual delivery wrapper completed successfully with the clean
`adc186db7213f3ccd1eacaa836cc721e9779fd14` checkout and its rebuilt CLI receipt:

```sh
python3 tooling/nsh_delivery.py setup --checkout /absolute/nsh
bash tooling/build_nsh_todos.sh
python3 tooling/nsh_delivery.py package \
  --library /absolute/lui/_build/default/examples/todos/native/liblui_todos.dylib \
  --output _build/nsh-current-package
codesign --verify --deep --strict --verbose=2 \
  '_build/nsh-current-package/LUI Desktop.app'
```

The CLI built the actual arm64 Rust-root macOS runner and the wrapper completed
without refreshing or bypassing the generated manifest/lock comparisons. Strict
signature verification passed for the final development ad hoc bundle. Logs are
local ignored evidence: `/tmp/lui-current-delivery-setup.log`,
`/tmp/lui-current-todos-build.log`, and `/tmp/lui-current-package.log`.
The receipt is
`_build/nsh-current-package/com.logseq.lui.desktop-0.1.0-macos-receipt.json`.
Runtime inputs match LUI `20fc6fbb`; subsequent commits before completion changed
documentation only.

| Receipt item | SHA-256 |
| --- | --- |
| CLI | `fff1937e1203ca12d363f341c038cb81cbc8991b21705f3061f019eae4b99b66` |
| Application Cargo lock | `2cf9e430aee832bab3d5686e099015ff82552d550056c7bb9b71951dbeae3fbb` |
| Generated runner lock | `ca0192480500e2fda4281d0e2c9b5e7b954eaac4504c44a73f9eb4163fabd2a1` |
| Final native runner | `a67b28b142bea2ae3f88541166e4ec506486b532dbeb7545a3edd4b36e8eb350` |
| Final tar archive | `b721e3341f0880e54c4437a5639ce5e8a24963b12f20e2c82e080473b0c8bdea` |

This proves the previously failing macOS packaging boundary with the corrected
CLI. It does not prove launch, UX, production signing/notarization or update
installation. No package was launched locally because the standalone launcher
does not expose the actual application's background qualification policy; the
developer's screen and running Logseq session were left unchanged. Actual
outside-checkout launch and upgrade remain CI gates, as do Windows/Linux builds.
