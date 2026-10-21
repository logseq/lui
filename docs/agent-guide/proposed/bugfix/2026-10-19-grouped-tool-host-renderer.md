# Grouped tool host renderer

## Problem

Transcript single rows use the host item renderer, metadata and styles, but
grouped tool children call the built-in tool card directly. Enabling work
grouping therefore loses host-specific tool details and identity attributes.

## Proposal

Route grouped children through a shared host-aware tool rendering helper while
retaining the built-in card when the host returns None. Preserve keyed child
identity, borrowed signal ownership, live metadata and the group disclosure
state. Use an ordinary non-interactive wrapper so tool accordions do not become
nested buttons. Keep the public API stable and update its documentation.

This is an upstream LUI change, published as a PR before Mapre changes its
installed package pin. Do not copy library source into the consumer. The user's
clean composer and full conversation scrolling milestones are now deployed;
this repair resumes the remaining grouped activity work.

## Alternatives considered

### Replace the consumer transcript

Rejected because it duplicates the library's grouping and lifecycle ownership
and conflicts with the requested reusable LUI AI integration.

## Acceptance criteria

- Actual mounted component tests reproduce missing host rendering before the
  fix. Cover custom rendering, default fallback, updated tool content and
  metadata, keyed child retention, disclosure and disposal without disposing
  caller-owned signals. Keep pure grouping/order tests intact.
- Compile native and Melange targets and run the existing relevant test suites.
  Validate actual browser behavior through the consumer after installation.
- Keep source functions at most 64 formatted lines. Do not modify Dune files,
  disable warnings or use unsafe casts. Commit and push, then create the LUI PR.
- Update Mapre only after upstream review/acceptance and prove its tool details,
  identities, grouped summaries and scroll behavior in an actual browser.

## Risks

- Grouping can remount children or accidentally dispose their borrowed signals.
  A native protocol-tree check alone does not establish browser semantics.

## Questions

None. The user explicitly requests grouped work in the UI reference, reuse of
LUI components, an upstream PR first and no vendoring.

## Verification

Four mounted component regressions fail against the original implementation:
grouped host rendering, grouped live metadata/callbacks, ordinary live metadata,
and keyed host lifetime. The shared host-aware body selection and a plain
group-child column make all four pass. Default tool fallback and output updates
remain covered; inserting/removing tools preserves child identity and the user's
disclosure choice. Removed host children dispose once while the caller message
stream continues to accept changes.

The focused 24-case lui_ai cohort and the complete 147-case test_lui native
target pass. Melange compilation through @web passes, as does the OCaml AST
64-line check on the changed source/test modules. No Dune file, warning setting
or unsafe cast changed. Actual consumer browser acceptance follows publication
and installed-package review; it is not established by the native checks alone.

The new decision passes its individual check. The repository-wide document check
still reports two existing legacy paths, 001-implementation-review_report.md
and 002-review-fixes.md; this change does not rename unrelated historical files
or claim that repository-wide check passed.
