# Parent virtual source-factory replacement regression

Source-only regression based on LUI `b73fc438e44c58209b8729470bb6c9d3e0989dad`.
No compiler, fixture build, engine, test or performance run was executed while
preparing this source. No production or SDK behavior is changed here.

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

The existing `ocaml_virtual` integration target drives a native engine Scroll
to the end and first proves that current-revision data occupies the viewport.
It then activates the replacement control, checks retained canonical Scroll/list
and outside-input IDs, native Scroll identity, increasing source generation,
bounded trees and actual current-revision text bounds inside the live viewport.
Two replacements exercise repeated ownership. The assertion permits either a
preserved or reset scroll position; it makes no new source-replacement scroll
policy. Current revision labels exclude stale native rows as a passing witness.
After each replacement there is no wheel, scroll command, synthetic VirtualWindow
or manual wake; only the existing native engine pump and read-only agent queries.

The target reuses the existing Desktop/agent/row helpers. Its two OCaml fixture
cases serialize ownership with one test-only mutex. The private builder adds the
`virtual_replacement` choice without any Dune changes. A prebuilt library can be
supplied only with `LUI_NSH_VIRTUAL_REPLACEMENT_LIBRARY`; the older virtual
fixture's override is kept separate so an unrelated library cannot satisfy the
new case accidentally.

For the serial qualification owner:

```sh
cargo test --locked --release --manifest-path platform/nsh/Cargo.toml \
  --test ocaml_virtual \
  real_ocaml_parent_source_factory_replacement_never_leaves_a_blank_viewport \
  -- --exact --nocapture
```

The fixture builder compiles the real OCaml entry when no prepared library is
provided. A failure is evidence for further source/adapter/SDK isolation, not
authorization to change source policy, add scroll resets, enlarge a queue or
modify the pinned SDK. A pass qualifies only this native-engine case; it does
not replace the actual AppKit picker witness or claim physical input/paint/FPS.
