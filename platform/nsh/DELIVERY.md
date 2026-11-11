# Desktop delivery

The delivery command packages the compiled Rust runner and its matching OCaml
library together. Run it on the operating system being packaged. Python 3.11+,
Node, Git, the project's Rust toolchain and the platform's native build tools
are required. Apple/iOS, Android and Web use their maintained delivery paths.

## Pinned toolchain

Build the CLI from a clean checkout of the same immutable NSH revision as the
app's `Cargo.toml`. The repository URL and full commit are read from that
manifest; a branch name, a short SHA or mixed NSH sources are rejected.
The published migration pin is
[`028574b7de9ee25a7c6f60660ef72fcb8790a27e`](https://github.com/logseq/nsh/commit/028574b7de9ee25a7c6f60660ef72fcb8790a27e).
The checkout must be clean at this commit. Read the manifest again when the
dependency is deliberately upgraded; a previously built CLI receipt then
requires regeneration.

```sh
export PATH="$HOME/.cargo/bin:$PATH"
RUSTUP_TOOLCHAIN=1.97.0 python3 tooling/nsh_delivery.py setup \
  --checkout ../nsh
```

This installs only into `platform/nsh/.nsh/toolchain/`. It does not replace a
system CLI or Cargo. Its receipt records the source revision, CLI version and
binary digest. Every subsequent delivery command checks that receipt. NSH's
`--nsh-source` option belongs to `nsh init`; it is not a packaging option at
the pinned revision. Delivery verifies the actual Cargo dependency graph,
including the generated `.nsh/rust` workspace, after NSH's path patching.
Registry NSH crates and checkouts at another revision are rejected.
The generated runner starts from the application's tested `Cargo.lock`.
Shared registry dependencies must retain their tested name, version and
source, and the generated lock must stay unchanged during packaging. A
feature-unification change that needs another version stops delivery and
requires requalifying the application lock. It is not accepted merely by
recording a different generated lock hash.

On macOS, delivery subprocesses inherit `CARGO_PROFILE_RELEASE_STRIP=none`,
including the CLI's generated-runner builds. This avoids the Mach-O
`mis-aligned LINKEDIT string pool` proc-macro loading failure tracked in
[Rust #157750](https://github.com/rust-lang/rust/issues/157750) and
[LLVM #203678](https://github.com/llvm/llvm-project/issues/203678). The original
release CLI build failed loading `rquickjs_macro`; the no-strip rebuild passed
that compilation stage on the same source pin. Release optimization and warning
settings are preserved. CLI and package receipts record the strip setting.
Linux and Windows retain their existing environment settings.

## Complete application packages

Build the OCaml application first. Its existing build receipt must match its
current sources; missing or stale receipts are rejected. The package command
accepts a library produced by another application using the same receipt tool.
The library is checked again after the runner build, and its copied bytes
must match the artifact digest originally verified. Changing application
manifests or either Cargo lock during packaging prevents release publication.
A Windows application must currently supply a DLL built by its Windows OCaml
native toolchain; the Unix helper does not establish Windows support.

```sh
library="$(bash tooling/build_nsh_todos.sh)"
RUSTUP_TOOLCHAIN=1.97.0 python3 tooling/nsh_delivery.py package \
  --library "$library" --output _build/nsh-packages
```

Use `--target macos`, `--target linux` or `--target windows` to make the target
explicit. The command refuses cross-OS packaging. `--arch aarch64`,
`--arch x86_64` and `--arch universal` select macOS architectures; universal
packages need a universal OCaml library and universal dependent libraries.
Linux and Windows use the native host architecture. Actual Mach-O, ELF and PE
headers are checked, rather than trusting the filename.

Add each non-system dependent native library with `--dependency PATH`. Add a
resource with `--asset SOURCE=relative/destination`. Paths containing spaces
and Unicode are passed as arguments, and asset paths cannot escape the
resource directory. macOS non-system dependency links are relocated to the
copied libraries with `@loader_path` before signing; unresolved development
paths are rejected. Linux dependent libraries must already have a suitable
`$ORIGIN` search path, and Windows loading must search the packaged DLL's
own directory. Native platform qualification must check the complete dynamic
library closure on the supported OS baseline.

The installed library paths are:

| Target | OCaml library |
| --- | --- |
| macOS | `<App>.app/Contents/Resources/lui/liblui_app.dylib` |
| Linux | `<App>/lui/liblui_app.so` |
| Windows | `<App>/lui/lui_app.dll` |

Dependent libraries sit beside the OCaml library, assets under `lui/assets/`.
No development-only library environment override is required. Delivery refuses
`LUI_OCAML_LIBRARY`, `NSH_RUNTIME` and `NSH_RUNTIME_DIR` overrides while building
a package. Launch the completed application from outside the checkout during
qualification.

For a package containing the real Todos OCaml application, run the native launch
gate after packaging:

```sh
python3 tooling/test_nsh_packaged_app.py _build/nsh-packages \
  --logs _build/nsh-packaged-qualification
```

Pass the completed application directory, or an output directory containing
exactly one complete package. The helper discovers the executable and library
from the in-package delivery receipt, starts the executable directly with a
temporary working directory outside the checkout, and removes development
library/runtime overrides and dynamic-library search overrides. A numeric
loopback `LUI_AGENT_LISTEN` address enables the existing public agent protocol.
The helper waits for its versioned hello, types a unique Todos draft, presses
Add, and requires exactly one matching row and an empty draft in the final
runtime tree. It then closes the agent and terminates the owned process within
a bounded deadline. `--timeout` controls startup and the agent flow; process
cleanup allows five additional seconds before forced termination.

The logs directory receives stdout, stderr, agent requests/replies, the final
tree and a JSON result, including failure details. It must be outside the signed
package. This gate qualifies packaged startup, native-library loading and public
runtime actions; it does not qualify pointer hit testing, visual appearance,
production signing credentials, or updater installation. The helper's Python
protocol fixtures test orchestration only. A successful run against the actual
native package is required as separate qualification evidence.

The in-package `lui-delivery.json` records source pins, lockfile hashes,
architectures, OCaml source hashes and input-library digests without developer
absolute paths. An external receipt records final archive/runner hashes and
signing status. Existing releases are not overwritten: use a new version or a
fresh output directory. Interrupted publication without its final receipt is
not eligible for manifest signing.

NSH first creates its platform package. LUI then copies the library/resources,
finishes signing and rebuilds the final archive. The early NSH archives and
installers are staging artifacts and are not published. This prevents an
update archive from omitting a library added after NSH's first package step.

## macOS distribution signing

With no identity, the complete package is signed ad hoc and verified locally.
Ad hoc signing does not establish distribution trust.

```sh
RUSTUP_TOOLCHAIN=1.97.0 python3 tooling/nsh_delivery.py package \
  --library "$library" --target macos \
  --macos-identity "Developer ID Application: Example Inc (TEAMID)" \
  --entitlements path/to/application.entitlements \
  --notary-profile release-notary \
  --output _build/nsh-release
```

Nested native libraries and the executable are signed before the application
bundle. Developer ID signing uses the hardened runtime and secure timestamps;
the application's entitlements are applied at bundle signing. With no explicit
entitlements file, the file produced by NSH from `nsh.json` is reused when
present. The command verifies signatures, submits a temporary ZIP through
`notarytool`, staples and validates the ticket, and asks Gatekeeper to assess
the completed bundle before creating update archives. Configure the named
notary keychain profile outside the repository. Credentials and private keys
do not belong in `nsh.json` or receipts.

## Windows signing and installer

Run in the native Windows build environment. The DLL, dependent DLLs,
executable and final installer can use a certificate already installed in the
signing environment:

```sh
python tooling/nsh_delivery.py package --target windows \
  --library path/to/lui_app.dll \
  --windows-thumbprint CERTIFICATE_THUMBPRINT \
  --timestamp-url https://timestamp.example.com \
  --iscc "C:/Program Files (x86)/Inno Setup 6/ISCC.exe" \
  --output _build/nsh-release
```

`signtool` signs SHA-256 and verifies each signature. Supply its path with
`--signtool` when it is not on `PATH`. Inno Setup is found on `PATH` or in its
usual installation locations, or selected by `--iscc`. Its NSH-generated
script is compiled again after resource copying and code signing. The final
installer is then signed and verified. Without Inno Setup, the directory and
ZIP remain available, and no installer is claimed. Without a certificate,
artifacts are explicitly recorded as unsigned.

## Signed whole-application updates

Configure the application-owned endpoint and public key in `nsh.json` before
packaging. The following is a configuration example, not a working endpoint:

```json
{
  "updater": {
    "url": "https://downloads.example.com/lui/latest.json",
    "publicKey": "BASE64_UPDATE_PUBLIC_KEY"
  }
}
```

Use the pinned CLI's `keygen` command to create local test keys outside the
repository. Keep production signing keys in release CI. Do not configure
`updater.packages`: Rust and OCaml changes travel together as a full native
application update.

After every target package is final, sign its manifest:

```sh
python3 tooling/nsh_delivery.py manifest \
  _build/nsh-release/LUI-Desktop-0.1.0-macos-aarch64.tar.gz \
  --key path/to/update.secret --notes path/to/changes.md \
  --base-url https://downloads.example.com/lui/0.1.0 \
  --output _build/nsh-release
```

Only archives with matching complete-application receipts and hashes are
accepted. Upload the final archives, `latest.json` and `latest.json.sig`
together. Creating a signed manifest does not by itself enable a Rust app's
runtime update flow; the application must use the updater adapter and own
its check/download/install/restart actions.

## Verification and current limits

```sh
python3 -m unittest tooling/test/test_nsh_delivery.py -v
```

Portable tests inspect actual tar/ZIP payloads, receipts, architecture
rejection and source-pin checks. macOS additionally compiles a native fixture
with a dylib dependency, relocates and signs it with real tools, deletes the
original libraries and launches it outside the checkout. Signing/notarization
and Authenticode command-order tests use mocked external tools.

These tests do not establish that the full LUI NSH package has launched on
every desktop target. Native Linux/Windows packaging, production Developer ID
and Authenticode credentials, notarization, installed application updates and
N-to-N+1 restarts remain qualification gates until those commands actually
run. A dry run or an ad hoc signature must not be reported as credentialed
production distribution evidence.

At the published migration pin, the LUI Rust verification recorded 44 passing
tests and strict Clippy success, including the updater's native test-key
installation fixture. That fixture verifies an N-to-N+1 native executable and
library replacement; it does not establish an installed LUI package update.
The delivery and packaged-agent Python suites contain 20 passing cases,
including real macOS dependency relocation, ad hoc signature verification and
native fixture launch. The actual recipe below also passed on arm64 macOS:
the release CLI and native runner built, the final `.app` passed ad hoc signing
verification, and the completed package launched outside the checkout without
development overrides. Through its real public agent, Todos accepted a unique
draft, added exactly one matching row and cleared the editor. Evidence is in
`_build/nsh-packaged-qualification-028574b7/`; the exact package/source digests
are recorded in the adjacent release receipt and the migration plan.

## Native macOS Todos qualification recipe

Run these commands from the LUI checkout after the final adapter checks.
Serialize builds sharing a Cargo target directory and serialize Dune calls;
independent target directories can build concurrently within available memory.
The current native target is arm64 macOS;
this recipe does not establish Linux or Windows qualification.

```sh
export PATH="$HOME/.cargo/bin:$PATH"
export RUSTUP_TOOLCHAIN=1.97.0
unset LUI_OCAML_LIBRARY NSH_RUNTIME NSH_RUNTIME_DIR

python3 tooling/nsh_delivery.py setup --checkout ../nsh
nsh_todos_library="$(bash tooling/build_nsh_todos.sh)"
node tooling/lui_build_receipt.mjs check --artifact "$nsh_todos_library"
nsh_package_output="_build/nsh-packages-028574b7"
python3 tooling/nsh_delivery.py package --target macos --arch aarch64 \
  --library "$nsh_todos_library" --output "$nsh_package_output"
python3 tooling/test_nsh_packaged_app.py "$nsh_package_output" \
  --logs _build/nsh-packaged-qualification-028574b7
```

Use a fresh output directory for a retry after a published package; delivery
refuses replacement of an existing release. Keep the checkout, app manifests,
OCaml sources and generated runner lock stable throughout the build. Both the
installed CLI and CLI-launched Cargo require the Rust toolchain on `PATH`.

Required inputs are the clean NSH checkout and its committed `Cargo.lock`,
LUI's tested `platform/nsh/Cargo.lock`, `Cargo.toml` and `nsh.json`, and the
OCaml Todos library plus its adjacent `.lui-build.json` receipt. Setup creates
`platform/nsh/.nsh/toolchain/nsh-cli-receipt.json`; packaging verifies that
receipt before invoking the CLI. The currently built macOS Todos library
depends only on the system `libSystem` and requires no extra `--dependency`
argument. Recheck `otool -L` if its native dependency closure changes.

Python 3.11+, Node, Git, OCaml/opam and Xcode's native tools must be available.
On the Apple M6 / 24 GiB macOS 27.2 reference machine, the successful unstripped
CLI release build took 7 minutes 21 seconds and the native runner release build
took 3 minutes 51 seconds. Available disk space changed from approximately
44 GiB to 36 GiB during the build/test sequence, including registry downloads
and concurrent checks; this is not an isolated peak-allocation measurement.
Cold builds and other machines can differ. Existing debug artifacts do not
remove the need to compile release profiles. The final
artifacts are the complete `.app`, rebuilt tar archive, external release
receipt and the separate qualification logs. With these arguments signing is
ad hoc; no production signing, notarization, update URL or private key is
configured or claimed.

## Rust update lifecycle

`lui_nsh::update::Updater` owns one worker and one `ureq` client. Clone its
handle to share it; create it once in application state. Read the updater
configuration packaged at `nsh/assets/nsh-updater.json` (under
`Contents/Resources/` on macOS), and pass the actual installed executable and
an application cache directory outside the installation:

```rust
use lui_nsh::update::Updater;

let updater = Updater::open(&configuration_bytes, &installed_executable, &cache)?;
let mut progress = updater.progress();
if let Some(offer) = updater.check().await? {
    if offer.can_install() {
        let download = updater.download(offer).await?;
        updater.install(download).await?;
        // The application decides when to restart after installation succeeds.
        nsh_core::element::desktop::restart();
    }
}
```

Run these futures in application-owned NSH tasks. The UI and engine threads
never wait for disk installation or network reads. The application displays
errors and decides when to check, download, install and restart; the adapter
does not add an idle polling timer or restart by itself. `progress.changed()`
wakes on a new state; the watch channel retains only the latest value and
coalesces download notifications to approximately ten per second.

Only matching installed configurations are admitted. A development host,
unsigned manifest configuration or TSX package update configuration is
rejected. Manifest and signature metadata are limited to 1 MiB and 4 KiB.
Archives require a signed SHA-256 and size of 1 byte through 2 GiB, and stream
through a 64 KiB buffer into a private cache file. The runtime accepts HTTPS,
including redirects, with system trust verification. It has finite DNS,
connection, response-header and per-read deadlines. It does not buffer a
complete archive in memory.

`Offer` and `Downloaded` are opaque, instance-bound tokens. A newer check
invalidates previous offers; a foreign or stale token cannot install an
unrelated download. The archive is checked again immediately before invoking
NSH's installation transaction. Failed/cancelled downloads remove partial
files, and failed verification leaves the installed application unchanged.
NSH owns archive extraction, application-ID/executable checks, macOS signature
verification and replacement/failure recovery. The signed release pipeline
ensures archives contain both compiled halves and their release receipt.

`cancel()` invalidates pending checks and downloads. A currently blocked read
returns by its 15-second deadline; cancellation is checked between chunks.
Installation is indivisible once it begins, so the UI must stop offering
cancellation while installing. Dropping the final updater handle cancels work
and closes the worker's queue without joining a network thread on the UI
thread. The worker removes its cache after the active read finishes.
Queued operations whose calling future was dropped are skipped before they
start; a cancelled queued install cannot replace the application later.

The request queue has eight entries. Excess work returns `ErrorCode::Busy`;
other typed errors distinguish configuration, transport, verification,
installation, cancellation, stale tokens and stopped workers. Production
applications should normally allow one update action at a time.
