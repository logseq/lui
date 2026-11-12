# Input focus and painted native bounds

Source checkpoint: `faeb7385` (combined implementation and review notes).
NSH remains pinned to `adc186db7213f3ccd1eacaa836cc721e9779fd14`.
No SDK, Dune, constructor or wire-schema change is required by these repairs.
Public behavior changes and compatibility rules are in `docs/api-migrations.md`.

## Submit keeps the existing single-line editor focused

The actual Logseq many-choice fixture demonstrated a real default mismatch:
Enter selected Alpha and cleared the query, but immediately typing `b` could
not reach the retained field. NSH's inherited `BlurAndSubmit` policy caused
the blur. The adapter now explicitly uses public `SubmitBehavior::Submit`
for single-line text inputs, matching the existing focus-preserving Web/Apple
submit path. Application callbacks may still close or blur their editor.
Textarea's explicit Submit/Newline policy and the separate TimeField are
unchanged. No imperative refocus, new parameter or delayed event is introduced.

Actual AppKit Enter and pointer cases both passed with the same native field:
`al` selected Alpha, immediately following `b` filtered to Beta without a focus
helper or intermediate observer, then choosing Beta cleared the query while
preserving all three persisted values. Escape/reopen and unchanged block order
and titles also passed. The actual application release OCaml library and worker
were loaded by the pinned native test driver; these are interaction tests, not
standalone release memory measurements or arbitrary remote-search race proofs.

Evidence: `/tmp/logseq-native-property-many-enter-focus-fixed.log` and
`/tmp/logseq-native-property-many-pointer-focus-fixed.log`.

## Native bounds include existing layer transforms

A stronger picker end-of-list test found a diagnostic defect, not missing
rendering: the own-window LUI CLI screenshot visibly painted the last icon,
while bare `NSView.convertRect` returned its frame thousands of points outside
the viewport. AppKit view conversion omits NSH's layer transforms.

The diagnostic now converts all four bounds corners through public existing
AppKit/CALayer coordinate APIs. It handles flipped views, live sublayer scroll,
committed bounds origins and transformed ancestors without manually subtracting
scroll offsets. Unlayered segments use ordinary AppKit conversion to the nearest
existing layer span. Both view and layer walks are bounded to 64 ancestors;
cycles, disconnected spans and nonfinite results fail instead of producing
misleading coordinates. No layers, focus, layout or scroll state are mutated by
the production diagnostic. This reports committed model geometry, not completed
animation or compositor presentation timing.

The actual AppKit probe passed live and committed scroll, a transformed flipped
ancestor, a plain unlayered hierarchy and disconnected hierarchy rejection.
Its private window is offscreen and ordered behind, never activated or made key,
and only that owned window is closed. Earlier unpresented fixtures had detached
backing layers, correctly refused by the new guard; expected coordinates were
not weakened. Runtime output reports actual layer availability, rather than
claiming an unlayered child when AppKit automatically supplies its layer.

Evidence: `/tmp/lui-native-painted-bounds-realized.log`. Actual picker inspection
then reported the last icon inside the body, but exposed the independent
end-of-list tab-reset defect. The stronger complete picker transition suite is
not yet qualified: `/tmp/logseq-native-picker-state-changes-painted.log`.

## Additional checks and scope

- All **286 release library tests passed**, none failed or skipped:
  `/tmp/lui-focus-painted-bounds-final-release-tests.log`.
- Release all-target strict Clippy passed:
  `/tmp/lui-painted-bounds-submit-release-clippy.log`.
- Eight real OCaml/runtime/public-list integration cases passed, including
  bounded 100,000-row demand, retained focus/keyed moves, image Load, Picked,
  input submission and protocol recovery:
  `/tmp/lui-submit-focus-ocaml-integrations.log`.
- The Parent viewport regression additionally requires a nonzero distant row
  wholly inside the actual public layout viewport, while retaining existing
  bounded-cell, focus-pin and disposal checks.
- Formatting, canonical contract and support inventory freshness passed.

These repairs do not complete Logseq UX, native IME/accessibility/performance,
cross-platform PDF, packaging/signing or installed whole-application updates.
