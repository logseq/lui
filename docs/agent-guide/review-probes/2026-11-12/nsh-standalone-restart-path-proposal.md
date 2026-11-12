# Proposal: retain the standalone executable before whole-app replacement

Status: scope review only; no SDK source or dependency pin changed.
Inspected NSH revision: `adc186db7213f3ccd1eacaa836cc721e9779fd14`.

## Supported API gap

LUI's signed whole-app updater installs through the public `nsh-updater` API.
The supported `nsh_core::element::desktop::restart()` command has no executable
argument. Each desktop runner eventually delegates restart to the SDK's
internal `restart::spawn_after_exit()`.

At this revision, `restart::program_path()` prefers an internally remembered
executable, otherwise calls `std::env::current_exe()` at restart time.
`restart::remember_program()` is called by the SDK's runtime updater, but not by
the public standalone desktop runners. An application using the separate public
updater therefore has no supported way to preserve this path before replacing
its installation. On Linux the old running image can resolve to a deleted path;
on macOS it can resolve inside the displaced bundle. This is a source-confirmed
qualification risk, not a claimed successful reproduction of every OS outcome.

The Rust-visible `nsh_core::restart` module is `#[doc(hidden)]` and explicitly
documents “Runner plumbing, not app API.” Importing it from LUI or Logseq would
cross the supported API boundary. The installation candidate does not do so.

## Minimal proposed change

Have the SDK itself call its existing internal capture at the start of each
standalone `run_app`, before any application root executes:

- `crates/nsh-platform-macos/src/app.rs::run_app`;
- `crates/nsh-platform-linux/src/app.rs::run_app`;
- `crates/nsh-platform-windows/src/app.rs::run_app`, after its existing
  replaced-process wait and before the new root starts.

Keep the existing public restart command, exit lifecycle, original arguments,
environment, working directory, macOS Launch Services handling and Windows
after-exit wait. Add no public function, application-side hidden import,
environment variable, helper process protocol or second restart implementation.
Review whether subsequent internal updater capture should preserve the initial
snapshot rather than overwrite it after a prior replacement.

## Qualification before promotion

Test the internal remembered-path behavior and existing restart command
construction, including paths with spaces and non-ASCII characters. Run platform
compiler/tests on the actual OS runners. Then exercise signed N1-to-N2 whole-app
replacement through the actual application's public update actions, owned
worker preparation and SDK restart. Verify N2 executable, loaded OCaml library,
private worker and durable graph data; do not equate an external driver launch
with SDK restart. Keep production installation disabled until this gate passes.

The HTTPS gate must use normal platform certificate verification. An ephemeral
loopback certificate may be trusted only inside disposable CI runners with
owned cleanup; never modify the developer's system trust or weaken production
TLS/signature validation.

## Authorization boundary

The installed [NSH skill](/Users/tienson/.codex/skills/nsh/SKILL.md) says,
“Do not change NSH to fit an app.” Existing explicit approvals cover earlier
minimal fork repairs, not this runner change. Request scope approval before
implementation; keep the input/capture proposal separate. Once approved,
publish only the reviewed minimal repair to `logseq/nsh` `fork/logseq`, pin an
immutable revision and rerun dependency qualification.
