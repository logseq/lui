# Web Simulator Platform

Status: accepted design

## Goal

Add a DOM-first Web Simulator platform to LUI that can render the same retained
application as a high-fidelity iOS or Android experience without Xcode, an iOS
Simulator, a physical device, or Apple hardware.

The simulator is a development and comparison target. It does not claim to run
UIKit, SwiftUI, Android, or Jetpack Compose binaries in the browser. LUI keeps
its typed retained runtime and projects the same semantic component tree into
platform-specific Web behavior and styling.

The first release supports two public simulator profiles:

- `ios`: Apple phone behavior and visual tokens;
- `android`: Material phone behavior and visual tokens.

Device traits such as tablet size, safe areas, keyboard presence, pointer class,
and color scheme remain independent from the platform profile. This allows a
later iPad profile without creating another renderer.

The initial device catalog includes iOS and Android phone/tablet presets in
portrait and landscape. Presets expose typed form-factor, orientation, and
pointer values plus viewport size, device scale, safe-area insets, and virtual
keyboard height. Phones use touch input; tablets use a hybrid pointer trait to
cover touch plus iPad/Android keyboard and pointer workflows.

## Non-goals

- Running an Apple or Android system image in WebAssembly.
- Reimplementing SwiftUI as a general-purpose browser framework.
- Making a full-screen Canvas renderer the default.
- Pixel-copying private platform assets or undocumented system behavior.
- Replacing the native Apple and Flutter/Android production backends.

## Rendering boundary

Standard LUI components remain semantic DOM elements. Text fields, buttons,
lists, tables, links, selection, focus, IME composition, accessibility, and
browser inspection continue to use native browser capabilities.

Canvas is an opt-in implementation detail for extension surfaces that need it,
such as charts, drawing, games, or specialized media. It is not a simulator
rendering layer.

The Web renderer owns one simulator platform value. It applies that value to both:

1. the application host marked by `data-lui-root`; and
2. the detached popup portal appended under `document.body`.

Both scopes expose `data-lui-platform="ios|android"`. Profile changes update
those attributes together and never recreate retained component DOM nodes.
Multiple renderer instances in the same document remain isolated.

Device state is projected to both scopes through `data-lui-form-factor`,
`data-lui-orientation`, `data-lui-pointer`, and `data-lui-keyboard`. The
corresponding `--lui-viewport-*`, `--lui-device-scale`, `--lui-safe-area-*`,
and `--lui-keyboard-height` variables are the only layout inputs consumed by
simulator-specific presentation. Focusing a semantic LUI text entry exposes
the platform keyboard height; blur restores zero without replacing the input.

The runtime backend capability profile remains `WebOS + WebHost`. The simulated
OS is a separate Web projection value, because a browser must not claim to be a
`SwiftUIHost` or `FlutterHost`. Extensions therefore continue to select their
Web adapters honestly while their surfaces receive iOS or Android presentation.

## Platform fidelity

Platform fidelity has three layers and is not treated as a CSS skin:

1. **Tokens**: typography, density, corner radius, elevation, color, motion,
   safe-area insets, and control sizing.
2. **Component behavior**: navigation transitions, sheets, dialogs, menus,
   toggles, focus, overscroll, keyboard avoidance, and gesture thresholds.
3. **Device shell**: viewport, pixel ratio, safe areas, status/navigation bars,
   virtual keyboard, touch/pointer mode, rotation, and reduced-motion settings.

`BottomTabs` is the first navigation component to carry this contract through
every backend. It owns two to five retained `BottomTab` destinations. Apple
renders the destinations with SwiftUI `TabView`, which adopts the system tab
bar and Liquid Glass on iOS 26. Android renders them with Material 3
`NavigationBar`. The Web Simulator keeps the same destination pages mounted
while reproducing the iOS floating glass bar or Android navigation indicator
with semantic `tablist`, `tab`, and `tabpanel` DOM roles.

Direct switches follow native field ordering: the label remains leading and
the platform-sized control remains trailing. Dialog and Sheet action buttons
emit ordinary model-owned events instead of mutating presentation locally.
Phone sheets expose a decorative, accessibility-hidden drag handle and arbitrate
downward dismissal against interactive descendants and scrolled content using
distance and velocity thresholds. SwiftUI uses `presentationDragIndicator`,
and Flutter uses the native Material bottom-sheet drag handle and route gesture.

The initial vertical slice establishes profile ownership and visibly different
tokens for Button, text entry, Switch, Card, Dialog, and Sheet. Later slices add
platform behavior component by component, with interaction tests before each
implementation.

## Extensions

Extensions keep the existing schema, fingerprint, retained-node, lifecycle,
and event contracts from ADR 0002.

- Map uses a semantic DOM region with retained button markers, accessible zoom
  and recenter controls, touch dragging, deterministic geometry, and validated
  `region-change` events. It does not require Canvas or a network tile service.
- Camera uses a retained DOM `video` surface backed by `getUserMedia` only after
  an explicit user action. It starts with a deterministic mock feed for CI,
  preserves its stream across simulator profile changes, exposes denied access,
  and stops every media track when returning to the mock or dropping the node.
- Native Apple and Android factories continue to use their native frameworks.

An extension may use Canvas inside its own retained surface. It cannot replace
the root DOM renderer or bypass the extension lifecycle.

## Comparison corpus

Reference applications are external, pinned inputs rather than vendored source.
A committed manifest records repository URL, immutable commit SHA, license,
selected source paths, device profile, viewport, scenario, and attribution.
Downloads go to `_build/web-simulator-references`, which is already ignored.

The initial corpus is:

| Platform | Repository | Pinned commit | License | Purpose |
| --- | --- | --- | --- | --- |
| iOS | `apple-sample-code/ComposingCustomLayoutsWithSwiftUI` | `9a1d0ec86596deb5d8e48e1286ea626ae3605122` | MIT-style Apple sample license | custom layouts and adaptive composition |
| iOS | `apple-sample-code/FrutaBuildingAFeatureRichAppWithSwiftUI` | `dc9af9a5fb5dfe334630aab727fa2369f442c7f2` | MIT-style Apple sample license | realistic navigation, cards, lists, and adaptation |
| iOS | `alexpaul/SwiftUI` | `d240d386f8ae165f2f14ce5d620bdc6e971bd30a` | MIT | small controls and interaction examples |
| Android | `android/compose-samples` | `018c5207fb63c4f78e5841bd8ddd4faabdf19d3a` | Apache-2.0 | Material components, navigation, and adaptive layouts |

Assets with separate terms are excluded unless their attribution and reuse
conditions are recorded. Visual references produced on native hardware may be
kept outside the repository when redistribution is unclear; the scenario and
measurement metadata remain committed.

## Verification

Behavior tests prove:

- `ios` and `android` profiles mark both host and portal scopes;
- switching profiles keeps retained DOM node identity and active input state;
- two renderers can use different profiles in one document;
- portaled Dialog, Sheet, Tooltip, Menu, and Toast inherit the owning profile;
- profile changes preserve extension nodes and lifecycle state;
- Bottom Tabs preserve destination DOM and form state while switching selection
  or changing between iOS Liquid Glass and Android Material presentation;
- semantic roles, keyboard behavior, focus, IME, and accessibility remain
  unchanged.

Styling tests prove that the built stylesheet contains root-scoped iOS and
Android token contracts and does not introduce a full-screen Canvas rule.

Playwright visual scenarios use fixed fonts, viewport, scale, color scheme,
locale, time, animation state, and mock extension inputs. Each scenario records
pixel difference, structural DOM assertions, interaction assertions, and
accessibility checks. Pixel comparison is a regression signal, not the only
definition of fidelity.

The comparison workflow is explicit and reproducible:

```sh
make fetch-web-references
make test-web-visual
```

The fetch step clones each public repository, checks out its immutable commit
in detached-HEAD state, and verifies the remote, license, and selected source
paths. It never executes reference code. The visual step launches the pinned
Playwright Chromium build, drives the Gallery from committed scenario metadata,
checks DOM roles and geometry, and compares screenshots against per-scenario
pixel budgets. Failed comparisons write review artifacts to
`_build/web-simulator-visual-diffs`.

Baseline changes require the separate `make update-web-visual-baselines`
command. They are committed only after visual review. These images are
deterministic Web regression baselines whose component choices and measurements
are traceable to the public source corpus; they are not presented as native
device screenshot pixel truth.

## Delivery sequence

1. Typed platform profiles, host/portal scoping, runtime switching, and initial
   component tokens.
2. Device shell and deterministic screenshot harness for iOS and Android.
3. Navigation, sheet, dialog, menu, switch, and keyboard behavior parity.
4. Deterministic Map and Camera extension adapters.
5. Tablet traits and iPad adaptive behavior.
6. Expand the pinned corpus and add per-component fidelity budgets.

Steps 1 and 2, Bottom Tabs and the Sheet portion of step 3, and step 4 are
implemented in the current branch. The first deterministic phone baselines and
per-scenario fidelity budgets cover buttons, switches, Bottom Tabs, and Sheet on both
platforms. Remaining component interaction parity and expanded tablet/native
comparison coverage stay explicit delivery gates rather than being inferred
from DOM behavior tests.
