# Vendored `drive`

Source: https://github.com/logseq/drive (`src/` at commit `17590f4`,
the `devin/lui-event-variants` event-vocabulary fix).

The unit suite drives UI behavior through `Drive.Session` / `Drive.Model`
/ `Drive.Scenario`. `drive` depends on `lui`, so an opam-installed
`drive` can only link the *installed* `lui` — never the workspace build
this suite must test. It is vendored so dune compiles it against the
local `lui` instead.

Refresh by copying `src/` from a newer `logseq/drive` revision and
updating the commit above; the `dune` file mirrors upstream's
`src/dune` minus `public_name`.
