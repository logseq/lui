# LUI Qt/QML Backend

A retained UI backend for LUI built on Qt 6 / QML. The C++ core consumes
JSON `patch_batch` objects from the OCaml runtime and exposes each wire node
as a `LuiNode` model object; the `Lui` QML module renders the tree through
one component per node kind.

## Layout

```
platform/qt/
├── CMakeLists.txt          # root project (lib + test + demo)
├── lib/                    # C++ backend core + Lui QML module
│   ├── lui_wire_schema.h   # generated kind/prop tables (tooling/generate_component_schema.mjs)
│   ├── lui_schema.{h,cpp}  # prop/kind support + node-property validation
│   ├── lui_node.{h,cpp}    # LuiNode model (properties/children/events)
│   ├── lui_qml_backend.{h,cpp}  # patch application, validation, event gates
│   └── lui_extension_registry.{h,cpp}  # extension identifier/spec registry
├── qml/                    # LuiNodeView dispatcher + one Lui<Kind>.qml per
│   │                       # node kind + LuiStyle.js palette helpers
│   └── icons/              # bundled SVG icons
├── test/                   # QtTest suite for the C++ backend
└── demo/                   # todos app: OCaml runtime + QML window
    ├── build-runtime.sh    # builds lui_todos_runtime.o from the OCaml side
    └── run.sh              # one-shot: runtime + cmake + launch
```

## Requirements

- Qt 6.2+ (`qt6-base-dev`, `qt6-declarative-dev`,
  `qt6-tools-dev` on Debian/Ubuntu)
- CMake 3.21+, a C++17 compiler
- opam + the repo's OCaml switch (demo only)

## Building

```sh
cmake -S platform/qt -B platform/qt/build
cmake --build platform/qt/build
ctest --test-dir platform/qt/build
```

## Demo

```sh
platform/qt/demo/run.sh
```

`build-runtime.sh` compiles `src/lui.cmxa`, `examples/todos`, and the
`platform/native/lui_ocaml_bridge.c` bridge into `lui_todos_runtime.o`
(mirrors the macOS `liblui_todos.dylib` dune rule — on Linux the
`-output-complete-obj` artifact is not PIC, so it is linked into the
executable rather than a shared library). The demo then feeds every patch
batch to `LuiQmlBackend::applyJson` and renders `luiBackend.rootNode` with
`LuiNodeView`.

## Wire protocol

Same JSON contract as the other backends: `{"generation":N,"ops":[...]}`
with `create-node`, `create-extension`, `drop-node`, `set-prop`,
`remove-prop`, `set-extension-prop`, `remove-extension-prop`,
`insert-child`, `remove-child`, `move-child`. Generations must increment by
exactly 1. Validation (child relationships, prop support per kind,
extension registration) mirrors the OCaml `lui_runtime` checks and the
Flutter `_validateStates` port; a rejected batch leaves state untouched and
surfaces the reason via `lastError`.

Events flow back through `LuiNode`'s `Q_INVOKABLE` methods
(`press()`, `toggle(bool)`, `textChanged(text)`, …) and the backend's
`luiEvent(nodeId, name, payload)` signal, which the host maps onto the
`lui_ocaml_*` entry points.
