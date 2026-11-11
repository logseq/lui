# Retained native fitting qualification

## Source and scope

The real OCaml `fit_app.ml` fixture uses ViewThatFits inside a top EdgeInset,
matching Journal's feedback composition. The native macOS run used pinned NSH
`bfa15d0c843c0d6f5bf3a2a230e8ca56b876b61c` and LUI production source at
`4ac22c03`, with the pending URL-scheme guard and missing Style import fixes.
The fixture and driver changes are committed with this evidence. This is not a
launch of Journal itself and does not establish other operating-system results.

```sh
python3 platform/nsh/tests/fixtures/build_virtual.py --fixture fit
LUI_OCAML_LIBRARY="$PWD/_build/nsh/fit-qualification/liblui_fit.dylib" \
  platform/nsh/.nsh/toolchain/nsh test \
  platform/nsh/tests/fixtures/fit_native.test.ts --target macos --trace
```

The test passed in 15.6 seconds. Assertions cover:

- Window resize that preserves the selected candidate also preserves its native
  editor focus: subsequent hardware input reaches the same retained draft.
- A resize that switches to the compact candidate leaves the independent main
  editor focused. AppKit's native spatial key-view loop reaches the pinned
  feedback with Shift+Tab; the hidden preferred editor cannot consume input.
- Candidate switching preserves independent drafts and expected Appear counts.
- Changing actual vertical text content selects the earlier fitting candidate.
- Hiding the outer feedback region leaves the main editor mounted and visible,
  excludes its candidates from Tab, and restores the selected candidate's draft.

The first draft used an undefined `bar` color token, then wrote screenshots to
an uncreated directory. The fixture now uses the existing `muted` token and the
builder-created qualification directory. No app filesystem permission was
added for screenshots. The forward-Tab assumption was corrected to the native
AppKit spatial order; all visibility, draft and hardware-input assertions remain.

## Visual review

All six wide/compact/restored screenshots in light/dark were inspected. The
existing theme tokens provide readable contrast, consistent control corners,
spacing and typography. The pinned region occupies its intended top space;
compact and restored layouts show a single candidate and the correct vertical
text. Inputs, native focus rings and unselected content retain their geometry.
The status-heavy screen is a qualification fixture, not a redesigned product
screen. No extra transition/controller was added for candidate switching.
Hover/pressed motion, screen-reader announcements, IME and pixel automation are
not established by these screenshots or by the mapped Headless tests.

Local log `/tmp/lui-nsh-fit-native.log`, SHA-256:
`b14df3d534b05dbae5ac7f37931341656de95bd593f821f09850ebfa37d73963`.
Screenshots and compiled libraries remain ignored build outputs.
