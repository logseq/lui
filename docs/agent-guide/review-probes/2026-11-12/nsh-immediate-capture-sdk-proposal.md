# Draft: minimal desktop input seams for canonical LUI pointer capture

Status: proposal for scope review, not an implemented or qualified SDK API. No
NSH source, dependency pin, LUI schema, compiler configuration or shipping input
behavior changes accompany this document. Evidence was inspected on 2026-11-12.
NSH source revision: `adc186db7213f3ccd1eacaa836cc721e9779fd14`.
LUI baseline: `20fc6fbbda28e5785a0d364bf816704375886df2`.

The existing authorization covers the keyed-list repair and read-only text
geometry API. The SDK additions below require a separate scope decision before
implementation or publication. The installed NSH skill says, “Do not change NSH
to fit an app.” This proposal identifies general native input capabilities that
LUI cannot supply from the current supported public primitives. It does not
assume authorization for another fork change.

## Observed result and its limits

The root-owned private AppKit probe passed 9/9 tests in 14.9 seconds:
`/tmp/lui-native-immediate-capture-proof-corrected.log`. It used the pinned public
native driver through `app.press`, full `app.drag`, `app.rightClick` and
`app.keyboard.press`, with visible trace text read by `app.texts`. These are
native-driver injected input events, not physical hardware or production LUI
integration proof. The independent earlier held-mouse routing probe passed 4/4:
`/tmp/lui-native-dnd-proof.log`.

Private immediate-probe files remain ignored under
`_build/nsh-native-immediate-capture-proof`. Executed source hashes:

- `src/lib.rs`: `9621fc59d923c9f814794379af7dcf8a507a3ce250aa92d5dec2f36c8364af08`.
- `immediate-proof.test.ts`: `633d25aa22ecaeb0d66929d2fac43f5218cd6f24aaaa79d7cb45b27ac53437c1`.

The passing cases include explicit observations of limitations:

| Observation | Consequence |
| --- | --- |
| `TouchClaim::on_start()` grants an unmoved leaf immediately; ordinary native Press still follows. | Claiming alone does not implement captured activation suppression. |
| An ancestor gets the grant, but an interactive child owns typed PressDown and activates. | The ancestor cannot construct its physical Down from its own PressDown callback. |
| Explicit BoxOnly gives the ancestor Down and prevents child activation. | This changes authored child hit policy and is not a transparent capture lowering. |
| The explicitly doc-hidden `ElementRef::cancel_press()` suppresses leaf native Press and preserves subsequent real Return activation. | There is implementation evidence for a cancellation seam, but no supported generic capture contract yet. Ancestor ordering still needs a dedicated test. |
| Current C MouseUp precedes source responder release; release beyond the window still reaches the responder without any current-hit MouseUp. | Current hit routing works, but it cannot supply fresh release metadata outside the window. |
| Right click produces ContextMenu and MouseUp with Right, without typed PressDown or a Touch grant. | A secondary Down must not be fabricated from a context-menu request. |
| Disablement cancels candidate state; actual scope cleanup cancels before later C release. | These lifecycle checks are feasible with existing ownership. They are not proof of every native cancellation source. |

Actual held Alt continuity, modifier changes during a drag, interleaved Escape
or focus loss, native Scroll takeover, Windows/Linux input and full LUI/OCaml
integration are unqualified. The private driver cannot hold a drag while a
separate key/focus step executes on macOS. A passing observation of a limitation
must never be reported as complete canonical capture support.

## Existing source and signatures

These are existing APIs, not proposed names:

- `crates/nsh-core/src/element/builder.rs:1558,1600,1675`:
  `on_mouse_move<M>(self, listener: impl IntoListener<MouseEvent, M>) -> Self`,
  `on_mouse_up<M>(self, listener: impl IntoListener<MouseEvent, M>) -> Self`,
  `on_press_down<M>(self, listener: impl IntoListener<PressEvent, M>) -> Self`.
  There is no corresponding public `on_mouse_down` in this revision.
- `ops.rs:412`: `MouseEvent` contains local `position`, `page_position`,
  `modifiers`, `pressed_button` and changed `button`. MouseUp is current-hit
  delivery; it does not mean captured completion.
- `ops.rs:572`: `PressEvent` contains positions, the modifiers **when the press
  began**, and clicks. Keyboard/assistive activation can report its default.
- `element/responder.rs:98`: `ResponderEvent` contains `location`, `page`,
  `timestamp`, `gesture`; no fresh modifiers or changed button.
- `element/responder.rs:192,221,238`:
  `TouchClaim::on_start() -> Self`, `capture(self) -> Self`, and
  `block_native(self, bool) -> Self`. The latter controls native scroll takeover,
  not native press suppression. `Interactive::keep_touches(self, bool) -> Self`
  refuses responder transfer; it does not manufacture pointer metadata.
- `element/element_ref.rs:194`: `#[doc(hidden)] pub fn cancel_press(&self)` ends
  an element's current press or one inside it without later PressUp/Press and
  resets active styles. Its core owner is `core/touch.rs:387`.
- `core/touch.rs:415`: the cancellation marker currently clears on any next
  PressDown. Cancelling on responder grant, before the same physical cycle's
  queued PressDown, is therefore not interchangeable with cancelling after
  typed Down. Do not promote an untested grant-time recipe.
- `nsh-platform-macos/src/input.rs:404`: a grant at mouse down intentionally
  leaves inner native presses alive; move-time grants cancel them. Native Down
  queues Touch Start before the native PressDown (`:1680` vicinity).

Existing desktop release paths deliver current-hit MouseUp before the captured
Touch End: macOS `input.rs:810`, Windows `input.rs:981`, Linux `input.rs:721`.
Their retained pointer/responder owners already provide gesture identity,
termination and native platform capture. Reuse these owners.

At the proposal baseline, LUI `platform/nsh/src/events.rs:368` derived Down/Up
from native PressDown/PressUp. The subsequent uncaptured release audit identified
PressUp-to-PointerUp as an incorrect lowering, not a promised origin-Up default;
the bounded host bugfix uses existing public MouseUp for actual mouse release
and matching TouchEnd for successful non-mouse release. `pointer-capture` is accepted by the generated contract but is
not lowered there. PressUp includes deactivation/cancellation and must not be
reinterpreted as successful captured release. The existing LUI contract is in
`docs/api-migrations.md`, “Owned pointer gestures on Row and Box” and “Primary
pointer capture retains non-primary events.”

## Proposed SDK delta

The following signatures and fields are proposed, **not available public APIs**.
Implementation review must confirm names and wire compatibility before use.

### 1. Typed physical mouse Down on the existing hit path

Add to the existing `Interactive` trait:

```rust
fn on_mouse_down<M>(self, listener: impl IntoListener<MouseEvent, M>) -> Self;
```

Use the same ancestor delivery and receiver-local coordinate projection as
`on_mouse_up`, with real changed `button`, held-button state and modifiers from
the native event. Include primary, secondary and supported other mouse buttons.
Control-click on macOS must use the same logical-button convention as existing
MouseUp, not a new independent translation. No Touch gesture is created for a
secondary button solely to make this callback work.

Specify and test ordering: the physical primary Touch Start/claim and native
PressDown precede this observation, while any successful native Press follows
it. This permits an admitted capture ancestor to observe real Down and cancel
its native subtree press before activation. The new callback is an observation,
not an OCaml round trip returning a default-action policy. It must not introduce
an extra native action or change old listeners' ordering. If this ordering
cannot be guaranteed on a platform, the cancellation recipe below is rejected
there until a native, predeclared policy is implemented and reviewed.

### 2. Fresh optional mouse state on existing responder events

Carry the native event's mouse state through the existing Touch report into
`ResponderEvent`; do not repick the tree or query the current cursor later.
A small shared payload avoids changing the meaning of responder `location`,
which currently remains relative to the original touch target:

```rust
#[non_exhaustive]
pub struct MouseState {
    pub modifiers: Modifiers,
    pub pressed_button: Option<MouseButton>,
    pub button: Option<MouseButton>,
}
// Proposed additions to existing public structures:
// TouchEvent:     pub mouse: Option<MouseState>
// ResponderEvent: pub mouse: Option<MouseState>
```

On physical Start/End, `button` is the actual changed button; on Move it is None.
Coordinates continue to come from the same event's existing touch/responder
page fields. The completion snapshot must be captured from the actual release,
including release outside the window, and preserve changes to modifiers since
Down. Do not populate it from the stored press's initial modifiers. Native
cancellation may have no fresh hardware sample and reports None.

These public Rust structures currently permit direct literals. Adding fields
requires explicit source migration of their constructors in all maintained SDK
backends/tests, including JS producers. Optional metadata remains absent on
producers that cannot observe it; absence is not “all modifiers false.” Existing
JS event fields remain unchanged; any new JS projection is optional. Desktop
qualification requires real samples on all physical mouse Start/Move/End paths,
including native capture and cancellation exits.

### 3. Support the existing subtree press cancellation operation

First choice: document and support the existing exact
`ElementRef::cancel_press(&self)` operation, with tests for the ancestor case and
the ordering in item 1. Call it from the Rust physical Down listener only after
local admission and successful primary claim, after the current cycle's native
PressDown. It cancels that native subtree's queued activation, not the responder
lifecycle, and does not suppress the next keyboard/assistive activation.

Promoting the method alone does not prove this ordering or change
`drop_cancelled_press` semantics. Do not call it earlier on grant and assume it
works. Do not infer keyboard input from fabricated pointer fields. This seam
promises suppression of the current native press activation and active feedback;
it does not retroactively promise prevention of initial focus/text-selection
side effects that may already have occurred before engine delivery.

If source/tests show that the required press suppression cannot be made reliable
with the existing operation, stop this implementation route. The fallback for
separate review is a **predeclared, opt-in claim policy**, default false, applied
by the existing native input/responder owner when a primary on-start claim is
admitted. It must not be a late boolean callback from OCaml and must not alter
`on_start` or `block_native` defaults. Its exact interface and handling of
conditional `ask` claims need a new review; this draft does not authorize
inventing or silently substituting it.

## Canonical LUI lowering after SDK qualification

No new `pointer_up_target` property is needed. Default capture remains false.
Uncaptured NSH mouse Up should use the current-hit physical MouseUp already
available in the public SDK, matching Web release semantics. Native press
deactivation must not masquerade as successful PointerUp. Existing mobile
gesture producers remain unchanged; their native non-mouse ownership is not a
promise that desktop mouse Up follows the press origin.

For the existing Row/Box capture API only:

1. Bind the existing native on-start claim and keep-touches policy on the same
   retained element. Capture intent is a predeclared property. Evaluate existing
   Rust admission/visibility/disabled/pointer policy locally; never ask OCaml to
   decide a platform default action synchronously. Do not substitute a four-point
   move threshold or BoxOnly hit policy.
2. On the new typed MouseDown, use the actual button/modifiers/page position.
   An admitted primary down with the existing claim owns one gesture, invokes
   the qualified supported subtree press cancellation, and emits canonical
   PointerDown once. A capture ancestor gets its own event even when an inner
   button owns native PressDown. Secondary Down uses its real raw event and
   never starts or ends the primary capture state.
3. Use the existing responder Move/Release callbacks for the owned primary
   sequence. Read fresh metadata from that exact event. Captured Up is emitted
   once on successful release, including outside the handle/window. Do not also
   emit Up from PressUp or current-hit MouseUp for the captured primary sequence.
   Retain current-hit MouseMove/MouseUp for applications that separately observe
   destination rows; they do not change origin ownership.
4. Secondary Up uses existing current-hit MouseUp with its actual button. It
   does not clear the primary capture. Simultaneous multi-button gestures remain
   outside the existing promise. No synthetic Down from ContextMenu is allowed.
5. Escape, host blur, responder termination/native takeover, disabled/hidden or
   excluded pointer policy, capture property removal and scope disposal cancel
   rather than commit. Reuse the element's existing incarnation/lifetime guards.
   A disposed source clears owned state without late application callbacks. An
   app that owns a preview must also clear it on its own scope cleanup.
6. For synthetic cancellation without a fresh sample, use the last authentic
   accepted detail as the existing Web cancellation implementation does; label
   it as cancellation, never as fresh release. Missing fresh release metadata
   must not emit successful Up with zeros or stale Down flags. Cancel the owned
   operation and report a bounded diagnostic instead.

Keep one capture state under the retained LUI element: admitted sequence and
last authentic detail. Do not add a second native pointer registry, independent
hit geometry, global row cache, controller, or app-owned native capture. Recheck
identity/admission at delivery. A queued event from an old incarnation never
starts, updates or completes a replacement node's drag. SDK native press
suppression must prevent child activation, not merely filter the LUI callback.

Production block-drop destination release can use the existing uncaptured
PointerUp after correcting its NSH lowering to current-hit MouseUp. Actual
uncaptured App callers do not require origin/deactivation delivery. No additional
public routing enum or SDK hit-test is needed for that route. App document
bridges must avoid duplicate ancestor forwarding and explicitly handle release
outside eligible rows; a prior MouseMove is not proof of the release target.
Captured Up still names its gesture owner, and the SDK capture seams remain
separate from this uncaptured bugfix. This proposal does not by itself complete
block drag/drop.

## Rejection and compatibility gates

Before enabling this capability, the actual NSH target build must identify a
qualified SDK revision. A statically authored `pointer_capture:true` on an
unqualified NSH target should fail with a target-specific compiler/PPX diagnostic;
its compile-failure case must preserve valid Web/mobile calls. Dynamic raw
properties still require boundary validation. Do not add a blanket cross-backend
ban, change Dune, disable warnings or weaken the existing validator.

A known unsupported target must reject capture at construction/patch validation
before starting a gesture. An unexpectedly missing sample after admission is a
runtime boundary failure: cancel, preserve identity safety and report the real
error. Do not report success with an empty or zero-filled payload. When support
ships, record public SDK source migrations, optional field semantics, actual
LUI backend qualification, modifier bits and cancellation behavior in
`docs/api-migrations.md`. A downstream Row/Box using `pointer_capture:true`
should require no API rewrite on qualified targets; applications using
Up without capture receive actual release rather than press deactivation.

## Required proof before scope can be considered complete

| Layer | Required regression |
| --- | --- |
| SDK core | Existing on-start/on-move claims and default inner Press behavior unchanged; cancellation after actual Down suppresses subtree activation; grant-time cancellation is not accidentally treated as equivalent; subsequent keyboard and accessibility activation work. |
| SDK core lifecycle | Disabled/hidden/pointer-excluded/retired nodes are not admitted; removal, identity reuse and rejection cannot affect a different live owner; native takeover terminates rather than commits. |
| macOS native | Leaf and capture ancestor over a real interactive child; real primary/Right/Control-click and supported other buttons; unmoved capture; current-hit C release and outside-window release; no duplicate native or canonical activation; subsequent Return/Space/AX activation. |
| Windows native | Equivalent held-mouse, child, outside capture, button/modifier and capture-loss tests using its actual platform driver/event route. A macOS pass does not qualify this target. |
| Linux native | Equivalent actual GTK mouse/capture/gesture route tests, including Scroll takeover and native cancellation; no dependence on macOS event ordering. |
| Fresh metadata | Hold Alt/Ctrl/Shift/Meta, change modifiers during movement, release inside/outside; compare exact native release sample. Use platform-level fixtures where the public driver cannot interleave keys; do not call passthrough or semantic Touch tests physical modifier proof. |
| LUI Rust/FFI | One admitted Down, moves, successful Up or Cancel, exact existing pointer mask including Alt16 and secondary8; no Press/PressDetail/child activation from the captured primary; uncaptured current-hit release regression, no Up on press deactivation, and destination observations. |
| LUI actual-target build | Unqualified static capture fails compilation; valid other-backend calls compile; dynamic unsupported properties reject at the boundary. No runtime-only test substitutes for the compile-failure case. |
| App | Existing shared Block_drag threshold/zone/cancel state and domain drop action receive the native sequence once; current target wins at release; source/editor identity survives preview; removal and outside release do not commit stale targets. Alt single-block reference remains a separately verified action. |

Do not pin or publish the proposed SDK change until its authorized scope, public
contract and platform qualification are reviewed. No graph view, external
file/text drop, broader pointer framework or release-routing API is included.
