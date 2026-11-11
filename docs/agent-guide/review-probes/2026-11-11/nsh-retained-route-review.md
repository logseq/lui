# NSH retained route review

The two source-review findings below were fixed before the initial draft.
The current checkpoint is identified by `nsh-support-inventory.md`. They are
distinct from the general property/event parity gaps in that inventory.
Validation used the real NSH headless engine with a desktop/macOS environment,
not a native Windows or Linux window. No Dune files were changed.

## Popup ownership validation misses unchanged sibling menus

Evidence: `platform/nsh/src/render.rs`, `validate_themes` around lines 802–833,
`validate_popup_shape` around lines 895–916, and `displayed_children` around
lines 738–762.

Begin with a valid column whose children are `[select10, dropdown20]`. Insert
a newly created button30 at index 1 without changing either existing child.
The transaction touches the column and button30. Neither the column's parent
nor its theme changes, so the existing dropdown20 is absent from the popup
shape-validation candidate set.

Consequently, the transaction can commit although dropdown20 no longer has
the adjacent picker owner required by `validate_popup_shape`. Publication
recomputes select10's popup as absent and exposes dropdown20 through ordinary
displayed children. A retained popup can therefore change placement and native
ownership during an unrelated sibling insertion instead of rejecting the
invalid final tree atomically.

Implemented resolution: each structurally changed parent validates the final
sibling sequence in one adjacency walk. It checks unchanged dropdown children
as well as new ones. Property-only edits retain the previously validated owner
without searching the parent again. Ordinary select/combobox property edits
also skip recomputing an unchanged popup association.

The regression `structural_sibling_insertion_revalidates_existing_menu_ownership_atomically`
keeps the sibling-owned menu retained outside the displayed root and edits a
live editor in the displayed root. The invalid sibling insertion is combined
with an editor change; rejection preserves Store generation, every existing
Store and renderer Signal Arc, child-vector sharing, the popup association,
editor value and native editor identity. A following valid property batch can
reuse the rejected generation and continue editing.

## Toolbar orientation changes do not update native keyboard navigation

Evidence: `platform/nsh/src/controls.rs` around lines 559–566 captures
`initial.string("orientation")` when constructing ToolbarProps. In contrast,
`style.rs` around lines 471–490 reads the current orientation for flex
direction.

Pinned NSH's `crates/nsh-base/src/toolbar.rs` around line 62 reads axis with
`get_untracked` once and creates `Roving::new(Pattern::Toolbar(axis))`. Its
documented horizontal keys are Left/Right; vertical keys are Up/Down.

Changing the retained LUI toolbar from horizontal to vertical can therefore
rotate the visible layout while its keyboard focus traversal remains
horizontal. Replacing the static property with a reactive Prop alone would
not change NSH's existing roving controller. A narrow interim policy would
reject an orientation mutation before publication, as the adapter already
does for unsupported changes to popup anchor sources. A complete dynamic
solution needs a public native behavior path and an identity-preserving
keyboard regression; remounting focused descendants is not equivalent.

## Toolbar remount requirement

Implemented interim policy: changing a retained toolbar between horizontal and
vertical now fails before Store/native publication. Omitted orientation and
explicit horizontal are equivalent. Creating a new toolbar incarnation can
select either orientation.

Applications that need to change the axis must deliberately remount the toolbar
through a new keyed/model node identity. This is an explicit lifetime change;
restore application-owned state and desired focus deliberately. The backend
does not silently remount a focused subtree to accommodate an axis change.

The regression `toolbar_axis_mutation_is_rejected_without_losing_horizontal_keyboard_state`
focuses the first toolbar item by keyboard, attempts the invalid axis/editor
batch, then confirms Right followed by Space still activates the second item.
The failed batch preserves all Store/Signal Arcs, generation, menu association
and accepted editor value; an ordinary presentation update remains valid.

## Validation evidence

- Ten focused `render::theme_tests` passed, including both new regressions and
  existing theme, popup, menu and identity checks.
- All seven `store_transactions` tests passed, including wire defaults and
  OCaml integer-range policy.
- Strict `cargo clippy --locked --all-targets -- -D warnings` and global
  `cargo fmt --check` passed with no warning suppression.

Local logs: `/tmp/lui-nsh-retained-validation-tests.log`,
`/tmp/lui-nsh-retained-store-tests.log`, `/tmp/lui-nsh-retained-clippy.log`, and
`/tmp/lui-nsh-retained-fmt.log`. These checks do not establish native Windows
or Linux window behavior.
