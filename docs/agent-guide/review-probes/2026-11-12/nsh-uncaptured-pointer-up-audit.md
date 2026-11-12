# Uncaptured NSH PointerUp audit

Source-only audit and bounded host correction; no SDK changes or new public
routing API. No compiler or native execution was run by the author of this
change. The root owns qualification.

## Contract conclusion

An origin/deactivation default was an NSH adapter implementation detail, not a
canonical promise. The Owned pointer gestures migration states that captured Up
means successful release; its capture=false default does not promise origin
release. The Android pointer-capability migration also explicitly prohibits Up
from cancellation during recomposition/removal. Web
`platform/web/melange/events/lui_web_events.ml:697` emits uncaptured Up from the
actual DOM pointerup target. Non-primary Up remains observable with capture
configured and does not complete the primary capture state.

Mobile source does not justify preserving incorrect desktop deactivation:
Android `LuiRender.kt:327` observes one native gesture and emits only after it
releases, retaining its Down detail. Apple `LUIAppleBackend.swift:1223` accepts
an explicit native hit/real-coordinate producer; its bridge does not prescribe
origin ownership. Apple and Android are not changed by this patch.

## Actual consumers inspected

Search covered the maintained LUI source/examples/tests, the App shared/native
sources, and the local mobile and logseq_journal OCaml sources; constructor
signatures, bridge entry points and serialization fixtures were distinguished
from application handlers.

| Actual caller | Capture | Required behavior |
| --- | --- | --- |
| App `Ui_parts.native_document_pointer_handlers`, used by `Tree.control_wrap`, `Tree.content_el`, `Add_button.el` | false | Emits document pointerup. Editor block drag resolves the current target at release (`editor_keys.ml:1547`); deactivation at the source is incorrect. |
| App `Right_sidebar_view.close_on_middle`, attached to panel wrapper/header/more/close | false | Close the item under the actual middle release, not a primary source's deactivation. The action is guarded by button=1. |
| App left Favorites navigation; Recent installs the same handler but ignores its primary Up | Favorites true, Recent false | Favorites requires captured completion/cancel; it is not evidence for uncaptured origin Up. Recent's uncaptured primary Up is a no-op. |
| App `Right_sidebar_view.item_drag` | true | Owner-completion/cancel contract; separate capture qualification. |
| App `Views_table.resize_handle` | true | Commit only successful owner release; cancel is a separate callback. |
| LUI data/gallery probes | no source-bound origin requirement | Serialize/display event names and samples. The existing Rust normal-click regression checks payload preservation, not deactivation or origin ownership. |
| local mobile/logseq_journal | no app-level uncaptured Up handler found | Journal bridge and native-events fixture transport/serialize the event; they do not establish origin semantics. |

No actual uncaptured handler inspected requires Up when a press merely moves
away, cancels, disables, unmounts or activates by keyboard. The existing NSH
`on_press_up` lowering can fire on those deactivation paths. Public
`Interactive::on_mouse_up` provides the actual released button/modifiers and
current-hit ancestry on macOS, Windows and Linux. Ancestor delivery mirrors
normal DOM bubbling; an App document bridge must install a single forwarding
owner on each relevant path, rather than forward the same release repeatedly.
That App placement audit is separate from this host correction.

## Bounded implementation and qualification

Mouse Up is translated from existing public MouseUp only. Non-mouse release
tracks one changed touch id within the retained element, records authentic
native Down modifiers, and emits only on that id's real TouchEnd. Cancel clears
the pending release; another id and duplicate End do not finish it. Mouse
TouchEnd cannot duplicate MouseUp. No new native registry or geometry is added.
Missing authentic Down modifiers do not become zero-filled release metadata.

The new tests dispatch public engine-boundary samples, explicitly not physical
mouse-driver proof. They check no Up at PressUp deactivation; destination owner
and fresh mouse release flags; middle/secondary/back/forward numbering; one
matching non-mouse End, wrong/duplicate End, Cancel cleanup, keyboard-only phases
and no duplicate mouse TouchEnd. Existing normal native Press/modifier tests
remain unchanged. Root qualification should additionally exercise the existing
actual AppKit held A-to-B-to-C route through LUI and review duplicate document
forwarding/outside-row cancellation in the App. Windows/Linux native execution
remains a platform evidence requirement rather than a macOS inference.

Canonical NSH capture, primary/non-primary typed Down coverage, fresh captured
release metadata and the existing keyboard PressDown observation remain separate
gaps. This patch neither claims to implement them nor invents a new routing
property to preserve a faulty adapter behavior.
