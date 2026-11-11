# NSH desktop controls

The OCaml application owns values and structural visibility. NSH owns native
activation, keyboard navigation, focus, popup dismissal and numeric editing.
The shared Rust UI layer owns presentation and uses semantic NSH theme tokens;
explicit LUI presentation properties are applied after its defaults.

Desktop controls use the existing compact spacing/type scale and minimum
heights that can grow with text. Switches, radios and checkbox indicators
have visible native parts. Popup families share the popover surface, border,
theme radius and shadow. Focus outlines do not change layout.

## Motion inventory

| State change | Native mechanism | Reduced motion |
| --- | --- | --- |
| Button, radio and toggle hover/press | Semantic accent wash, native color transition, instant/fast tokens | Immediate wash |
| Authored command variant, size and icon changes | Retained native control; color transition uses the existing fast token, icon/geometry bindings update immediately to reflect the accepted model | Immediate color and content |
| Switch value | Track color and thumb transform transition, fast token | Immediate value |
| Checkbox/radio glyph | Immediate accepted value; do not animate a model rejection | Immediate value |
| Slider drag | Native slider tracks the pointer directly; no bridge animation | Same direct tracking |
| Progress value | Native progress geometry; frequent updates do not replay entrances | Same value |
| Tab selection | NSH Tabs' native following indicator | NSH reduced-motion behavior |
| Dialog and sheet open/close | NSH modal/sheet transition and focus lifecycle | NSH reduced-motion behavior |
| Menu/popover open/close | Shared native popup transitions once anchored composition is integrated | Immediate surface |
| Standalone update menu and confirmations | System application menu and native alert dialogs; discrete download/install states, no custom animation | System accessibility behavior |

The standalone application root discovers an explicitly packaged updater
configuration. Its native application menu owns check, cancel, download and
install/restart actions; the embeddable renderer does not replace its host's
menu. Installation requires an explicit user action and restarts only after
successful replacement. Missing configuration creates no worker or network
request. Errors and update decisions use native alerts, and the standard edit
and window menu roles remain available. This adds no in-content overlay or
per-frame OCaml animation.

These are implementation intentions. Headless behavior tests do not qualify
appearance or motion. Light/dark screenshots, keyboard-only and screen-reader
flows, minimum window size, large text and real desktop motion remain required
before visual qualification is marked complete.
