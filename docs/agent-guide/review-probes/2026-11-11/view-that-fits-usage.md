# ViewThatFits downstream usage

The requested removal is conditional on both maintained applications not using
the component. That condition is false; keep the API and its implementations.

- `mobile` at `82b6da991bc0e6987f652f6f5cd91d1e37f58498`: no source
  references found for `ViewThatFits`, `view_that_fits`, `view-that-fits` or
  `viewThatFits` in the repository search excluding dependency/build trees.
- `logseq_journal` at `6c030857d0bc417d11394a73282a87416b8006cc`:
  `app/journal_header.ml:48` directly calls `Lui_elements.view_that_fits` to
  choose compact/expanded operation feedback. This is a production path:
  `app/application.ml:2264` calls `Journal_header.feedback`, which reaches
  `feedback_with_visibility`.
- Journal also calls SwiftUI's own `ViewThatFits` in
  `swift/JournalChrome.swift:650`. That is independent of the LUI component
  and does not replace the OCaml call above.

No downstream source or Dune file was changed. NSH fitting remains a required
compatibility seam rather than an unused component to retire.
