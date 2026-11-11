# CI package-download DNS failures at 21b56f98

Source commit: `21b56f98ddb8695cd3aa2e5a4e915f9f5196ad83`.
Evidence: GitHub job logs and the NSH workflow job-status API, fetched on
2026-11-11 at approximately 15:51 UTC. No local build or test was run for this
read-only triage, and no source or CI configuration was changed.

## Failed and cancelled jobs

| Workflow/job | Terminal evidence | What did not run |
| --- | --- | --- |
| [NSH: Linux OCaml integration](https://github.com/logseq/lui/actions/runs/43040812514/job/130591792403) | `setup-lui-ocaml`/`ocaml/setup-ocaml` apt downloads repeatedly report `Temporary failure resolving 'azure.archive.ubuntu.com'`; `/usr/bin/sudo` exits 100 at 15:26:28 UTC | Compiler setup, generation/tooling checks and real OCaml integration |
| [NSH: Linux package and whole-app upgrade](https://github.com/logseq/lui/actions/runs/43040812514/job/130591792504) | Same DNS failure while fetching bubblewrap, multilib and musl packages; `/usr/bin/sudo` exits 100 at 15:28:49 UTC | NSH CLI build, packaging, outside-checkout launch and whole-app upgrade |
| [NSH: Linux Rust adapter](https://github.com/logseq/lui/actions/runs/43040812514/job/130591792854) | GTK/GStreamer apt installation keeps retrying after the same DNS failures; terminal message is `The operation was canceled.` at 15:38:36 UTC | Rust installation, formatting, Clippy, adapter tests and runner build |
| [Maintained backends: Web](https://github.com/logseq/lui/actions/runs/43040812342/job/130591790868) | Playwright `install-deps chromium firefox webkit` reports temporary DNS failures for `azure.archive.ubuntu.com`, `archive.ubuntu.com` and `security.ubuntu.com`; cancellation at 15:11:32 UTC | Subsequent Web qualification steps |

The two failed jobs stop with apt download errors before project compilation.
The two cancelled jobs stop during system-library installation. Cancellation is
not a pass, and these logs do not identify who or what requested cancellation.
There is no compiler, test assertion, package-version conflict or missing-package
diagnostic establishing a deterministic source regression in these four jobs.

The failures recur across different installation paths in the same time window,
which supports a runner/network DNS incident rather than a project-source cause.
The minimal next action is to retry the affected jobs on a runner with working
DNS. This evidence does not justify changing mirrors, dependency lists, exit-code
handling or test coverage.

## Other verified states at the observation time

- [macOS native package and whole-app upgrade](https://github.com/logseq/lui/actions/runs/43040812514/job/130591792488)
  completed successfully, including the outside-checkout launch and real LUI
  N1-to-N2 authentication/install/restart steps.
- macOS [OCaml integration](https://github.com/logseq/lui/actions/runs/43040812514/job/130591792336)
  and [Rust adapter](https://github.com/logseq/lui/actions/runs/43040812514/job/130591792668)
  jobs also completed successfully.
- [Windows Rust adapter](https://github.com/logseq/lui/actions/runs/43040812514/job/130591792756)
  completed successfully. The separate [Windows native OCaml/package job](https://github.com/logseq/lui/actions/runs/43040812514/job/130591792035)
  remained in progress: native DLL build/load, real C ABI/input/recovery/teardown
  and the pinned packaging CLI steps had passed; unsigned packaging was running
  and outside-checkout package launch was pending. This is not completed Windows
  package qualification.

These are time-stamped results for the stated commit and workflow attempt. They
do not qualify later working-tree changes, production signing credentials,
screen-reader output or unexecuted Linux/Web/Windows package paths.
