# OCaml Web desktop host

This host runs an OCaml/Melange frontend in the system WebView. OCaml owns
startup, asset loading, update state, verification and installation. macOS
uses public WKWebView and WKURLSchemeHandler APIs through a small Objective-C++
binding. Linux and Windows use pinned `webview/webview` for WebKitGTK 4.1 and
WebView2. No Go, Rust, Electron
or JavaScript UI framework is shipped. The updater's small DOM controller is
JavaScript; application views and reducers remain OCaml.

Native component rendering is outside this host. Existing Apple/macOS/iOS
and Android packages remain available.

## Build and run

Use Python 3.12+, an OCaml 5 switch, a C++17 compiler and the standalone
dependencies (these do not change the repository's Dune files):

```sh
opam install platform/desktop/lui-desktop.opam --deps-only
npm --prefix platform/web ci
opam exec -- dune build @web
npm --prefix platform/web run build
node tooling/build_web_release.mjs
python3 tooling/desktop.py build \
  --config platform/desktop/components.json \
  --frontend _build/web-release \
  --output _build/desktop/Components.app
open _build/desktop/Components.app
```

Use an output directory without `.app` on Linux and Windows. The builder
refuses an existing directory; each build should have a new output path.
Application identity, platform, version, build number and update public key
are embedded in the executable. `lui-desktop.json` is a copy for tooling,
not an application configuration loaded from the network.

Linux needs `pkg-config`, `libgtk-3-dev` and `libwebkit2gtk-4.1-dev` (or
`libwebkit2gtk-4.0-dev` on distributions without 4.1) to build,
and GTK 3, WebKitGTK 4.1, `curl` and CA certificates at runtime. Windows needs
the native OCaml/MinGW toolchain and WebView2 Runtime. Supply
`--webview2-headers PATH` pointing to `WebView2.h` from
`Microsoft.Web.WebView2` **1.0.1150.38**. Windows headers are not downloaded
or vendored by this repository. macOS needs the Xcode command-line tools and
uses its built-in WebKit. macOS and Windows provide `curl`; Linux packages
declare it as a dependency. No OpenSSL executable is used at runtime.

macOS loads packaged assets directly at `lui://localhost`, with no local TCP
listener. The native bridge accepts built-in desktop actions and explicitly
registered application commands from the main frame of that origin. The update helper owns its own update state and
uses the same custom scheme. Linux and Windows retain the loopback transport
while their native scheme adapters remain pending.

The frontend must be a production bundle with relative asset URLs and an
`index.html` containing `</head>`. The host reserves `__lui/*` and
`__lui-desktop.css`. The Linux/Windows transport serves static assets on a
loopback-only ephemeral port under a random, per-launch 256-bit capability
path. Its mutations require the same Origin and `application/json`. A restrictive CSP permits
local scripts, styles and assets, with inline styles for LUI. Frames,
inline scripts, arbitrary remote connections and form submissions are
disabled. Applications needing remote APIs must explicitly extend this
policy in the host; there is no arbitrary privileged IPC escape hatch.

Only the desktop bundle loads its thin scrollbar stylesheet. The Gallery
uses two columns and omits its phone simulator toolbar in this host. Regular
browser Gallery and mobile rendering retain their existing behavior.

Application code can open the update window without referring to JavaScript:

```ocaml
if Lui_web_desktop.available () then
  ignore (Lui_web_desktop.check_for_updates ())
```

`check_for_updates : unit -> bool Js.Promise.t` resolves `false` in a browser.
The desktop shortcut is Command/Ctrl+Shift+U. The update window runs in an
on-demand OCaml helper. Repeated requests reuse a live helper. Remind Me Later
or closing its window exits the helper and its WebKit session; a later check
starts a fresh one. No updater WebView or helper exists before the first check.
The main application closes its updater helper before exit or replacement.

## Typed application commands

Share a command descriptor between native OCaml and the Melange frontend:

```ocaml
(* app_commands.ml: compiled for both targets *)
let echo =
  let name = Result.get_ok (Lui_command.Name.of_string "app.echo") in
  Lui_command.v ~name ~request:Lui_command.Codec.string
    ~response:Lui_command.Codec.string
```

Register handlers in a native-only module. The initializer runs only in the
main application, never in updater or installer helpers:

```ocaml
(* desktop_app.ml *)
let commands () =
  [Lui_desktop_commands.handle App_commands.echo (fun text -> Ok text)]
```

```sh
python3 tooling/desktop.py build \
  --config platform/desktop/components.json --frontend _build/web-release \
  --ocaml-source /absolute/path/app_commands.ml \
  --commands /absolute/path/desktop_app.ml \
  --output _build/desktop/Commands.app
```

Compile the shared module into your frontend through its existing build. The
builder accepts repeated `--ocaml-source` arguments in dependency order; supply
an adjacent `.mli` when the module has one. `--commands` supplies the native
initializer above. Direct embedders can use `Lui_desktop.run_with_commands`;
the existing `run` entry point registers no application commands.

```ocaml
let echo text = Lui_web_desktop.invoke App_commands.echo text
(* (string, Lui_command.error) result Js.Promise.t *)
```

Descriptors fix request and response types: an incompatible handler or client
argument fails compilation on its actual target. Names are validated lowercase
dot-separated identifiers, at most 128 characters; `lui.*` is reserved and
duplicate registrations fail startup. The host exposes no reflection or
unregistered native method calls.

Codecs encode UTF-8 strings inside a JSON result/error envelope. Built-ins cover
unit (empty string), string, boolean (`true`/`false`) and canonical signed
32-bit decimal integers. Use `Codec.make` for application records and validate
dynamic data in its decoder. A descriptor is a shared contract; it does not
generate a serializer or check that separately deployed versions agree.

Handlers run asynchronously on OCaml worker threads, with at most 16 in flight
per window. They must not call UI-thread-only native APIs directly. The payload
and encoded response limit is 1 MiB each. Unknown commands, invalid arguments
and overload return structured errors before running the handler. Exceptions
become redacted `internal_error` replies. The Melange API resolves errors as
`Error`; an ordinary browser returns `Unavailable`.

The WebKit bridge bounds pending requests at 256 and times out after five
minutes. Closing/navigating the page rejects pending requests and discards stale
native replies. This does not cancel work already running in a handler;
applications own cancellation and side effects. The macOS updater helper has
no application handlers. The optional loopback transport uses its launch
capability for application command calls.

## OS packages

Package on the actual target OS. Build the app, finalize its code signatures,
then produce update artifacts from that final tree. No command uploads files
or publishes a release.

```sh
# macOS: ad hoc signature and local DMG (not a distributable Developer ID build)
python3 tooling/desktop.py package --app _build/desktop/Components.app \
  --output _build/desktop/packages

# Distribution signing and notarization, using existing local credentials
python3 tooling/desktop.py package --app _build/desktop/Components.app \
  --output _build/desktop/signed-packages \
  --identity 'Developer ID Application: Example (TEAMID)' \
  --notary-profile example-notary

# Windows: requires makensis; --thumbprint uses an existing signing certificate
python tooling/desktop.py package --app _build/desktop/Components \
  --output _build/desktop/packages --thumbprint CERTIFICATE_THUMBPRINT

# Linux: requires dpkg-deb and rpmbuild for their respective formats
python3 tooling/desktop.py package --app _build/desktop/Components \
  --output _build/desktop/packages --formats deb rpm pkgbuild \
  --base-url https://downloads.example.com/components
```

macOS signs/verifies the app, submits and staples it when a notary profile is
provided, creates/signs the DMG and submits/staples the DMG. Windows creates a
per-user NSIS installer and signs native executables and the installer when
a certificate thumbprint is provided. WebView2 Runtime is a Windows prerequisite.
Linux emits a tar archive and checksum-pinned `install.sh`, Debian and RPM
packages, and a per-architecture PKGBUILD. Run `makepkg -p PKGBUILD-amd64` (or
`PKGBUILD-arm64`) with the archive beside it. `--formats` can select a subset.

The first-install script installs under `~/.local/opt/<slug>`, creates a
command and desktop entry, and refuses to overwrite an existing install.
Debian/RPM/Arch installations carry `.lui-package-managed`: the application
explains that updates belong to the package manager and never replaces those
managed files itself. User data lives outside the application tree.

## Signed updates and deltas

Create a key outside the repository and put only its public hex value in
the build configuration:

```sh
python3 tooling/desktop.py keygen \
  --private /secure/path/components-update.pem \
  --public /secure/path/components-update.pub
```

```json
{
  "name": "Components",
  "slug": "components",
  "identifier": "dev.example.components",
  "version": "1.1.0",
  "build": 2,
  "updates": {
    "url": "https://downloads.example.com/components/update-darwin-arm64.json",
    "public_key": "<64 lowercase hex characters from the .pub file>"
  }
}
```

Each platform has its own feed. Increment `build` monotonically for every
release; `version` is its human-readable semantic version. Keep the app ID,
slug, architecture and public key stable. In-place signing-key rotation is
not supported. The shipped sample has no update feed and says so when checked.

After OS signing and notarization, generate a full package, optional deltas
against previous finalized application directories and a signed feed:

```sh
python3 tooling/desktop.py release \
  --app _build/desktop/Components-2.app \
  --previous /releases/Components-1.app \
  --key /secure/path/components-update.pem \
  --base-url https://downloads.example.com/components \
  --notes /releases/notes-2.txt \
  --output _build/desktop/update-2
```

Publish artifact files first and the JSON feed last. Preserve old release
trees to generate subsequent deltas. A delta copies unchanged files from
the installed tree and contains changed/new files; removed files disappear
when the complete new tree is reconstructed. These are **file deltas**, not
bsdiff-style binary patches. The CLI omits deltas larger than the full package.
Files are streamed; artifacts are capped at 2 GB and indexes at 8 MB/100,000
files. Application-internal symlinks and nonregular files are rejected.

The feed signs the exact payload bytes, prefixed with `lui desktop update v1\n`,
using Ed25519. It authenticates app ID, architecture, monotonic build,
plain-text release notes, URLs, sizes and SHA-256 hashes. Downloads require
HTTPS, including redirects. Every reconstructed file is hashed, and paths,
aliases, collisions, modes and offsets are validated. A damaged delta, changed
base or reconstruction failure retries the authenticated full package.

When configured, background checks run after 10 seconds and every 24 hours
while the main page is open. Skip persists that build in the user's data
directory. A manual check offers skipped builds again. Remind Me Later closes
the window; it does not schedule another check before the next regular check
or launch. Installation always requires a user action and a restart; there
is no silent auto-install preference in this first host.

The UI shows release notes and download progress. An external copy of the
OCaml executable waits for the old process to exit, renames the complete
installation, and starts the replacement. The previous tree remains until
the new Web frontend loads and acknowledges the expected build. Failed
startup restores and relaunches the previous tree. User data is untouched.
Interrupted swaps leave `.lui-previous` for recovery instead of overwriting it;
the current installer refuses a competing backup. Installation errors are
recorded in `lui-update-install.log` beside the application. The updater
requires write access to the installation's parent directory.

## Verification and current qualification

```sh
python3 -m unittest discover -s tooling/test -p 'test_desktop.py'
python3 -m unittest discover -s tooling/test -p 'test_desktop_commands.py'
opam exec -- dune build @all
opam exec -- dune runtest
npm --prefix platform/web test
```

Local macOS arm64 compilation, actual WKWebView Gallery rendering and an
ad-hoc-signed DMG have been exercised. The regression suite compiles and runs
the actual OCaml update engine with signed feeds and real full/delta trees.
The native lifecycle probe opens/closes the real update helper three times,
checks successful exit and checks that newly created WebKit processes end:

```sh
LUI_DESKTOP_TEST_APP=/absolute/path/Components.app/Contents/MacOS/app \
  python3 -m unittest discover -s tooling/test -p 'test_desktop_window.py'
```

The installed-upgrade qualification builds an ad-hoc-signed fixture, installs
it from a DMG outside the checkout and drives the actual updater over local
HTTPS. Its application frontend and appended updater automation are fixtures;
native host and update-engine sources are unchanged. It checks full/delta
replacement, damaged-delta fallback, invalid-signature refusal, failed-start
rollback, finalized-tree hashes, code signatures and preserved user data:

```sh
python3 tooling/qualify_desktop_macos.py \
  --output _build/desktop/macos-qualification
```

Developer ID/notarization requires the application's credentials. Windows and
Linux native compilation, installed application upgrades, package-manager
installation and production signing still require target-system qualification.
The implementation must not be described as production-qualified on those
platforms solely because package-generation commands exist.
