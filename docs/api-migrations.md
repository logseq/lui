# LUI API migration guide

## Unreleased: compact Apple drawer resting geometry

A compact drawer's retained sidebar now rests outside the viewport when fully
closed, with no animation or gesture active and no remaining drag displacement.
Previously, it rested just 20 points to the left, covered by the main content
but still geometrically within the screen.

The resting translation is non-interpolating and separate from the existing
parallax and opacity animations. The panel remains mounted after its first
reveal, preserving its view identity; its sizing, environment, hit-testing and
accessibility policy remain unchanged. Regular-width `NavigationSplitView`
layout is unchanged.

No API or wire migration is required. For example, setting the drawer's
`selected` state to `false` still closes it without removing its sidebar
children; setting it back to `true` reuses the retained panel. Keep existing
accessibility identifiers and open/close checks. Offscreen geometry and
automation snapshot presence do not establish VoiceOver focusability.

## Plain text-entry styling (2026-11-02)

Apple and Android text-entry controls accept `plain-input` in `style-class`.
This opt-in style preserves the normal text binding, secure entry, accessibility
and input events, and omits the platform field decoration. Existing controls
keep their current appearance. Applications own the background, border, padding
and corner radius through the existing surface properties.

For example, `text_field ~style_class:"plain-input" ~padding_horizontal:18
~min_height:54 ~border_width:1 ~corner_radius:27 ~border_color:"border" []`
creates a shared outlined pill field. The same style supports `secure_field`;
password masking remains native. No wire-schema migration is required.

Apple modal surfaces also honor `theme` and `theme-mode` on the modal node
itself, in addition to ancestor scopes; the modal scope wins. This fixes
`themed ~tokens (sheet ...)` without requiring a wrapper node.
