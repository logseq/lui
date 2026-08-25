# Vercel Native UI API parity matrix

Status: authoritative design

Reference: `vercel-labs/native` revision
`4e015e925fc9974e2ab92840d6f8bb5a8f201c2d`

Reference source: `skill-data/native-ui/SKILL.md` and the closed schema in
`src/primitives/canvas/ui_schema.zig`.

LUI's implementation registry is [`schema/components.json`](../../schema/components.json).
It records the pinned public boundary and the currently implemented wire kinds
and properties once. `make generate-component-schema` derives:

- LG `node-kind` and `property` variants;
- LG wire-name encoders;
- Swift wire enums;
- the Dart node-kind enum and decoder.

`make test-schema` rejects stale generated files and duplicate protocol names.
Component-specific semantics, native widget behavior, and bespoke validation
remain handwritten and must pass the platform parity gates; the manifest does
not replace those platform decisions.

## Compatibility rule

LUI's supported public UI component API is a deliberate subset of the Vercel
Native UI API expressed as LG data. Inside that subset, the syntax changes;
the vocabulary and behavior do not.

The deliberate exclusions are `span`, `code`, `markdown`, `chart`, and
`series`. LUI keeps `text` as a plain-text leaf and does not own rich-text
runs, syntax highlighting, Markdown parsing/rendering, or a chart engine.

```html
<row gap="8" main="center" cross="center">
  <button variant="primary" on-press="save">Save</button>
</row>
```

```clojure
[:row {:gap 8 :main "center" :cross "center"}
 [:button {:variant "primary" :on-press save} "Save"]]
```

Parity for every in-scope component requires all of the following:

1. the same element names and parent/child constraints;
2. the same public attribute names, legal values, defaults and element scope;
3. the same visible content model and event meaning;
4. the same controlled versus runtime-owned state boundary;
5. equivalent keyboard, focus, accessibility and dismissal behavior;
6. equivalent validation: an invalid or meaningless attribute is rejected, not
   silently ignored;
7. retained identity when a Signal changes one property;
8. platform-native presentation where Vercel Native delegates to the OS.

LUI must not add a convenience prop, compound part or alias to a standard
component. A capability absent from Vercel Native remains internal until the
reference API contains it. This explicitly excludes public `:flex`,
`:grid/col`, responsive `:cols-*`/`:span-*`, and `:aspect-ratio` APIs.

## Syntax-only adaptations

| Vercel Native | LUI |
| --- | --- |
| element name `text-field` | keyword `:text-field` |
| attribute `min-width` | map key `:min-width` |
| literal enum `space_between` | string `"space_between"` |
| model binding | Signal source |
| message name in `on-*` | LG callback |
| child text | string child or reactive `:text` value |
| conditional/loop markup | LG/Signal composition with stable keys |

These adaptations cannot change defaults or introduce additional state.

Vercel Native's markup-language constructs are intentionally out of scope.
`template`, `use`, `import`, `if`, `else` and `for` are replaced by LG
functions, macros, `defui`, ordinary conditionals and keyed collection APIs.
LUI does not add a markup parser or a second template system.

## Element inventory

The following names are the public target. Qualified LUI-only part names are
not substitutes for these elements.

### Layout and containment

| Elements | Contract |
| --- | --- |
| `row`, `column` | horizontal and vertical flex flow |
| `stack`, `panel`, `card` | overlay containers; `gap` is invalid |
| `scroll` | one scroll region; direct children share the content box and overlay, so flow content uses an explicit `list` or `column` child |
| `list`, `grid` | vertical list and equal-cell grid |
| `resizable`, `split` | runtime-owned resize interactions |
| `tree` | disclosure tree and roving keyboard focus |

### Navigation and collections

`tabs`, `toggle-group`, `button-group`, `radio-group`, `breadcrumb`,
`pagination`, `table`, `table-row`, `table-cell`, `dropdown-menu`, `menu-item`,
`accordion`, and `list-item`.

### Surfaces and overlays

`alert`, `bubble`, `reactions`, `dialog`, `sheet`, `tooltip`, and
`context-menu`.

### Text and media

`text`, `badge`, `status-bar`, `icon`, `image`, and `media-surface`.

### Controls

`button`, `toggle-button`, `toggle`, `switch`, `select`, `avatar`, `checkbox`,
`radio`, `slider`, `progress`, `text-field`, `input`, `search-field`,
`combobox`, `textarea`, `separator`, `spacer`, `skeleton`, and `spinner`.

### Composite data views

`stepper`, `step`, `timeline`, `timeline-item`, `input-group`, and
`input-group-actions`.

## Shared attribute vocabulary

Attributes are admitted only on the same elements as the reference schema.

### Layout

- `gap`, `padding`, `grow`, `width`, `height`, `min-width`, `max-width`
- `main`: `start`, `center`, `end`, `space_between`
- `cross`: `stretch`, `start`, `center`, `end`
- `columns`, only on `grid`; omitted means the reference-derived layout
- `wrap`, `overflow`, `text-alignment`, only where the reference admits them
- `virtualized`, `virtual-item-extent`, and scroll `overscroll`
- `anchor`, `anchor-alignment`, `anchor-offset`, and `tooltip-delay`

There are no responsive breakpoint attributes. Responsive Web design uses
ordinary external CSS selected through the platform tweak mechanism.

### Appearance and state

- `variant`: `default`, `primary`, `secondary`, `outline`, `ghost`,
  `destructive`
- `size`: `default`, `sm`, `lg`, `icon`; `text` additionally admits `heading`
  and `display`
- `disabled`, `checked`, `selected`, `value`, `placeholder`, and `icon`
- component-specific fields retain the exact reference names and domains

### Focus, semantics and identity

- `autofocus` only on focusable controls
- `role`, `label`, and `expanded` with reference validation
- `key` for sibling identity and `global-key` for parent-independent identity

### Events

LUI uses callbacks in place of named messages but preserves the reference event
names and payload semantics: `on-press`, `on-double-press`, `on-toggle`,
`on-change`, `on-input`, `on-submit`, `on-dismiss`, `on-resize`, `on-hold`, and
`on-drag` where admitted by the reference element.

## Completed provisional API removals

| Removed public shape | Current parity shape |
| --- | --- |
| `:box` | internal primitive; public callers use `:stack` or `:panel` |
| `:heading`, `:paragraph`, `:label` | `:text` plus the reference text/semantic attributes |
| `:text-input`, `:text-area` | `:text-field`/`:input` and `:textarea` |
| compound `:text-field/*` | direct reference text-entry elements |
| `:padding-horizontal`, `:padding-vertical`, `:max-height` | not public parity attributes |
| `:class` | Web platform escape hatch, not standard component API |

Migration is allowed to break the provisional API. Compatibility aliases would
create a second component language and are therefore not retained.

The four direct text-entry elements are now schema-supported retained leaves.
They share `text`, `placeholder`, `disabled`, `autofocus`, `label`,
`on-input`, and `on-submit`; `textarea` alone adds `submit-on-enter` and grows
without a public autoresize or line-count property. Web maps them to native
`input`/`textarea`, Apple to SwiftUI text controls, and Flutter to retained
Material `TextField` widgets.

## Platform mapping

| Contract | Web | Apple | Flutter |
| --- | --- | --- | --- |
| row/column/list | CSS flex via Tailwind | `HStack`/`VStack` | `Row`/`Column` |
| stack/panel/card | CSS overlay/surface | SwiftUI overlay/ZStack | `Stack`/Material surface |
| scroll | CSS scrolling overlay box | `ScrollView` + `ZStack` | `SingleChildScrollView` + `Stack` |
| spinner | semantic CSS activity glyph | indeterminate `ProgressView` | `CircularProgressIndicator` |
| icon | bundled SVG CSS mask | SF Symbols `Image` | Material `Icon` |
| grid | CSS grid | `LazyVGrid` | `GridView` |
| controls | native HTML first | SwiftUI controls | Flutter widgets |
| list-item | native button row | SwiftUI Button row | Material `ListTile` |
| modal/menu | browser platform API when suitable | SwiftUI presentation | Flutter presentation APIs |

Backends may differ internally, but they cannot expose backend-specific props
on a standard component.

## Parity gate

Each delivered element must have:

- a schema test for accepted and rejected attributes;
- the same default and enum tests as the pinned reference;
- retained wire and incremental update coverage;
- Web, SwiftUI and Flutter mapping coverage;
- accessibility and interaction coverage proportional to the element;
- a state-complete example in `examples/components/`.

Updating the pinned Vercel Native revision requires a reviewed matrix diff
before implementation changes.
