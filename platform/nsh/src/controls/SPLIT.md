# NSH native panel Split

The desktop adapter uses one public ResizablePanelGroup with two keyed
ResizablePanels. Native NSH owns the solver, minimum/maximum ranges, drag state,
handle capture, adjustable actions, right-to-left placement and child layout.
No adapter geometry solver, focus/divider controller, source-tree copy or
per-move callback is involved.

An absent wanted width gives equal native panels. `first-pane-width` binds the
first logical panel's absolute wanted size; child `min-width` / `max-width`
become its native range. The native default minimum is 100 points. A changed
wanted-size prop resets the corresponding native drag choice. Model echo is
optional: completed drags notify once, in absolute first-panel points, and NSH
keeps the user's layout until the source changes. Notification disable does
not lock the native panels.

The native centered hit band is 9 points. Its visual indicator follows scoped
border/primary tokens and native hover/active group states. Native adjustable
steps are 10 points. Desktop arrow-key resizing is not supplied by this NSH
component; the adapter adds no keyboard/focus subsystem.

## Compatibility

Reject ratio `value`, custom `resize-handle-width`, nonzero handle offset, and
track-animation variants atomically. Zero offset and zero duration are harmless
native defaults. Explicit `gap` maps to native group spacing; omitted gap uses
the native zero spacing around the overlaid band. These desktop rules are
recorded with migration examples in `docs/api-migrations.md`. Authored pointer
enter/leave handlers also reject: observe a surrounding LUI container instead of
adding an adapter wrapper around the native group. Wanted widths must fit native
points.

No actual UI Split calls were found in the audited mobile/journal revisions;
string/list split helpers were excluded. Apple/iOS, Android and Web remain
maintained and retain their own implementation and defaults.

## Qualification boundary

The new focused regressions exercise actual native panels: default equal sizing,
completed-drag pixel notifications without model echo, natural pixel source and
constraint updates, notification disable, keyed editor identity/focus/draft,
right-to-left output and atomic rejection. They replace tests for the removed
controller. The implementation agent ran formatting and source checks only;
the main session must run these tests and repeat real desktop qualification.

The existing navigation OCaml fixture must remove its `~value`, custom handle
width/offset and ratio/refusal assertions. Use two native Split examples with
omitted sizing and with `~first_width`; both completion callbacks save absolute
points. A no-echo action demonstrates native local retention, not refusal.
Preserve root's newer native-driver TypeScript and timeout wiring when adapting
that fixture. Existing historical screenshots/receipts keep their recorded
source boundary.
