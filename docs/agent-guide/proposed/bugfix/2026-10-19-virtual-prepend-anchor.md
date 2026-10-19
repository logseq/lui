# Preserve virtual-list reading position across prepend

## Problem

A host cannot reliably restore a virtualized message using total scroll-height
changes. Unmeasured older rows and disappearing offscreen expanded tool groups
change that total independently of the reader's anchor. Mapre reproduces a
later reply moving the reading position after loading older history.

## Proposal

Preserve the first intersecting retained row and its actual viewport offset
when new rows are prepended. Resolve its retained identity in the new sequence,
materialize it through the virtualizer, and restore the measured offset. Keep
measurement corrections until another collection change, explicit scroll
intent or user scroll input. Appends must never reuse a prepend correction.
Mapre will remove its duplicate height-based prepend adjustment after actual
consumer acceptance. Existing tail-follow and explicit scroll intents retain
ownership of their behavior.

## Alternatives considered

### Repeated total-height compensation

Rejected because tail geometry and virtualized measurement are unrelated to
the visible row's position.

## Acceptance criteria

- Browser tests fail first on mixed-height prepends and pass using retained IDs.
- Repeated prepends, later appends, user scrolling and explicit scroll requests
  preserve their intended position without stale correction or tail jumps.
- The Mapre grouped-tool and existing history/scroll browser tests pass together.
- Melange compilation, formatting and focused function-length checks pass.

## Risks

- Scroll ownership can compete with a host; remove Mapre's duplicate prepend
  compensation when consuming this implementation.
- Row deletion or navigation must cancel an anchor that no longer exists.

## Questions

None. This implements the existing authorized latest-first Chat and grouping
requirements without changing sandbox or model execution.

## Verification

Two actual browser cases reproduce lost row identity after mixed-height and
repeated prepends before implementation; the explicit-scroll case characterizes
existing priority. All three pass afterward in Chromium, Firefox and WebKit.
The 20-case Chromium cohort also covers ordinary lists, pinned replay, tall
responses, explicit scroll completion and retained DOM attributes.

The actual Mapre consumer removes total-height compensation and passes all 31
grouped activity, tool-call, recent history and scrolling browser cases together.
This includes history beyond 1,000 rows, concurrent live events, keyboard/touch
input, navigation and restored completed tools. Melange and install builds pass;
the new helper module passes the 64-line AST check. New modules are formatted
with explicit outside-project ocamlformat support. Whole-repository @fmt still
reports existing Dune formatting differences and absent ocamlformat config;
no unrelated files or Dune declarations are modified. The consumer integration,
additional regression cohort, CI and production rollout remain separate gates.

### CI reparenting correction

CI39212575627 passes six jobs and 135 of 136 browser cases. The unchanged
virtual-tree focus case fails because a virtual list moved into a new tree
inherits the reading position of its old container when tree rows are inserted
at the front. The same existing test reproduces this locally before correction.
Only preserve a prepend anchor within the same retained parent; a reparent
also cancels any pending correction. Do not special-case tree IDs or weaken
the bounded-DOM assertion. Focus, explicit scroll and consumer regressions must
pass again on this source before release.

After this correction all eighteen Chromium virtual-list, tree-focus,
prepend and Chat-scroll cases pass together, including the unchanged failing
CI assertion. Melange/install compilation passes. Exact-head CI is still
required; this local correction does not erase the original failed run.
