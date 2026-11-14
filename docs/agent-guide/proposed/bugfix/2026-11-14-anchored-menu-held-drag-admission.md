# Guard retained anchored menu declarations during held drag

## Problem

Apple anchored dropdowns can be presented outside `LUIAnchoredPopoverStore`. `LUIStackView` selects `LUIAnchoredMenuHost`, whose three presentation branches set a local `isPresented` Boolean to `model != nil` whenever the menu model revision changes. Its Boolean binding sends `Dismiss` using the captured model without a retained-declaration tombstone or an exact presentation lease. Consequently, dismissing a native menu does not by itself prevent a later patch from reopening the same retained declaration; a delayed callback also lacks an explicit host/session identity check. These are source-level gaps, not a physical held-drag reproduction.

The earlier coverage matrix correctly distinguished `menu_card`/`dropdown_menu` from guarded `popover` declarations, but its menu inventory was incomplete and must not be interpreted as ten identical native presenters. It listed ten consumer sites and omitted the shared calendar's month selector. Actual dispatch also matters: a menu under a stack, a column, and a native `menu_trigger` does not take the same Apple presentation path.

## Proposal

Add a **backend-owned, menu-specific retained-declaration admission domain** for the existing `LUIAnchoredMenuHost`. Reuse the popover guard's lifecycle rules, physical-button sampling policy and exact callback matching principles; do not put menus into the existing popover store or share its live tombstone dictionary. On macOS, reject a new or rebound hosted-menu candidate observed while any physical mouse button is held, and keep that declaration suppressed until its retained menu model really retires. Preserve an already admitted unchanged menu during ordinary drag/selection. Releasing the button does not replay rejected declarations.

On iOS, the physical-held predicate remains false, as in the existing popover guard. Both the hosted popover branch and the confirmation-dialog branch use the menu dismissal lifetime/lease checks. Keep their current presentation-selection policy and geometry.

This is a **proposed design**, requested as a document-only deliverable. It does not authorize implementation, assert a reproduced menu reopening bug, or claim that all application dropdowns acquire coverage. No public Swift/OCaml API, wire field, schema, event type, Core acknowledgment or receipt format changes. No app/source/test/pin changes are part of this deliverable. The later implementation must record the intended timing/lifetime behavior change in `docs/api-migrations.md`.

## Evidence baseline and scope correction

Current SDK base is **`3a3fcc929ffd6c844525bfc919bf3180d4eff2c5`**; application inventory is **`26350662d0c6bd59b3b08c5b4181dfb895ce16db`**. The menu root, popover store, backend and `lui_elements.ml` files are byte-identical between SDK `494beda57a234a9c8edb67a7707a76c02b0a5b65` (the coverage audit baseline) and this SDK base. Source links below pin the current SDK, not a mutable branch. The application's subsequent pin-only update does not change these factory bodies.

| Existing source | Consequence |
| --- | --- |
| [Node dispatch][dispatch], [stack presenter selection][stack], [committed child slots][slots] | Only the actual `LUIAnchoredMenuHost` path is in this admission domain. A stack selects the first anchored dropdown; a combobox trigger has higher presenter priority. A select with no menu is not an open declaration. Row/column layouts have different view types. |
| [Hosted menu Boolean/revision/dismiss path][host] | Replace revision-driven reopening with admission for an exact retained declaration and current attachment lease; preserve both platform branches. |
| [Menu attachment placement][placement], [menu presentation policy][policy] | Menu anchoring is the host content's `UnitPoint`, not popover named-target/root/rectangle resolution. iOS chooses a popover for disabled/nested/arbitrary/empty content, otherwise a confirmation dialog. |
| [Popover store][popover-store], [backend popover synchronization][popover-sync] | Reuse the retained-model/no-replay invariants. Its candidate/retained sets are popover-only and cannot collect or preserve menu tombstones correctly. |
| [Dropdown content and Escape][dropdown], [native menu trigger][native-trigger] | Hosted Escape needs the same exact close lease. Inline dropdowns and native `Menu` tracking remain separate paths; do not turn a submenu into a new guarded root popup. |
| [Existing virtual popup ownership][ownership], [commit synchronization][commit] | Integrate with existing committed models and ownership callbacks; admission is not native presentation/focus/scroll/release proof. |

The audit's **ten original consumer sites** are retained below. They are source factory sites, not simultaneous instances. The `menu_card` wrapper's own `dropdown_menu` constructor is not an additional consumer. “Host path” is a static dispatch classification, not proof of a live native window:

| # | Pinned app site | Parent/path evidence and scope |
| --- | --- | --- |
| 1 | [Cards deck/options dropdown][app-cards] | `opts_box` attaches its dropdown under the selector's `box`; hosted-menu candidate. |
| 2 | [Reusable dots menu][app-dots] | Factory returns a `row`; its dropdown is not automatically routed through `LUIStackView`. A host-only change cannot claim coverage for this path. |
| 3 | [Export selector][app-export] | `box` with select + conditional `menu_card`; hosted-menu candidate. |
| 4 | [Component context submenu][app-submenu] | Child of `menu_trigger`; native `Menu`/submenu semantics, not an independent `LUIAnchoredMenuHost` session. |
| 5 | [Component point context menu][app-context] | Has `at` and `anchor`; selected only in the [component-menu environment branch][app-context-route]. Coverage depends on its actual parent/selected host slot. Do not infer a named anchor or universal point-menu coverage from the constructor. |
| 6 | [Property type selector][app-property-type] | `box` with select + conditional `menu_card`; hosted-menu candidate. |
| 7 | [Property repeat selector][app-property-repeat] | `column` with select + conditional `menu_card`; not automatically this host. |
| 8 | [Settings date-format selector][app-date-format] | `column` control in `date_format_row`; not automatically this host. |
| 9 | [Settings language selector][app-language] | `lang_trigger` uses a `box` specifically for hosted anchoring. |
| 10 | [View sort selector][app-sort] | `box` with select + conditional `menu_card`; hosted-menu candidate. |
| Additional helper consumer | [Calendar month selector][app-calendar] | A live `menu_card` call inside `Ui_components.calendar`, omitted from the earlier matrix; [property date content calls that calendar][app-calendar-use]. Its immediate parent is a `column`, not automatically this host. |

Thus the corrected inventory is **three direct consumer constructors + eight `menu_card` consumers = eleven sites**, plus the shared wrapper implementation. The additional calendar entry is a correction to the prior audit, not a newly added application menu. This proposal does **not** reroute row/column/point/native-menu paths or advertise eleven guarded native hosts. Extending admission to those presenters requires a separate path-specific decision, especially for native press-drag tracking.

## Separate domain, shared rules

Use a small internal `@MainActor` menu admission owner, conceptually `LUIAnchoredMenuAdmission`, held by `LUIAppleBackend`. Names in this document describe internal responsibilities, not new public Swift declarations.

| Concern | Proposed owner and lifetime |
| --- | --- |
| Retained menu declarations | Backend model registry, filtered by actual dropdown model identity, independent of visibility, eligible host slots or SwiftUI mount state. Retained does not mean presented. |
| Menu tombstones | Menu admission owner keyed by exact retained menu model identity, holding that model while it remains retained. Purge only on real backend model retirement/replacement/reset; numeric node ID reuse cannot revive the old object. |
| Logical candidates | Current reachable host model + selected anchored-menu slot + exact menu model, using the existing stack/combobox priority. Reuse committed child data rather than inspecting only mounted views. |
| Native presentation lease | Unique host attachment incarnation, current host/menu model identities, selected native presentation mode and weak current native attachment/window evidence. It authorizes one native binding session. It is not a Core receipt. |
| Geometry | Current host attachment point, anchor side/alignment/offset and size; mutable placement data, never the declaration identity. |

The popover store keeps its own retained popover set, named/root/point anchor resolver, items and tombstones. Feeding menu entries into `anchoredPopovers.synchronize` would either discard them during popover-only retained filtering or conflate unrelated anchor slots. A single global “any popup closed” bit would also suppress unrelated menus and popovers.

Initially leave B's implementation unchanged. Share the policy vocabulary and physical-button read (`NSEvent.pressedMouseButtons != 0` on macOS; false on iOS); extract a small pure/internal helper only if implementation reveals identical operations in both stores. A generic popup manager, cross-surface cooldown and shared live tombstone set are unnecessary.

## Menu anchor and session semantics

Pass the exact owning host model internally from `LUIStackView` into `LUIAnchoredMenuHost`; the current initializer supplies only the optional menu model. The host is the stack content modified by `.popover`/`.confirmationDialog`, **not necessarily its preceding select/button child**. Validate that this exact host is still current and still selects this exact menu via the committed slot and presenter priority.

An admission identity must distinguish:

- retained menu object/incarnation and node ID;
- current owning host object/incarnation and node ID;
- exact native host attachment/window incarnation;
- current presentation lease and iOS native mode for stale-callback rejection.

Do not use model revision, key text, anchor coordinates, anchor alignment/offset, menu contents or rectangle movement as a fresh opening session. Replacing the owning host or native attachment is a rebind even when the numeric menu ID stays the same. A private attachment probe/lease must detect real attach/detach/window replacement; a UUID recreated on every body evaluation or a `@State` flag that silently survives a different host does not establish that identity. Do not assume a SwiftUI background probe contains sibling native controls.

Preserve `attachmentPoint`, `arrowEdge` and `arrowEdgeOffset` exactly. `AnchorTarget`/popover root fallback/global `AnchorRect` resolution are not imported. Point properties can coexist with menu anchoring, but this guard observes whichever host the current renderer actually selected; it must not relocate the menu or reinterpret its coordinate space.

For an iOS policy change between confirmation dialog and popover, revoke the old native lease **before** programmatic teardown, then bind the existing admitted declaration to a fresh mode-specific lease if still eligible. Mode/geometry changes do not clear a tombstone. Old native setters must not dismiss the replacement. No mode change invents a new logical open event.

## Admission, dismissal and retirement

Synchronize retained models and logical host candidates at the existing committed-tree boundary before view presentation updates. Sample physical buttons when a declaration first becomes a logical candidate and again when a new/rebound native attachment requests admission. If first seen while held, tombstone immediately even if geometry/view attachment is not ready; deferring that decision until after release would silently replay it.

| Transition/evidence | Proposed result |
| --- | --- |
| New eligible hosted declaration, current host/attachment, no held button | Admit one native lease; ordinary release-activated and keyboard opens continue. |
| Current unchanged admitted declaration while held | Keep it admitted; do not close an already open menu just because the user drags/selects inside it. |
| New declaration or host/attachment rebind observed while held | Reject and tombstone that retained menu declaration; no new native presentation, synthetic `Dismiss` or item activation. |
| Matching native close/Escape for current admitted lease | Take/revoke the lease and tombstone the declaration **before** emitting the existing `Dismiss` once. |
| Native callback from an older model, host, attachment, mode or lease | Ignore it; no event or mutation of the current session. |
| Revision/content/rect/size changes, unrelated commit, temporary invisibility or ineligibility | Recompute placement/eligibility as needed; never clear a tombstone. A temporary lack of a candidate is not retirement. |
| Button release | No replay, timer or observer-driven reopening. A retained tombstoned declaration remains suppressed. |
| Actual retained-model retirement | Remove only that declaration's menu tombstone/leases. A later genuinely new declaration after release may open. |
| Host detach/disposal | Revoke only its exact native lease and ownership attachment; never erase another host's lease or mistake view disposal for model retirement. |

Replace all three `onChange(model?.revision)` assignments with synchronization/admission results. Observe exact model/host/lease identity as well as revision, because replacement objects can share a revision number. Native binding getters are side-effect-free: all suppression/retirement mutations occur in main-actor commit/attachment callbacks, not SwiftUI body evaluation. A rejected binding remains false without repeatedly trying presentation.

Binding setters and hosted Escape capture the immutable admitted lease, then resolve the current backend models/host slot/attachment and compare the complete lease before closing. Do not look up “whatever menu is now in this host” and dismiss it on behalf of an old callback. Revocation happens before `performDismiss`; a reentrant reducer may retire the old declaration and create a new one while handling that event. Cleanup after the callback cannot clear the new lease. Programmatic retirement or native-mode migration is not a second interactive dismissal.

`LUIDropdownMenuView` currently sends Escape directly to `performDismiss`. A private hosted-content close callback can route that path through the current lease while preserving the existing inline fallback. Existing item `Press`, enabled checks and native confirmation-dialog action behavior remain; do not synthesize an extra dismiss on selection or replay an action after release. Root/native `Menu` submenu tracking is excluded from this host domain.

Wake from committed candidate changes, actual attachment changes and native close callbacks. No polling, fixed settling sleep, 150ms Appearance suppression marker, queued release reopen, mandatory new event or application “open token” is introduced. A failed/absent attachment remains ineligible until real evidence changes.

Physical sampling has a defined limit: if a stale producer first delivers a **new** declaration only after release, the existing API carries no causal input identity that proves it belongs to the earlier drag. Do not claim this proposal rejects that case or invent a cross-drain activation capability without evidence. Native mouse-down/press-drag root menu activation has different semantics and must not be blanket rejected through this custom hosted-menu rule.

## Minimal future implementation shape

| Touchpoint | Internal change |
| --- | --- |
| New internal menu admission type, or a dedicated backend-local section | Retained menu tombstones, current candidate/lease registry, held predicate and exact take/dismiss matching. Keep menu state independent from B. |
| `LUIAppleBackend.swift` | Track retained dropdown identities, derive actual host candidates from committed data/reachability, synchronize at commit/reset/drop, and preserve model-incarnation checks across deferred native callbacks. Use one bounded/linear pass or existing tracked sets, not repeated whole-tree scans per SwiftUI getter. |
| `LUISwiftUIRoot.swift` | Supply owning host identity, bind all three menu branches to admission, manage exact attachment leases, route hosted Escape, preserve menu geometry/presentation policy and native/inline exclusions. |
| Private host-attachment probe if no current seam suffices | Main-actor attach/detach/window evidence with exact lease cleanup. Do not add a wire-visible host ID or infer liveness from a constructor callback. |
| `docs/api-migrations.md` after implementation is authorized | Record behavior-only retained-dismissal/held-admission change and concrete reopen migration; public/wire interfaces unchanged. |

No OCaml view, app wrapper, Dune/schema, Android/Web/Electron code or far-scroll completion changes are needed for this **host-scoped** proposal. Any later rerouting of row/column or point menus is separately reviewable work, not an incidental way to inflate coverage.

## Migration wording to use after implementation

Apple hosted anchored dropdowns no longer reopen merely because an interactively dismissed retained menu receives another revision. On macOS, a declaration first admitted/rebound while a mouse button is held stays suppressed after release. Closing must retire the mounted declaration; a later independent activation after release may create a new one. A local false-to-true toggle coalesced before the host observes removal is not sufficient retirement.

For example, a selector's existing `on_dismiss` sets its `open` signal false and lets the conditional dropdown removal commit. The next ordinary activation sets it true again. Updating an item's label to force a revision is no longer a reopen mechanism. Existing event names, API signatures and selected-value handlers are unchanged. This does not add the guard to native `Menu`, row/column inline dropdowns, comboboxes or tooltips.

## Alternatives considered

### Reuse the existing popover store and its tombstone set

Rejected: the store collects popover models and resolves named/parent/root/rect anchors. Hosted menus have their own retained set, owning content anchor and iOS native-mode lifecycle. Combining the live dictionaries changes B's authority and filtering and risks cross-surface suppression. Reuse its rules instead.

### Keep only a per-view dismissed Boolean, or clear suppression on revision/geometry loss

Rejected: remounts/virtualization lose local state while the declaration remains retained; revision/geometry changes are exactly the suspected reopening path. Backend model retirement must own tombstone collection.

### Add a timer or automatically retry on mouse-up

Rejected: release replay presents a declaration already rejected during the drag, and an arbitrary deadline cannot establish a new opening session. Appearance's application-specific suppression window is not a generic SDK menu contract.

### Apply one global held predicate to every dropdown, native `Menu` and context submenu

Rejected: press-drag tracking and permanently mounted native menu declarations are valid different lifecycles. Source constructor counts do not prove presenter coverage. Keep this first decision scoped to the existing hosted presenter; expand only with explicit per-path semantics.

## Acceptance criteria

- Source inventory explicitly includes the ten earlier sites and calendar helper correction; each claimed covered case resolves to the actual `LUIAnchoredMenuHost` path. Native/inline/combobox exceptions are stated without claiming runtime coverage.
- A matched close followed by retained-model revision, resize, source invisibility, reparenting, view remount and button release cannot reopen the tombstoned hosted declaration. Only real model retirement removes its tombstone.
- New or rebound hosted candidates observed held remain suppressed even if their native view first attaches after release; an unchanged already-open menu continues drag/selection normally.
- No-button fresh declarations and genuinely retired-then-recreated declarations open normally. Same numeric IDs with replacement objects do not accept old callbacks or inherit an unrelated object's identity.
- Stale native close/Escape callbacks cannot dismiss a replacement host/model/mode/lease. Matched dismissal emits the existing event once; reentrant replacement survives old cleanup.
- iOS popover and confirmation-dialog paths share dismissal lifetime checks without a macOS button predicate. Mode changes preserve content/action semantics, revoke the old lease first, and do not clear suppression.
- Rejected/absent sessions do not create popup ownership pins. Admitted sessions continue existing `LUIVirtualPopupOwnership` and native ownership tracking; suppressing a declaration is not evidence that a previously native popup has physically closed.
- No `Focus`/IME operation, `VirtualScrollIndex`/`ScrollCompleted` dependency, mandatory acknowledgment, opaque-release decision, nested source/owner, new wire/API or release timer appears. Existing flat B1 planning and app editor/navigation fences remain independent.
- Future implementation evidence distinguishes deterministic retained-state/lease checks from actual macOS drag/outside-dismiss/keyboard and iOS mode behavior. This proposal has run no build, tests, GUI or physical acceptance and transfers no CLEAN result from the popover/far-scroll work.

## Risks

- Stricter dismissal lifetime intentionally removes revision-as-reopen behavior documented in the old host comment. A client that keeps a dismissed hosted declaration mounted must adopt actual retirement before reopening; native `Menu` clients must not be swept into that migration.
- An application intentionally opening this custom hosted menu on mouse-down would be rejected by the proposed held rule. Such activation needs a separate explicit policy/provenance design; no unsupported exception or synthetic causal token is assumed here.
- Backend logical eligibility and real native attachment occur at different times. Both sampling seams and exact-lease cleanup are implementation obligations; a view-only predicate can miss a held rejection or erase it on remount.
- The additional calendar consumer and nonuniform routing mean a host-only patch leaves meaningful dropdown paths outside this domain. That limitation is explicit; it is not complete popup/PL parity.
- Native callback ordering, iOS mode transitions, selection/focus/IME and actual retained-row release still need focused implementation review and physical validation. Admission state alone proves none of them.

[dispatch]: https://github.com/logseq/lui/blob/3a3fcc929ffd6c844525bfc919bf3180d4eff2c5/platform/apple/Sources/LUIAppleBackend/LUISwiftUIRoot.swift#L794-L834
[stack]: https://github.com/logseq/lui/blob/3a3fcc929ffd6c844525bfc919bf3180d4eff2c5/platform/apple/Sources/LUIAppleBackend/LUISwiftUIRoot.swift#L2080-L2114
[slots]: https://github.com/logseq/lui/blob/3a3fcc929ffd6c844525bfc919bf3180d4eff2c5/platform/apple/Sources/LUIAppleBackend/LUIAppleBackend.swift#L1889-L1938
[host]: https://github.com/logseq/lui/blob/3a3fcc929ffd6c844525bfc919bf3180d4eff2c5/platform/apple/Sources/LUIAppleBackend/LUISwiftUIRoot.swift#L2485-L2592
[placement]: https://github.com/logseq/lui/blob/3a3fcc929ffd6c844525bfc919bf3180d4eff2c5/platform/apple/Sources/LUIAppleBackend/LUISwiftUIRoot.swift#L2605-L2643
[policy]: https://github.com/logseq/lui/blob/3a3fcc929ffd6c844525bfc919bf3180d4eff2c5/platform/apple/Sources/LUIAppleBackend/LUISwiftUIRoot.swift#L4303-L4335
[popover-store]: https://github.com/logseq/lui/blob/3a3fcc929ffd6c844525bfc919bf3180d4eff2c5/platform/apple/Sources/LUIAppleBackend/LUIAnchoredPopover.swift#L8-L79
[popover-sync]: https://github.com/logseq/lui/blob/3a3fcc929ffd6c844525bfc919bf3180d4eff2c5/platform/apple/Sources/LUIAppleBackend/LUIAppleBackend.swift#L1998-L2055
[dropdown]: https://github.com/logseq/lui/blob/3a3fcc929ffd6c844525bfc919bf3180d4eff2c5/platform/apple/Sources/LUIAppleBackend/LUISwiftUIRoot.swift#L4478-L4525
[native-trigger]: https://github.com/logseq/lui/blob/3a3fcc929ffd6c844525bfc919bf3180d4eff2c5/platform/apple/Sources/LUIAppleBackend/LUISwiftUIRoot.swift#L4713-L4742
[ownership]: https://github.com/logseq/lui/blob/3a3fcc929ffd6c844525bfc919bf3180d4eff2c5/platform/apple/Sources/LUIAppleBackend/LUISparseVirtualList.swift#L21-L29
[commit]: https://github.com/logseq/lui/blob/3a3fcc929ffd6c844525bfc919bf3180d4eff2c5/platform/apple/Sources/LUIAppleBackend/LUIAppleBackend.swift#L1277-L1301
[app-cards]: https://github.com/logseq/logseq/blob/26350662d0c6bd59b3b08c5b4181dfb895ce16db/deps/ui/src/cards/cards_view.ml#L12-L65
[app-dots]: https://github.com/logseq/logseq/blob/26350662d0c6bd59b3b08c5b4181dfb895ce16db/deps/ui/src/core/menu_item.ml#L54-L89
[app-export]: https://github.com/logseq/logseq/blob/26350662d0c6bd59b3b08c5b4181dfb895ce16db/deps/ui/src/export/export_view.ml#L35-L74
[app-submenu]: https://github.com/logseq/logseq/blob/26350662d0c6bd59b3b08c5b4181dfb895ce16db/deps/ui/src/popups/popups_view.ml#L809-L825
[app-context]: https://github.com/logseq/logseq/blob/26350662d0c6bd59b3b08c5b4181dfb895ce16db/deps/ui/src/popups/popups_view.ml#L861-L865
[app-context-route]: https://github.com/logseq/logseq/blob/26350662d0c6bd59b3b08c5b4181dfb895ce16db/deps/ui/src/popups/popups_view.ml#L1624-L1633
[app-property-type]: https://github.com/logseq/logseq/blob/26350662d0c6bd59b3b08c5b4181dfb895ce16db/deps/ui/src/properties/properties_dialog.ml#L365-L397
[app-property-repeat]: https://github.com/logseq/logseq/blob/26350662d0c6bd59b3b08c5b4181dfb895ce16db/deps/ui/src/properties/properties_value.ml#L826-L849
[app-date-format]: https://github.com/logseq/logseq/blob/26350662d0c6bd59b3b08c5b4181dfb895ce16db/deps/ui/src/settings/settings_page.ml#L292-L352
[app-language]: https://github.com/logseq/logseq/blob/26350662d0c6bd59b3b08c5b4181dfb895ce16db/deps/ui/src/settings/settings_view.ml#L102-L195
[app-sort]: https://github.com/logseq/logseq/blob/26350662d0c6bd59b3b08c5b4181dfb895ce16db/deps/ui/src/views/views_head.ml#L226-L251
[app-calendar]: https://github.com/logseq/logseq/blob/26350662d0c6bd59b3b08c5b4181dfb895ce16db/deps/ui/src/shared/ui_components.ml#L1372-L1403
[app-calendar-use]: https://github.com/logseq/logseq/blob/26350662d0c6bd59b3b08c5b4181dfb895ce16db/deps/ui/src/properties/properties_value.ml#L982-L991
