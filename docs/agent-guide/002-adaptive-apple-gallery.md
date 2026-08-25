# Adaptive Cross-Platform Component Gallery

Status: accepted design

## Goal

Present the component showcase as one component page at a time on every host:

- iPhone starts with a component list and pushes one component detail.
- iPad and Mac use a persistent sidebar and detail column.
- Flutter uses Material navigation rail or drawer according to width.
- Web uses a responsive sidebar or horizontal compact component picker.
- The selected detail renders the existing LG retained subtree directly.
- Component state and events remain owned by the LG model and Signals.

## API boundary

Do not add a public LUI `Sidebar` component. Sidebar is absent from the pinned
Vercel Native component API, and the Gallery navigation shell is host-owned
rather than application UI.

The shared Gallery root has exactly one direct retained child per public LUI
component. Each child is a complete page with exactly one heading. Hosts derive
read-only descriptors from those direct children; no host maintains a second
component registry. A descriptor contains only the retained page node id and
its first visible heading or text label.

The navigation shell is showcase infrastructure, not part of the public LUI
component API. Rendering a selected page still goes through the normal retained
backend entry point, so switching pages never recreates LG state or introduces
a VDOM.

## Apple mapping

The SwiftUI host uses `NavigationSplitView` and `List`:

- compact width: component list, then pushed detail;
- regular width and macOS: sidebar plus selected detail;
- detail content uses a vertical `ScrollView`, safe-area-aware padding, grouped
  system background, and a navigation title;
- the host owns navigation selection only; it never mirrors component state.

## Flutter mapping

The Flutter host derives the same page descriptors from the wire-retained root:

- compact width: Material `NavigationDrawer` plus one selected page;
- regular width: scrollable `NavigationRail` plus one selected page;
- page widgets keep stable retained node keys when navigation changes;
- patch callbacks rebuild only host projection metadata while backend node
  handles continue to invalidate incrementally.

## Web mapping

The Web host derives the same page descriptors after the initial retained batch.
It mounts only the selected page DOM node into the content region. Other pages
stay detached but retained, so selection moves existing DOM rather than
rebuilding it. Desktop uses a left sidebar; compact width uses a horizontal,
scrollable component picker.

## Verification

The LG integration test proves all 63 public components are unique direct page
roots. Browser verification asserts 63 derived navigation entries and exactly
one mounted component heading. Flutter backend tests cover direct-root section
projection and retained widget identity.

Maestro exercises list-to-detail navigation and real interactions for Button,
Tabs, Dialog, text input, Checkbox/Switch Signal sharing, and Radio selection.
Apple unit tests cover section projection and retained observation.

Text-entry details keep a native draft while focused. LG receives incremental
text events, but an echoed or transformed Signal value cannot replace the
native draft during marked-text composition. This preserves Chinese IME
composition, selection, and the insertion point; external values reconcile
after editing ends.
