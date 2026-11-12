# Parent virtual source-factory replacement regression

Regression based on LUI `b73fc438e44c58209b8729470bb6c9d3e0989dad`.
It was prepared without compiler or test execution, then qualified serially at
`c11ccfbd` as recorded below. No production or SDK behavior is changed here.

The actual Logseq color-case failure retained the same Scroll and VirtualList
nodes, advanced source generation from 12 to 13, and replaced the demanded end
indices 674–688 with prefix indices 0–22 while the physical viewport stayed near
the end. Only the Icons heading remained visible. This rules out a simple
per-factory generation reset. The application separately changes color through
retained foreground bindings; this generic regression keeps source replacement
independent of that presentation correction.

`virtual_replacement_app.ml` uses real OCaml constructors and the native ABI.
Its 320-point Scroll owns a 64-point header and Parent VirtualList. The Scroll
and outside input live outside the reactive source-factory branch. A real
button rebuilds that branch with the same 1,000 items/keys and a new row-label
revision. The normal virtual source allocates its own generation; the fixture
does not fabricate metadata or viewport feedback.

The separate `ocaml_virtual_replacement` integration target drives an engine Scroll
to the end and first proves that current-revision data occupies the viewport.
It then activates the replacement control, checks retained canonical Scroll/list
and outside-input IDs, native Scroll identity, increasing source generation,
bounded trees and actual current-revision text bounds inside the live viewport.
Two replacements exercise repeated ownership. The assertion permits either a
preserved or reset scroll position; it makes no new source-replacement scroll
policy. Current revision labels exclude stale native rows as a passing witness.
After each replacement there is no wheel, scroll command, synthetic VirtualWindow
or manual wake; only the existing native engine pump and read-only agent queries.

The target reuses the existing private Desktop/agent/row helpers through
`tests/support/ocaml_virtual.rs`. The replacement case has its own Cargo-auto
integration binary, `ocaml_virtual_replacement`, so it never initializes the
original fixture's different OCaml library in the same OS process. A mutex
cannot provide that isolation: `runtime.rs` rejects a second initialized library
and retains OCaml process-global state without dlclose. The private builder adds the
`virtual_replacement` choice without any Dune changes. A prebuilt library can be
supplied only with `LUI_NSH_VIRTUAL_REPLACEMENT_LIBRARY`; the older virtual
fixture's override is kept separate so an unrelated library cannot satisfy the
new case accidentally.

For the serial qualification owner:

```sh
cargo test --locked --release --manifest-path platform/nsh/Cargo.toml \
  --test ocaml_virtual_replacement \
  real_ocaml_parent_source_factory_replacement_never_leaves_a_blank_viewport \
  -- --exact --nocapture
```

The fixture builder compiles the real OCaml entry when no prepared library is
provided. A failure is evidence for further source/adapter/SDK isolation, not
authorization to change source policy, add scroll resets, enlarge a queue or
modify the pinned SDK. A pass qualifies only this native-engine case; it does
not replace the actual AppKit picker witness or claim physical input/paint/FPS.

## Executed release qualification

At `c11ccfbd`, the new real OCaml integration passed in 41.84 seconds using the
published NSH pin. Both source replacements supplied current-revision rows
inside the live parent viewport without a second scroll or synthetic demand.
Evidence: `/tmp/lui-parent-source-replacement-release.log`.

The original isolated `ocaml_virtual` target also passed in 6.38 seconds after
its shared transport extraction:
`/tmp/lui-original-parent-source-release.log`. Release all-target strict Clippy
and Rustfmt passed: `/tmp/lui-parent-replacement-release-clippy.log`.

These results establish the Headless native-engine seam, not AppKit parity.
The actual application's previous color failure occurred with a real macOS
scroll owner; the independent public-native-driver case below now supplies
additional platform evidence. The application's paint-only color correction
also passed its separate actual AppKit case. These bounded cases do not imply
that every source replacement hierarchy has been qualified.

## Executed independent AppKit qualification

The ignored `_build/nsh-native-parent-source-replacement-proof` harness uses the
same real OCaml fixture with a private public-API Desktop root and the pinned
NSH native test driver. At LUI `7ad9d6ca`, it passed in 44.0 seconds:
`/tmp/lui-parent-source-appkit-bounded-gestures.log`. Evidence remains in the
owned temporary root `lui-parent-source-native.YdzdJD/`, including read-only
canonical/native observations and successful exact-group cleanup.

Initial demand reached indices 985–999. After two actual replacement-button
presses, generations advanced 1 → 2 → 3, while canonical/native entry
incarnations stayed Scroll 6, source 10 and outside input 4. Each state contained
40 canonical nodes; new-revision rows 993–999 remained fully inside the native
320-point viewport. The test issues no wheel, scroll, VirtualWindow, focus or
manual wake after either replacement. The observer uses only the existing
tree/native-bounds operations against its verified own process group.

The first harness invocation failed before its initial observation because it
requested a 100,000-point gesture. The native driver emits 20 points per display
frame, while its transport bounds each command to 30 seconds. The corrected
setup uses two initial 22,100-point gestures to cover the actual 44,064-point
source. No command deadline or post-replacement assertion was relaxed. The
original failure remains `/tmp/lui-parent-source-appkit-native.log`.

This is functional native-driver evidence, not a standalone release performance
measurement or hardware-input/accessibility proof. The Rust CLI is built in
release mode, its generated native test host is a development host, and the
OCaml fixture builder uses its existing default Dune profile. No production
adapter or SDK patch was necessary for this minimal replacement case. The
previous application-specific color failure should not be generalized into an
unproven framework-wide defect.
