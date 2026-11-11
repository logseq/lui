# Native surface composition gaps

This records source inspection against NSH revision
`028574b7de9ee25a7c6f60660ef72fcb8790a27e`, rechecked against official main
`de7f3637171b769f18474796fd5159a60b2de726`. Toast and ResizeHandle source is
unchanged between those revisions. The only ContextMenu-file change is an
ordinary Menu keyboard `for_focus` option; it does not change ContextMenu
composition. The public builder adds MouseUp observation, with no new
layout-through attachment or controlled toast reset API. All gaps below remain.
These are specific composition requirements, not permission to use private NSH
APIs or a claim that the merged fork has already completed runtime qualification.

## Motion inventory for the next native increment

| State change | Native mechanism | Reduced motion |
| --- | --- | --- |
| Resizable pointer movement | ResizeHandle capture; direct bounded width update | Same direct tracking |
| Resizable source or constraint update | Immediate accepted geometry | Same immediate geometry |
| Toast arrival/removal and stack expansion | ToastStack's native measured layout and motion tokens | Native reduced-motion path |
| Toast swipe | Toast's native pointer tracking and release | Direct tracking; controlled refusal remains an explicit API gap |

Headless qualification checks native behavior and geometry. It does not qualify
light/dark appearance, screen-reader output or real desktop animation.

## Context menus on an existing host

`nsh-base/src/menu.rs` implements `ContextMenu` as an ordinary root `View`
containing its trigger slot and a native menu surface. The trigger slot uses
NSH's layout-through holder mechanism and preserves the filled element's
reference. The outer root remains an additional layout participant.

Wrapping an existing LUI host therefore changes its relationship to its parent.
In particular, flex growth, intrinsic sizing, margins and explicit dimensions
cannot simply remain on the nested trigger. Moving only those declarations to
the menu root also requires an explicit rule for the trigger's inner dimensions
and intrinsic layout. A general style partition would add substantial layout
complexity to the adapter.

The required public API is an attachment/controller form of native ContextMenu
that observes an existing trigger without replacing its layout placement. NSH
must continue to own secondary-click and long-press handling, keyboard opening,
roving focus, collision handling, dismissal and focus restoration. Qualification
must compare host bounds, ElementRef/native ID and an edited child's focus and
draft before and after opening, dismissing and updating menu actions. MenuItem
also needs the separately reviewed opt-in typed activation-details projection
before LUI press-detail/modifier callbacks can be claimed.

The adapter does not substitute a generic View for this behavior.

## Toast dismissal refusal

`nsh-base/src/toast/root.rs` animates the toast offscreen before emitting
`ToastEvent::DismissRequest`. There is no public controlled visibility or reset
prop. When the application retains the same LUI toast after receiving Dismiss,
the native translation remains offscreen. Remounting to reset it would discard
editor/native identity. The maintained Apple implementation resets its drag
offset after requesting dismissal.

The required public behavior is a controlled dismissal response, or a public
reset that restores the retained native toast when the application refuses the
request. A refusal must preserve the toast and its children, including focus and
draft. This requirement concerns native swipe dismissal; the adapter can keep
timeout notification separate from structural visibility.

Native ToastStack already supplies stacking, hover/touch expansion, Escape and
layout motion. Its public placement belongs to the whole stack. Distinct LUI
toast placements consequently need explicit routing to stacks; moving a toast
between stacks requires separate identity qualification.

## ResizeHandle accessibility

The public ResizeHandle owns drag capture and exposes DragStart, DragMove,
DragEnd and StateChange. Its band has the Adjustable role, but its props do not
expose increment/decrement action callbacks. The LUI resizable adapter therefore
puts the existing canonical 16-point adjustable actions on the existing LUI
root and uses the native handle for pointer interaction.

Consolidating those actions on the native band requires public handle action
callbacks and corresponding range/value presentation. The adapter does not
claim a new native keyboard-arrow implementation. Its current Headless
qualification covers real native drag and release, minimum/maximum bounds,
source-width reset, constraint updates and retained editor ID/draft.
