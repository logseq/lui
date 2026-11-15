# Fence Sparse Far-Scroll Completion with Native Observations

## Problem

An Apple sparse reveal can have a current logical target and a mounted, measured row while the native viewport is still elsewhere. `LUISparseVirtualState.setOffset` puts the requested offset into `offset` before calling the native writer. `finishTargetIfReady` compares that scalar with the desired offset, checks for a cached target height, yields, and emits success without rechecking the generation, semantic target, owner or actual row geometry. A same-index generation change need not cancel the queued completion. This permits a source-derived early-success schedule; absent geometry or measurement can also leave a token pending. These are source risks, not a reproduced explanation of a particular flaky run.

Cold semantic retention deliberately mounts a target outside the bounded B1 viewport window. Mounted membership therefore cannot substitute for native placement. Cross-section estimates, folds, width/height changes, pagination, source-origin movement and native document clamping can change that placement after a completion was queued.

The application already rejects stale logical intents. Its `issued_reveal.ml` matches source/owner leases, token and phase; navigation/editor callers additionally fence repository, route, revision, epoch, UUID, scope and exact control/occurrence. Those app fences cannot prove that the SDK's physical scroll completed and must not be weakened to compensate.

## Proposal

Tighten the **SDK's existing Apple sparse `ScrollCompleted(..., "succeeded")` precondition**. Maintain separate desired and native-observed offset/evidence, and require two fresh native samples around the existing asynchronous completion boundary. After `Task.yield()`, re-resolve the current request, generation, key/index/row, logical and physical owner, source anchor, actual offset and target anchor rect before success. A changed sample discards the queued completion and re-evaluates the still-current request; it does not replay a retired request.

This is a proposed design, not an implementation or runtime acceptance result. It covers both shared-owner and standalone Apple sparse lists on macOS/iOS. Keep one flat source under each independent shared owner. Existing B1 window/pin/cold-retention logic, scroll anchor meanings, positive-token deduplication, missing-target/cancellation outcomes and application authority remain. No public Swift/OCaml API, wire field/event/outcome, schema, capability, C bridge, app fence or opaque receipt format changes are proposed. Android, Web and the separate non-sparse list completion path are outside this change.

The initial gate is the existing **1 logical-point** offset tolerance, also used for geometric stability comparisons below. Identity/key/generation checks are exact. This is a concrete proposed tolerance to validate, not a measured claim about current flaky runs. There is no fixed settling sleep, automatic editor TTL, new focus operation or synthetic receipt.

## Evidence baseline

The implementation target is SDK `bc89138b7c44804ab5c0cf72e833635c85261db1`; inspected `c37d14686c9d24c698a91688e1d324d786fb47e6` has identical relevant runtime files. App comparison is immutable `675724cafacc0b310463dae4f1ec10065c85b560`. The earlier source analysis is titled *Far-scroll convergence and completion: source analysis* (SHA256 `01a12c8b91d30481fa6e864b48e7c39de19c23edf22df26a35ff91376b17b717`).

| Existing source | What the proposal must preserve or change |
|---|---|
| [Sparse configure/measurement][sparse-config] and [completion][sparse-completion] | Keep current-generation row/index admission, bounded extents and token lifecycle; replace optimistic completion evidence and the incomplete post-yield check. |
| [Core flat target lookup and reconciliation][core] | `ScrollTarget` is mapped from the complete flat source to `VirtualScrollIndex`; B1 stale-generation rejection and bounded reconciliation already exist. No new Core acknowledgment is needed. |
| [Shared binding/geometry types][shared-types] and [native metrics/anchor frame][shared-geometry] | Reuse owner node/epoch, current row keys and top-origin/inset conversions. Existing `anchorFrame` reads cached `source.geometry` and returns a vertical rect with synthetic width 1; neither is a fresh full-geometry observation by itself. |
| [Shared native write][shared-write] and [native writer][native-write] | Propagate the existing internal native write Boolean/availability instead of discarding it; an accepted write is still not observed arrival. |
| [Row/source probes][probes] and [standalone native probe][standalone] | Reuse lifecycle and native layout/offset callbacks. Current row/source marker registration is shared-only; standalone needs an internal row/source observation seam too. |
| [Issued producer][issued], [navigation][navigation] and [outline editor fences][editor] | Preserve their logical authority, exact control and independent navigation/editor leases. Scroll success remains separate from native register/ack and OCaml-owned release. |

## Minimal internal change shape

Use a request record plus an observation/candidate record inside the existing state and native probes. Names below are conceptual private/internal names, not new public APIs or compiled Swift declarations.

| State | Proposed meaning and writers |
|---|---|
| Existing `offset`, treated explicitly as a planning/window cache | May retain current optimistic updates for bounded B1 prediction and reading compensation. It is never completion proof. A private rename to `windowOffset` is optional; a repository-wide offset rewrite is unnecessary. |
| `desiredOffset` | Last requested source-local target offset, with its attempt/write sequence. Only a request/correction writes it. Recompute its clamp from the current native geometry before completion. |
| `observed` | Optional immutable native sample: actual offset plus source origin, viewport/document geometry, insets, target rect and live identities. Only a real native read supplies it. Never initialize it from `desiredOffset`, `offset`, an estimated height or a successful write result. |
| `pendingReveal` | Internal attempt identity, existing positive token, opaque `scrollTarget` string, source model/incarnation and declared owner binding if shared. `handledToken` keeps its current deduplication role. |
| `completionCandidate` | Task/attempt identity, current generation and index, exact row/model/marker, source/owner/window identities, relevant mutation revision and queue-time native sample. Only that task may clear its completion slot. |
| Native observation serial and relevant mutation revision | A serial advances on every actual native acquisition, even for equal geometry. A mutation revision advances only for changed relevant identity/layout/metadata. Repeated equal samples do not perpetually invalidate a candidate. |

`setOffset` records desired/planning state and requests a native write. It does not populate `observed`. Shared geometry delivery and standalone `viewport` callbacks may continue updating the planning cache as they currently do; their physically read data also feeds observation. The completion gate uses only a fresh native observation, never the planning cache or a cached callback alone.

Preserve speculative **bounded** B1 planning rather than accidentally making target mounting wait on completion. An unavailable native writer may still have a desired target window; it simply cannot prove success. Do not mount all intervening indices or convert predicted row membership into physical evidence. This proposal leaves the existing derived-window/`VisibleRange` behavior in scope as-is; it does not promote that event into a native visibility certificate or change journal pagination policy.

Proposed implementation touchpoints are limited to:

| File | Internal work |
|---|---|
| `platform/apple/Sources/LUIAppleBackend/LUISparseVirtualList.swift` | Desired/observed separation, request/candidate/task identity, invalidation, pre/post-yield checks and attaching observation markers to bounded mounted rows. |
| `platform/apple/Sources/LUIAppleBackend/LUISharedVirtualViewport.swift` | A fresh internal completion-sampling helper over current owner/source/row registries; parameterize/refactor anchor conversion to consume geometry acquired in the same sample; retain native write availability/result. |
| `platform/apple/Sources/LUIAppleBackend/LUISharedVirtualProbe.swift` | Route source/row attach, detach and changed-layout evidence through the sparse state; preserve existing shared registration forwarding. Reuse these private markers for standalone sparse content. |
| `platform/apple/Sources/LUIAppleBackend/LUISparseScrollProbe.swift` | Standalone owner connection identity, fresh metrics/rect acquisition closure, disconnect invalidation and internal write-issued result. |
| `docs/api-migrations.md` at implementation time | Document stricter scroll-stage completion timing only, using the draft below. No API/wire migration. |

No source, test or migration-guide edit is part of this documentation task. Implementation tests are follow-up work, not created here.

## Identity and key fences

All acquisition, state mutation and final event delivery remain on `@MainActor`. After the asynchronous boundary, perform the complete gate synchronously, with no further `await` between validation, taking the matching attempt and emission.

1. **Attempt/token:** state is active; the task is not cancelled; internal attempt/task identity and existing token match; `model.scrollToken` still names that command. Numeric token equality alone cannot admit an older task after disposal/reconfiguration. Keep current token reuse/dedup behavior.
2. **Source:** the exact source model is still the backend's current retained object; state/model generation, current `VirtualGeneration` and the candidate generation agree. Sample the committed metadata again after B1 delivery, which may synchronously cause reconciliation.
3. **Semantic target:** the nonempty opaque `model.scrollTarget` equals the captured requested string, and current `VirtualScrollIndex`, state target index and current mounted `Row(id,index)` agree. Do not decode application key namespaces or infer UUID/scope from physical IDs. Header/Block/Footer and extension rows are equally eligible.
4. **Shared key mapping:** re-read current `VirtualRowKeys` and current children together, following `anchorKeys`'s canonicalization pattern rather than trusting cached `Source.binding.keys`. The target child's current position must carry the requested key, with the same declared owner node/epoch. For standalone lists there is no exported per-row semantic key array: the existing Core-issued `(key, generation, VirtualScrollIndex)` mapping remains authoritative; do not invent a new wire proof.
5. **Row:** re-resolve the current retained row model or extension model, exact native marker and marker generation. Require attachment in the current source hierarchy and the current measured row/index. A cached height alone or a reused numeric row ID is insufficient.
6. **Owner/source anchor:** compare the declared shared owner node/epoch and live owner model, plus exact native scroller, window, source anchor and probe connection incarnation. For standalone, its native scroll connection is the physical owner fence. Resolve live weak references; an `ObjectIdentifier` without a live-object check is insufficient. No native view is kept alive to make a stale candidate pass.

A generation/index/layout change invalidates the **candidate** even if the numeric index or key stayed equal. When the same logical source/owner/key request remains current, configuration may rebase that pending request to the newly committed index/generation and acquire new evidence; it must not send an old-generation success. A declared owner epoch/source lifetime retirement does not silently transfer the old command to a different logical owner. Use the existing cancellation/retirement path and require a fresh command where ownership changed. A native probe reconnect under the same live logical binding invalidates physical evidence and may be reacquired without pretending the old marker survived.

## Native observation and geometry predicate

Acquire queue-time sample A and post-yield sample B through a direct internal native reader. The shared helper must call the current `metrics`/`geometry` logic and convert the exact row marker using **that newly acquired geometry**; calling the existing cached `anchorFrame` unchanged is not enough. Read the same owner/source/row incarnation for offsets, clamp and rect. A disconnected owner, missing source anchor, stale marker generation, nonfinite coordinate or nonpositive viewport/row extent produces no sample.

Standalone uses its existing native scroll probe for owner metrics and private source/row markers for rects. Mount/reuse the source marker at the actual source bounds; the current zero-sized `LUISparseScrollProbe` is an ownership/notification probe and must not be mistaken for the source's full layout rect. Both variants retain only bounded mounted-row weak markers and remove them on detach. This adds no nested source or second window authority.

Normalize to the existing **top-origin logical-point** coordinates. In the shared case:

```text
observedLocal = actualOwnerOffset - currentSourceOrigin
desiredLocal = currentTargetOffset(index, existingScrollAnchor)
clampedLocal = clamp(currentSourceOrigin + desiredLocal,
                     0, max(0, actualDocumentHeight - actualViewportHeight))
               - currentSourceOrigin
```

Use AppKit's flipped-document conversion and UIKit's current adjusted insets as in existing native geometry code. A shared local offset may be negative when the viewport begins before the source; do not clamp it to zero just to pass the test. Preserve `center`/`bottom` and sparse default/`nearest` = top semantics.

Completion requires all of the following at A and again at B:

- `abs(observedLocal - clampedLocal) <= 1` using freshly recomputed native document/viewport/source geometry, not old estimates or a successful write Boolean.
- The exact attached current-generation row anchor agrees with the current sparse placement/measurement within 1 point and has a nonempty vertical intersection with the native viewport. Validate the anchor point under the current clamp; do not require an oversized row to fit entirely or an end-of-document row to reach an impossible unclamped alignment.
- A and B have the same identity/key/generation/mutation fence; B's actual-read serial is greater than A's. The target rect, source origin, viewport/document extents, insets and relevant widths are unchanged within 1 point. Include real marker bounds/source width: the existing shared vertical helper's synthetic width 1 cannot detect wrapping-width changes.

Estimated prefix heights remain useful for the initial jump. A discrepancy between the physical anchor and the current sparse placement means remeasure/reconcile and retry; never invent a fallback rect from `extents.origin` and mark it native. Rect agreement and fresh physical placement are the completion evidence. Native window attachment/geometry here is a scroll-stage claim, not proof of foreground presentation, exact editor/control readiness, focus or IME acceptance.

`Task.yield()` is only an asynchronous revalidation boundary. It does not guarantee a display frame or completed SwiftUI layout. Two current native reads plus mutation checks prove the placement observed at queue/send, not permanent future layout stability. Known newer source/layout/marker work invalidates the candidate; later independent layout changes remain observable events rather than a promise that a past success can never move.

## Completion flow, invalidation and wakeups

Illustrative control flow only; helper names represent private SDK work described above:

```text
finishTargetIfReady:
  resolve current live request / committed generation / target index
  acquire native sample A for the exact current source, owner and row
  if unavailable: keep the current request pending; await a real dirty event
  recompute desired clamp from A; request an eligible correction if needed
  if A is not ready: return without scheduling success
  capture candidate = (attempt, task slot, generation, key/index/row,
                       owner/source/window, mutation revision, sample A)
  enqueue at most one MainActor completion task
    yield
    if this task no longer owns the slot: return without clearing a newer task
    re-resolve every identity and current committed metadata field
    acquire fresh sample B; recompute desired clamp and anchor predicate
    if any fence or geometry predicate fails:
      clear only this candidate; retain/rebase only a still-current request
      arrange bounded dirty-driven reevaluation; emit no success
      return
    take only this matching attempt and clear its pending/completion state
    emit the existing ScrollCompleted(source, token, "succeeded") once
```

Clear/take the matching attempt **before** calling the event sink: event delivery may synchronously re-enter Core and configure a new request. A cancelled older task's cleanup must never clear a new task/token. Supersession, missing-target and disposal keep the existing terminal vocabulary and deduplication paths; a failed stabilization check is an internal pending reason, not a new wire outcome.

Invalidate the queued candidate on changed generation/key/index/row, source/declared owner lifetime, native connection/window/source anchor/row marker, measured extents, width, insets, source origin, viewport/document geometry or observed placement. An absent geometry update must clear old observation, not leave a previously valid sample usable. Equal physical rereads update freshness without manufacturing a mutation.

Wake from existing configuration, changed measurement, native offset/layout/bounds/insets, row/source attach/detach and owner connection callbacks. Ensure these paths actually schedule sparse reevaluation; today shared row-marker callbacks chiefly schedule the shared coordinator. No target measurement or attachment should depend on a one-shot construction callback.

Keep one delivery and one completion task per active state. A queue invalidated by new evidence may request one coalesced reevaluation for that dirty revision. Persistent missing geometry or an unchanged failed native write must wait for a real readiness/input change, rather than a self-sustaining yield loop or repeated identical corrective writes. A fresh direct read is allowed even when no offset notification fires, so an already-aligned/no-op request can complete. Preserve initial animation intent; write acceptance never shortcuts waiting for observed placement.

For diagnosis, internal debug records may join source/owner identity, attempt/token, key hash, generation, write-issued result, observation serial, desired/observed offset, geometry signature, candidate queue/invalidation/send and pending reason. Do not log document text, expose a public diagnostic API, parse receipts or treat debug records as a new protocol.

## Application and migration boundary

The app's navigation and editor obligations remain independent when they share a source/owner. No change is needed to `issued_reveal.ml`, injected epoch/UUID/scope/route/repository/current-control checks, or source leases. `ScrollCompleted` still advances only the existing navigation scroll phase. It does not register a native editor, acknowledge retention, release an opaque receipt, end composition or acquire focus. OCaml retains release authority.

At implementation time, add a behavior-only entry to `docs/api-migrations.md`; do not edit signatures/schema or publish this unimplemented behavior as current during the proposal task. Draft wording:

> Apple sparse scroll completion now waits for current native offset and target-row geometry and rechecks token, source generation, target and owner after its asynchronous boundary. A queued success whose identity or geometry changed is discarded and reevaluated; missing native readiness remains pending until existing cancellation/missing-target handling or fresh evidence. An already-mounted target or accepted scroll write alone no longer establishes success. Public APIs, wire fields, event names/outcomes, anchor meanings and token deduplication are unchanged. Callers must continue matching the current token and intent. Scroll completion remains separate from editor readiness, focus/IME and retention acknowledgement/release.

The entry should name any implementation-time deviation from this timing policy. No application migration, new timeout, pin update or wire-version handshake is required by the proposed guard itself.

## Alternatives considered

### Add a fixed sleep or reuse a test fixture's readiness timer

A sleep cannot fence a source update, native owner replacement or geometry change after the delay. Runtime-check helpers have controlled writer assumptions that production lacks. Use observed data and lifecycle wakeups instead.

### Recheck only token/model, generation, or write success

Each is necessary but insufficient alone: the same token/index/model can outlive new geometry; a native write may be accepted before arrival or clamped differently. Check the complete current evidence tuple and physical sample.

### Mount the full path/span or add nested owners/window acknowledgments

This defeats bounded flat mounting and adds authority the existing current-generation row/owner markers can supply internally. Keep the current flat B1/retention architecture and wire.

### Relax app currentness or equate scroll completion with native handoff

This would admit stale logical intents and collapse independent navigation/editor obligations. Keep the fix in SDK completion evidence; retain exact control proofs and opaque OCaml release.

## Acceptance criteria

- Documentation-only delivery changes exactly this canonical proposed document; no runtime, tests, pins, generated contracts, API migration guide or PR state changes. Single-file and whole-repository canonical validation results are reported separately.
- A follow-up implementation cannot complete solely from an optimistic planning offset, cached height, successful native write or cold-retained mounted membership. Suppressed/unavailable native writes never produce success from the request scalar.
- Changing generation at the same index, key/index mapping, source/owner epoch/model, native scroller/window, row/source marker or measured anchor/width between A and B prevents that queued success. A still-current surviving key can rebase and later complete with new evidence; a retired request cannot replay.
- Cross-section variable heights, folds, insertion/pagination and native document/source-origin/inset changes either reconverge with a bounded current target window or remain explicitly pending/cancelled/missing under existing semantics. No whole-span mounting or nested source is introduced.
- Shared and standalone, AppKit and UIKit both supply fresh current physical evidence. Already-aligned/no-op and legitimate tail-clamped/oversized-row requests can complete; absence of an offset-change notification alone does not stall them.
- Stale/cancelled task cleanup cannot clear or complete a newer attempt. Success is emitted at most once per existing token handling, with no `await` after final validation and no mutation of a new request during synchronous event reentrancy.
- Missing geometry/measurement has a real configuration/layout/connection wakeup and does not cause unbounded task, native-write or retry churn. Guard evaluation never steals focus, modifies selection/composition or releases another lease.
- Implementation verification must exercise controlled queue/resume changes and actual native observation, not just uniform-row happy paths. Preserve bounded residency and original terminal/token/anchor behavior. Native physical scrolling, editor/focus/IME and exact register/ack/release acceptance are separate evidence, not implied by canonical document validation.

## Risks

- Stricter observation can expose missing native callbacks as a visible stall where old code emitted premature success. Both direct rereads for no-op requests and attachment/layout wakeups are required. This design deliberately adds no editor TTL or new public timeout outcome.
- Two sampled placements do not guarantee that later asynchronous text/image measurement, IME auto-reveal or another scroll writer will not move the viewport. Trace those writers rather than weakening logical fences; generalized writer arbitration is a separate decision.
- Native geometry must come from the same live owner/source and normalized coordinate system. Reusing cached shared geometry, a zero-sized standalone ownership probe, a synthetic width or stale marker would merely relabel the original bug.
- A mutation counter that changes for every equal sample can starve completion; a counter that ignores real metadata/width/anchor changes can admit stale success. Distinguish acquisition freshness from evidence mutation explicitly.
- Additional weak marker observation is bounded by mounted rows but still adds callbacks on standalone lists. Avoid full-source scans, per-frame deep tree walks or a second owner/window hierarchy.
- The 1-point tolerance and animation/correction scheduling need targeted validation on both Apple platforms. No physical failing trace or implementation result exists for this proposal. Public/wire compatibility does not eliminate the intentional behavior change that scroll success may arrive later or remain pending when readiness cannot be observed.

[sparse-config]: https://github.com/logseq/lui/blob/bc89138b7c44804ab5c0cf72e833635c85261db1/platform/apple/Sources/LUIAppleBackend/LUISparseVirtualList.swift#L117-L313
[sparse-completion]: https://github.com/logseq/lui/blob/bc89138b7c44804ab5c0cf72e833635c85261db1/platform/apple/Sources/LUIAppleBackend/LUISparseVirtualList.swift#L315-L389
[core]: https://github.com/logseq/lui/blob/bc89138b7c44804ab5c0cf72e833635c85261db1/src/lui_dynamic.ml#L534-L667
[shared-types]: https://github.com/logseq/lui/blob/bc89138b7c44804ab5c0cf72e833635c85261db1/platform/apple/Sources/LUIAppleBackend/LUISharedVirtualViewport.swift#L76-L135
[shared-geometry]: https://github.com/logseq/lui/blob/bc89138b7c44804ab5c0cf72e833635c85261db1/platform/apple/Sources/LUIAppleBackend/LUISharedVirtualViewport.swift#L427-L518
[shared-write]: https://github.com/logseq/lui/blob/bc89138b7c44804ab5c0cf72e833635c85261db1/platform/apple/Sources/LUIAppleBackend/LUISharedVirtualViewport.swift#L840-L851
[native-write]: https://github.com/logseq/lui/blob/bc89138b7c44804ab5c0cf72e833635c85261db1/platform/apple/Sources/LUIAppleBackend/LUIHostScrolling.swift#L25-L68
[probes]: https://github.com/logseq/lui/blob/bc89138b7c44804ab5c0cf72e833635c85261db1/platform/apple/Sources/LUIAppleBackend/LUISharedVirtualProbe.swift#L72-L204
[standalone]: https://github.com/logseq/lui/blob/bc89138b7c44804ab5c0cf72e833635c85261db1/platform/apple/Sources/LUIAppleBackend/LUISparseScrollProbe.swift
[issued]: https://github.com/logseq/logseq/blob/675724cafacc0b310463dae4f1ec10065c85b560/deps/ui/src/virt/issued_reveal.ml#L54-L150
[navigation]: https://github.com/logseq/logseq/blob/675724cafacc0b310463dae4f1ec10065c85b560/deps/ui/src/virt/navigation_reveal.ml#L61-L210
[editor]: https://github.com/logseq/logseq/blob/675724cafacc0b310463dae4f1ec10065c85b560/deps/ui/src/virt/outline_viewport_state.ml#L128-L228
