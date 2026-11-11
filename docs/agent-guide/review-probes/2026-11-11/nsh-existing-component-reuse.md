# Existing desktop component reuse audit

Date: 2026-11-11. Scope: the original 48 admitted desktop kinds, before the
Basic, Collections and Surfaces family expansion. The route set is taken from
LUI commit `43873f6d`; mappings below inspect the current adapter source. Public
native API comparisons use official-main merge
`de7f3637171b769f18474796fd5159a60b2de726`, not an inferred release API.

This is a source audit. It adds no runtime qualification and does not establish
complete LUI API parity for an admitted kind. The main-sync qualification and
support inventory record build and test evidence separately.

## Result

The adapter already delegates ordinary control behavior to `nsh-base`: Button,
Tab, Checkbox, Toggle, Switch, Radio, RadioGroup, Slider, NumberInput, Progress,
Tabs, ToggleGroup, Toolbar, ToolbarGroup, Menu, Submenu, MenuItem and Sheet.
The private `ui` layer supplies scoped tokens, parts and motion; it does not
implement another keyboard or focus controller. Core Text, Input, View, Scroll,
Image, Modal and VirtualList are appropriate primitives where the canonical LUI
contract describes those primitives.

Two compositions need particular care: the retained LUI menu graph is not the
data-owned Select/Combobox model, and LUI external popup anchors are not owned
trigger slots. Replacing these adapters by name alone would change event and
lifetime behavior. Native RadioGroup now exposes a label property, which enables
a small improvement; removing its outer host also requires preserving that host's
generic event and identity contract.

## Mapping of all 48 kinds

The grouped rows below enumerate every original kind exactly once. “Native”
means the public NSH behavior component, not a lookalike drawn by the adapter.
Local entry points are [render.rs](../../../../platform/nsh/src/render.rs),
[controls.rs](../../../../platform/nsh/src/controls.rs),
[ui/mod.rs](../../../../platform/nsh/src/ui/mod.rs),
[ui/controls.rs](../../../../platform/nsh/src/ui/controls.rs) and
[virtual_rows.rs](../../../../platform/nsh/src/virtual_rows.rs).

| LUI kinds | Actual implementation | Adapter responsibility or limit |
| --- | --- | --- |
| `text`, `heading`, `paragraph`, `label`, `kbd` | Core Text in `Renderer::node` | Reactive text and canonical typography/style defaults. Rich TextView is a different contract, not a required replacement. |
| `text-field`, `secure-field`, `input`, `search-field`, `textarea` | `ui::input` → public `nsh_base::input` → core Input | Text/Submit translation, controlled value, placeholder, masking, multiline, readonly, disabled and label. Search-field currently shares the Input host rather than a separate search controller. |
| `root`, `row`, `column`, `box`, `panel`, `card`, `spacer` | Core View plus canonical compiled style and retained children | These are layout/presentation containers. No generic base Card or Panel exists. HoverCard adds hover-popup behavior and is not equivalent. `box display=contents` is explicitly rejected. |
| `list` | Core Scroll with List accessibility role | Eager authored children; large/sparse collections use the separate virtual-list contract. |
| `grid` | Core View grid | Authored children and column count; out-of-u16 column counts are rejected before publication. |
| `divider` | Noninteractive core View with token-colored one-point rule | Simple decoration; no base Divider behavior is being replaced. |
| `input-group`, `input-group-actions` | Named core Group / core row | Border, spacing and authored children; no corresponding behavior-rich base InputGroup exists. |
| `scroll` | Core Scroll | Canonical scroll request/completion adapter; native engine owns scrolling. |
| `virtual-list` | Core VirtualList through `virtual_rows::element` | Sparse metadata validation, retained row identities, demand/pin feedback and canonical scroll tokens; native component owns virtualization. |
| `image` | Core Image | **Incomplete resource translation at audit time:** render reads `source`, while canonical Image supplies `image`/`url` and optional source crop coordinates. See the actionable gap below. |
| `button` | `ui::controls::CommandButton` → native Button, or native Tab inside Tabs context | Canonical Press, selected/disabled state, variant/size/icon presentation. Keyed icon/label/authored-child slots retain child identity when reordered. |
| `toggle-button` | Native Toggle | Canonical `selected` is the pressed value; native Change becomes Toggle. Shares command appearance/slots. |
| `toggle`, `checkbox` | Native Checkbox | Canonical checked/mixed state and Toggle event; parts styled in the scoped UI layer. |
| `switch` | Native Switch | Controlled checked state; native requests translated to canonical Toggle without optimistic model mutation. |
| `radio` | Native Radio | Controlled checked state; Change precedes Toggle as in LUI. Repeated Press activation is not implemented and `press-enabled` is rejected. |
| `radio-group` | Named core Group containing native RadioGroup | Native roving keys remain in RadioGroup. Main now supports a native group label. Outer host currently carries common events/style/ref; root corrected its outdated API-gap comment during this audit. |
| `slider` | Native Slider | LUI unit interval maps to min=0/max=1; native Change becomes Value. |
| `number-stepper` | Native NumberInput | Canonical value/min/max/step; absent max remains absent, rather than imposing 100. |
| `progress` | Native Progress | LUI fraction multiplied by 100 for the native percentage contract. |
| `tabs` | Private named Group plus native Tabs; LUI buttons become native Tab | Native roving focus, disabled skipping and indicator remain native. Main TabsProps still lacks a group-label property. |
| `button-group` | Native ToolbarGroup | Native toolbar context and group semantics. Root's reuse fix now forwards the authored accessibility label directly. |
| `toggle-group` | Native ToggleGroup | Native grouped toggle behavior; children remain canonical controlled nodes. |
| `toolbar` | Native Toolbar | Native roving context and label; changing axis after mount is explicitly rejected to retain correct native context. |
| `select`, `combobox`, `menu-trigger` | Native Menu/Submenu plus trigger slot; combobox uses native Input | Keeps authored menu graph and application-controlled opening/query. Native menu owns traversal, submenu behavior and dismissal. These routes do not claim the native Select data model or native Combobox filtering contract. |
| `dropdown-menu` | Retained core View mounted as the owning native Menu/Submenu popup content | Structural popup ownership is validated atomically. It is not a stand-alone generic fallback for a menu controller. |
| `menu-item` | Native MenuItem | Authored children, disabled/checked state, native menu traversal, per-item canonical Press on activation. |
| `dialog` | Public `nsh_base::dialog()` → core Modal, with styled visible panel | Native modal/cancel behavior. Automatic close is disabled so canonical Dismiss requests remain application-owned; authored dimensions reach the panel. |
| `sheet` | Native Sheet | Controlled open lifetime, native backdrop/cancel semantics and styled popup part. |
| `popover`, `tooltip` | Core Overlay using native external anchors, placement and hint policy | Preserves external target/rectangle/point anchors and retained children. Popover translates cancellation/outside dismissal; tooltip uses native hint timing/focus visibility. See the trigger API boundary below. |

Count: 5 text + 5 input + 7 containers + 5 eager layout/grouping + 2 scroll +
1 image + 10 controls + 4 control groups + 5 menu/picker + 4 modal/overlay = 48.

## Public source evidence

The immutable source links below are the authority for reuse decisions:

- [Input re-export](https://github.com/logseq/nsh/blob/de7f3637171b769f18474796fd5159a60b2de726/crates/nsh-base/src/lib.rs#L103): `nsh_base::Input/input` is the core host alias. Using this native host does not omit a hidden base input controller.
- [Button](https://github.com/logseq/nsh/blob/de7f3637171b769f18474796fd5159a60b2de726/crates/nsh-base/src/button.rs), [Checkbox](https://github.com/logseq/nsh/blob/de7f3637171b769f18474796fd5159a60b2de726/crates/nsh-base/src/checkbox.rs), [Radio](https://github.com/logseq/nsh/blob/de7f3637171b769f18474796fd5159a60b2de726/crates/nsh-base/src/radio.rs), [Switch](https://github.com/logseq/nsh/blob/de7f3637171b769f18474796fd5159a60b2de726/crates/nsh-base/src/switch.rs), [Slider](https://github.com/logseq/nsh/blob/de7f3637171b769f18474796fd5159a60b2de726/crates/nsh-base/src/slider.rs) and [NumberInput](https://github.com/logseq/nsh/blob/de7f3637171b769f18474796fd5159a60b2de726/crates/nsh-base/src/number_input.rs): actual control state and interaction implementations used by the adapter.
- [Tabs](https://github.com/logseq/nsh/blob/de7f3637171b769f18474796fd5159a60b2de726/crates/nsh-base/src/tabs.rs#L92) and [Toolbar/ToolbarGroup](https://github.com/logseq/nsh/blob/de7f3637171b769f18474796fd5159a60b2de726/crates/nsh-base/src/toolbar.rs): native roving patterns and parts, not custom LUI key handling.
- [SelectItem and selection event policy](https://github.com/logseq/nsh/blob/de7f3637171b769f18474796fd5159a60b2de726/crates/nsh-base/src/select.rs#L26), [Combobox](https://github.com/logseq/nsh/blob/de7f3637171b769f18474796fd5159a60b2de726/crates/nsh-base/src/combobox.rs), [Menu](https://github.com/logseq/nsh/blob/de7f3637171b769f18474796fd5159a60b2de726/crates/nsh-base/src/menu.rs): the data-owned picker and authored menu contracts differ.
- [PopoverProps](https://github.com/logseq/nsh/blob/de7f3637171b769f18474796fd5159a60b2de726/crates/nsh-base/src/popover.rs#L12), [Tooltip](https://github.com/logseq/nsh/blob/de7f3637171b769f18474796fd5159a60b2de726/crates/nsh-base/src/tooltip.rs) and [core element APIs](https://github.com/logseq/nsh/blob/de7f3637171b769f18474796fd5159a60b2de726/crates/nsh-core/src/element/builder.rs): slot-owned triggers versus core external anchors/hints.
- [Navigation host constructors](https://github.com/logseq/nsh/blob/de7f3637171b769f18474796fd5159a60b2de726/crates/nsh-base/src/navigation.rs#L38): `dialog()` is the public native Modal constructor.
- [ComponentElement boundary](https://github.com/logseq/nsh/blob/de7f3637171b769f18474796fd5159a60b2de726/crates/nsh-core/src/element/builder.rs#L2548): a typed component hears its declared events and exposes its declared semantic props; it is not Interactive or Accessible. Host methods cannot simply be moved to it by analogy.

## Decisions and next improvements

### Keep the native Menu composition for the existing picker contract

Canonical Select/Combobox own an arbitrary retained menu-node hierarchy, including
nested menu triggers, disabled items and authored children with independent
NodeIDs. Each activated menu item dispatches its own Press; selecting an already
selected item can still perform application work. Native SelectItem instead owns
a unique value/title list, and native Select emits Change only when the value
changes. A custom row renderer does not erase that ownership or event policy.

The current Menu/Submenu composition reuses native traversal and dismissal while
preserving this API. A future optional data-owned picker API could use native
Select/Combobox directly. It must not silently flatten the existing child graph
or reinterpret per-item Press as value Change.

Existing focused tests cover disabled skipping, controlled open refusal, query
and Input identity through opening, and right-arrow submenu selection. Before
changing this route, add repeated activation of the same item, retained nested
editor identity/draft across reorder and popup close/reopen, and IME/query
ownership coverage. Test names are in `render.rs`: `native_menu_keyboard_*`,
`model_owned_select_*`, `combobox_keeps_*`, `native_submenu_*`.

### Keep external anchors; seek a native component seam rather than moving nodes

Base Popover owns its trigger slot and lazily creates content on opening. Base
Tooltip attaches its policy to its surrounding trigger owner. LUI can instead
target an existing sibling NodeID, an explicit rectangle, or a point; its popup
children already have retained identities. Moving the trigger into a new base
component would change ownership, layout or editor lifetime.

Core Overlay is a public native placement/hint host, so its use here is deliberate.
It does not prove full equivalence to every base Popover/Tooltip interaction.
The smallest upstream-compatible improvement would be a public externally
anchored behavior attachment that retains the original trigger/child owners.
Require tests for anchor removal/recreation, external pointer focus, Escape
restoration, keyboard tooltip visibility, scroll/reposition and retained editor
identity before replacing the current seam. Existing `externally_anchored_*` and
`anchored_tooltip_*` tests establish only their named scenarios.

### Forward native group semantics where the API now exists

ToolbarGroup already has a label prop and now receives LUI's authored name. The
regression `button_group_passes_its_authored_name_to_the_native_toolbar_group`
checks the actual native group, not an extra label-only wrapper.

RadioGroupProps on main now has `accessibility_label`; forward this label directly
to the native radiogroup. Root has corrected the old missing-label API comment
without changing runtime behavior. Retain the
current outer host until its common pointer/lifecycle/ref/style duties have a
qualified public projection. Blindly removing it would cross the documented
ComponentElement boundary. Require the native radiogroup's name, unchanged arrow
navigation and disabled skipping, one pointer event per activation, and stable
native IDs/style geometry. Tabs still lacks the corresponding list label prop;
its named Group is therefore a separate, documented composition.

### Repair Image translation before claiming complete support

At this audit snapshot `Renderer::node` reads `source` for Image. Canonical
`lui_protocol.ml` validates `ImageIdValue` or nonempty `UrlValue`, plus an optional
complete source crop quartet. A registered resource is also not equivalent to a
URL string. Use the canonical URL property for native URL sources, implement the
existing resource ownership bridge before accepting image IDs, and map or
explicitly reject crop semantics before publication. Add actual pixel/geometry
tests for URL replacement, crop and resource lifetime; merely finding an Image
host in the tree would miss this problem. No resource implementation is added by
this report.

### Preserve sparse updates and explicit limits

Keep the existing per-entry signals, incarnation guards, scoped theme getters
and keyed authored children. Reuse should not add a second tree, focus manager,
virtualizer or data-list schema. Keep explicit Radio repeated-activation,
toolbar-axis, display-contents and native numeric representation restrictions
visible in validation and migration notes. An admitted route is an implementation
path, not a statement that every canonical property and event has been qualified
on every desktop OS.
