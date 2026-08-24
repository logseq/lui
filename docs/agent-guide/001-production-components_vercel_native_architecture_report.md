# Vercel Native architecture research

Date: 2026-08-24

Status: accepted implementation guidance

Reference repository: `vercel-labs/native`

Pinned revision: `4e015e925fc9974e2ab92840d6f8bb5a8f201c2d`

Persistent local checkout:
`/Users/tiensonqin/Code/projects/vercel-native-reference`

This report records how Vercel Native works below its public component API,
with special attention to its two different Web paths. It complements the
API parity matrix; it does not replace Vercel Native as the API authority.

## Executive conclusion

Vercel Native is not a platform-widget adapter comparable to React Native. Its
main UI path is a custom Zig retained canvas engine:

1. a TypeScript `Model`/`Msg`/`update` core and `.native` markup are compiled to
   native code;
2. every committed message derives a fresh widget tree and layout;
3. structural widget ids reconcile engine-owned state from the previous
   layout;
4. stable display-list object ids are diffed into dirty regions and resource
   cache operations;
5. a platform host presents retained draw packets or reference-rendered pixels
   and supplies OS input, IME, accessibility and selected system surfaces.

Its Web support has two unrelated meanings:

- WebViews embed an existing website inside a native desktop application.
- The documentation site compiles the canvas engine to WebAssembly and paints
  interactive component previews into an HTML canvas.

Neither path is a production browser DOM backend for Vercel Native UI. LUI
therefore keeps retained DOM as its primary Web renderer. The strongest ideas
to borrow are the single generated schema, structural identity, explicit
state-reconciliation rules, retained display-list revisions, deterministic
headless rendering and build-time capability elimination.

## End-to-end architecture

```text
TypeScript core                 .native markup
Model / Msg / update            bindings / events / structure
        |                               |
        | native AOT compiler           | comptime compiler
        +---------------+---------------+
                        |
                 typed Ui builder
                        |
            fresh structural widget tree
                        |
               flex/grid layout pass
                        |
       stable-id runtime-state reconciliation
                        |
             retained display-list emission
                        |
        object-id diff + dirty rects + caches
                        |
     packet presenter or CPU reference renderer
                        |
     Metal / Direct2D / GDI / Cairo / mobile host
```

The important distinction is that Vercel Native rebuilds the authored view and
layout after an update, but does not repaint the whole surface. Rebuild,
reconcile and paint are separate phases.

## Authoring and compilation

The default application core is a closed, deterministic TypeScript subset. It
uses one Elm-style loop:

- `Model` contains application state;
- `Msg` is a discriminated union;
- `update(model, msg)` is the only application-state transition;
- side effects are `Cmd` data whose results return as messages;
- the view is a pure derivation from the committed model.

The core compiler produces native code. A JavaScript engine is not shipped in
the application. Work that requires ambient TypeScript facilities lives behind
a service/effect boundary and is also compiled ahead of time.

`.native` markup has two engines with a parity contract:

- development can interpret markup for hot reload;
- release builds parse and compile it at Zig comptime;
- both produce the same structural ids and typed handler table;
- release binaries can compile out the parser and interpreter.

This dual-path design is useful, but LUI does not need Vercel Native's markup
language. LG already supplies functions, macros, conditionals, keyed
collections and Signal bindings.

## One schema, many consumers

`src/primitives/canvas/ui_schema.zig` is the authoritative vocabulary registry.
At the pinned revision it contains:

- 70 elements;
- 102 attributes;
- 15 events;
- stable nonzero `u16` codes assigned once and never reused;
- value classes, element predicates, accessibility naming rules and event
  payload/scoping metadata;
- order-independent fingerprints over `(code, name)` pairs.

The validator, runtime interpreter, comptime compiler, contract checker, LSP,
CLI diagnostics, binary document format and documentation generator consume
the same registry. Derived lists are generated at comptime rather than copied
by hand. Bespoke semantic validation remains ordinary code referenced by named
rule hooks; the registry does not try to become a validation programming
language.

The docs preview generator writes `component-vocab.json` from the registry.
Docs attribute tables, component indexes, icon galleries and eject metadata
read that generated artifact and fail on unknown entries. This is the most
directly reusable design for LUI: the parity schema should generate protocol
metadata, validation, documentation tables and showcase inventory.

## Identity and reconciliation

Widget identity is structural. The id hashes:

- the parent id;
- the stable widget-kind code;
- an explicit key, or the sibling index when unkeyed.

`global-key` instead hashes a global seed, widget kind and key, allowing a node
to retain identity across reparenting. `for` propagates item keys into every
emitted node and adds stable slots when one iteration emits multiple nodes.

The runtime derives a fresh widget tree and layout after an update, then uses
the ids to restore transient state from the retained tree. Reconciliation is
indexed to avoid an `O(n^2)` scan at the node budget. The rules are explicit
per state family:

- user scroll offsets survive while the source offset is unchanged;
- a changed source offset performs programmatic scrolling;
- editable text, selection, composition and internal scroll survive while the
  source text is unchanged or faithfully echoes runtime text;
- controlled source changes win over retained control values;
- active drags and animations keep runtime-owned geometry until they settle;
- focus, hover, pressed state and semantics stay attached to stable identity;
- failed builds do not adopt a partially mismatched layout/handler pair.

Two arenas alternate between builds so the previous handler tree remains valid
while an event from it dispatches. New layout adoption is validated and
atomic. This is a robust reference for backend-owned state, even though LUI's
Signal graph can avoid deriving unrelated subtrees in the first place.

## Layout, display list and incremental presentation

The widget tree is laid out into a flat retained `WidgetLayoutTree`. The shared
engine owns row, column, grid, overlays, scroll regions, controls and composite
layout. It does not delegate ordinary component layout to SwiftUI, Flutter or
HTML.

Rendering emits stable-id display-list commands. The runtime compares the
current list with the last presented summary and classifies additions,
removals and changes. It computes:

- a dirty-bounds union and a bounded list of refined dirty rectangles;
- render batches and pipeline actions;
- path, image, layer, visual-effect, glyph-atlas and text-layout cache actions;
- a `requiresRender` decision;
- frame diagnostics and budget risk.

An unchanged canvas revision can skip rendering and presentation entirely.
Animation state may keep frames dirty without changing the authored tree, with
one final settling frame.

LUI should retain its finer Signal scheduling but use the same conceptual
separation:

```text
Signal invalidation -> typed retained patch -> backend state reconcile
                    -> backend-specific dirty/presentation decision
```

## Platform strategy

Vercel Native shares one canvas renderer across platforms rather than mapping
the component catalog to each platform's widget catalog.

| Platform | Main presentation path | OS-owned integration |
| --- | --- | --- |
| macOS | retained packets through Metal, pixel fallback | AppKit window, native scrolling, menus, dialogs, IME, accessibility |
| Windows | retained Direct2D packets where supported, GDI/software fallback | Win32 window, WebView2, menus, IME, accessibility |
| Linux | deterministic software renderer and Cairo/GTK presentation | GTK window, WebKitGTK, menus, IME, accessibility |
| iOS | reference-rendered RGBA damage uploaded to a Metal texture | UIKit host, touch, keyboard/IME, selected native chrome |
| Android | reference-rendered pixels copied into the Android surface | Android host, touch, soft keyboard/IME |

Mobile is experimental. The iOS host is Objective-C/UIKit rather than SwiftUI,
and the Android host does not map the catalog to Flutter widgets. This backend
choice is not part of the public API contract and is not a reason for LUI to
abandon its SwiftUI and Flutter mapping strategy.

Vercel Native does selectively delegate experiences whose platform identity
matters: scroll physics on macOS, application/context menus, dialogs, tray,
keyboard/IME and accessibility bridges. The same authored context menu can use
a real OS menu on desktop and an anchored canvas fallback elsewhere.

## Web path A: native application hosting WebViews

This is embedded web content, not Vercel Native UI running in a browser.
Existing React, Vue, Svelte, Next.js or static frontends run inside a native
shell. Development uses a managed localhost dev server; production serves
bundled assets through a custom origin with optional SPA fallback.

The system backends are:

- macOS: `WKWebView`;
- Linux: WebKitGTK;
- Windows: WebView2.

CEF provides bundled Chromium on macOS. Linux and Windows Chromium selections
fail early until their CEF hosts exist; they do not silently fall back to the
system engine. Supported engines expose the same runtime/WebView API.

WebViews are named native surfaces with logical frames and native stacking.
Untrusted child content receives no bridge by default. Navigation origins,
permissions and bridge command categories are checked explicitly.

The manifest has one web-layer inference contract. A frontend block, WebView
capability, WebView shell node or Chromium engine enables the layer. Native-only
apps compile it out. An explicit exclusion that contradicts a web declaration
is a build error. Packaging carries the same resolved decision so executable
and artifact cannot disagree.

Useful LUI lessons:

- declare optional host capabilities once;
- eliminate unused platform layers at build time;
- make overrides explicit and reject contradictions;
- expose capability queries and explicit unsupported errors;
- separate dev-server sources from bundled production assets;
- keep a strict, origin-aware bridge boundary.

An optional WebView element or host capability can be added to LUI later, but
it is separate from the browser backend.

## Web path B: browser WASM component previews

The documentation build compiles the same preview scene catalog and canvas
runtime to `wasm32-freestanding` in `ReleaseSmall` mode. The committed artifact
is loaded once by the React documentation shell. Each preview creates its own
retained runtime and scene inside that shared WebAssembly instance.

The WebAssembly module has no imports. JavaScript owns:

- the monotonic clock and `requestAnimationFrame` loop;
- the HTML canvas and RGBA blit;
- viewport activation and instance destruction;
- pointer, wheel, keyboard and DOM focus translation;
- CSS sizing, device-pixel ratio and cursor mirroring;
- theme controls.

The engine owns layout, hit testing, focus target, text/control state,
animation and model dispatch. A preview rebuild uses two arenas, reconciles by
stable widget id, emits a retained display list and CPU-renders RGBA8 pixels.
`preview_render` returns clean when the canvas revision and scale are unchanged,
allowing JavaScript to skip both rendering and `putImageData`.

The page controls cost aggressively:

- static light/dark WebP images provide SSR, no-JavaScript and loading fallback;
- the shared module is warmed before a tile enters the viewport;
- instances are created near visibility and destroyed offscreen;
- a global LRU caps live instances at 12;
- the animation loop parks after 600 ms of inactivity;
- the loop pauses while the document is hidden;
- `ResizeObserver` and device-pixel ratio drive backing-store scale;
- wheel is captured only after the preview owns focus, preserving page scroll;
- pointer capture keeps gestures stable;
- Escape releases the embedded application focus back to the page.

### Measured limits at the pinned revision

The committed `docs/public/wasm/component-preview.wasm` was measured locally:

- 1,800,621 raw bytes;
- 564,369 bytes with gzip level 9;
- zero WebAssembly imports;
- 24 exports;
- 17,563,648 bytes of initial linear memory;
- `preview_instance_bytes()` returns 119,079,024 bytes, approximately
  113.6 MiB per live preview before variable allocations and RGBA buffers.

The last measurement conflicts with the source comment that calls an instance
"single-digit megabytes". The fixed-capacity runtime has grown beyond that
comment. With a 12-instance cap, worst-case fixed instance storage alone can be
well above one GiB. This makes viewport destruction essential and confirms
that this host is a controlled docs preview, not a general browser renderer.

### Browser gaps

The canvas exposes one DOM accessibility node with `role="application"` and an
ARIA label. Individual widgets are not represented by DOM elements or a
browser accessibility tree.

The engine exports `preview_text` and a `textInputActive` query, but the current
React host sends printable `keydown` text and does not wire `beforeinput`,
composition events or a hidden textarea. Browser/mobile IME, dead-key and
virtual-keyboard behavior is therefore incomplete. Clipboard shortcuts also
cross a browser-security boundary that the native engine cannot own by itself.

CPU-rendering a full RGBA buffer, copying it out of WebAssembly memory and then
calling `putImageData` is acceptable for small previews. It is not the desired
primary path for ordinary accessible browser applications.

## Showcase and testing design

Vercel Native generates static component images and live preview scenes from
the same scene catalog. Its `NullPlatform`, deterministic CPU renderer,
accessibility snapshots and automation protocol make headless tests and pixel
goldens independent of the window server.

The LUI showcase should borrow the source-of-truth relationship:

- one LG gallery scene per public schema element;
- generated component inventory and documentation metadata;
- deterministic snapshots from the same scenes where a backend permits them;
- live platform versions using the same LG source;
- static fallback images for documentation, not as the application UI;
- viewport resource budgets only for genuinely expensive embedded surfaces.

## Adopt, adapt and reject

### Adopt directly

1. One closed schema with stable element/property/event codes.
2. Generated validators, protocol tables, docs and showcase inventory.
3. Schema fingerprints and deliberate migration rules.
4. Stable sibling keys and parent-independent global keys.
5. Explicit controlled-versus-runtime-owned reconciliation rules.
6. Atomic backend adoption and old-state preservation on failure.
7. Dirty revisions, skip decisions and observable frame/patch budgets.
8. Deterministic headless rendering and accessibility snapshots.
9. Build-time capability inference and elimination.
10. Explicit unsupported errors instead of silent platform substitution.

### Adapt to LUI

1. Keep Signal-granular dependency tracking instead of rebuilding the whole
   authored view after every state change.
2. Reconcile transient state inside retained DOM, SwiftUI and Flutter objects
   rather than one custom canvas widget tree.
3. Let each backend use native layout and controls where doing so preserves the
   Vercel Native contract.
4. Use backend-specific dirty/presentation mechanisms: DOM property patches on
   Web, observable model changes on SwiftUI, retained Element/RenderObject
   updates in Flutter.
5. Generate documentation and showcase metadata in a language-neutral artifact
   consumable by all LUI build stages.

### Reject for the primary LUI architecture

1. A canvas-only Web backend for the standard component catalog.
2. Full view rebuild as the normal Signal update path.
3. CPU RGBA copy and canvas blit for ordinary browser UI.
4. One large fixed-capacity runtime per Web component or preview.
5. Canvas-level accessibility in place of native DOM semantics.
6. Maintaining a second markup/template language alongside LG.
7. Copying Vercel Native's custom-renderer backend strategy merely because LUI
   shares its public component API.

## Concrete LUI decisions

1. Retained DOM remains the production Web backend. No React dependency and no
   Vercel-style canvas replacement are introduced.
2. The Vercel Native component API remains the public vocabulary authority;
   backend implementation is allowed to differ.
3. The handwritten parity matrix becomes a review artifact generated or
   checked from one central closed schema rather than a second source of truth.
4. Stable ids, schema codes and fingerprints are introduced before scaling the
   component catalog.
5. Each backend documents which transient state it owns and how a controlled
   source change wins without replacing the platform object.
6. The gallery in `examples/components/` and its docs inventory derive from the
   same schema and LG scenes.
7. An optional WebView/native-web-content capability is deferred until the core
   component and showcase waves need it.
8. A WASM/custom-canvas surface remains a possible specialized component for
   charts, editors or graphics, never the default Web component renderer.

## Source discrepancy to track

The pinned source contains conflicting descriptions for omitted grid columns:

- `Ui.ElementOptions.columns` says zero derives a near-square count;
- `widget_tree.gridColumnCount` says and implements one column per child,
  producing a single row;
- layout and intrinsic-size paths both call `gridColumnCount`.

LUI must follow executable behavior and upstream tests when parity is
implemented. This discrepancy should be rechecked whenever the pinned revision
is updated.

## Primary source index

- [Repository README](https://github.com/vercel-labs/native/blob/main/README.md)
- [App model](https://native-sdk.dev/docs/app-model)
- [Native UI](https://native-sdk.dev/docs/native-ui)
- [UI schema](https://github.com/vercel-labs/native/blob/main/src/primitives/canvas/ui_schema.zig)
- [Structural UI builder](https://github.com/vercel-labs/native/blob/main/src/primitives/canvas/ui.zig)
- [Runtime reconciliation](https://github.com/vercel-labs/native/blob/main/src/runtime/canvas_widget_runtime.zig)
- [UiApp rebuild loop](https://github.com/vercel-labs/native/blob/main/src/runtime/ui_app.zig)
- [Canvas frame planning](https://github.com/vercel-labs/native/blob/main/src/primitives/canvas/frame.zig)
- [Platform support](https://native-sdk.dev/docs/platform-support)
- [Frontend/WebView hosting](https://native-sdk.dev/docs/frontend)
- [Web engines](https://native-sdk.dev/docs/web-engines)
- [Web-layer inference](https://github.com/vercel-labs/native/blob/main/src/primitives/app_manifest/web_layer.zig)
- [WASM preview host](https://github.com/vercel-labs/native/blob/main/tools/docs_wasm_preview.zig)
- [WASM TypeScript wrapper](https://github.com/vercel-labs/native/blob/main/docs/src/lib/live-preview.ts)
- [Browser preview lifecycle](https://github.com/vercel-labs/native/blob/main/docs/src/components/component-preview-live.tsx)
- [Docs preview generator](https://github.com/vercel-labs/native/blob/main/tools/docs_component_previews.zig)
