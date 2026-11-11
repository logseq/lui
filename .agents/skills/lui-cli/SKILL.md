---
name: lui-cli
description: Inspect running LUI apps with the repository CLI, verify build freshness, run semantic agent commands, and capture NSH macOS app content in the background. Use for LUI CLI testing, screenshots, or native startup diagnosis.
---

# LUI CLI

Use `tooling/lui_agent.mjs` in the LUI checkout. It connects to an explicitly
enabled app endpoint; it does not launch or discover arbitrary desktop apps.
Resolve the checkout, application artifact, and endpoint before running commands.

## Connect to the actual build

Native NSH roots opt in with `LUI_AGENT_LISTEN=127.0.0.1:49380` at launch.
`LUI_OCAML_LIBRARY` selects the OCaml library. Use the app's build/launch script
for its other resources and platform services. Reuse a running endpoint when it
already serves the requested app.

```sh
node "$LUI_ROOT/tooling/lui_agent.mjs" \
  --tcp 127.0.0.1:49380 --artifact "$APP_ARTIFACT" --json hello
```

`--artifact` verifies the artifact's `.lui-build.json` receipt and source hashes
before connecting. Exit code 3 means stale or missing build evidence: use the
reported build command, then retry. `--unchecked` is an explicit diagnostic
exception; it prints a warning and must not be presented as fresh-build evidence.
If connection is refused, check the app log for `lui-agent listening on ...` and
its actual port before retrying. A startup failure may precede the listener.
Receipts describe the artifact on disk; rebuilding does not restart an existing
listener. Restart only the task-owned app and verify the endpoint's process
identity before treating its screenshot as evidence for the new build.

Read the hello response's advertised operations. Generic OCaml hosts and the
updated Logseq NSH bridge support the same semantic tree/event API. Logseq uses
its real reducer through `Lui_agent.app_target`, with ordered patch publication
before each reply. An older Logseq library without the optional agent export
must be rebuilt before using semantic commands. macOS native screenshot capture
is intercepted by the NSH host independently of the OCaml semantic operations.

## Capture app content

```sh
node "$LUI_ROOT/tooling/lui_agent.mjs" \
  --tcp 127.0.0.1:49380 --artifact "$APP_ARTIFACT" \
  "screenshot \"$OUTPUT_PNG\""
```

The CLI writes the PNG and reports its absolute path and pixel dimensions.
Inspect the resulting image with the image-viewing tool. Successful capture
proves that an image was produced; it does not establish that the app mounted
successfully. An error screen is a real startup failure to diagnose.

NSH macOS captures the application's own content view in process, on AppKit's
main queue. It does not capture the desktop or other apps and does not require
Screen Recording permission. System menus, other windows, and separately
composited video/shader surfaces are outside this capture. Other NSH operating
systems currently report screenshot support as unavailable.

When the user requests a dark or locked screen, preserve that condition. For
the Logseq NSH runner, launch with `LUI_AGENT_BACKGROUND=1` and the agent endpoint
enabled. This uses the background AppKit policy. Do not unlock, activate apps,
change display power, or substitute a desktop capture. For migration tests, use
an isolated graph/state directory; inspection of an existing user session should
retain its requested graph.

For a private Logseq native qualification, also use the runner's explicit
`--startup-preflight <absolute-private-root>` option and the environment setup in
`deps/ui/nsh/README.md` in the Logseq checkout. It selects empty owner-local
credentials and private native storage; changing HOME alone does not isolate the
OS keychain. Build before applying the private HOME environment. The regular
runner retains native credentials and storage.

## Semantic inspection and scripts

On a host advertising the semantic API, commands include:

```text
hello
dump
tree
find prop:accessibility-identifier=events-editor
prop id:4 text
type id:4 "hello 世界"
press "Save"
wait "text:Saved" 5
expect-prop id:4 text "hello 世界"
```

Pass complete command lines as individual quoted arguments, or use
`--script /path/to/flow.agent`. `--json` emits structured replies. Check the exit
status: 0 is success, 1 reports scenario failures, 2 is usage/connection failure,
and 3 is a stale artifact. The CLI reports each failing line and stops on a lost
connection. Selector details are implemented by the parser and matcher in
`src/lui_agent.ml`; inspect that source before inventing selector syntax.

Semantic commands act on the OCaml tree. They do not qualify native hit testing,
keyboard focus, IME, or visible layout. Use screenshots and the appropriate
native integration tests for those claims.

## Diagnose startup accurately

Distinguish process launch, OCaml/model startup, worker/database startup, native
mount, and usable UI. Inspect the screenshot and current logs before reporting
that the application is running normally. A loaded graph or journal route can
coexist with a rejected renderer batch.

For NSH background/locked-screen measurement, use `app::wait_for_commit()` before
querying an unbound native reference. `next_frame()` waits for a display tick and
can stall indefinitely under lock. Native measurement supplies its own layout
commit. A header alone is insufficient startup evidence: require the expected
page content in the screenshot as well as successful model/worker startup.

Record the actual app/LUI/NSH revisions, command, artifact freshness, screenshot
path, and remaining qualification gaps. Keep generated images and receipts in
ignored build directories. For native backend details, consult
`platform/nsh/README.md`; for shared host setup, consult the repository's
`testing-lui-demos` skill.
