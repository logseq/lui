# Fractional geometry implementation and qualification

Source candidate based on `12c5ef7f6e1d61dc4d16b004d24249c7c48ecc40`.
The scope is Height, MaxWidth and MaxHeight only. It excludes rem spacing,
fractional Width/minimum dimensions, a CSS parser and a general length algebra.

## Implementation

The existing constructor integer labels and wire enums/names remain unchanged.
Point/signal aliases flow through `apply_universal` into the same property.
Constructor ownership rejects competing integer/point sources before mounting.
The existing nesting PPX resolves known constructors and traces bounded aliases
for explicit conflicts and invalid point literals; opaque values are checked
at their dynamic boundary. Canonical geometry compares integer pairs exactly
and mixed pairs without rounding large integers into float equality.

Generated typed metadata adds ViewNumber only where the new three aliases
overlap their old integer labels. The data-view scalar and binding checks
accept that numeric union without broadening ViewInt/ViewFloat elsewhere.
Generated JSON explicitly decodes these three dimensions, rejects wrong scalar
types and duplicate aliases, and preserves whole canonical numbers as IntValue.

Web CSS setters, popup height limits, split bounds and virtual height estimates
read the admitted floats. The unused `media_size` helper is untouched. Apple
keeps the old Int accessors/state types, adds internal numeric accessors, and
uses them in ordinary/image/control frames, sheet/alert geometry, touch-target
floors, max bounds and resizable clamps. Android uses numeric dp conversion in
chrome and its sheet body. Every backend's complete-size validation admits and
compares the new numeric fields. NSH's existing numeric StyleValue lowering is
retained; its handwritten surface-bound comparison is updated alongside the
canonical source used by generated value validation.

An existing node's integer-to-float update is an ordinary same-property change.
No remove/re-add, node remount, alternate renderer or unit-owner cache is added.

## Source generation and required root qualification

Only these pure source generators were run:

```sh
python3 tools/gen_json_view.py
node tooling/generate_component_schema.mjs
```

No compiler, tests, runtime, SDK build, app launch or publication was run here.
The normal NSH exporter invokes Dune and ocamlopt, so its outputs deliberately
remain unchanged under the source-only restriction. Do not publish this source
candidate until the root runs the exporter and commits its actual contract,
validator and oracle output. Do not hand-edit fingerprints or oracle verdicts.

From the LUI worktree root, using the qualified toolchain and serialized build
ownership, run:

```sh
python3 tooling/generate_nsh_contract.py
python3 tooling/generate_nsh_contract.py --check
node tooling/generate_component_schema.mjs --check
opam exec --switch=5.5.1 -- dune build @runtest -j 1
node --test --test-concurrency=1 tooling/test/ppx-hygiene.test.mjs tooling/test/component_schema_test.mjs
opam exec --switch=5.5.1 -- dune build @web
node --test platform/web/test/image-sizing.test.mjs
swift test --no-parallel --filter LUIFractionalGeometryTests
cargo test --locked --manifest-path platform/nsh/Cargo.toml --lib fractional_image_geometry_is_exact_and_updates_without_native_remount
```

Run the maintained Apple package suite and iOS build-for-testing gate:

```sh
make test-apple
xcodebuild -scheme LUI-Package -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/lui-fractional-ios build-for-testing
```

Run Android's actual
Compose target from `platform/android`:

```sh
./gradlew --no-daemon :lui:testDebugUnitTest --tests dev.lui.LuiEditorVirtualTuningTest
```

The authored checks cover 63.25 dimensions, retained fractional updates and
integer-to-float replacement, finite/negative/range rejection, exact mixed
bounds, JSON aliases and malformed scalar values, and PPX failure/positive
cases. SwiftUI, Compose and NSH tests reach actual layout; the Web test reaches
the real property/store/image lowering with a recording DOM. Device-scale
pixel conversion is expected on Android; source dp fractions must survive to
that final conversion. App thumbnail and fractional viewport-resize UX still
require the downstream App build after the qualified immutable runtime update.


## Independent review followup

The original source candidate `f6032296cb660aeb5ac8402a95e8404c8ecb5eb7`
remains immutable. Independent review found Accordion's existing
`accordion_height` writer could override the new floating Height after
`apply_universal`, or race its point signal. The followup includes that existing
integer alias in pre-mount, PPX and generated JSON conflict admission. Static,
optional-forwarded, reactive and dynamic/JSON cases reject the competing owners;
positive integer-only Accordion calls remain valid.

The new FloatValue admission for Height/MaxWidth/MaxHeight and all point aliases
now shares one portable finite float32 range on every backend profile. Its
maximum is `3.4028234663852886e38`. The original source's target-dependent
runtime guard is removed; canonical admission now rejects oversized new float
fields everywhere. This changes no previously valid integer call or unrelated
float field. Finite `1e40` negative cases cover PPX, constructor, initial signals,
JSON and canonical dynamic admission, without target-environment probing or a
new cache. Apple and Android validators enforce the same cap; the NSH generated
validator must still be regenerated by the root's normal exporter.

The NSH geometry scenario uses the existing public `Headless.wait_until` after
its update. Its exact condition requires both height 64.125 and the previous
native node ID before the final assertions. This waits for committed layout;
it adds no sleep, retry loop or relaxed expectation. These followup tests are
authored source only. No compiler, test or runtime was run in either source
worktree, and no contract hashes or oracle verdicts were fabricated.
