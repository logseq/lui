# Apple backend testing

From this directory, run the macOS acceptance gate:

```sh
python3 ../../tooling/test/run_apple_tests.py --no-parallel
python3 ../../tooling/test/run_apple_tests.py --no-parallel --filter LUISparseVirtualNativeTests
```

From the repository root, `make test-apple` uses the root package; use
`python3 tooling/test/run_apple_tests.py --package-path platform/apple --no-parallel`
to select this nested manifest explicitly. These manifests share the Apple
source/test directories but have distinct package products/build locations.
The wrapper preserves SwiftPM arguments, environment (including
`LUI_APPLE_BOUNDED_LIBRARY`) and working directory.

PASS requires the outer command and one observed normal swiftpm-testing-helper
to exit 0, plus one nonempty successful terminal Swift Testing summary following
its run-start marker in this invocation's output. XCTest's summary alone does
not qualify. NO_TESTS_FOUND, missing helper status, incomplete execution, failed
or multiple runs, list-only/XCTest-only commands and unsupported output formats
fail closed. A short-lived helper may finish before process discovery; that
produces a conservative rejection rather than an inferred successful exit.

This gate uses Darwin process observation and the installed Testing 1902 console
format. It does not alter upstream Swift Testing or intercept a manually typed
bare `swift test`; such a command is a diagnostic run, not this acceptance path.
CI/job time limits and SwiftPM's cancellation/child-teardown behavior remain in
force. No app-hosted runner, iOS runtime acceptance or native input result is
implied. iOS build-for-testing and the UIKit runtime-check launcher are separate.
