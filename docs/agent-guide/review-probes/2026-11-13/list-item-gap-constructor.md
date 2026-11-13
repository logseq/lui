# ListItem gap constructor correction

Base LUI source: 93712b51ab40d7c5882fed1501568a55ab6722ba. This is a source-only correction. No compiler, native app, test, worker or user process was run.

## Admission evidence

`Lui_protocol.common_property_supported` admits MainAlignment/CrossAlignment on ListItem but excludes Gap. The final `property_supported` function has no ListItem Gap override. `Lui_runtime.set_prop` applies that matrix before emitting a property to any host. Apple's gap branch in `LUIWireProtocol.swift` excludes listItem; its main/cross branch includes it. Android's gap branch in `LuiKindRules.kt` excludes listItem; `isMainCrossKind` includes it. The pinned generated NSH contract agrees: main/cross are present, gap is absent. Generic and Web do not bypass the canonical OCaml matrix.

Only the falsely advertised constructor label is removed. The implementation passes gap=None to its existing universal implementation. Other constructor labels, backend defaults, provider layout, wire matrices and dynamic validation are unchanged. In particular, main/cross must remain valid: the actual App's styled navigation rows use both.

## Consumer source audit

Read-only lexical call inspection covered actual authored `mobile/shared/src`, `logseq_journal/app`, and App `deps/ui/src` plus `deps/ui/native`, followed by direct source inspection of nested spacing and the three journal ListItem producers. No ListItem constructor directly supplies or optionally forwards gap. Mobile `view_query.ml` puts gap on its child Row. Journal `journal_status_view.ml` does the same. Journal native-row adapters in `journal_view.ml` and favorites in `application.ml` pass supported labels and child content. App `ui_components.nav_item` retains its valid main/cross calls. No consumer source or mobile toolchain files are modified.

## Source changes and qualification

The existing PPX hygiene harness receives rejected direct/qualified/aliased/optional-forward/reactive gap calls, requiring the actual OCaml label diagnostic. The same harness preserves valid ListItem main/cross calls. The existing recording-runtime suite mounts actual valid ListItems under Web, NSH, SwiftUI, Kotlin and Generic profiles; it checks emitted alignment/padding and one real press callback, then requires exact kind/property rejection of a dynamic Gap write before host emission.

`node tooling/generate_component_schema.mjs` regenerated the typed-view contract from the canonical signature. Only `src/lui_wire_schema.ml` changes among its generated outputs; the facade `Lui.Elements` is an alias of the canonical module and needs no handwritten forwarding copy.

Root must run the native contract exporter before final qualification/publication because it compiles OCaml and refreshes source hashes. It was deliberately not run by this source-only author. Use the source generator for those outputs, never manual hash edits. The actual App strict gate's old gap fixture expects the pre-correction probe-stage failure; once the immutable LUI pin changes, that fixture must expect an OCaml compile failure instead. Dynamic property rejection remains covered by the runtime test.

Root qualification commands, serially:

```sh
node tooling/generate_component_schema.mjs --check
python3 tools/gen_json_view.py
python3 tooling/generate_nsh_contract.py
node --test tooling/test/ppx-hygiene.test.mjs tooling/test/component_schema_test.mjs
opam exec -- dune exec test/test_lui.exe -- test protocol
python3 tooling/generate_nsh_contract.py --check
```

The generated native contract outputs, if changed, are `platform/nsh/contract.json`, `platform/nsh/src/contract_generated.rs`, and `platform/nsh/tests/fixtures/contract_oracle.json`. Full maintained-target gates remain required before publishing the LUI revision and changing App pins. These source tests do not establish physical native geometry or keyboard delivery.

## Executed candidate qualification

The integration run first caught a stale generated JSON-view constructor
forwarding `?gap`. Regenerating with `tools/gen_json_view.py` removed only that
invalid forwarding label; no handwritten generated source or hash patch was
used. Native contract generation then succeeded and changed only the three
canonical source hashes in `platform/nsh/contract.json`.

The two existing Node compiler/schema suites passed all 12 tests, including
invalid direct, qualified, aliased, forwarded and reactive gap calls. The first
protocol run exposed a test-fixture error: it asserted a queued Press callback
before flushing the app. Adding the same real event flush used by the existing
Gallery tests preserved the callback assertion; all 23 protocol tests then
passed, including all five maintained host profiles. Full LUI target and app
pin qualification remain required before publishing this candidate.
