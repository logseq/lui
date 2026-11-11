# NSH component batch qualification

Date: 2026-11-11 (UTC)

This checkpoint adds seven admitted routes: Breadcrumb, Pagination, Stepper,
Step, Timeline, TimelineItem and Split. The source inventory now records 77 of
87 canonical kinds. Admission remains partial support: restrictions and missing
properties/events in the inventory are outstanding migration work.

## Exact baseline and environment

The integration parent is `bf88e72f`; the source hashes below identify the tested
uncommitted integration, including dispatch wiring and fixture corrections. NSH
is pinned to `d21573c25984e9603bf878ae8bb73c1e23408936`, which incorporates upstream
main `de7f3637171b769f18474796fd5159a60b2de726` and the authorized keyed repairs.
Rust is 1.97.0. Local commands use `CARGO_BUILD_JOBS=2`,
`CARGO_PROFILE_DEV_STRIP=none` and `CARGO_PROFILE_TEST_STRIP=none`; these avoid the
local macOS debug proc-macro strip issue without disabling compiler warnings.

## Completed checks

- `make test`: 18 schema/tooling tests, 249 core cases, 5 wire cases, 4 indexed
  sequence cases, 6 plugin and 8 fetch cases passed. The full PPX hygiene file
  also passed separately, with 239,267 property checks at seed 5351196.
- `cargo test --locked --manifest-path platform/nsh/Cargo.toml`: 110 library
  tests plus 16 integration tests passed; no failures or ignored tests. This
  includes real OCaml Todos, clock, Image Load ABI and bounded virtual rows.
- Strict `cargo clippy --locked --manifest-path platform/nsh/Cargo.toml
  --all-targets -- -D warnings` passed.
- All 36 `test_nsh_*.py` tooling tests passed. Generated contract freshness,
  native source inventory freshness and changed Rust formatting passed.

The 53 focused control tests include the seven new routes, native roving without
activation, live required nonnegative Stepper active values, Timeline marker
precedence/pointer modifiers, and Split controlled drag/refusal, both-pane
constraints, RTL, parent resizing and editor focus/draft through keyed reorder.
Unsupported animation options still reject atomically; this is not animation
parity or cross-platform visual qualification.

## Actual macOS BottomTabs application

Build the real canonical OCaml fixture without Dune changes:

```sh
python3 platform/nsh/tests/fixtures/build_virtual.py --fixture tabs
LUI_OCAML_LIBRARY="$PWD/_build/nsh/tabs-qualification/liblui_tabs.dylib" \
  _build/nsh/dev-cli-d21573c/bin/nsh test platform/nsh/nsh.json \
  --target macos --trace < platform/nsh/tests/fixtures/tabs_native_steps.js
```

The copied development CLI reports NSH 0.5.0 at d21573c. Its development host uses
AppKit input and rendering. The source-authored steps passed: first page only on
mount; model refusal does not materialize another page; keyboard skips the
disabled middle tab; page buttons remain Buttons; accepted selection visits a
page once; independent native editor drafts survive switching and keyed reorder;
Appear follows visibility instead of unrelated body edits. Four tab requests
and final Home=2/Search=2 appearances were observed through the actual OCaml
model. The generated OCaml library has a source build receipt.

Screenshots in `_build/nsh/tabs-native/` were viewed in light and dark at 390x844
and 900x650 logical points. Text, disabled controls and icons remain readable;
inputs, page actions and the three equal trigger lanes retain alignment. The
fixture intentionally uses a bounded 280-point tab body. It is a qualification
surface rather than an application layout specification. Screenshots and build
outputs are ignored local evidence and are not committed.

The screenshots verify the shared theme foreground repair also survives the
actual tab page tree in both appearances. They do not verify OS text selection,
IME composition, a screen reader, all hover/focus/motion states, packaged tabs,
or any Windows/Linux visual behavior.

Verbose host build output exposes an existing debug-link warning: `__eh_frame
section too large (max 16MB) to encode dwarf unwind offsets in compact unwind
table, performance of exception handling might be affected`. Cargo also reports
its configured target-directory override and an unused generated nsh-bundler
patch. None was suppressed. Strict adapter Clippy remains clean; this debug-host
warning is not a release-package performance result.

## Earlier actual macOS Image and Todos checks

`/tmp/lui-nsh-image-native-main.log` records a successful native run with local
file URL decoding, source A-to-B replacement, missing-source recovery, three
successful Load callbacks, and one native Image/editor identity across changes.
The reviewed source-B screenshot shows its decoded blue image at 120x60. This
is not an HTTP, pixel-assertion or packaged Image qualification; the separate
`tooling/test_nsh_image_app.py` packaged qualifier remains to be run.

`/tmp/lui-nsh-inherited-text-native.log` records the successful real Todos run
with Unicode text input, Add and light/dark screenshots after the inherited
semantic foreground fix. Unicode injection is not IME composition evidence.
Those earlier logs identify earlier source states; the current full regression
and tab screenshots validate the shared renderer at the hashes below.

## Evidence hashes

Logs and binaries below are local ignored artifacts, not committed dependencies.
Their hashes identify the exact evidence rather than claiming a portable CI run.

| File | SHA-256 |
| --- | --- |
| `platform/nsh/src/render.rs` | `579576ed0435b902a237acf01a6dff0749bb7141e3a2a5245c117f67711c83b7` |
| `platform/nsh/src/controls.rs` | `5da2fa423dff1dcb39f306cb32ba48642a6d1d363c9bf10190ede144eba591b7` |
| `platform/nsh/src/controls/navigation.rs` | `c21da66e709415de4c6e215bf03db32babe1fee96c648404c15eaffebe9201de` |
| `platform/nsh/src/controls/surfaces.rs` | `08753f9c53af3e327964d79dd3ba6eb19665da476c7970e5642db68bf744c216` |
| `platform/nsh/src/controls/collections.rs` | `f2bce1c3d0bc60aa4c8ec46ffbb68edca7be5d2d28a7b5fd63ffa2077548797f` |
| `platform/nsh/src/images.rs` | `05abb04e33d18dc2ab8646345793fb432f4d0c55b28238bb41d49436ec654791` |
| `platform/nsh/tests/fixtures/tabs_app.ml` | `9d195305e2efb4530d10a64522b4d7d6b822243ffbc685e91bd34193bfd63293` |
| `platform/nsh/tests/fixtures/tabs_native_steps.js` | `37b66b89b191848f45bed20c4947cc3d0cc1f63dba94f9bfe168bce2ed10c110` |
| `_build/nsh/tabs-qualification/liblui_tabs.dylib` | `fd17c995a84404bef3996a06a62ea5b081e03bf03ca009848541c282e2988339` |
| `/tmp/lui-nsh-tabs-native-final.log` | `4960a590115a58ef6d44f8740cbc694a406df4ebc4362aef4ec5f3c023ef7f62` |
| `/tmp/lui-nsh-component-batch-rust-tests.log` | `8faa649306b0aa877c4de011a00a9ea2137e8c1f5c9dfc3ac1ac778d435d7498` |
| `/tmp/lui-nsh-component-batch-clippy.log` | `b5fdbe2fe321722a74301a70ff1a7704cb6089451b4896306da7d21eba806df2` |
| `/tmp/lui-nsh-component-batch-python.log` | `03f1f7ca4aa3578428cc8c7880587fc32906fdb7d92ca4f65277dc5e6a1b8136` |
| `/tmp/lui-nsh-component-batch-make-test.log` | `5f921c2feedaa14e497336668ff34f19e65bc7ad1913fdc4ec1b4f7a7850d0a2` |
| `/tmp/lui-nsh-image-native-main.log` | `66d471f493e00517eaf70d909960f692c6438bc47ec7fb1292d74292ccbd3ead` |
| `/tmp/lui-nsh-inherited-text-native.log` | `f39ebd72254589be75e40b241cba2a1042a9255185b155ca98356cf8e1e18bf3` |
