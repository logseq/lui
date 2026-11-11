# Windows OCaml DLL startup review

## Finding

The documented OCaml 5.5 native MainDll route is designed for explicit
`caml_startup`, matching the existing LUI bridge's first call on its persistent
worker. Source review found no automatic OCaml-startup call introduced by
selecting `-output-complete-obj -o application.dll`. Actual native Windows
runtime and packaged-launch CI remain required; this is source evidence,
not a Windows execution result.

`ctypes.CDLL` does execute Windows loader and C-runtime initialization. The
builder now states the narrower verified boundary: its export probe invokes
no `lui_ocaml_*` function. It must not claim that loading arbitrary native
dependencies cannot run constructors, initialize another runtime, or have
side effects.

## Source chain

1. The [OCaml 5.5 embedding manual](https://ocaml.org/manual/5.5/intfc.html#s%3Aembedded-code)
   specifies explicit startup for an embedded native shared library.
2. [OCaml 5.5.1 asmlink.ml](https://github.com/ocaml/ocaml/blob/5.5.1/asmcomp/asmlink.ml#L297)
   selects `Ccomp.MainDll` when an output-C-object request has the configured
   DLL suffix. It includes the runtime and autolink archives; this branch
   does not call runtime startup.
3. [OCaml 5.5.1 configure.ac](https://github.com/ocaml/ocaml/blob/5.5.1/configure.ac#L1411)
   defines the Windows MainDll linker as `flexlink -maindll` with the
   configured toolchain chain. This is not the plugin-DLL mode.
4. OCaml 5.5.1 pins FlexDLL submodule
   `3400287999afcdc737f35c1d0e1447c7d2ae5a83`. Its
   [reloc.ml](https://github.com/ocaml/flexdll/blob/3400287999afcdc737f35c1d0e1447c7d2ae5a83/reloc.ml)
   treats non-plugin modes as the main program. It links the FlexDLL runtime
   object, while the plugin-only branch adds `flexdll_initer`. The native
   linker retains the normal CRT DLL entry point for MainDll.
5. [FlexDLL's entry-point documentation](https://github.com/ocaml/flexdll/blob/3400287999afcdc737f35c1d0e1447c7d2ae5a83/README.md#advanced-topic-static-constructors-and-the-entry-point)
   explains loader/CRT constructors and its plugin relocation entry point.
   That initializer is not an OCaml `caml_startup` call.
6. [OCaml 5.5.1 startup_nat.c](https://github.com/ocaml/ocaml/blob/5.5.1/runtime/startup_nat.c#L78)
   initializes the runtime and enters `caml_start_program` from
   `caml_startup_common`, reached through `caml_startup`. The existing
   `platform/bridge/lui_ocaml_bridge.c` calls `caml_startup` only in its
   first `lui_ocaml_start`, then uses the existing runtime-lock discipline.

The MinGW runtime deliberately references a winpthreads symbol to retain static
TLS-related thread support, as described in
[startup_aux.c](https://github.com/ocaml/ocaml/blob/5.5.1/runtime/startup_aux.c#L168).
This supports leaving runtime-library selection to the configured OCaml linker;
it does not establish that every application has no dependent DLLs.

## Qualification boundary

The Windows builder compiles the bridge with the active OCaml compiler's C
configuration and requests a complete native DLL directly from `ocamlopt`.
It then loads that real DLL and checks the required exports without invoking
them. It records compiler configuration and the generic LUI build receipt.

The Windows job subsequently opens the DLL through LUI's persistent worker,
exercises real Todos editing and runtime recovery/repeated start-stop, builds
the pinned native NSH CLI, packages the actual executable with the DLL, and
launches it outside the checkout. Those steps must pass on Windows before
claiming native Windows support. Additional CRT constructors, dependency
resolution, linker export behavior, host-thread runtime ownership and native
window behavior remain actual-execution checks. No loader or runtime behavior
was changed in this review.
