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

## Reactive test placement correction

The root's first compile reported that `test/test_lui.ml` is not preprocessed
by the LUI PPX. Its reactive syntax therefore produced a signal where a float
was expected. The followup keeps that target's constructor/wire/identity checks
static, using ordinary runtime property updates for retained wire changes.
The real reactive update, Accordion signal conflict and invalid initial signal
cases move to an executable program in the existing PPX-enabled hygiene
fixture. It runs the five backend profiles through `Lui_app` and authored
`reactive` props, without manual signal mapping, direct signal-label plumbing,
example-app exports or a Dune change. This relocation is source-only; the root
must rerun the core suite and the PPX fixture before recording a pass.


## Static crossbounds and canonical JSON null followup

The existing constructor tracer now diagnoses a known invalid minimum/fixed/
maximum ordering whenever a new point alias participates. It resolves numeric
literals, transparent local and constructor aliases, `Some`/optional forwarding
and constant reactive projections using the same bounded lexical ownership
analysis. Reactive projection parameters shadow outer bindings, so an outer
negative or below-minimum variable cannot be misread as a dynamic parameter's
constant value. Integer comparisons remain exact above float precision; mixed
comparisons truncate only a finite, representable float. Unknown dynamic
arguments remain admitted to existing runtime boundary validation. Accordion's
final integer Height writer and icon's point-size fallback follow the actual
constructor precedence. Equal bounds and opaque dynamic sources are positive
compile fixtures; minimum violations, maximum violations and precision-boundary
violations are negative fixtures in the maintained PPX harness.

The original generated dimension decoder rejected canonical JSON `null` even
though the pre-alias `v_int` decoder treated it as omission. This followup
restores omission for exactly `height`, `max-width` and `max-height`, before
alias ownership checks. Thus canonical null may coexist with a numeric new
point alias. New `*-points:null` remains invalid, and the existing restrictive
kind validator still sees the original raw property: tooltip/file-picker
canonical-null dimensions continue to reject. Constructor, mounted JSON and
unsupported-kind regressions cover the concrete compatibility cases.

The root's compiler also found warning 5 in six newly added core rejection
fixtures because an unmounted view is a function. Those fixtures now bind the
view with the existing `let _view = ... in ()` idiom instead of passing it to
`ignore`. The portable-range diagnostic assertion accepts compiler line wraps;
it continues to require the actual PPX rejection. This followup is source-only;
no compiler, test, native runtime or compiled contract exporter was run here.
The root must rerun `@runtest`, the PPX hygiene harness and schema/contract checks
before recording qualification.

## Local qualification of the integrated candidate

The integrated implementation is `6d80dc6d`, based on the qualified desktop
runtime `12c5ef7f`. NSH remains pinned to
`adc186db7213f3ccd1eacaa836cc721e9779fd14`; this candidate changes no SDK source.
The following local results are separate from downstream App acceptance and
cross-platform CI:

- `@runtest -j1` with strict successful-action stderr passed, including all
  263 cases in the main suite. The revised static constructor, dynamic JSON,
  retained wire update and canonical null cases executed.
- All 44 tooling tests passed, including executable reactive fixtures,
  compile-failure cases, constructor/schema checks and exhaustive nesting
  properties. Normal compiler-driven contract generation and both generated
  contract/schema checks passed; no oracle verdicts were edited by hand.
- `make test-nsh` passed: 45 Python checks, strict all-target Clippy, all
  315 Rust library cases, every native OCaml integration target and compile-fail
  documentation tests. The sparse virtual/replacement fixtures ran as part of
  this command. These are regression checks, not downstream performance claims.
- The Web target built and all nine image-sizing tests passed. Android's
  `LuiEditorVirtualTuningTest` ran four tests with no failures or skips.
- Three focused Swift fractional geometry tests passed. The generic iOS
  Simulator `build-for-testing` succeeded for its maintained package/test
  targets; this is compilation evidence, not simulator execution.

The initial checks exposed and corrected real fixture/compiler problems rather
than suppressing them. The core test target does not enable LUI PPX, so reactive
checks moved to its existing executable PPX harness. Swift's ambiguous numeric
initializer references became explicit conversions. SwiftUI logical frame size
is measured with ImageRenderer before native hosting intrinsic pixel rounding.
NSH's public engine rounds committed frames to the device pixel grid; native
tests now verify the exact 1x/2x/4x outputs and exact fractional retention at 8x,
with the same native node retained throughout.

Complete Rust oracle tests also exposed default serde_json floating parsing
moving the float32 maximum one float64 step above the admitted range. The JSON
fixture itself was already exact. The candidate enables the library's existing
`float_roundtrip` feature, matching the production OCaml encoder, and tests
both the exact maximum and its immediately larger decimal. No validation range
was widened, exporter serializer added or dependency version changed.

Logs are `/tmp/lui-fractional-runtest-bounds.log`,
`/tmp/lui-fractional-tooling-full.log`, `/tmp/lui-fractional-nsh-complete.log`,
`/tmp/lui-fractional-web-build.log`, `/tmp/lui-fractional-web-image.log`,
`/tmp/lui-fractional-android.log`, `/tmp/lui-fractional-swift-layout.log` and
`/tmp/lui-fractional-ios-build.log`. Earlier failed logs remain separate.
Full Apple regression execution, actual Linux/Windows CI, downstream App
fractional layout/resize UX and packaging remain required before claiming the
complete migration qualified. This candidate has not replaced the installed
App or advanced its pinned runtime.
