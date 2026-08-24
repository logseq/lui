# Solid UI correspondence matrix

Status: design

Reference: `stefan-karger/solid-ui` revision `21ba4fa`

Local reference checkout:
`/Users/tiensonqin/Code/projects/solid-ui/apps/docs/src/registry/ui`

## Compatibility target

LUI Web provides one component family for every file in Solid UI's 54-entry UI
registry. Solid UI defines the Web parity baseline. LG data forms replace TSX,
retained LUI primitives replace Solid components, and Signal replaces Solid's
reactive props and context state. Public behavior and visual output do not
change merely because the runtime changes.

For each family, correspondence requires:

1. the same component-family name and public named parts;
2. the same public props, variants, sizes, orientation and controlled state;
3. the same enabled, disabled, readonly, selected, expanded, invalid and
   loading states where the reference supports them;
4. the same keyboard navigation, focus management, dismissal and accessible
   relationships;
5. matching default and dark-theme visuals, responsive rules and motion;
6. retained identity: a property patch must not recreate unaffected native DOM
   elements or reset native transient state;
7. the same observable state attributes used by the reference styles, including
   `data-expanded`, `data-closed`, `data-checked`, `data-selected`,
   `data-disabled` and `data-invalid` where applicable;
8. a gallery page reproducing the reference examples and edge states.

JSX syntax and Solid/Kobalte context objects become LG data forms and Signal
scopes. Web prop names and compound-part boundaries otherwise stay aligned.
Tailwind utilities and class-variance-authority are compiled into static LUI
CSS and variant tables; they are not runtime dependencies. `:class` remains an
application override after component defaults.

## Implementation principles taken from Solid UI

- **Headless foundation, styled wrapper.** Solid UI wraps Kobalte, Corvu and a
  few focused libraries. LUI keeps the same separation between `lui.behaviors`
  and `lui.components`.
- **Compound parts.** Dialog, Select, Menu, TextField and similar families
  expose root, trigger, content, item, label and description parts instead of a
  single flag-heavy component.
- **Controlled state is Signal state.** Reference controlled props become
  Signal sources plus typed change events. Components do not copy values into a
  second state model. Native transient state remains in the retained backend
  node.
- **Variants are finite and composable.** Variant and size tables resolve to
  semantic tokens and part styles. Application overrides merge after defaults.
- **State drives styling.** Expanded, closed, checked, selected, disabled and
  invalid states are available to parts as typed state and the same Web data
  attributes used by Solid UI.
- **Accessibility is structural.** Labels, descriptions, errors, hidden form
  controls, focus traps and keyboard navigation belong to behavior contracts,
  not optional styling.
- **Small dependencies.** LUI does not adopt Solid UI's runtime dependencies.
  Native platform APIs are used first and LUI implements only reusable gaps.

## Public component inventory

The names below mirror the exports of the reference files. LUI uses kebab-case
tags and qualified part tags, for example `DialogContent` becomes
`:dialog/content` and `TextFieldErrorMessage` becomes
`:text-field/error-message`.

### Foundations and layout

| Solid UI family | LUI public family and parts | Web substrate |
| --- | --- | --- |
| AspectRatio | `:aspect-ratio` | retained `div`, native aspect-ratio CSS |
| Flex | `:flex` | retained flex layout |
| Grid | `:grid`, `:grid/col` | retained grid layout |
| Resizable | `:resizable`, `/panel`, `/handle` | pointer + keyboard resize behavior |
| Separator | `:separator` | semantic separator |

### Content, status and data display

| Solid UI family | LUI public family and parts | Web substrate |
| --- | --- | --- |
| Avatar | `:avatar`, `/image`, `/fallback` | image loading state |
| Badge | `:badge`; default, secondary, destructive, outline | styled text primitive |
| BadgeDelta | `:badge-delta` | Badge composition |
| BarList | `:bar-list` | keyed rows and native layout |
| Callout | `:callout`, `/title`, `/content` | alert/status semantics |
| Card | `:card`, `/header`, `/footer`, `/title`, `/description`, `/content` | retained composition |
| Charts | `:chart`, `:bar-chart`, `:bubble-chart`, `:donut-chart`, `:line-chart`, `:pie-chart`, `:polar-area-chart`, `:radar-chart`, `:scatter-chart` | LUI chart surface and semantics |
| DeltaBar | `:delta-bar` | retained vector/layout primitive |
| Progress | `:progress`, `/label`, `/value-label` | native progress semantics |
| ProgressCircle | `:progress-circle` | retained vector primitive |
| Skeleton | `:skeleton` | reduced-motion-aware animation |
| Table | `:table`, `/header`, `/body`, `/footer`, `/head`, `/row`, `/cell`, `/caption` | native table elements |
| Timeline | `:timeline` | keyed retained composition |
| Alert | `:alert`, `/title`, `/description` | alert semantics |

### Actions and forms

| Solid UI family | LUI public family and parts | Web substrate |
| --- | --- | --- |
| Button | `:button`; default, destructive, outline, secondary, ghost, link; default, sm, lg, icon sizes | native button |
| Checkbox | `:checkbox` | native checkbox plus styled control |
| Combobox | `:combobox`, `/item`, `/item-label`, `/item-indicator`, `/section`, `/control`, `/trigger`, `/input`, `/hidden-select`, `/content` | input, listbox and overlay behaviors |
| DatePicker | `:date-picker`, `/label`, `/control`, `/input`, `/trigger`, `/content`, `/view`, `/view-control`, `/prev-trigger`, `/next-trigger`, `/view-trigger`, `/range-text`, `/table`, `/table-head`, `/table-body`, `/table-row`, `/table-header`, `/table-cell`, `/table-cell-trigger`, `/year-select`, `/month-select`, `/positioner` | date model, grid and overlay behaviors |
| Label | `:label` | native label |
| NumberField | `:number-field`, `/group`, `/label`, `/input`, `/increment-trigger`, `/decrement-trigger`, `/description`, `/error-message` | native input plus numeric stepping behavior |
| OTPField | `:otp-field`, `/input`, `/group`, `/slot`, `/separator` | one native input with visual slots |
| RadioGroup | `:radio-group`, `/item`, `/item-label` | native radios plus roving focus |
| Select | `:select`, `/value`, `/hidden-select`, `/trigger`, `/content`, `/item`, `/label`, `/description`, `/error-message` | select/listbox and overlay behavior |
| Slider | `:slider`, `/track`, `/fill`, `/thumb`, `/label`, `/value-label` | native range semantics and retained parts |
| Switch | `:switch`, `/control`, `/thumb`, `/label`, `/description`, `/error-message` | native checkbox semantics |
| TextField | `:text-field`, `/input`, `/text-area`, `/label`, `/description`, `/error-message` | native input and textarea |
| Toggle | `:toggle`; default and outline variants, default/sm/lg sizes | pressed-button semantics |
| ToggleGroup | `:toggle-group`, `/item` | single/multiple selection behavior |

### Disclosure and navigation

| Solid UI family | LUI public family and parts | Web substrate |
| --- | --- | --- |
| Accordion | `:accordion`, `/item`, `/trigger`, `/content` | disclosure behavior |
| Breadcrumb | `:breadcrumb`, `/list`, `/item`, `/link`, `/separator`, `/ellipsis` | nav and list semantics |
| Carousel | `:carousel`, `/content`, `/item`, `/previous`, `/next` | retained scroll/snap behavior |
| Collapsible | `:collapsible`, `/trigger`, `/content` | disclosure behavior |
| Menubar | `:menubar`, `/menu`, `/trigger`, `/content`, `/item`, `/separator`, `/item-label`, `/group-label`, `/checkbox-item`, `/radio-group`, `/radio-item`, `/portal`, `/sub-content`, `/sub-trigger`, `/group`, `/sub`, `/shortcut` | menu and roving-focus behaviors |
| NavigationMenu | `:navigation-menu`, `/item`, `/trigger`, `/icon`, `/viewport`, `/content`, `/link`, `/label`, `/description` | navigation and overlay behaviors |
| Pagination | `:pagination`, `/items`, `/item`, `/ellipsis`, `/previous`, `/next` | navigation semantics |
| Sidebar | `:sidebar`, `/content`, `/footer`, `/group`, `/group-action`, `/group-content`, `/group-label`, `/header`, `/input`, `/inset`, `/menu`, `/menu-action`, `/menu-badge`, `/menu-button`, `/menu-item`, `/menu-skeleton`, `/menu-sub`, `/menu-sub-button`, `/menu-sub-item`, `/provider`, `/rail`, `/separator`, `/trigger` and `use-sidebar` behavior | responsive layout, Sheet and Tooltip composition |
| Tabs | `:tabs`, `/list`, `/trigger`, `/content`, `/indicator` | tabs and roving-focus behaviors |

### Overlays and feedback

| Solid UI family | LUI public family and parts | Web substrate |
| --- | --- | --- |
| AlertDialog | `:alert-dialog`, `/portal`, `/overlay`, `/trigger`, `/content`, `/title`, `/description` | modal dialog behavior |
| Command | `:command`, `/dialog`, `/input`, `/list`, `/empty`, `/group`, `/item`, `/shortcut`, `/separator` | filtered collection and dialog behavior |
| ContextMenu | `:context-menu`, `/trigger`, `/portal`, `/content`, `/item`, `/shortcut`, `/separator`, `/sub`, `/sub-trigger`, `/sub-content`, `/checkbox-item`, `/group`, `/group-label`, `/radio-group`, `/radio-item` | context menu behavior |
| Dialog | `:dialog`, `/trigger`, `/content`, `/header`, `/footer`, `/title`, `/description` | native dialog plus focus behavior |
| Drawer | `:drawer`, `/portal`, `/overlay`, `/trigger`, `/close`, `/content`, `/header`, `/footer`, `/title`, `/description` | modal drag/dismiss behavior |
| DropdownMenu | `:dropdown-menu`, `/trigger`, `/portal`, `/content`, `/item`, `/shortcut`, `/label`, `/separator`, `/sub`, `/sub-trigger`, `/sub-content`, `/checkbox-item`, `/group`, `/group-label`, `/radio-group`, `/radio-item` | menu and overlay behaviors |
| HoverCard | `:hover-card`, `/trigger`, `/content` | hover/focus disclosure behavior |
| Popover | `:popover`, `/trigger`, `/content` | Popover API plus placement behavior |
| Sheet | `:sheet`, `/trigger`, `/close`, `/content`, `/header`, `/footer`, `/title`, `/description` | Dialog composition with side variants |
| Sonner | `:sonner/toaster` | toast region behavior |
| Toast | `:toast/toaster`, `:toast`, `/close`, `/title`, `/description`; `show-toast`, `show-toast-promise` | live region and timed queue behavior |
| Tooltip | `:tooltip`, `/trigger`, `/content` | tooltip delay and placement behavior |

## Delivery waves

1. **Foundation:** tokens, variants, retained styling, Button, Card, Badge,
   Label, TextField, Checkbox, Switch, Separator, Progress, Skeleton, Flex,
   Grid and AspectRatio.
2. **Collections and disclosure:** Accordion, Collapsible, Tabs, Toggle,
   ToggleGroup, RadioGroup, Slider, Select, Pagination, Breadcrumb and Table.
3. **Overlay foundation:** Dialog, AlertDialog, Popover, Tooltip, DropdownMenu,
   ContextMenu, HoverCard, Sheet, Toast and Sonner.
4. **Advanced inputs and navigation:** Combobox, Command, DatePicker,
   NumberField, OTPField, Menubar, NavigationMenu, Drawer and Sidebar.
5. **Data and gesture components:** Avatar, BarList, BadgeDelta, Callout,
   Carousel, Charts, DeltaBar, ProgressCircle, Resizable and Timeline.

Each wave lands with its corresponding `examples/components/` gallery pages.
Web reaches all 54 families. Other platforms implement the same public contract
for daily components first, using platform-native presentation where an exact
visual copy would violate platform interaction conventions.
