#!/usr/bin/env python3
"""Build and run native presentation regression checks without XCTest."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = "dev.lui.nativePresentationCheck"
CHECKS = {
    "file-preview": ("FilePreviewLaunch.swift", "FilePreviewLaunchCheck"),
    "drawer-first-reveal": ("DrawerFirstReveal.swift", "DrawerFirstRevealCheck"),
    "bounded-virtual-rows": ("BoundedVirtualRows.swift", "BoundedVirtualRowsCheck"),
}


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def collect_failure(simulator, destination):
    """Preserve this check's native launch evidence before uninstalling it."""
    destination.mkdir(parents=True, exist_ok=True)
    commands = {
        "application-log.txt": ["xcrun", "simctl", "spawn", simulator, "log", "show",
                                "--last", "2m", "--style", "compact", "--predicate",
                                'process == "NativePresentationCheck" OR '
                                'eventMessage CONTAINS "dev.lui.nativePresentationCheck"'],
        "device.json": ["xcrun", "simctl", "list", "devices", "--json"],
    }
    container = subprocess.run(["xcrun", "simctl", "get_app_container", simulator, BUNDLE, "data"],
                               capture_output=True, text=True)
    if container.returncode == 0:
        log = Path(container.stdout.strip()) / "Documents/native-check.log"
        if log.exists():
            (destination / "checkpoints.txt").write_bytes(log.read_bytes())
            print(log.read_text(), flush=True)
    for filename, command in commands.items():
        try:
            output = subprocess.run(command, capture_output=True, text=True, timeout=20)
            (destination / filename).write_text(output.stdout + output.stderr)
        except subprocess.TimeoutExpired as error:
            (destination / filename).write_text(str(error))
    crashes = Path.home() / "Library/Logs/DiagnosticReports"
    for crash in crashes.glob("NativePresentationCheck*.ips"):
        if time.time() - crash.stat().st_mtime < 300:
            (destination / crash.name).write_bytes(crash.read_bytes())
    print(f"Native check failure evidence: {destination}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("check", choices=CHECKS)
    parser.add_argument("--simulator", default="booted")
    parser.add_argument("--diagnostics-dir", type=Path)
    args = parser.parse_args()
    filename, check_type = CHECKS[args.check]
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
    run(["swift", "build", "--package-path", str(ROOT), "--configuration", "release",
         "--disable-sandbox", "--disable-keychain", "--product", "LUIAppleBackendStatic",
         "--triple", "arm64-apple-ios17.0-simulator", "--sdk", sdk, "-Xswiftc", "-enable-testing"])
    build = ROOT / ".build/arm64-apple-ios-simulator/release"
    with tempfile.TemporaryDirectory(prefix="lui-native-check-") as temporary:
        directory = Path(temporary)
        source = directory / "Check.swift"
        check = Path(__file__).with_name(filename).read_text().replace("@main", "", 1)
        source.write_text(check + r"""
@MainActor func nativePresentationCheckpoint(_ message: String) {
    setbuf(stdout, nil)
    print(message)
    let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("native-check.log")
    let previous = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    try? (previous + message + "\n").write(to: file, atomically: true, encoding: .utf8)
}
@main struct NativePresentationCheckApp: App {
    init() { nativePresentationCheckpoint("NATIVE_PRESENTATION_APP_INIT") }
    var body: some Scene {
        WindowGroup {
            Text("Native presentation check").task {
                nativePresentationCheckpoint("NATIVE_PRESENTATION_CHECK_BEGIN")
                do {
                    try await CHECK_TYPE.main()
                    nativePresentationCheckpoint("NATIVE_PRESENTATION_CHECK_COMPLETE")
                    exit(0)
                } catch {
                    nativePresentationCheckpoint("NATIVE_PRESENTATION_CHECK_FAILED: \(error)")
                    exit(1)
                }
            }
        }
    }
}
""".replace("CHECK_TYPE", check_type))
        app = directory / "NativePresentationCheck.app"
        app.mkdir()
        run(["xcrun", "--sdk", "iphonesimulator", "swiftc", "-O", "-parse-as-library",
             "-target", "arm64-apple-ios17.0-simulator", "-sdk", sdk, "-I", str(build / "Modules"),
             str(source), str(build / "libLUIAppleBackendStatic.a"), "-Xlinker", "-dead_strip",
             "-o", str(app / "NativePresentationCheck")])
        (app / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": BUNDLE, "CFBundleExecutable": "NativePresentationCheck",
            "CFBundleName": "Native presentation check", "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1", "MinimumOSVersion": "17.0",
            "UIDeviceFamily": [1], "UILaunchScreen": {},
        }))
        run(["codesign", "--force", "--sign", "-", str(app)])
        run(["xcrun", "simctl", "install", args.simulator, str(app)])
        diagnostics = args.diagnostics_dir or Path(tempfile.mkdtemp(prefix="lui-check-failure-"))
        try:
            output = subprocess.run(["xcrun", "simctl", "launch", "--console", "--terminate-running-process",
                                     args.simulator, BUNDLE], capture_output=True, text=True, timeout=30)
            print(output.stdout + output.stderr)
            if output.returncode != 0 or "NATIVE_PRESENTATION_CHECK_COMPLETE" not in output.stdout:
                diagnostics.mkdir(parents=True, exist_ok=True)
                (diagnostics / "launch.json").write_text(json.dumps({
                    "returncode": output.returncode, "stdout": output.stdout, "stderr": output.stderr,
                }, indent=2))
                collect_failure(args.simulator, diagnostics)
                raise SystemExit("Native presentation check did not complete")
        except subprocess.TimeoutExpired as error:
            diagnostics.mkdir(parents=True, exist_ok=True)
            (diagnostics / "launch-timeout.txt").write_text(
                f"{error}\nstdout={error.stdout!r}\nstderr={error.stderr!r}\n")
            collect_failure(args.simulator, diagnostics)
            raise
        finally:
            run(["xcrun", "simctl", "uninstall", args.simulator, BUNDLE])


if __name__ == "__main__":
    main()
