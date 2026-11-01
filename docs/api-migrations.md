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
