# Component gallery

This showcase renders the same OCaml model, reducer, and component tree
(`examples/gallery`) on MyGo desktop and Web/Melange hosts. The host directories
contain only lifecycle, event, and rendering bridge code; interactive state lives in
the shared OCaml application.

## Desktop (MyGo)

MyGo is the default desktop host. Build the shared OCaml application library
and launch it from the repository root:

```sh
library=$(./tooling/build_mygo_components.sh)
go -C platform/mygo run ./cmd/lui-mygo -library "$library" -title Components
```

See the [MyGo guide](../../platform/mygo/README.md) for Go and system
dependencies. The former `webview-shell` example was removed with the OCaml
desktop renderer; Web output still runs in a browser.

## Web/Melange

Build the existing browser host from the repository root:

```sh
opam exec -- dune build @web
npm --prefix platform/web run build
node tooling/serve_web.mjs --port 8977
```

Open `http://127.0.0.1:8977/examples/components/web/index.html` in a browser.
The former Apple/SwiftUI and Android gallery packages, their native input
probes and mobile build/test scripts have been removed. The shared OCaml
Gallery and `native` application library remain for MyGo.
