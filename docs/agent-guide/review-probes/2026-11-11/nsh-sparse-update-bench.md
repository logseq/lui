# NSH sparse Store update qualification

## Status and scope

The executable is `platform/nsh/examples/sparse_update_bench.rs`. Three native
release runs completed on the reference machine. All identity and touched-set
assertions passed in every warmup and measured iteration.

This probe measures the Rust adapter's public wire decoder, generated canonical
final-node validator, and transactional retained Store. It does not initialize
the renderer or an NSH engine. Binding publication, host-specific validation,
NSH commit/layout, operating-system views, frame timing, application callbacks,
and OCaml-to-Rust transport are outside its scope. Passing this probe alone does
not satisfy the complete Stage 8 performance qualification.

## Reference machine

Named reference: **LUI-NSH-M6-24GiB**.

| Item | Observed value |
| --- | --- |
| Model identifier | Mac18,5 |
| Processor | Apple M6, 12 logical CPUs |
| Physical memory | 25,769,803,776 bytes (24 GiB) |
| Operating system | macOS 27.2, build 26B123 |
| Rust | rustc 1.97.0 (2d8144b78 2026-07-07) |
| Target | aarch64 macOS |
| NSH dependency | logseq/nsh `028574b7de9ee25a7c6f60660ef72fcb8790a27e` |
| LUI starting revision | `d6e9551266f73d5b9292d0eb92e82984c301e5db`, with the migration working tree |

The machine details were read with `sysctl`, `sw_vers`, and `rustc --version`.
No other Cargo build ran during measurement. Normal desktop CPU activity was
observed before the run; this was not an isolated idle machine. The results
therefore include host noise and do not replace the plan's idle reference-machine
qualification. This is a local reference measurement, not a cross-platform result.

## Workload and method

The probe creates each fixture once through `Store::apply_snapshot`: one column
root and enough text children to retain exactly 1,000 or 100,000 nodes. It then
uses the same text properties and node IDs in both sizes. One case changes one
label; the other changes 100 distinct labels in one batch. Values alternate
between two equal-length strings so every sample performs an actual update.
Only the sequential batch generation changes. The default run uses 200 warmup
iterations and 2,000 measured iterations for each case.

Each sample constructs and serializes a fresh ordinary property batch, and
prepares the touched final-node validator inputs, before starting any timer.
It does not cache decoded batches or perform fixture-sized work within a
sample. `std::hint::black_box` retains the measured public calls. Assertions
and percentile calculation are outside the timers. No timing assertion is
used in CI.

| Stage | Timed public operation |
| --- | --- |
| `decode` | `Batch::decode` on the serialized property batch, including JSON allocations |
| `standalone_final_validation` | `contract::validate_node` on the prepared final touched nodes |
| `transaction_including_validation` | `Store::apply`, including scalar validation, final-node validation, touched-node cloning and map commit |

The standalone validator measurement overlaps validation performed inside
`Store::apply`. These are diagnostic measurements, not additive pipeline
segments. Their sum is not an end-to-end latency. Transaction timing excludes
renderer binding publication and host-specific final-node constraints.

Every warmup and measured iteration checks that `Changes.updated` is exactly
the requested set, no nodes are removed, the root and an unrelated leaf keep
their original `Arc<Node>`, the root's large child vector keeps its original
`Arc`, and changed leaves retain their child-vector identity and incarnation.
These fixed witnesses and bounded touched-node assertions detect accidental
reconstruction; they do not independently prove the absence of a full-map scan.
The implementation should also be reviewed for such scans. The benchmark
performs no complete-map scan within a timed sample or its assertions.

## Reproduction

From `platform/nsh`, with no heavy build running concurrently:

```sh
CARGO_BUILD_JOBS=2 CARGO_PROFILE_RELEASE_STRIP=none \
  cargo run --release --locked --example sparse_update_bench -- \
  --reference LUI-NSH-M6-24GiB --warmup 200 --samples 2000
```

The executable rejects debug builds. Output includes sample counts and
nearest-rank median, p95, and p99 in microseconds for all twelve combinations
of retained count, operation count, and stage. Preserve the raw output with the
measurement evidence when populating the result table.

## Results

Each table entry is **median / p95 / p99 in microseconds**. Each run contributes
2,000 measured samples per row, after 200 warmup samples. Run 1 follows the
release build; runs 2 and 3 launch the same executable again. No run was
removed. Stage percentiles overlap as explained above and must not be added.

| Nodes | Operations | Stage | Run 1 | Run 2 | Run 3 |
| --- | --- | --- | --- | --- | --- |
| 1,000 | 1 | Decode | 0.500 / 0.667 / 0.708 | 0.208 / 0.250 / 0.250 | 0.291 / 0.333 / 0.375 |
| 1,000 | 1 | Standalone final validation | 1.041 / 1.333 / 1.375 | 0.458 / 0.500 / 0.542 | 0.583 / 0.666 / 0.750 |
| 1,000 | 1 | Transaction, including validation | 1.625 / 2.042 / 2.084 | 0.667 / 0.750 / 0.833 | 0.875 / 1.000 / 1.166 |
| 100,000 | 1 | Decode | 0.167 / 0.167 / 0.208 | 0.166 / 0.167 / 0.250 | 0.166 / 0.167 / 0.208 |
| 100,000 | 1 | Standalone final validation | 0.333 / 0.375 / 0.375 | 0.333 / 0.334 / 0.417 | 0.333 / 0.334 / 0.375 |
| 100,000 | 1 | Transaction, including validation | 0.500 / 0.542 / 0.583 | 0.500 / 0.542 / 0.625 | 0.500 / 0.542 / 0.583 |
| 1,000 | 100 | Decode | 11.291 / 11.625 / 12.333 | 11.167 / 11.583 / 12.500 | 11.167 / 12.000 / 15.584 |
| 1,000 | 100 | Standalone final validation | 32.833 / 34.084 / 40.333 | 32.292 / 33.500 / 37.625 | 32.709 / 39.334 / 49.959 |
| 1,000 | 100 | Transaction, including validation | 50.375 / 52.250 / 58.625 | 50.125 / 51.750 / 58.458 | 50.750 / 59.542 / 80.084 |
| 100,000 | 100 | Decode | 11.250 / 11.584 / 12.417 | 11.125 / 11.500 / 11.750 | 11.167 / 11.708 / 16.916 |
| 100,000 | 100 | Standalone final validation | 33.375 / 33.958 / 38.208 | 33.208 / 34.166 / 38.000 | 33.041 / 34.667 / 42.792 |
| 100,000 | 100 | Transaction, including validation | 51.584 / 52.584 / 60.625 | 51.583 / 52.875 / 59.291 | 51.583 / 56.417 / 74.000 |

The following ratios divide each 100,000-node median by its corresponding
1,000-node median in the same run:

| Operations | Stage | Run 1 ratio | Run 2 ratio | Run 3 ratio |
| --- | --- | --- | --- | --- |
| 1 | Decode | 0.334 | 0.798 | 0.570 |
| 1 | Standalone final validation | 0.320 | 0.727 | 0.571 |
| 1 | Transaction, including validation | 0.308 | 0.750 | 0.571 |
| 100 | Decode | 0.996 | 0.996 | 1.000 |
| 100 | Standalone final validation | 1.017 | 1.028 | 1.010 |
| 100 | Transaction, including validation | 1.024 | 1.029 | 1.016 |

For the 100-operation case, transaction medians range from 50.125 to 51.584 µs
and p95 from 51.750 to 59.542 µs. Within-run transaction median growth is
1.6–2.9%; standalone validation growth is 1.0–2.8%; decode is essentially
unchanged. These measurements do not show the plan's greater-than-20% growth
trigger for this fixed hot subset.

The one-operation 1,000-node case varies substantially between process runs:
transaction median is 1.625, 0.667, and 0.875 µs, while the 100,000-node median
is 0.500 µs each time. The cases run in a fixed order, and building a large
fixture also exercises the CPU before measuring it. Host scheduling, frequency
and startup effects are possible explanations; this probe does not isolate
the cause. The ratios below one must not be interpreted as a performance gain
from retaining more nodes. The current one-operation timings are not a reliable
estimate of the retention-size effect.

The workload repeatedly updates the first one or 100 leaves. It describes a
hot fixed subset, not random access across all retained nodes. Source review
of `Store::apply_inspected`, `Transaction::edit` and `Transaction::validate`
shows a bounded touched-node map and final validation over touched nodes;
ordinary property updates perform BTreeMap lookups rather than a complete
retained-map scan. Lookup cost can still depend on retained count. The Arc
assertions additionally verify that the root's large child vector and fixed
unrelated node witnesses survive without reconstruction.

## Build identity and remaining qualification

The successful command used the public application manifest and its unchanged
locked Git dependency on `028574b7de9ee25a7c6f60660ef72fcb8790a27e`. An initial
attempt to select this example through the CLI-generated workspace was rejected
because LUI is not a workspace member; no generated-workspace measurement is
reported. The application lock file was unchanged before and after execution.
The release build took 1 minute 50 seconds; timings begin only after compilation.
`CARGO_PROFILE_RELEASE_STRIP=none` preserves the qualified macOS packaging
configuration; no architecture cross-compilation flag was used.

SHA-256 identifiers at measurement:

| Input | SHA-256 |
| --- | --- |
| `platform/nsh/Cargo.lock` | `602d68ce05d82a95d05bb219ebb09fe626a0483f27d99627161dadddd78c649f` |
| `platform/nsh/src/store.rs` | `9f7cdbdc822740ce1610eb59f77bc35be889ba792f71843cb67174761d7e29a1` |
| `platform/nsh/src/wire.rs` | `612218e3a7e92946ea50f021bd01085efc2602daa52afae66a2b18bb744cbec0` |
| `platform/nsh/src/contract.rs` | `6df93259771d313fc03c856867538d893704e28896b87d307476247b2def72f6` |
| `platform/nsh/src/contract_generated.rs` | `6e9e5ba2263a4cc6a7ec30756493b3ea3420ecde8af91f180afd482067dc67f3` |
| `platform/nsh/examples/sparse_update_bench.rs` | `56ec714b08c0a2ebee9a2647c5aa31993d230c17de33333f38d7d8800e88c154` |
| Release executable | `5bf1f74d22cd9fa0e218b4fd218af20d0b9e8905ea2512c653b286332aa7f567` |

Raw local captures are `/tmp/lui-nsh-sparse-update-release.log`,
`/tmp/lui-nsh-sparse-update-repeat2.csv`, and
`/tmp/lui-nsh-sparse-update-repeat3.csv`; every timing row is reproduced above.

No cache or production hot-path instrumentation was added. Standalone Store
latency is not the complete adapter decode/validate/publish target, even though
its measured p95 is below 2 ms. The baseline revision predates this NSH adapter,
so this probe is not a baseline-backend comparison.

Separate evidence is still required for binding counts and publication,
NSH/native commit and layout, actual event-to-visible latency and frame times,
idle wakeups, memory/owner retention, and other operating systems.
