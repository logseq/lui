# Acceptance Dual Gate Patch

## Problem

The 3a3 macOS broad run naturally exited 0 without a terminal Swift Testing summary. SwiftPM, XCTest and the Swift Testing helper all exited 0 while Swift Testing was unfinished. Root command status alone cannot certify completion. The existing scratch observer records evidence but does not fail acceptance.

## Proposal

Propose an external macOS Python wrapper, `tooling/test/run_apple_tests.py`, which launches `swift test` with the caller's arguments, environment and working directory. PASS requires the outer command to exit 0, exactly one observed normal swiftpm-testing-helper to exit 0, and exactly one matching nonempty successful terminal Swift Testing run in the fresh combined output. An XCTest summary, test listing or NO_TESTS_FOUND does not satisfy this policy. Missing helper status fails closed.

The user explicitly requested this dual gate, all four invocation surfaces, an uncommitted minimal candidate, internal incomplete-exit verification and artifact delivery. These policy and delivery questions are already answered. This is a proposed candidate, not authorization to commit, push or land it. Baseline: `3a3fcc929ffd6c844525bfc919bf3180d4eff2c5`.

## Process and output contract

The wrapper supervises only its launched process tree. Darwin kqueue NOTE_EXIT/NOTE_EXITSTATUS records actual helper wait status; a missing EXITSTATUS flag is never interpreted as 0. The wrapper does not infer helper success from SwiftPM's status. Public macOS libproc functions (`proc_listchildpids`, `proc_pidpath`, declared in the SDK's libproc.h) identify descendants and helper executable paths through explicitly typed ctypes bindings, without pointer casts. Fork/exec notifications trigger immediate ancestry refresh, supplemented by periodic refresh. No private Swift Testing/runtime hook is used. Normal SwiftPM argument/environment handling remains upstream-owned.

R2 binds every observed PID to a frozen incarnation/watch record using public `proc_pidinfo(PROC_PIDTBSDINFO)` start-time fields. Parent identity is checked around ancestry discovery, incarnation is fenced around watch registration and path acquisition, and kqueue `udata` carries a unique, unreused watch generation. Exit status belongs to that generation, not a mutable PID-indexed status table. A changed incarnation, uncorrelated event, duplicate exit or ambiguous helper classification fails closed. Missing evidence is not guessed successful; a vanished optional build process cannot supply helper evidence. The diagnostic includes start-time and watch/parent-generation metadata.

The minimal supported scope is one ordinary Swift Testing helper/run, as used by the current package and fixture filter. Multiple helpers/runs, missing observations, list-only/XCTest-only/quiet output, exit-test subprocess modes and unsupported summary formats fail closed. An extremely short helper may still disappear before discovery, yielding a conservative rejection. Initial ps-based observation actually missed a 1 ms pure Swift Testing case and was replaced by direct libproc observation; that same real-toolchain case then passed. Do not substitute a synthetic success or an inferred child code. Observation can change scheduling, so this wrapper is an acceptance gate rather than a new drain diagnosis.

The output parser consumes only bytes from this newly launched command through EOF, requires the Swift Testing run-start marker before its terminal summary, permits ordinary ANSI display formatting, and requires a positive test count. A failed summary or extra run marker cannot be overridden by an earlier success. The parser does not use historical files as live evidence. The initial certificate format is the installed Testing 1902 console form; an incompatible future format fails closed pending an explicit adapter update.

Keep raw command output visible. Print a final JSON diagnostic containing outer status, observed helper status and the terminal verdict; it is not an alternative input certificate. Preserve existing CI/job time limits rather than adding a different test timeout. Interruption or monitor failure cannot produce PASS; on interruption, signal the owned SwiftPM command and let its cancellator handle its children. The wrapper never enumerates unrelated roots for teardown.

R2 latches SIGTERM and SIGINT through launch and cleanup instead of raising asynchronously across `Popen` assignment. Both enter the same failure/cancellation path; handlers are restored on return. Signal the owned SwiftPM root with SIGINT, allow four seconds for its own cancellator, then kill/reap that root within the remaining portion of a five-second cleanup bound. Repeated signals cannot interrupt this cleanup. A cleanup failure is reported as failure; an unresponsive kernel process cannot be promised reaped within a userspace deadline. No process-group or unrelated-root teardown is added, and normal test execution has no new deadline.

## Invocation surfaces

- `Makefile` test-apple calls the wrapper with `--no-parallel`; CI's existing `make test-apple` inherits it.
- The CI native-fixture swift-test bypass calls the same wrapper with its existing filter and fixture environment.
- Root direct invocations use `python3 tooling/test/run_apple_tests.py [swift test arguments]`, including `--package-path platform/apple` where desired.
- From `platform/apple`, use `python3 ../../tooling/test/run_apple_tests.py [swift test arguments]`. Add a local README and root instructions. A bare manually typed `swift test` is still upstream SwiftPM and cannot be intercepted by repository configuration; it is not the acceptance entrypoint.

The iOS build-for-testing and UIKit runtime-check commands are unchanged. No production source, dune file, Testing interface, native UI lifecycle or wire contract changes are proposed.

## Alternatives considered

### Trust SwiftPM exit status alone

Insufficient: the archived broad run already demonstrates exit0-incomplete. SwiftPM also normalizes no-matching-tests separately from failures.

### Parse output without observing helper status

Smaller, but it weakens the explicitly requested helper-exit condition. The inspected upstream SwiftPM maps normal exit 0 to success and NO_TESTS_FOUND to a non-failure state; this candidate preserves an independent child-status check instead.

### Replace the runner or install runtime hooks

Out of scope. The gate detects incomplete execution; it does not fix loop ownership, suppress CFRunLoopStop, pause Testing or select an app-hosted launcher.

## Acceptance criteria

- A controlled helper emitting the archived serial broad output and exiting 0 is rejected for missing terminal completion.
- A controlled helper emitting an archived complete successful run and exiting 0 is accepted; a nonzero helper cannot be hidden by an outer exit 0.
- Empty/no-tests, failed, absent/mismatched/duplicate terminal runs and outer failure are rejected. Existing ANSI formatting does not alter the verdict.
- Make and the CI bypass route through the same implementation; direct root/nested commands resolve to it and preserve selection and fixture environment.
- Deliver design, uncommitted patch and verification logs. Synthetic process/archived-output verification is not a fresh native suite PASS.
- Reject the pending-old-incarnation exit/path-reclassification sequence and registration/path lookup reuse windows; valid stable helper identity/status remains acceptable and unknown watch generations are rejected.
- Wrapper-only SIGTERM and SIGINT produce a nonzero diagnostic and owned-root cancellation/reaping; verify forced cleanup remains bounded under repeated signals while an unrelated sentinel survives.

## Risks

- Darwin process discovery is sampled: a missed/short-lived helper is rejected, not guessed successful. New process modes require a deliberate supported mapping.
- A console certificate is toolchain-sensitive. The wrapper validates one trusted test invocation; it is not a security boundary against test code forging another runner's console text.
- No claim of broad, native input, focus, iOS or release acceptance follows from wrapper verification.

## Decision inputs

The requesting user's 2026-11-15 instruction selects the policy, the four entrypoints and the no-commit/artifact-only delivery boundary. Implementation details above are the candidate for review. No additional user choice is needed to prepare that authorized candidate; landing and any broader runner mode remain outside this task.

## Candidate verification

### R1 evidence

The uncommitted candidate passed a 13-row controlled-process/archived-output table: incomplete exit0, complete success, a helper failure masked by outer exit0, outer failure, NO_TESTS_FOUND, empty exit0, failed summary, no helper, XCTest-only summary, a second unfinished run, ANSI formatting, nested working directory/filter/environment, and explicit nested package selection. Each controlled helper was an actual Darwin child process; its console text was replayed, not a fresh SDK test result.

A separate simulator-free, AppKit-free scratch package exercised the actual installed SwiftPM/Testing 1902 helper. Normal one-test completion produced helper exit0 and a terminal success and was accepted. A deliberately early `exit(0)` inside that scratch test produced outer/helper exit0 without a terminal summary and was rejected. A nonmatching filter produced outer exit0, helper exit69 (NO_TESTS_FOUND) and a zero-test successful summary and was rejected. NOTE_EXITSTATUS was present in all three helper observations. This validates the invocation boundary, not the WindowServer drain cause or native SDK behavior.

Initial ps-based observation conservatively rejected the very short normal package case; the final direct-libproc observation accepted it. A verifier initially assumed that NO_TESTS_FOUND would suppress the console summary; the installed toolchain actually emits a zero-test summary. The verifier was corrected to require rejection plus helper69 and a zero count, without changing the gate policy.

No repository build/broad suite, native UI, simulator, physical input or app-hosted comparison was run. Scratch fixtures/build outputs stay outside the patch and are removed after evidence capture. The original broad remains exit0-incomplete; no runtime readiness is upgraded.

### R2 evidence

The exact R1 preimages reproduced all three deterministic identity/status joins (pending old exit, registration window and path window), and wrapper-only SIGTERM exited the supervisor without interrupting its controlled command. These are adapter-model PID-reuse sequences, not a reproduced kernel PID-reuse event. R2 rejects them. Its six-row identity table also accepts a stable helper, rejects an unknown watch generation and rejects reuse after an old status was already consumed.

Three live controlled-process rows passed: wrapper-only SIGTERM, wrapper-only SIGINT, and repeated signals while the root ignores SIGINT and requires forced cleanup. Each returned a failing gate, reaped its owned root and left an unrelated sentinel alive; forced cleanup completed in about four seconds. A fresh AppKit-free scratch SwiftPM package supplied four actual-toolchain rows: normal helper0 plus terminal success accepted; outer/helper0 without a terminal summary rejected; outer0/helper69 with a zero-test terminal rejected; wrapper-only SIGTERM cancelled the real invocation, left no live test helper and preserved an unrelated sentinel. These validate the tooling boundary only. No new SDK broad/native GUI/mobile or release claim follows, and the earlier R1 parser matrix is historical rather than a new R2 run.
