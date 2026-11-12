# Public NSH responder capture probe

Status: source prototype only; no compilation or runtime result is claimed.
No installed application, display, native window or user graph is touched.

The prototype in `platform/nsh/src/responder_capture_tests.rs` uses the pinned
NSH revision `2635333e4cc0d3be8032c97f3a5e08d3685179c6`, the existing Cargo test
dependencies and public APIs only. It does not wire the production LUI
`PointerCapture` property or introduce an NSH fork change.

Run the parent's serialized existing release library test command with the
`responder_capture_tests` filter. The fixture uses a manual engine clock and
public `Headless.press`, `drag`, `drag_and_hold`, `hover` and `drop_held` steps.

## Proposed assertions

| Case | Required observation |
| --- | --- |
| Start claim, keep touches | A gesture begins on Row A, moves outside A to a point geometrically inside Row B and releases. A receives one grant and one release; B does not become the responder. Raw touch targets remain the press origin. |
| Move claim and child control | A normal child tap activates once without a grant. A drag beginning on that child claims only after movement, receives one release and does not replay the child action. |
| Ancestor takeover | A keeping its touches survives the outer capture claim; allowing takeover produces one A termination and one outer grant. |
| Native Scroll | A blocking claim prevents scroll takeover. A nonblocking claim allows Scroll to take the gesture, producing cancellation/termination instead of a later release to A. |
| Touch versus hover | Touch controller movement does not also invoke MouseMove. A separate hover over B produces an unheld MouseMove without changing A's held touch gesture. |

## Scope limits before production capture

The resolved public source exposes `Interactive::claim_touches`,
`keep_touches`, responder grant/move/release/terminate callbacks and
`TouchClaim::on_start`, `on_move`, `capture`, `ask` and `block_native`.
These can retain gesture delivery outside a source row and negotiate with
Scroll without a dependency change.

Public `Headless.drag` currently constructs `PointerType::Touch`, even under
the desktop environment. `hover` creates MouseMove with no pressed button;
it cannot simulate a held hardware mouse. This probe therefore cannot qualify
native mouse modifiers/button continuity or whether a real backend emits both
MouseMove and responder movement for the same physical motion.

`ResponderEvent` contains location, page, timestamp and gesture. It has no
modifier/button state or current hit-test target. `TouchPoint.target` and path
describe the press origin. Capturing a gesture therefore does not by itself
give the application the destination row needed by Logseq's drop controller.
No public current-view hit-test API was found in the resolved core/engine
surface. The prototype does not invent one, add a geometry cache or substitute
the capture origin for the drop target.

An always-on start claim must not be assumed equivalent to browser pointer
capture: child controls and Scroll arbitration need explicit acceptance. The
prototype's move-claim case tests one public policy that preserves a normal
child tap, without asserting that this policy implements every LUI caller's
capture contract. Production mapping remains separate until these assertions
pass and native mouse, cancellation and target semantics have direct evidence.

## Follow-up: actual AppKit held-mouse routing

The private Rust probe in ignored `_build/nsh-native-dnd-proof/` passed all four
native macOS cases against immutable NSH `adc186d` in 43.0 seconds. It registers
only its private probe UI set required by the CLI; it changes no shipping API,
NSH source, application bridge or graph. The public native `app.drag` driver
sends held `LeftMouseDragged` events through the fixture's own AppKit window.
This is separate from the Headless Touch observations above.

The passing cases establish:

- A claims after four points of movement while B and C receive actual held-Left
  mouse movement. C receives current-target MouseUp before A's captured release;
  the fixture observes exactly one C drop and no source click.
- Releasing over blank root space cancels instead of accepting a stale C target.
- Removing A during movement through B clears its scope-owned active state and
  rejects the subsequent C release, without relying on a dead responder's
  termination callback.
- An ordinary source click invokes exactly one action and never grants capture.

Current destination identity comes from public `on_mouse_move`/`on_mouse_up`
listeners, with local coordinates and modifiers from `MouseEvent`; no current
hit-test API or geometry cache is needed for this narrow route. Recorded native
mouse modifiers were all false. Actual held-Alt input, in-drag focus/Escape
cancellation, Scroll arbitration, autoscroll, stationary-pointer repicking,
Windows/Linux execution and production editor identity remain unqualified.

This move-threshold proof does **not** implement canonical `pointer_capture`:
that property owns an admitted primary gesture from Down and suppresses
automatic activation. Immediate capture, typed Down ownership and interactive
descendant suppression require their own proof. The production capture mapping
and native `Block_dnd` implementation remain incomplete. Full native traces are
retained in ignored `_build/nsh-native-dnd-proof/run.log` and
`/tmp/lui-native-dnd-proof.log`.
