# Actual Logseq NSH whole-application updates

## Scope and source baseline

This is a source audit and implementation sequence, not update qualification.
No application, installer, signing operation or update was run for this audit.
The inspected revisions are:

| Repository | Revision |
| --- | --- |
| Logseq, `refactor/lui` integration | `71e72b56b2f308721aedea9b4ee44f0af9cebad2` |
| LUI provider | `71829581408c8bab6bda1e96aaeae8bcf9264105` |
| NSH, authorized fork | `bfa15d0c843c0d6f5bf3a2a230e8ca56b876b61c` |

Paths below are relative to the named repository. The target is replacement of
an installed desktop application on macOS, Windows and Linux, including its Rust
host, OCaml library, database worker and resources. A TSX package, UI asset update
or replacement of only the OCaml library cannot fulfill this target. Maintained
Web, Apple/iOS and Android backends and Electron's separate updater are outside
this cutover.

## What the actual application currently mounts

Logseq `deps/ui/nsh/src/lib.rs` mounts its services, extension registry and
`lui_nsh::app::desktop()`. It does not create an updater. Its
`deps/ui/nsh/nsh.json` selects `App`, identifies `com.logseq.logseq`, and has no
`updater` source or public key. It currently says version `0.1.0`, build `1`,
whereas `resources/package.json` says `2.0.2`. The real UI version flows through
`deps/ui/src/shared/version.ml` and generated `Version_gen.app` from the latter.

`deps/ui/src/settings/settings_page.ml`, `version_row`, renders the version and
changelog link. Its `cp__settings-app-updater` class does not provide a check,
download or install action. `deps/ui/nsh/src/services/menu.rs` owns the native
application menu; `deps/ui/native/menu_commands.ml` supplies translated labels
and handles reload, sidebar and documentation commands. The native service
switch in `deps/ui/nsh/src/services/mod.rs` has no update operation.

The Electron implementation is separate:
`deps/db-worker/desktop/electron_updater.ml`, initialized by
`deps/db-worker/desktop/electron_main.ml`, uses `electron-updater` and IPC
`check-for-updates`, `install-updates`, `get-downloaded-update`,
`updates-callback` and `auto-updater-downloaded`. It has its own `auto-update`
preference and production automatic-check policy. Those handlers do not become
NSH services merely because the native application also has a database worker.

## Existing updater to reuse

LUI `platform/nsh/src/update.rs` already provides the public application-owned
`Updater`, `Offer`, `Downloaded`, progress and error APIs. `from_installed` reads
the installed configuration; `open` requires a matching installation. One worker
and HTTP agent perform bounded metadata reads and streamed downloads, manifest
signature verification and archive size/hash verification. NSH's
`crates/nsh-updater/src/install.rs` owns archive installation; public
`nsh_core::element::desktop::restart()` owns native restart.

LUI rejects unsigned configurations and `updater.packages`: this path requires
signed whole-application updates. A development host with no installed updater
asset does not start an updater worker or network request. Preserve that rule.

LUI `platform/nsh/src/desktop_updates.rs` already implements check, cancellation,
download, confirmation and install/restart actions, but it is private and
replaces the application menu. `platform/nsh/src/lib.rs::DesktopApp` mounts that
menu. Replacing the actual Logseq root with `DesktopApp` would lose its typed
Logseq bridge, registered factories and services; mounting both menu owners
would overwrite one menu with the other. Reuse the public updater service and,
where practical, extract the existing action UI into a menu contribution that
Logseq's current menu owner installs. Do not add another downloader, worker,
cache, signature implementation or global menu owner.

## Current package is incompatible with the NSH installer

Logseq `deps/ui/scripts/package-nsh.sh` and `package-nsh.mjs` produce a qualified
actual application archive, but not an NSH updater installation:

| Target | Current layout | Installer requirement and consequence |
| --- | --- | --- |
| macOS | `Logseq NSH.app/Contents/MacOS/{Logseq,logseq-nsh}` and `Contents/Resources/` | Bundle root is usable, but `Contents/Resources/nsh/app.json` and `Contents/Resources/nsh/assets/nsh-updater.json` are absent. |
| Linux | `Logseq-NSH/bin/{logseq,logseq-nsh}` and `Logseq-NSH/Resources/` | `Installation::of` takes the executable's parent as the installation root. Treating `bin` as the root would exclude the OCaml library, worker and resources from replacement; required `bin/nsh` metadata is also absent. |
| Windows | Native DLL build candidate exists in `deps/ui/nsh/build_windows_dll.py`. | No complete qualified Windows package/update path exists in this baseline. |

NSH `crates/nsh-updater/src/install.rs::Installation::of`, `package_id` and
`resources` require matching configuration bytes and app ID at the canonical
`nsh` locations. Merely adding a manifest URL to the current package does not
make installation valid. `Installation::directory` is public, but LUI's current
`Updater::open` intentionally uses the installed-package checks; bypassing those
checks is not the proposed integration.

Use a canonical updater root containing the complete app. Preserve macOS's
bundle structure. For Linux/Windows, placing the native executable at that root
can retain an app-owned `Resources/` subtree while making the whole directory
the replacement unit. Update actual library, worker and launcher resource-path
resolution together: Logseq `deps/ui/nsh/src/lib.rs::library_path`,
`deps/ui/native/daemon_client.ml`, and `deps/ui/scripts/launch-nsh.sh` currently
rely on the executable-relative `../Resources` convention. Qualify without
library/worker/resource environment overrides.

LUI `tooling/nsh_delivery.py` provides useful signing, receipt and manifest
machinery, but its generic payload copier hardcodes `liblui_app`/`lui_app.dll`
and `lui/assets`. It cannot replace the actual Logseq package recipe unchanged.
Preserve the real `liblogseq_ui`/`logseq_ui.dll`, database worker, fonts, images,
dictionaries, theme assets and all receipt-owned resources. Retain the actual
staged startup gate and source/final-artifact receipt checks.

## Implementation sequence

1. **Unify release identity and layout.** Use one authoritative version source
   for displayed version, updater configuration, package metadata and manifest.
   Preserve `com.logseq.logseq`; reconcile `nsh.json` with the existing
   `resources/package.json` source. Package the full actual application under a
   canonical installer root and write its matching `nsh/app.json` and
   `nsh/assets/nsh-updater.json` before signing. Keep production updater absence
   explicit until a real source and key are configured.
2. **Attach application-owned actions.** Open the existing `Updater` once in
   the actual App's owner and contribute actions to Logseq's existing menu.
   Reuse existing confirmation/error/progress behavior. Release owner-scoped
   subscriptions and cancel outstanding work at teardown. Check/download/install
   must not create permanent polling or touch an unrelated application's menu.
   Decide and document whether the Electron automatic-check preference should
   also apply; do not silently infer an implemented automatic-check policy.
3. **Finalize platform archives.** Keep macOS nested-code signing, hardened
   runtime, optional notarization and stapling in the existing packager. Sign
   Windows executable/DLL/worker and installer where applicable. Linux archives
   need an explicit native-library/distribution policy. Finalize all code and
   stapling before hashing and generating release receipts or manifests.
4. **Generate the signed release manifest with the pinned NSH CLI.** Reuse
   `crates/nsh-cli/src/updater.rs` / `nsh update-manifest`, not a second manifest
   or signing implementation. It expects
   `<name>-<version>-<os>-<arch>.zip` or `.tar.gz`; current version-last
   `Logseq-NSH-darwin-arm64-2.0.2.zip` naming is incompatible. Use NSH platform
   names such as `macos-aarch64`, `windows-x86_64`, `linux-x86_64` and the
   architectures actually shipped. Manifest hashes must describe the final
   archives containing every compiled half and resource.
5. **Qualify actual Logseq N to N+1.** Only after the following acceptance gates
   pass should this integration be described as working whole-app updates.

## Required external inputs

The release owner must select the actual HTTPS feed or GitHub release location,
Ed25519 public key embedded in installed packages, and protected offline/CI
release signing key. No example URL, fixture key or temporary test identity is a
production input. Distribution signing additionally needs existing macOS
Developer ID/notary credentials and Windows Authenticode/timestamp configuration.
The public update-signature key and OS signing identities have different jobs.
Unsigned/ad-hoc local evidence does not establish distribution trust.

## Actual N to N+1 acceptance

- Build and stage two actual Logseq releases with distinguishable Rust, OCaml
  and worker/resource receipts. Both must pass the existing real application
  startup/body gate with private graph data and isolated credentials.
- Launch installed N outside the checkout without development library, worker
  or resource overrides. Through the actual native action, authenticate the
  signed manifest, download the correct platform archive and verify its hash
  and size before installation. Test rejection of tampered metadata/archive,
  wrong app/platform, stale offers and cancelled downloads without replacing N.
- Confirm installation, quit through NSH's native lifecycle, and restart N+1
  through the platform restart path. Observe a real dated journal/body and the
  retained application data, not just an agent hello or a version label.
- Check installed final hashes for Rust host, OCaml library, worker and owned
  resources, matching the N+1 receipt. Verify native signing and the relevant
  OS distribution checks independently on macOS and Windows. Qualify writable
  installation behavior and permission-denied behavior on each target.
- Run the test on actual macOS, Windows and Linux package layouts. An installer
  source recipe or cancelled CI job is not qualification.

The audited `.github/workflows/nsh-desktop.yml` builds, packages and checks
outside-checkout packaged startup on macOS/Linux; it does not run upgrades.
LUI `tooling/qualify_nsh_upgrade.py` is reusable evidence and orchestration, but
its existing fixture uses local signed assets and an external driver-managed
quit/restart. It explicitly does not qualify HTTPS, native update-menu actions
or platform-managed restart, and its generic application ABI cannot substitute
for actual Logseq's seven-argument bridge and services.
