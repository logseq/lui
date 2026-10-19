# Bounded Tool Group Layout

## Problem

Mapre's actual browser consumer shows a completed tool-group summary spanning
1160px while ordinary message content is bounded to 768px. The transcript's
Tool_group path bypasses the centered content column used by Single rows.

## Proposal

Give grouped tools the same centered bounded content surface as messages while
keeping the outer scroll viewport full width. Share the static layout helper
between Single and Tool_group, preserve host renderers, keyed child identity,
reactive metadata and disclosure state. Do not add app-specific CSS, vendor a
copy, alter Dune files or add another scroll owner.

## Alternatives considered

### Constrain the scroll viewport

Rejected because it recreates ignored wheel input in blank conversation gutters.

### Override the consumer with layout CSS

Rejected because the generic transcript already owns content_width and must
apply it consistently across row kinds and platforms.

## Acceptance criteria

- Native mounted grouped-only transcripts respect an explicit non-default
  content_width and include centered content layout; the case fails first.
- Existing host-rendering, streaming, keyed lifetime, disclosure and transcript
  tests pass. The outer viewport still grows across the conversation pane.
- The actual Mapre browser consumer has bounded centered activity, accessible
  disclosure and stable host details on desktop and mobile.
- Submit the upstream PR and consume an installed reviewed package; no vendoring.

## Risks

- Group summaries gain the same horizontal/vertical padding as message content;
  disclosure height changes must retain the host's scroll anchoring behavior.

## Questions

None. This completes the existing transcript layout contract and the user's
explicit request to fix shared LUI issues upstream before consumer integration.

## Verification

The new grouped-only mounted native case fails before the fix because no
centered/bounded content node exists. It now passes with a non-default 560px
content_width; all 25 AI cases and all 148 native test_lui cases pass. Melange
and install targets compile. The helper is shared with ordinary message rows;
no scroll viewport, event handler, public signature or dependency changes.
The consumer's desktop browser first reports an unbounded 1160px summary.
Final installed-package consumer acceptance remains pending; this decision
stays proposed until that actual browser proof is complete.
