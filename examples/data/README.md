# EDN views with OCaml-owned state and events

This is an experiment, not a public LUI API. EDN declares view structure, bindings,
components, conditional/platform branches and action names. OCaml supplies the typed
model, derived fields, action signatures, event decoder, reducer and asynchronous
work. EDN does not evaluate functions or run business logic.

## Run

Use the project's OCaml 5.5.0 switch and its `melange-edn-core` pin. The script
builds the existing `lui.cmxa` target and compiles this example into
`_build/data-view`; it does not edit dune files or mount a graphical window.

```sh
OPAMSWITCH=5.5.0 sh examples/data/run.sh
OPAMSWITCH=5.5.0 sh examples/data/run.sh --check
OPAMSWITCH=5.5.0 sh examples/data/run.sh examples/data/scenarios.edn --mount-only
OPAMSWITCH=5.5.0 sh examples/data/run.sh examples/data/extensions.edn --profile web
OPAMSWITCH=5.5.0 sh examples/data/run.sh examples/data/extensions.edn --profile ios --mount-only
OPAMSWITCH=5.5.0 sh examples/data/run.sh examples/data/extensions.edn --profile android --mount-only
OPAMSWITCH=5.5.0 sh examples/data/run.sh examples/data/extensions.edn --profile web --benchmark 250 --mount-only
```

The default todo example scripts input, addition, toggling and reordering over a
headless patch backend. `--mount-only` starts with a sample item and skips scripted
interactions. `--profile` selects a declared host profile; it does **not** run that
host's UI. `--benchmark N` reports in-memory root parse, filesystem module load
and parse, static validation/compilation, cached graph recompilation and OCaml
model-update/retained-render timings separately. These are development-machine
measurements, not browser, iOS, Android or large-list benchmarks.

## Module format

`todos.edn` imports `frame.edn` and `todo-row.edn`; the frame imports `labels.edn`.
Imports are explicit and aliases are local to each source document:

```edn
{:version 1
 :imports {:layout "frame.edn"}
 :components
 {:workspace
  {:props {:caption :string}
   :slots [:body]
   :view [:column
          [:text {:text {:bind [:props :caption]}}]
          [:slot :body]]}}
 :view
 [:use :workspace {:caption "Tasks"}
  {:body [:if {:bind [:model :empty?]}
          [:text {:text "Empty"}]
          [:text {:text "Tasks available"}]]}]}
```

The real example uses `[:use :layout/panel ...]`. A component's `:props` are a
shape declaration; its `:slots` enumerate required slots. Slots evaluate in the
caller's scope, so a slot can bind to the caller's model or keyed row. Shape
expressions include `:string`, `:keyword`, `:bool`, `:int`, `:float`, vectors,
records, tuples, nullable values and finite enumerations. Module-local names can
coexist; ambiguous references must be namespace-qualified. `:view` is optional
in imported component-only documents, mandatory at the entry point. A standalone
view vector remains valid for small single-file experiments.

The compiler takes a host-supplied `Sources.loader` callback returning canonical
source identity and content. The native example resolves imports relative to the
importer and normalizes their paths. Web clients can supply an already-fetched
source map, without making core compilation depend on filesystems or async I/O.
Only transitively imported documents are loaded. A `Sources.cache` reuses parsed
units with the same canonical identity **and content**; changing content invalidates
the unit. The compiled plan is reusable across model changes; no EDN is parsed
or recompiled by a model signal update.

## View vocabulary

- Standard `[:kind {:property value ...} children ...]` nodes use generated
  OCaml constructor contracts plus canonical protocol admission. A wire property
  is not automatically a valid typed argument. `:root` and internal section
  wrapper nodes are runtime-only.
- `{:bind [:model :field]}` and `{:bind [:props :field]}` read typed contract
  paths. `[:for {:items {:bind [:model :items]} :as :item :key [:id]} child]`
  introduces a keyed row alias; nested lists can use different aliases.
- `[:when condition child]`, `[:if condition then else]` and
  `[:platform {:web view :ios view :macos view :android view :default view}]`
  select retained views. Other supported profile keys include `:linux`,
  `:windows` and `:generic`. All listed branches are compiled.
- `:on {:press :add}` or `:on {:input [:rename {:bind [:item :id]}]}` refers
  only to declared OCaml actions; arguments read the current scope at event
  time. The original typed LUI event (input text, checkbox state, pointer
  coordinates, extension fields) is decoded by OCaml, not by EDN.
- `[:ext/split-view ...]`, `[:ext/split-tab ...]` and
  `[:ext/gallery-accent ...]` in `extensions.edn` use the real gallery schema.
  Its split event updates an OCaml-owned ratio; only `:split-tab` admits
  standard children. `:platform` supplies a standard fallback for generic,
  Linux and Windows profiles.

## Contracts and validation boundary

### Preserve OCaml view types

`tooling/typed_view_schema.mjs` derives constructor contracts from
`src/lui_elements.mli` and canonical value encoders in `lui_elements.ml`, rather
than treating the broader wire schema as the typed API. Generation fails on an
unknown signature or value domain. The compiler preserves constructor property
surfaces, required labeled arguments, closed variants, abstract child categories,
fixed child arity and named element slots. The typed `align` modifier is also
available on standard nodes returning `t`. Components, slots, conditions, keyed
collections and platform branches do not erase their children's result types.
Branches must agree on that result type even in unused component definitions.

Values do not silently coerce between OCaml types:

```edn
[:row {:grow 1.0}]                          ; float, not integer 1
[:spinner {:size :sm}]                      ; closed variant, not string "sm"
[:icon {:name [:app "company-logo"]}]       ; explicit open icon constructor
[:file-picker {:request [:int 1]}]          ; explicitly tagged picker token
[:column {:data-attrs [["data-id" "item"]]}] ; string-pair list, not wire text
[:popover {:anchor :below :anchor-rect [0.0 0.0 12.0 12.0]}]
[:input-group
 {:slots {:actions [:input-group-actions [:button {:text "Send"}]]}}
 [:textarea]]
```

Bindings must have the same domains: a general `:string` or `:keyword` binding
cannot satisfy a finite variant; declare its exact keyword enumeration in the
OCaml model contract. Optional arguments may be nullable, required ones may not.
`split` and `drawer` need exactly two unconditional children, `input-group` one.
Use `:slots` for `input-group`'s `:actions`, `list-section`'s `:header`/`:footer`
and `list-item`'s `:swipe-actions`; structural wrappers cannot be supplied as raw
wire nodes to bypass the typed API.

The stronger `Lui_split.mli` contracts are generated separately: for example,
`split-branch.orientation` accepts only `:horizontal` or `:vertical`, although
its host wire schema carries strings. Other generated extension APIs export
`view_contracts` from the same declarations as their typed constructors. Pass
these to `Data_contract.create ~extension_contracts`; handwritten extensions need
an authoritative typed contract too. A registry entry without a typed contract
is rejected, and caller-supplied contracts cannot weaken built-in Split types.
An unsupported OCaml API is rejected, not inferred from permissive wire scalars.

### Static and runtime checks

`Data_contract.create` freezes a model shape, action signatures, the existing
`Lui_extension.extension_registry`, typed extension contracts and per-profile
host fingerprint manifests.
The native example reads literal split fingerprints from actual Web, Apple and
Android host sources. The Web gallery accent adapter uses the shared OCaml
registry rather than a separate host literal; its registered tweak fingerprint
is supplied from that registry. Hosts must provide truthful registration data:
static checks cannot prove that a host actually implements its adapter.

`Data_view.compile_files ~contract ~load ~entry ()` resolves imports, checks
cycles and duplicate declarations, and validates every component plus every
reachable document view, including unused definitions and inactive branches.
It checks binding shape/path, expression type, component props/slots, action
arity and typed event support, standard kinds/properties/children/scalar ranges,
structurally impossible property sets, extension profile/host/fingerprint,
required extension properties, child admission and extension event names.
Errors include source document and component/view context, not token-level
line/column locations. Host manifests are checked before mounting the selected
branch; inactive platform branches are schema-checked without requiring their
host to be installed on the current platform. The runtime still validates
rendered values against the canonical LUI protocol.

Static validation cannot decide the actual values of nullable bindings,
duplicate keys in live model lists, whether an external image/file exists,
permission grants or real native UI behavior. OCaml must validate event payloads
and business authorization. The source-size/expansion limits prevent accidents,
not malicious EDN; do not treat remote documents as trusted executable content.

| Scenario family | Declarative representation | Verification boundary |
| --- | --- | --- |
| Layout, forms, text fields, buttons, checkbox/toggle/radio, value controls, scroll | Standard kinds and bound properties/actions | Headless todo and scenario mounts; no real input/IME or focus test |
| Keyed lists, virtual lists, tables, trees, tabs, split | `:for` and standard kinds | Keyed-node identity/reorder/action regression check; scenario mounts only for the rest |
| Dialogs, menus, nested menus, sheets/overlays, loading/error | Standard kinds, `:if`, `:when`, projected OCaml state | Admission checked; native presentation and async workflows not exercised |
| Files, media, resource IDs, accessibility, navigation/pointer events | Standard schema, OCaml resources/actions | Schema admission only; resources and permissions remain host-owned |
| Custom cross-platform controls and tweaks | Extension registry and `:platform` fallback | Split example mounts in a headless profile; host UI parity not proven |

The `Signal.map`/`Lui_dynamic` implementation is a view-plan runtime bridge;
applications supply `project` and `dispatch`. There is no EDN `eval`, arbitrary
OCaml function lookup, hot replacement, transactional rollback or claim of
complete browser/mobile/native GUI parity. Measure large models and run real
host interaction suites before promoting this experiment to a production API.
