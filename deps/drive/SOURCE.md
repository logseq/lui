# Vendored `drive`

Source: https://github.com/logseq/drive (`src/` at commit
`1e1653d5bdd0810e89d9e3a32b2e0ea2811c1cf5`, upstream `main`).

The unit suite drives UI behavior through `Drive.Session` / `Drive.Model`
/ `Drive.Scenario`. `drive` depends on `lui`, so an opam-installed
`drive` can only link the *installed* `lui` — never the workspace build
this suite must test. It is vendored so dune compiles it against the
local `lui` instead.

Refresh by copying `src/` from a newer `logseq/drive` revision and
updating the commit above; the `dune` file mirrors upstream's
`src/dune` minus `public_name`.

## Local additions

Not yet upstream; carry them forward when refreshing:

- Refused-call diagnostics: optional `last_error` / `resync` target symbols
  in `drive_target.c`, `Ffi.check_refusal` (drain, `Model.clear`, resync,
  then fail the scenario line) and `Model.clear`.
- Application clock control: `Session.clock_command` and the driver's
  `clock` field, the scenario `clock pause|resume|advance <duration>|settle`
  command, `Ffi` clock calls, and the optional `clock_advance` /
  `clock_set_paused` target symbols in `drive_target.c`.
