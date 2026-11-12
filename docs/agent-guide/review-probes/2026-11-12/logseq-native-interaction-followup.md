# Logseq native interaction follow-up

Date: 2026-11-12

## Source checkpoint

LUI production source: `f5d8613a`; the strict-Clippy follow-up only collapses
a nested conditional in the native split test. NSH is pinned to
`2635333e4cc0d3be8032c97f3a5e08d3685179c6`.
Actual Logseq worktree: `feat/nsh-host`, source through `540b06e771`.
The Rust run predates the subsequent OCaml-only click-policy change; its exact
Rust source is the same as the later checkpoint. The two compiled OCaml runners
use the release native archives rebuilt after `8433558ad0`.

## Verified checks

- Actual Logseq release Rust library suite: **46 passed**, none ignored. Includes
  real CoreText committed-layout and wrapped-hidden-markup partition tests,
  retained native editor input/selection protocol, raw pointer event ordering,
  deferred focus, clipboard request contracts and application services.
- Actual native OCaml admission runner: **passed**, including shared block-click
  editor entry and focus request, rapid NSH same/different-target clicks, retained
  Apple coalescing, delegated persisted links, worker/save/abort/timer races.
- Production native virtual-row runner: **passed** for 1k/100k source rows and
  complete generated Emoji/icon datasets. Counts actual mounted picker controls,
  checks overlapping identity, canonical row interaction pins, last-item selection
  and bounded mount counts. The fixture now sends the direct canonical row owner
  that the native host actually pins, rather than a nested grid.
- Packaged native-readiness Python fixtures: **7 passed**. Reject missing,
  nonintersecting, hidden, transparent and incomplete native Journal evidence.
- LUI strict all-target Clippy: **passed**, with `-D warnings`.
- LUI generated support inventory freshness: **passed**.

Commands, from the appropriate repository root (Rust uses toolchain 1.97.0,
`CARGO_BUILD_JOBS=2`, and existing target directories):

```sh
cargo test --release --locked --manifest-path deps/ui/nsh/Cargo.toml --lib
OCAMLPATH=/Users/tienson/Codes/projects/lui/_build/install/default/lib \
  python3 deps/ui/nsh/run_update_preparation_native.py
OCAMLPATH=/Users/tienson/Codes/projects/lui/_build/install/default/lib \
  python3 deps/ui/nsh/run_virtual_rows_native.py \
  --ppx deps/ui/_build/default/.ppx/4b25d097aea985e97f176eaf0c4d964e/ppx.exe
python3 -m unittest discover -s deps/ui/nsh -p test_packaged_background.py
cargo clippy --locked --manifest-path platform/nsh/Cargo.toml --all-targets -- -D warnings
python3 tooling/nsh_support_inventory.py --check
```

The explicit PPX path names an existing local build artifact; the runner also
supports the installed `lui.ppx` package on other machines. No Dune file changed.

## Evidence hashes

| Local log | SHA-256 |
| --- | --- |
| `/tmp/logseq-nsh-combined-lib-current.log` | `192cfb8b1177060572886630d855acdc170d7890007c77bad23628cb8fa82a0d` |
| `/tmp/logseq-nsh-native-admission-current.log` | `98617884da9acf95a7bbe44d7077ee73bbd0afd3f74cfc4dcf04e72c229b91b2` |
| `/tmp/logseq-nsh-virtual-rows-current.log` | `219d408f31fb8f91ac434266e400360967544945ce66ff1a7d35404146229a1a` |
| `/tmp/lui-nsh-clippy-current.log` | `7c0af9a00516c161ba3dd6d60c201e6be734594515e9cde7785c308556465008` |

## Limits and next gates

These are retained-runtime, headless engine and native text-layout checks; they
are not real macOS pointer/keyboard/IME or pixel-parity qualification. Headless
Input does not implement selected-range typing: the selection regression observes
the actual native `SetSelection` command and sends its corresponding replacement.
The actual release startup click/type gate remains required.

The visible app previously failed on externally anchored menu popovers. Native
trigger-owned menu migration and its actual opening regression are still pending
at this checkpoint. Soft-wrap caret affinity, structured outline clipboard
semantics, full visible UI/UX review, Windows/Linux execution and final
signing/package/update acceptance remain open. Do not infer migration completion
from these test results.
