# ADR 0006: Native backend window host on SDL3, with a native text input escape hatch

Status: proposed

Date: 2026-11-19

## Context

The experimental self-drawn native backend (`platform/native`) hosts its
windows on SDL3 for macOS and Linux (`lui_window`, `lui_window_linux`,
`lui_sdl3`), and on a direct Win32 host for Windows (`lui_window_windows`).
The platform-neutral seam above the window host is `Lui_window.Input`,
`Lui_ime`, `Lui_host` and `Lui_scene`; renderers, layout, paint and the
patch protocol do not depend on SDL.

SDL3 unifies window creation, the event loop, keyboard and pointer events,
GPU surface creation and headless operation. It does not unify the areas
where the native backend already maintains per-platform code: text shaping
(`lui_text`, `lui_text_pango`, `lui_text_dwrite`), accessibility (`lui_ax*`),
desktop shell services (`lui_shell*`), WebView embedding (`lui_webview`) and
packaging (`lui_pkg*`).

The hosts were migrated to SDL3 recently, but they use it at roughly the SDL2
feature level:

- Text input uses start/stop, an input rectangle and composition events. The
  OCaml binding keeps SDL2-style names such as `set_text_input_rect`, and
  `Lui_ime` only models `Editing`, `Commit`, `Focus` and `Caret`.
- The event loop sleeps in `Sdl.wait_event_timeout`, so the host cannot
  render during live window resizing or schedule frames from the display's
  refresh.
- `lui_metal` obtains the `CAMetalLayer` through `SDL_Metal_GetLayer` but
  only uses it to create the device and drawable.
- Menus, popovers and tooltips are drawn inside the window, so they cannot
  extend beyond its bounds.
- There is no mechanism for work on other threads or domains to schedule
  work on the UI thread.
- Comments in `lui_ime`, `lui_window` and `lui_webview` still describe SDL2
  APIs (`SDL_SetTextInputRect`, `SDL_GetWindowWMInfo`).

One gap cannot be closed inside SDL3. System input methods use a
bidirectional protocol: the input method asks the application for the text
around the caret, the geometry of arbitrary character ranges, and requests
replacement of already-committed text. SDL3's text input delivers composition
and commit events only. Without surrounding text and replacement ranges,
reconversion, context-aware suggestions, system autocorrection, the
"replace" menu and dictation edits do not work. For a text-editing product
this is the most visible native-feel defect.

Replacing SDL wholesale with direct AppKit and X11/Wayland hosts would solve
that gap, together with window chrome customization, but it would make the
backend responsible for display-server differences on Linux and for
reimplementing work SDL3 already provides. The maintained macOS desktop
product uses the Apple SwiftUI backend, so a direct AppKit host for the
native backend is not currently required.

## Decision

1. SDL3 remains the window and event host of the native backend on macOS and
   Linux. The Win32 host remains the Windows host. The window host is an
   implementation behind `Lui_window.Input`, `Lui_ime` and the per-surface
   driver; new platform code must not leak SDL types above that seam.

2. Use SDL3's capabilities before writing platform-specific host code.
   Extend the pinned SDL3 OCaml binding as needed and adopt:
   - `SDL_SetTextInputArea` with the caret offset,
     `SDL_StartTextInputWithProperties` (multiline, input type,
     autocorrect and capitalization hints), and
     `SDL_HINT_IME_IMPLEMENTED_UI` with
     `SDL_EVENT_TEXT_EDITING_CANDIDATES` where the backend draws the
     candidate list itself;
   - `SDL_RunOnMainThread` as the only way for other threads or domains to
     schedule UI-thread work;
   - `SDL_CreatePopupWindow` for menus, popovers and tooltips that must
     escape the parent window. These remain retained nodes of the same LUI
     tree; only their presentation surface changes;
   - the `CAMetalLayer` returned by `SDL_Metal_GetLayer` for drawable count
     and display sync configuration, with display-link driven frame
     scheduling on macOS, and SDL3 main callbacks or event watches so frames
     continue during live resizing;
   - `SDL_GetWindowProperties` for every native handle (Cocoa, X11, Wayland),
     replacing remaining SDL2-era assumptions;
   - SDL3 tray, file dialog and MIME clipboard APIs where they satisfy the
     existing `lui_shell*` contracts. The `lui_shell*` interfaces stay; only
     their implementations may delegate to SDL3.

3. Add a native text input client as the one deliberate bypass of SDL. On
   macOS, the host implements the input client on its surface view; on Linux,
   it talks to the input method framework (IBus or Fcitx) directly. Both
   provide surrounding text, replacement ranges, marked range geometry and
   reconversion. SDL text input remains the fallback when the native client
   is unavailable.

   `Lui_ime` stays the platform-neutral contract and grows the requests this
   protocol needs: surrounding text queries, range geometry queries and
   replacement of committed ranges. The focused field's text model answers
   them; host code only translates. The Windows host gains the same
   requests through IMM32, and later through the Text Services Framework.

4. Capabilities outside SDL3 remain in platform modules: accessibility
   (`lui_ax*`), the application menu bar, notifications, global shortcuts,
   and window chrome customization through native handles obtained from
   SDL3 window properties.

5. A direct AppKit window host for the native backend is out of scope until
   the native backend becomes a shipping macOS target. Revisit this ADR at
   that point, or if window chrome requirements cannot be met through native
   handles without conflicting with SDL3's window state.

## Consequences

### Positive

- The window host stays shared across macOS and Linux, including headless CI
  through the dummy video driver.
- Popup surfaces, UI-thread scheduling, frame pacing and live resizing are
  addressed without new platform hosts.
- The highest-value native behavior, input method integration, is
  implemented natively where SDL3 cannot provide it.
- `Lui_ime` becomes testable against the full input method protocol without
  a window, as it is today for composition.

### Negative

- The pinned SDL3 binding fork must expose more of SDL3, and its API names
  move away from the SDL2-compatible surface.
- The native text input client coexists with SDL's own text input handling
  on the same view or window; focus, key filtering and fallback must be
  coordinated carefully.
- Window chrome customization through native handles can drift from SDL3's
  internal window state and needs per-platform tests.
- Linux input method support depends on the user's input method framework.

## Rejected alternatives

### Replace SDL3 with direct platform hosts on macOS and Linux

Rejected for now. It duplicates window, event and display-server handling
that SDL3 provides, increases Linux maintenance, and is not required while
the macOS desktop product uses the Apple SwiftUI backend.

### Rely on SDL3 text input alone

Rejected because SDL3 provides no surrounding text or replacement range
protocol. Reconversion, autocorrection and dictation edits would remain
unavailable.

### Implement popups as separate top-level LUI roots

Rejected because menu, popover and tooltip state belongs to the retained
node that owns it. Splitting it into another root would break model-owned
presence, focus restoration and dismissal ordering.

## Delivery sequence

1. Update the pinned SDL3 binding and the native hosts to the SDL3 text input,
   window property and main-thread APIs; correct SDL2-era comments.
2. Add UI-thread scheduling through `SDL_RunOnMainThread` and document the
   threading rule in the native backend README.
3. Move frame scheduling on macOS to display-link pacing with explicit Metal
   layer configuration, and keep rendering during live resizing.
4. Present menus, popovers and tooltips through SDL3 popup windows where they
   must escape the parent window.
5. Extend `Lui_ime` with surrounding text, range geometry and replacement
   requests, with pure tests.
6. Implement the native text input client on macOS, then Linux; extend the
   Windows host through IMM32.

## Acceptance criteria

- No SDL type or call appears above the window host seam.
- On macOS and Linux, a CJK input method can reconvert committed text in a
  focused text field, and the candidate window follows the caret in
  multi-line and scrolled fields.
- macOS dictation and autocorrection can replace committed text.
- Disabling the native text input client falls back to SDL text input with
  composition still working.
- A menu or popover near a window edge extends beyond the window and keeps
  focus restoration and Escape ordering of the in-window implementation.
- An idle window performs no periodic wakeups, an animating window renders
  at the display's refresh rate, and rendering continues during live
  resizing on macOS.
- Work posted from another domain runs on the UI thread before the next
  frame that observes it.
