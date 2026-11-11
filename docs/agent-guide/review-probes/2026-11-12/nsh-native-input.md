# Native Input blur and navigation qualification

Date: 2026-11-12

The actual macOS NSH window ran the OCaml Input fixture at LUI `b8089ed3` with
NSH `bfa15d0c843c0d6f5bf3a2a230e8ca56b876b61c`. Native typing, focus transfer,
Enter, live policies, composition cancellation/UTF-8 commit and focused previous /
next callbacks passed together. The run completed in 15.2 seconds. Its log
`/tmp/lui-nsh-native-input-navigation.log` has SHA-256
`ff9d9c7e5ba74c9a24c00487dc1d35b5606b3ede6bf5852197c7621d6340f4c3`.

The fixture asserted one blur submission of the committed draft, no duplicate
submission after single-line Enter, independent multiline Enter and later blur,
initially false policies toggled live, disabled/submit guards and stable native
identities for all four editors. Previous/next counts were primary 1/2 and
optional 1/1. The scoped bindings leave unfocused, modified and composing keys
with native editing.

Light/dark screenshots in `_build/nsh/input-qualification/inputs-light.png` and
`inputs-dark.png` were both inspected. The controls, borders, foreground, focus,
spacing and multiline clipping were readable in both modes; the four retained
editors and callback evidence were visible. These generated artifacts are not
committed.

This proves the dedicated Input adapter fixture on macOS at the stated revision.
It does not qualify the later actual Logseq editor conduit, the application host
services, Button/Row/Box NavigationKey, native IME candidate positioning, or
Windows/Linux application behavior. Those remain separate acceptance gates.
