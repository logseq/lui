# ADR: Platform tweaks

Status: accepted

Date: 2026-08-25

## Context

Applications need platform-only presentation changes that do not belong in
LUI's standard cross-platform component attributes. Examples include a
SwiftUI `ViewModifier`, an Android modifier, and an application-owned Web
style recipe.

Applying a modifier to `LUISwiftUIRoot` already works at the application-shell
boundary, but there is no supported way to apply an application-owned modifier
to one retained LUI node. SwiftUI modifiers are generic Swift code and are
order-sensitive. They cannot be serialized as source strings or unordered
property maps.

Dynamic native components are a separate concern and are defined by
[ADR 0002](0002-dynamic-components.md). Platform tweaks reuse its
application-scoped registry, schema, fingerprint, freeze, scalar value, and
atomic validation rules.

## Decision

LUI will support registered platform tweaks in node attributes. A platform
tweak is a named application-owned presentation recipe. The public authoring
API is an ordered vector under a reserved operating-system key such as `:ios`.

```clojure
[:button
 {:on-press save
  :ios [:glass-primary
        [:outer-shadow {:radius 8}]]}
 "Save"]
```

The authoring form lowers to transparent retained decorator nodes. Callers do
not write those nodes directly.

```text
node platform attributes
    -> authoring macro lowering
    -> retained tweak decorators
    -> application-registered platform modifier factory
```

### Tweak identities and registration

Every tweak has an application-local kebab-case identifier such as
`glass-primary` or `outer-shadow`. Identifiers do not require a namespace.

A tweak uses the registry lifecycle defined by ADR 0002:

- duplicate or invalid identifiers fail registration;
- a tweak cannot shadow a standard component or registered component;
- LG and host schemas must have the same fingerprint; and
- the registry is immutable after the application starts.

Each tweak schema declares its admitted properties, scalar value types,
required values, defaults, and supported operating-system and host profiles.
A tweak does not declare application events or independent children.

The Apple host registration API has this shape:

```swift
try extensions.registerTweak(LUIAppleTweak(
    identifier: "glass-primary",
    fingerprint: glassPrimaryFingerprint,
    properties: glassPrimaryProperties
) { content, context in
    let prominent = context.property("prominent") == .bool(true)
    return AnyView(
        content
            .buttonStyle(.glassProminent)
            .glassEffect()
            .controlSize(prominent ? .large : .regular)
    )
})
```

The registry contains executable host code and is configured only by the
embedding application. LG data cannot register a factory, name an arbitrary
Swift type, or evaluate a modifier expression.

### Authoring grammar

The initial reserved platform keys are `:ios`, `:macos`, `:android`, and
`:web`. These keys are authoring metadata, not standard component properties,
and are removed before standard component schema validation.

The value of a platform key is an ordered vector of tweak specifications:

```text
tweak-spec = :name | [:name {...properties}]
```

Examples:

```clojure
[:button
 {:ios [:glass-primary]
  :android [:material-primary]
  :on-press save}
 "Save"]

[:panel
 {:ios [[:glass-card {:prominent true}]
        [:outer-shadow {:radius 12}]]}
 content]
```

The tweak vector and each tweak specification are compile-time authoring
structure. Property values inside a tweak property map may be literals,
Signals, or other supported binding expressions.

Keyword names are encoded as application-local registry identifiers, so
`:glass-primary` resolves to the registered `"glass-primary"` tweak.

### Platform selection

Only the vector for the current operating-system profile is lowered. A
non-matching platform key is intentionally inactive and produces no retained
tweak node. This is not the same as silently ignoring a selected tweak.

When a key matches the current platform:

- every named tweak must be registered;
- its schema fingerprint must match;
- its host profile must be supported; and
- every property must pass schema validation.

Any failure rejects the complete atomic patch batch.

### Modifier order

Vector order defines modifier application order and matches a native modifier
chain. The first tweak is applied first and the second tweak is applied to its
result:

```clojure
{:ios [:glass-primary
       [:outer-shadow {:radius 8}]]}
```

```swift
content
    .modifier(GlassPrimary())
    .modifier(OuterShadow(radius: 8))
```

Duplicate tweak identifiers are allowed in one vector because modifier
composition may intentionally apply the same recipe more than once with
different properties.

### Internal lowering

The authoring macro lowers a tweak vector to retained decorator nodes in
reverse nesting order. The previous example becomes conceptually:

```clojure
[:lui.internal/platform-tweak {:name "outer-shadow" :radius 8}
 [:lui.internal/platform-tweak {:name "glass-primary"}
  [:button {:on-press save} "Save"]]]
```

The internal form is not public authoring API. Each decorator:

- has one and only one child;
- has retained identity and reactive property patches;
- participates in the same atomic patch validation as other extension nodes;
- is transparent to layout and application semantics; and
- passes its fully rendered child through the registered host factory.

The wire protocol reuses ADR 0002's generic extension creation and property
operations with a distinct `lui-tweak-v1` schema fingerprint. The registry
marks the identifier as a tweak and enforces its single-child contract on both
sides of the wire. It never serializes Swift, Kotlin, Dart, JavaScript,
closures, or platform objects.

### Placement relative to standard modifiers

Platform tweaks wrap the fully rendered standard node, including its built-in
surface and accessibility modifiers. They therefore run after standard LUI
attributes.

For example:

```clojure
[:panel
 {:padding 16
  :ios [:glass-card]}
 content]
```

first applies LUI's standard padding and surface behavior, then applies the
registered `glass-card` recipe to the result.

A capability that must participate inside a standard component's
implementation is a dynamic component or a reviewed standard component, not a
platform tweak.

### Scope

Platform tweaks are restricted to presentation and platform integration that
does not create an independent semantic component. A tweak must not replace
LUI event handlers, change controlled-state ownership, remove accessibility
meaning, or emit application events.

Appropriate tweaks include:

- SwiftUI visual `ViewModifier` recipes;
- native button, list-row, or control styles;
- platform-only effects, margins, backgrounds, and transitions; and
- application design-system recipes.

The following require another boundary:

- stateful controls and native views use ADR 0002 dynamic components;
- gestures with application events use typed LUI events or a dynamic
  component;
- navigation, dialogs, and sheets use standard semantic components or the
  application shell; and
- lifecycle effects remain in LG lifecycle APIs.

### Application-shell customization

The tweak registry does not replace normal host composition. Platform chrome
that wraps an entire LUI root remains application-owned:

```swift
TabView {
    LUISwiftUIRoot(backend: backend, rootID: homeRootID)
    LUISwiftUIRoot(backend: backend, rootID: settingsRootID)
}
.toolbar { AppToolbar() }
```

Bottom bars, root navigation containers, window chrome, whole-screen
environment modifiers, and modifiers already expressible around
`LUISwiftUIRoot` should stay in the application shell.

## Consequences

### Positive

- Callers express platform tweaks next to ordinary node attributes.
- Ordered vectors preserve native modifier composition without public nested
  decorator syntax.
- Applications can use their native design systems without expanding LUI's
  standard component vocabulary.
- Reactive tweak properties retain identity and use atomic patch validation.
- Non-matching platform tweaks do not leak into another backend.

### Negative

- Reserved platform keys add authoring-macro complexity.
- Dynamic factories require platform type erasure at the tweak boundary.
- Tweak schemas and factories add application setup work.
- Tweaks are not automatically portable or covered by LUI's cross-platform
  parity guarantee.
- All tweaks run outside standard node modifiers; arbitrary interleaving is
  intentionally unsupported.

## Rejected alternatives

### Require callers to nest decorator elements

Rejected as public API because modifier chains become noisy and obscure the
semantic component tree. Decorator nodes remain the normalized internal form.

### Serialize SwiftUI modifier expressions

Rejected because source strings and closures are not portable data, cannot be
validated safely, and would require dynamic code evaluation.

### Use an unordered modifier map

Rejected because SwiftUI and other platform modifier systems are
order-sensitive and may apply the same modifier more than once.

### Treat Web `class` as a universal native style name

Rejected because CSS classes have Web-specific cascade and composition
semantics. Native modifier ordering and availability require an explicit
platform tweak contract.

### Silently ignore an unknown selected tweak

Rejected because previews would diverge from native applications and missing
presentation or interaction affordances could become invisible failures.

## Delivery sequence

1. Add tweak schemas and factories to the application-scoped extension
   registries from ADR 0002.
2. Reserve and parse `:ios`, `:macos`, `:android`, and `:web` node attributes.
3. Lower selected tweak vectors to internal retained decorator nodes.
4. Extend atomic patch validation and wire encoding for tweak decorators.
5. Add Apple tweak rendering with a stable `AnyView` boundary.
6. Add Web and Flutter tweak factories with the same ordering and validation
   rules.
7. Add examples for ordered tweaks, reactive tweak properties, inactive
   platform keys, and application-shell alternatives.

## Implementation status

Implemented on 2026-08-25 in the LG authoring/runtime layer and retained Web,
SwiftUI, and Flutter hosts. The component Gallery applies one shared
`gallery-accent` declaration to a paragraph; each host registers its own
presentation factory. The decorator remains a retained node and the Gallery
still mounts one component page at a time.

## Acceptance criteria

- An application registers a SwiftUI modifier recipe without modifying LUI's
  generated component schema or backend switch.
- A caller applies ordered tweaks with `:ios [...]` node attributes.
- Vector order matches native modifier order, including duplicate recipes.
- Non-matching platform keys create no tweak nodes.
- Unknown selected tweaks, schema mismatches, invalid properties, and invalid
  child counts reject the atomic batch.
- Reactive tweak property changes preserve the component and decorator
  identities.
- Built-in component behavior and wire decoding remain unchanged.
- Root modifiers and bottom bars remain possible in the application shell
  without tweak registration.
