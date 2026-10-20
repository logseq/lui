# UI as data: EDN view experiment

Conclusion: **EDN can serve as LUI's declarative view format, but should not become a business scripting language.**
OCaml owns the typed model, actions, reducer, derived state and asynchronous tasks;
EDN describes only structure, properties, bindings and event routing.
This directory is an experiment, not a new public `lui` API. It changes no dune files or production dependencies.

## Running

Requires the project dependencies, `ocamlfind` and `melange-edn-core`. Validation used
the OCaml `5.5.0` switch and the `ocaml-signal` pin from `lui.opam.locked`.
If the EDN reader is not installed, pin the version used by this experiment:

```sh
opam pin add --switch=5.5.0 melange-edn-core.0.5.0 \
  'git+https://github.com/logseq/melange-edn.git#3cb79f278e972388a0a2b2ea1caec7a008a0b956' -y
OPAMSWITCH=5.5.0 sh examples/data/run.sh
OPAMSWITCH=5.5.0 sh examples/data/run.sh --check
OPAMSWITCH=5.5.0 sh examples/data/run.sh examples/data/scenarios.edn --mount-only
```

`run.sh` builds `lui.cmxa` through the existing dune target, then compiles the interpreter
and example with `ocamlfind`. Artifacts are written only to `_build/data-view`.
The default example uses a real `Lui_app` with a headless patch backend to simulate
input, insertion, toggling and reordering. **It does not open a graphical window.**
`--mount-only` starts with one sample item and mounts the supplied document without running the todo interactions.

## Data flow and boundaries

```text
OCaml typed model ── project ──> EDN-compatible read model
                                     │
EDN source ── compile ──> view plan ── bindings / keyed scopes ──> LUI retained patches
                                     │
                              action name + current arguments + native event
                                     │
OCaml dispatch ──> typed action ──> reducer ──> model signal
```

`main.ml` contains the OCaml model, reducer and action decoder; `todos.edn` contains no computation.
For example, `can-add?`, `empty?` and summary text come from the OCaml `project` function,
not expressions assembled in EDN. The projection should expose only what the view needs,
rather than serializing the entire business model.

```ocaml
Data_view.compile ~actions:["remove"] source
Data_view.render document ~model ~project ~dispatch
```

`compile` returns `(t, string) result`. `dispatch` receives an allowlisted action name,
EDN arguments and the original `Lui_protocol.event`. OCaml checks argument types,
arity and event payloads before constructing a typed action.
The allowlist controls callable names; it does not replace business authorization.

## View syntax

```edn
{:version 1
 :components
 {:entry
  [:row
   [:text-field {:text {:bind [:props :title]}}]
   [:button {:text "Remove"
             :on {:press [:remove {:bind [:props :id]}]}}]]}
 :view
 [:column {:gap 8 :padding 16}
  [:when {:bind [:model :empty?]}
   [:text {:text "Nothing here"}]]
  [:for {:items {:bind [:model :items]} :as :item :key [:id]}
   [:use :entry {:id {:bind [:item :id]}
                 :title {:bind [:item :title]}}]]]]}
```

- Elements: `[:kind {:property value ...} child ...]`. The property map is optional;
  children must be view vectors. Kinds and properties use `Lui_wire_schema` wire names,
  not OCaml constructor parameter names.
- Documents: a versioned map, or a single root view vector for fragment experiments.
  `:root` is reserved for the runtime.
- Bindings: `{:bind [:model :field]}`, `{:bind [:props :field]}` or `{:bind [:item :field]}`.
  Paths support nested maps and integer vector indices. Missing paths are errors,
  not silently converted to empty strings.
- Properties: strings, keywords, booleans, integers and finite floats. Keywords become
  wire strings; integers are promoted when the target property requires a float.
  `nil` removes a property; it does not hide an element.
- Conditions: `[:when boolean-expression child]`. No else branch or general expression
  language; OCaml projects complex conditions.
- Lists: `:items` must be a vector; `:key` is a path within each item. Keys must be unique
  strings, keywords or integers. Aliases cannot replace `:model` or `:props`.
  Nested lists can use different aliases to access outer items.
- Reuse: `[:use :component props-map]`. Values passed by the caller are available through
  `:props` inside the component. Recursive expansion is rejected.
- Events: `:on {:press :add}` or `:on {:input [:rename {:bind [:props :id]}]}`.
  Input text, checkbox values and pointer data reach OCaml through the original event,
  not an EDN payload expression. Arguments sample the current scope **when the event fires**,
  rather than capturing an item from the initial mount.
- Extensions: `:ext/<registered-name>` delegates to the existing extension registry.
  The LUI runtime ultimately validates the schema, platform capabilities, property types,
  children and event admission. The prototype has no extension registration example.

Common events include `:press`, `:input`, `:submit`, `:toggle`, `:value`, `:change` and `:dismiss`.
`event_specs` also maps existing pointer, navigation, scrolling and file-picker protocol events.
Standard kinds reject incompatible events. `:on` configures event admission flags automatically.

## Validation and applicability

| Scenario | Result and evidence | Limitations |
| --- | --- | --- |
| Forms, enablement and input events | Todo example: bound draft, OCaml validation, input / submit / press routing | IME, focus and selection have not been tested through platform interaction |
| Keyed editable lists | `check.ml`: reorder emits moves, text-field IDs survive, properties update in place, events read updated items, removal disposes nodes | Verifies the retained contract, not lossless focus across platforms |
| Conditions / empty states | Initial todo empty state disappears when the first item is added | Single branch only; hidden branches do not retain local UI state |
| Component reuse | Todo rows use `:use` / `:props`, exercising bindings and current event arguments | No slots, dynamic component names or local state |
| Split, tabs, tables, trees, slider, select, virtual-list | `scenarios.edn` passes schema validation and mounting on the generic headless backend | Representation and mounting only, not complete interaction, virtualization performance or platform parity |
| Dialogs, menus, asynchronous loading/error | OCaml can project switches, data and commands; EDN can use `:when` and standard kinds | Actual overlays, keyboard and asynchronous flows have not been tested end to end |
| Files, media, custom editors | Wire scalars / resource IDs, or preregistered extensions | OCaml / host code still owns resource lifecycles and editor state; unverified |

The EDN experiment has not been tested through a browser, iOS or native GUI.
It does not establish support for "all scenarios."

## Validation rules and remaining work

Compilation checks the document version, duplicate fields, unknown kinds / properties / actions,
literal scalars, child-kind relationships and component expansion. Model-dependent paths,
types, conditions and duplicate list keys are checked during projection.
Standard property combinations and event admission are also checked before mounting/updating;
the runtime still enforces platform validation. Errors are strings or runtime exceptions:
there are no source locations, typed binding schemas or transactional rollback guarantees.
Bindings in inactive conditions are checked only when activated; unused components are not expanded.

The interpreter's `Signal.map` / `Lui_dynamic` usage is a scope-owned runtime bridge,
not an application-authored reactive view. Applications supply only `project` / `dispatch`.
The interpreter neither calls `Lui_elements.dyn` nor takes ownership of the caller's model signal.

- No arithmetic, function calls, `eval`, closures, arbitrary OCaml function lookup or code loading.
  Do not gradually turn the format into a second programming language.
- No EDN document hot replacement or hot-reload state migration; `t` remains fixed while mounted.
- No arbitrary map/vector wire properties. Structured properties must follow the existing
  protocol encoding rather than accepting arbitrary EDN maps.
- Each model change reprojects and traverses the active view. Lists pass the full environment
  into row scopes. Measure projection, validation, key diffing and allocation costs on large
  models/lists before introducing dependency slicing.
- The 1 MiB source and 128-level view expansion limits discourage accidental misuse;
  they are not a sandbox against malicious EDN input. Do not load untrusted remote documents
  directly. Production use needs parser/AST/node budgets, permissions and error isolation.

Next, validate a real page across actual backends before deciding whether to promote this
format into a public library. Prioritize binding/action schemas, error locations and typed
OCaml projection helpers over adding an EDN computation DSL.
