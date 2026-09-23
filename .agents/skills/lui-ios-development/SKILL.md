---
name: lui-ios-development
description: Develop and debug LUI apps on iOS/macOS with the Apple backend — schema vocabulary limits, extension child rules, emit-error diagnosis, dyn remount render loops, OCaml-5 multi-domain threading hazards, iOS simulator entitlements/keychain, and V.Sheet presentation freezes.
---

# LUI iOS/Apple development

Hard-won rules for building LUI applications that run on `LUIAppleBackend`
(iOS simulator/device, macOS). Each item is a symptom-to-fix pair observed in
production migration work.

## Emit/patch errors → blank screens, never crash loud

`emit_patch` (the OCaml→host patch stream) returns 0 on exception: a schema
violation mid-emit yields a *partial* op stream and the host renders whatever
mounted before the throw — typically a blank or half-blank screen with **zero
error output**.

- Diagnose by printing `caml_format_exception` in the host's emit bridge and
  checking whether the emitted op count per extension node matches what the
  Swift/Flutter view expects.
- Runtime validation errors carry details only when built with detailed
  messages (kind/property/value and parent/child kinds). If you see bare
  `invalid_arg "invalid property value"` / `"unsupported child kind"`, you're
  on a build without them — upgrade; the detail version names the offending
  kind, property, and value directly.

## Schema vocabulary limits (throw inside `set_prop`)

Property *values* are closed vocabularies — unsupported values throw during
emit:

- `RoleValue`: `treeitem | navigation | navigation-heading` only. Toolbar
  placement strings (`bottom_bar`, `principal`…) are NOT roles.
- `VariantValue`: `default | primary | secondary | outline | ghost |
  destructive`. (`plain`→`ghost`, `prominent`→`primary`.)
- `list-item` requires a label/text or at least one mounted child — bare
  list-items throw on the backend.
- **`press-enabled`**: list-item/menu-item rows are inert without
  `PressEnabled` (`supportsPress` gates `performListItemPrimaryAction` in the
  Apple backend). Buttons don't need it; list rows do — without it taps are
  silently swallowed.

## Empty nodes mount NOTHING — extension children are positional

`V.empty ()`/an absent child produces no node on the host. Host views that
address children **by index** break: e.g. a chrome component requiring exactly
N children renders `EmptyView` when it gets N−1. Absent slots must still mount
a real (possibly zero-size) container node as a placeholder.

## Extension schema: `standardChildren` + children whitelist must match reality

An extension node's declared schema must match what the app actually mounts:

- Mounting standard children under an extension declared
  `standard-children:0` → `unsupported child kind` at emit.
- The `children` whitelist (which extension kinds may nest under this one) and
  `standardChildren` flag are baked into the component **fingerprint** — and
  the fingerprint is computed independently on each host (Swift, Flutter) and
  in the OCaml registry. All three must stay in sync or one platform emits
  while the other rejects.
- Keep the schemas OCaml-declared once (see `examples/gallery/extension_schemas.ml`);
  host files carry only the `fingerprint:` literals. `Lui_extension_check.check_registry`
  extracts every `lui-extension-v1|`/`lui-tweak-v1|` literal from the host
  registration sources and compares it to the canonical fingerprint the OCaml
  registry emits — run it under `dune runtest` (`test/test_lui.ml`,
  "extension fingerprints") so drift fails CI instead of blanking a screen.
  The reported `expected` value is the corrected literal to paste back.

## `dyn` remounts the whole tree on every publish → render loops

`Lui_elements.dyn` remounts its ENTIRE view subtree on every published model
change under its `?equal` — the default `equal` is `(fun _ _ -> false)`
(always remount). Mount-time emitters turn an always-remount `dyn` into a
~10 Hz infinite loop:

- fresh `SecureField`/`Input` fire `TextChanged("")` on mount;
- extension views with `.task` handlers (e.g. an on-appear settings refresh)
  fire their event on every mount;
- reducers that rebuild an identical record keep republishing.

Defenses:

- **`dyn ~equal:` (first line)**: pass a structural or field-wise equality —
  `dyn ~equal:(=) f model_source` for immutable record models, or a narrower
  compare on just the fields the branch reads — so the subtree stays mounted
  when a publish doesn't change this branch. `equal` compares model values
  before `f` runs (and `f` only recomputes on real remounts).
- Value-echo dedup is built in: `Lui_runtime.dispatch` drops
  `TextChanged`/`ToggleChanged`/`ValueChanged` events whose payload equals
  the property last sent to the host (or the unset default `""`/`false`/
  `0.0`), so a mounted control re-reporting its bound value no longer
  reaches the reducer. Genuine edits still deliver. (`Appear`/`ExtensionEvent`
  echoes have no recorded value to compare — stop them at the `?equal` gate.)
- `Signal.cutoff (==)` (or structural equality) on the model signal feeding
  `dyn` — still useful to stop republishing identical models at all;
- editor `apply_text_edit` (and equivalents) return `None`/`same` when the new
  document is identical to the stored one;
- gate mount-triggered effects by comparing against last-applied state
  (`<> Some settings`-style guards) so remounts don't re-dispatch;
- never store-compare records that are rebuilt fresh each update.

Symptom: steady ~100% CPU, ~10 Hz patch traffic, input focus lost every
cycle (typed text vanishes). A healthy idle app sits ~0–3% CPU.

## OCaml 5 multi-domain hazards on Apple hosts

- Every host→OCaml call must run inside
  `caml_leave_blocking_section()` … `caml_enter_blocking_section()` (needs
  `#include <caml/signals.h>`). Without it, worker domains starve during STW
  and downloads/network stalls look like hangs (worker parked in
  `iomux_poll`, 0% CPU, no IO).
- Never block a host-domain systhread on `Mutex`/`Condition` inside the
  worker→UI mailbox path: a waiter holding the shared mutex while re-acquiring
  its domain lock deadlocks against the UI thread (which holds the domain lock
  parked in CFRunLoop). Use a wakeup hook fired *on the producing domain* that
  enqueues onto the UI pump instead of a dedicated waiter thread.

## iOS Simulator entitlements & keychain

- The simulator reads entitlements from the **`__TEXT,__entitlements`
  section**, not the code signature. Entitlements baked into the signature are
  validated as *macOS* entitlements → exec killed (error 163) regardless of
  signing identity. Embed at link time: `-Xlinker -sectcreate -Xlinker
  __TEXT -Xlinker __entitlements -Xlinker entitlements.plist` (what Xcode
  does), then sign adhoc.
- With `application-identifier` + `keychain-access-groups` in the embedded
  section, adhoc-signed sim binaries get working keychain (Amplify, secure
  storage) — no Apple Development certificate needed for the simulator.
- Flat iOS bundles only: `Info.plist` + the binary at bundle root; a stray
  `Contents/` dir fails `simctl install` ("Missing bundle ID").

## V.Sheet presentation freezes on the iOS Simulator

Presenting a `V.Sheet` while a native `Menu`/context presentation is (or was
recently) open wedges the SwiftUI presentation layer on the simulator: stuck
overlay, input dead, 0% CPU — the app looks frozen. (The same hazard class
manifested as a ~100% CPU invalidation loop under the previous renderer.)

Testing workaround — render the modal's content inline instead of through the
sheet, e.g. `V.column [base; Navigation_stack.create ~title ~path:[] content]`,
which exercises identical reducer logic. **Never merge this patch** — it is
for sim verification only; sheets work on real devices.

## Simulator input & testing notes

- Remount-per-publish can steal focus or wipe a half-typed field — enter
  secrets via pasteboard instead of typing:
  `printf '%s' "$PW" | pbcopy && xcrun simctl pbsync host <udid>`, click the
  field, `cmd+v`.
- `xcrun simctl launch --console-pty <udid> <bundle-id> > console.log` is the
  only stdout/stderr channel (the app writes no os_log). Kill any previous
  `simctl launch` console process before relaunching — a dead consumer wedges
  stderr writes.
- `xcrun simctl io <udid> recordVideo out.mov` (SIGINT to stop) /
  `screenshot out.png`; `ps -o %cpu` distinguishes render-loop (~100%) from
  dead-end idle (~0%).
