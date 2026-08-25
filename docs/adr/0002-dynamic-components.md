# ADR: Dynamic components

Status: accepted

Date: 2026-08-25

## Context

LUI intentionally exposes a closed, typed standard component protocol. The
closed protocol gives every standard element the same validation, retained
identity, event semantics, accessibility contract, and backend coverage on
Web, Apple, and Flutter.

Applications still need native capabilities that do not belong in the
standard component catalog. Examples include an iOS MapKit view, a photo
picker, an application-specific media editor, and an Android Compose view.

Today a new native node kind requires changes to LUI's generated protocol,
wire decoder, retained validation, and each exhaustive backend renderer. A
custom `defelement` can compose existing nodes, but it cannot register a new
native node kind.

Applications must be able to add native components without forking LUI or
adding every application-specific type to `schema/components.json`. This
extension boundary must not weaken the standard component contract or allow
unvalidated code and data to cross the wire boundary.

Platform presentation tweaks are a separate concern and are defined by
[ADR 0003](0003-platform-tweaks.md).

## Decision

LUI will provide dynamic component registries. LUI itself will add the generic
extension component protocol once. After that, an application or library can
register additional components without modifying LUI source.

The standard component registry remains closed. Extensions live in an
application-scoped registry, use a separate wire representation, and cannot
shadow or alter a standard component.

```text
standard LUI node
    -> generated closed protocol
    -> built-in Web / SwiftUI / Flutter renderer

registered component
    -> extension schema and retained extension node
    -> application-registered platform factory
```

### Extension identities

Every extension has an application-local stable identifier such as `map`,
`map-marker`, or `video-editor`. Identifiers do not require a namespace because
each registry belongs to one application/backend instance and is not a global
package catalog.

Registration fails when:

- an identifier is already registered;
- an identifier is empty or does not use the admitted kebab-case shape;
- an extension attempts to shadow a standard element;
- the LG and host schemas have different fingerprints; or
- registration occurs after the registry is frozen.

Registries are mutable only during application startup. Creating the first
LUI application or applying the first patch batch freezes the relevant
registry. A running retained tree never changes the meaning of an extension
identifier.

### Schemas

Each component registration declares:

- its application-local identifier;
- the supported operating-system and host profiles;
- whether it accepts children and any admitted child relationships;
- its admitted properties, scalar value types, required values, and defaults;
- its admitted events and scalar payload fields; and
- a deterministic schema fingerprint.

Extension wire values are a closed set: string, boolean, integer, and finite
floating-point values. Arbitrary JSON objects, executable strings, closures,
Swift types, Dart objects, DOM objects, and platform handles do not cross the
wire boundary.

Structured collections should normally use retained extension children. For
example, a map contains keyed marker nodes rather than receiving one opaque
JSON marker array. A host-owned resource may instead be referenced by a stable
application identifier.

Both the LG runtime and the host backend validate extension operations against
the registered schema. Unknown properties, invalid values, unsupported child
relationships, and undeclared events reject the complete atomic patch batch.

### Authoring API

Libraries define typed or macro-generated wrappers around the generic
extension API. Application views do not construct raw extension operations.

```clojure
(defui places-screen [region markers on-region-change]
  (if (platform? proto/IOS)
    [:map
     {:latitude (:latitude region)
      :longitude (:longitude region)
      :latitude-delta (:latitude-delta region)
      :longitude-delta (:longitude-delta region)
      :on-region-change on-region-change}
     (map
      (fn [marker]
        [:map-marker
         {:key (:id marker)
          :id (:id marker)
          :latitude (:latitude marker)
          :longitude (:longitude marker)}])
      markers)]
    [:text "Map preview is unavailable on this platform"]))
```

An extension package may generate the `defelement`, property bindings, event
decoding, and host registration stubs from one manifest. Code generation is
encouraged to prevent the LG and host schemas from drifting, but the runtime
registry remains the authority.

### Platform availability

Unsupported platform extensions fail explicitly. They are never silently
ignored and do not automatically render as an empty view.

The author must select an extension with `platform?` or `host?` and provide a
fallback when the application can run on another backend. A library may offer
multiple host implementations under one semantic application-level wrapper,
but it must register each implementation explicitly.

An extension does not become part of LUI's cross-platform compatibility
promise merely because more than one backend registers the same identifier.
Reusable cross-platform semantics should graduate into the reviewed standard
component catalog.

### Retained component behavior

A registered component is a normal retained node with a stable LUI node
identifier. It participates in insertion, removal, moves, keys, global keys,
property patches, mount, and unmount. The host backend keeps an observable
extension node model and calls the registered factory for that component
identifier.

The Apple registration API has this shape:

```swift
let extensions = LUIAppleExtensionRegistry()

try extensions.register(LUIAppleExtension(
    identifier: "map",
    fingerprint: mapFingerprint,
    properties: mapProperties,
    events: mapEvents
) { context in AnyView(AppMapView(context: context)) })

let backend = try LUIAppleBackend(extensionRegistry: extensions)
```

The factory receives only validated properties, retained children, lifecycle
state, and an event emitter scoped to its node. It does not receive mutable
access to the retained tree or wire decoder.

The dynamic boundary may use platform type erasure such as SwiftUI `AnyView`.
Built-in components remain statically rendered and do not pay that cost.
Factories must keep their output view structure stable for a retained node;
property changes update the node model rather than replacing its identity.

### Extension events

A registered component emits only events declared by its schema:

```swift
context.emit(
    "region-change",
    values: [
        "latitude": region.center.latitude,
        "longitude": region.center.longitude,
        "latitude-delta": region.span.latitudeDelta,
        "longitude-delta": region.span.longitudeDelta,
    ]
)
```

The generic host event includes the retained node identifier, extension
identifier, event name, and validated scalar payload. The application-level LG
wrapper decodes this into a typed callback value before application code sees
it.

Transient platform state remains in the host component. A map owns gesture
recognition, camera momentum, and selection during interaction, then emits a
declared semantic event. The application model remains authoritative for
controlled state.

### Wire protocol

The wire protocol will add generic operations for:

- creating an extension component with its identifier and schema fingerprint;
- setting or removing a named extension property;
- attaching, moving, and removing retained children through the existing tree
  operations; and
- dispatching a validated extension event.

The exact encoding is versioned independently from extension identifiers.
Built-in node kinds and properties continue to use generated closed enums.
Unknown built-in wire names remain errors; they are not reinterpreted as
extensions.

Extension operations remain part of the same atomic `PatchBatch`. A host
factory is never called for a partially validated batch.

### Security and ownership

Registries contain executable host code and are therefore configured only by
the embedding application. LG application data cannot register a factory,
load a library, evaluate source strings, or select an unregistered native type.

Registration and rendering obey these rules:

- no dynamic code evaluation;
- no reflection-based construction from an arbitrary class name;
- no implicit network or file access;
- no access to another node's event emitter or mutable model;
- no mutation of the registry after freeze; and
- no silent fallback for an unknown extension.

Capabilities such as camera, location, purchases, and file access remain
subject to the host application's permission and capability boundaries. A
registered visual component does not receive those capabilities automatically.

## Consequences

### Positive

- Applications can embed native platform views without forking LUI.
- The standard protocol keeps its closed validation and generated backend
  coverage.
- Extension nodes retain identity and participate in the normal atomic patch
  lifecycle.
- Platform availability and schema mismatches fail early and visibly.

### Negative

- Extension manifests and host factories add setup work to an application.
- Dynamic host factories require type erasure at the extension boundary.
- Extension schemas duplicate some concepts from the standard component
  schema and require fingerprinting and code-generation support.
- Application extensions do not receive automatic cross-platform parity,
  accessibility, or simulator coverage.
- A generic extension event is less statically precise inside LUI core; typed
  wrappers must restore precision at the application boundary.

## Rejected alternatives

### Add every native component to LUI

Rejected because application-specific components would continuously expand the
standard protocol and require irrelevant implementations on every backend.

### Let `defelement` create arbitrary native kinds

Rejected because `defelement` is an authoring macro, not a host registration,
wire validation, lifecycle, or renderer mechanism.

### Silently ignore unsupported extensions

Rejected because the preview would diverge from the native application and a
missing interactive component could become an invisible functional failure.

### Use one unvalidated JSON payload per extension node

Rejected because it bypasses closed property validation, produces coarse
updates, hides schema drift, and makes retained child identity impossible for
structured collections.

## Delivery sequence

1. Define extension identifiers, scalar values, schemas, fingerprints, and
   frozen registry behavior in LG.
2. Add generic retained extension component nodes.
3. Extend atomic patch and event encoding with independently validated
   extension operations.
4. Add an Apple component registry with a stable `AnyView` boundary.
5. Implement an application-owned MapKit example without adding its identifier
   to `schema/components.json`.
6. Add Web and Flutter registry interfaces with the same lifecycle and
   validation rules.
7. Add macro-generated typed LG wrappers. Host registrations stay explicit so
   native factories remain ordinary Swift, Dart, or Web code.

## Implementation status

Implemented on 2026-08-25 for the LG runtime and retained Web, SwiftUI, and
Flutter backends. The component Gallery exercises an application-owned MapKit
extension on Apple hosts and a native retained card on Web and Flutter without
adding either identifier to the standard generated component schema.

## Acceptance criteria

- An application registers and renders a MapKit-backed component without
  editing generated LUI component schemas or backend switches.
- Unknown identifiers, schema fingerprint mismatches, invalid properties,
  invalid child relationships, and undeclared events reject the atomic batch.
- Registries cannot change after the application starts.
- Built-in component behavior and wire decoding remain unchanged.
- Unsupported platform use fails unless the author selects an explicit
  fallback subtree.
- Extension property changes preserve the host component and child identities.
