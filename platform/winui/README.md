# LUI WinUI 3 Backend

A retained UI backend for LUI built on WinUI 3 (Windows App SDK). `LUI.Core`
consumes JSON `patch_batch` objects from the OCaml runtime and exposes the
node tree through `LUIBackend`; `LUI.WinUI` renders that tree with WinUI
controls and routes user input back through the protocol event gates.

## Layout

```
platform/winui/
├── LUIWinUI.sln
├── LUI.Core/                 # net8.0, no UI dependencies (portable)
│   ├── LUIWireSchema.g.cs    # generated kind/prop tables
│   │                         #   (tooling/generate_component_schema.mjs)
│   ├── LUIWireValue.cs       # wire value union (string/bool/int/float)
│   ├── LUISchema.cs          # prop/kind support + node validation
│   ├── LUINodeState.cs       # node/extension state + event records
│   ├── LUIExtensionRegistry.cs  # extension identifier/spec registry
│   ├── LUIBackend.cs         # patch application, validation, event gates
│   ├── LUIBackendException.cs
│   └── LUIOcamlBridge.cs     # P/Invoke over platform/native/lui_ocaml_bridge.c
├── LUI.WinUI/                # net8.0-windows + Windows App SDK
│   ├── LUIElement.cs         # one retained control per node id; gestures
│   ├── LUIElement.Sync.cs    # per-kind property/children application
│   ├── LUIElementFactory.cs  # node kind -> WinUI control mapping
│   ├── LUIPropertyApplier.cs # shared frame/padding/color/text props
│   ├── LUIMenuBuilder.cs     # dropdown/context menus, tooltips
│   ├── LUIModalPresenter.cs  # dialog/sheet/drawer/toast overlay
│   ├── LUIThemeColors.cs     # semantic colors -> theme resources
│   ├── LUIIconGlyphs.cs      # icon names -> Segoe Fluent Icons
│   ├── LUISyncContext.cs     # sync context + image/surface registries
│   ├── LUIExtensionContext.cs   # extension visual host contract
│   ├── LUIWinUIRoot.cs       # root grid: content + overlay layers
│   ├── LUIWinUIBackend.cs    # engine: element map + batch->control sync
│   └── LUIWinUIHost.cs       # composition root (bridge + backend + root)
├── LUI.Core.Tests/           # xUnit protocol tests (runs on Linux)
└── LUI.Demo/                 # unpackaged WinUI app hosting the todos demo
```

## Data flow

OCaml runtime → `lui_ocaml_start(callback, platform=5, host=5)` → JSON
patch batch per turn → `LUIBackend.ApplyJson` validates and commits →
`Applied` event carries changed/dependent/removed ids → `LUIWinUIBackend`
re-syncs only those elements (controls are retained, so focus survives).
Gestures → WinUI events → `Perform*` gates → `OnEvent` → `lui_ocaml_*`
entry points → next patch batch.

Host code **5** selects `WinUIHost` on the OCaml side (`host_kind` in
`src/lui_protocol.ml`); code 4 is reserved for the Qt/QML backend.

## Requirements

- .NET SDK 8.0+
- Windows App SDK 1.6 runtime (demo app, unpackaged)
- Windows 10 1809+ (`net8.0-windows10.0.19041.0`, min `10.0.17763.0`)

## Building

```sh
dotnet build platform/winui/LUIWinUI.sln -p:EnableWindowsTargeting=true
dotnet test  platform/winui/LUI.Core.Tests/LUI.Core.Tests.csproj
```

- `LUI.Core` and `LUI.Core.Tests` are plain net8.0 — they build and test
  on Linux/macOS too.
- `LUI.WinUI`/`LUI.Demo` compile on any OS with
  `-p:EnableWindowsTargeting=true` (cross-compilation produces IL only);
  final packaging/`Publish` must run on Windows.

## Hosting

```csharp
using LUI.WinUI;

var host = new LUIWinUIHost();
host.Start();                    // boots the OCaml runtime via the bridge
window.Content = host.Root;      // LUIWinUIRoot is a Grid
```

`host.Root` also works without the native bridge: feed patch batches
directly with `host.Backend.ApplyJson(json)`.

## Extensions

Extension specs are registered on the protocol side
(`host.Backend.Backend.Extensions.Register(...)`); their visuals come from
`LUIExtensionVisual` registrations on the WinUI side — a factory called
once per extension node plus an optional update delegate re-applied each
batch:

```csharp
host.Backend.RegisterExtensionVisual(
    "my-extension",
    new LUIExtensionVisual(
        factory: ctx => BuildMyControl(ctx.State, ctx.Children),
        update: ctx => ApplyMyProps(ctx.State)));
```

Custom events flow back with `ctx.EmitEvent("name", values)`; image and
media-surface registries live on `host.SyncContext.Images` /
`.Surfaces` (keyed by the ids used in `image`/`surface` properties).

## Known approximations

- `container-relative-frame` is approximated by explicit sizing recomputed
  on parent `SizeChanged`.
- `resize-duration`/`resize-easing` animations are applied instantly.
- `tooltip-delay` uses WinUI's default hover timing.
- `control-size`/`size` map to the closest WinUI density preset.
- `space-between` main alignment falls back to the nearest supported
  distribution.
