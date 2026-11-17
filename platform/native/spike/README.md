# SDL3 substrate validation

This experimental demo opens an SDL3 window, handles keyboard/resize events,
uploads an animated CPU framebuffer and draws SDL3 debug text. It does not
require SDL_ttf.

```sh
export SDL3_LIBRARY="$(brew --prefix sdl3)/lib/libSDL3.dylib"
opam exec -- dune exec platform/native/spike/spike.exe
SDL_VIDEODRIVER=dummy opam exec -- dune exec platform/native/spike/spike.exe -- --headless --frames 120 --no-text
```

Escape/Q quits, Space pauses, and R resets the animation. `--size WxH` selects
window dimensions. Headless execution uses a virtual clock and reports the
CPU framebuffer checksum. `--no-text` disables the debug-text overlay.
