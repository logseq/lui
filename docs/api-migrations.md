# LUI API migration guide

## Unreleased: Android list and menu content padding

Android `list-item` and `menu-item` apply authored padding inside their native
Material controls, replacing native padding on each specified edge rather than
adding a second outer inset. Unspecified edges retain Material defaults. An
authored fixed height removes unspecified native vertical padding so compact
nested controls do not consume the label's entire height.

Compact selection rows can keep their existing geometry:

```ocaml
list_item ~height:44 ~padding_vertical:0 [
  menu_item ~height:44 ~padding_vertical:0 ~text:"Choice" ~selected:true []
]
```

Remove explicit padding or height to use the corresponding Material defaults.
Native selection, press events, disabled states and other hosts are unchanged;
no wire or schema migration is required.

## Unreleased: Android button content alignment

Android buttons center their label or icon/label group using the native Material
control. Custom child content now honors child `grow`; descendant text inherits
the button's `text-alignment` (center by default) unless it declares its own.
Icon/label pairs reserve space for either leading or trailing icons and ellipsize
long labels within the remaining width. Other hosts and press events are unchanged.

`text-alignment` no longer implicitly expands a label or its button to the full
available width. Adjacent aligned buttons therefore keep their natural widths.
Use explicit sizing when expansion is intended:

```ocaml
button ~grow:1.0 ~text_alignment:`center ~text:"Continue" []
button ~grow:1.0 [text ~grow:1.0 ~value:"Continue" []]
```

An explicit child `text_alignment` still takes precedence. No wire/schema
migration is required.

## Unreleased: Android text wrapping and overflow

Android text, labels and paragraphs now honor the existing `white-space` and
`text-overflow` properties. For example, `text ~white_space:"nowrap"
~text_overflow:"ellipsis" ~value:"Long title" []` stays on one ellipsized line
inside a constrained row. `pre` disables soft wrapping while preserving explicit
line breaks; omitted properties retain wrapping and clipping. Existing
`line-clamp` limits remain supported. No wire/schema migration is required;
other hosts are unchanged.

## Unreleased: Android sheets expand for text input

Android sheets that support the medium detent now expand when the software
keyboard is visible, keeping form fields and actions above the IME. Hiding the
keyboard leaves the sheet expanded; dismissal and explicit height constraints
are unchanged. Existing `sheet ~detents:"medium,large" [...]` forms need no
application workaround or wire/API migration. Apple and other hosts are unchanged.

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

Navigation sheet actions now honor `icon`, `min-width`, and `min-height`.
An icon-only action must supply an accessibility label, for example
`button ~icon:(`app "close") ~label:"Close" ~min_width:44 ~min_height:44
~style_class:"confirmation-action plain-action" []`. The optional `plain-action`
class hides the shared toolbar background on Apple platforms 26 and later.
Existing actions retain their system toolbar appearance.
