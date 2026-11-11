# NSH display-none visibility projection

This source review uses the immutable NSH `bfa15d0` checkout resolved by LUI.
The implementation was prepared without running Cargo or the native GUI; the
parent integration run owns execution evidence.

## Native source evidence

- `nsh-core/src/core/mod.rs`, `emit_frames_in` (around line 8495), handles
  display-none by assigning zero frames and zero input-content bounds, then
  recursing into children. `Node::mounted_view_style` (around line 786) does not
  derive `ViewStyle.hidden` from display-none.
- macOS `text_input.rs::place` (around line 2182) hides the native input pad when
  those frames have no area. This is input geometry, not an AX subtree policy.
- macOS `access.rs::spec_for` (around line 1046) derives hidden accessibility
  state from the actual visibility flag or `Accessibility.hidden`.
  `reached` suppresses the hidden parent's accessible children. The native
  regression `a_hidden_style_hides_the_subtree` verifies this path.
- Windows `access.rs` (around line 347) and `access/uia.rs` (around line 279)
  exclude `style.hidden` nodes; `access.rs::style_changed` refreshes the tree when
  that flag changes. Linux `access.rs` (around lines 300 and 390) uses the same
  visibility flag to suppress the subtree and refresh its accessibility state.
- macOS `input.rs::is_key_stop` checks native target visibility, while native
  input pads have their own focus lifecycle. Headless `Screen::tab_stops` excludes
  hidden ancestors through `shown`; `layout_nodes` exposes that ancestor state.

## Adapter change and scope

The existing exhaustive canonical Display provider emits native Display and a
hidden marker. Only canonical `none` adds public `StyleKey::Visibility=true`.
Neither `block` nor an absent display property emits a visible override. This
keeps an ordinary descendant from reversing the hidden ancestor's native
visibility. Removing the local display-none declaration lets the existing
reactive inline-style patch restore the local default, without a separate
visibility signal, tree walk or controller.

The focused Headless regression checks the actual `MountItem::ViewStyle.hidden`
updates consumed by those native AX adapters, hidden ancestor propagation,
public role matching, pointer rejection, Tab/Enter routing, restoration of both
explicit-block and default display, native IDs and retained editable content.
Headless does not instantiate VoiceOver, UIA or AT-SPI: the AX claim is a verified
native mount projection plus the source paths above, not an OS accessibility
client session. Active-focus removal and actual OS accessibility navigation
remain appropriate platform qualification cases.
