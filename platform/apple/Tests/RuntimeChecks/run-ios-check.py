#!/usr/bin/env python3
"""Build and run native presentation regression checks without XCTest."""
import argparse
from pathlib import Path
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = "dev.lui.nativePresentationCheck"
CHECKS = {
    "file-preview": ("FilePreviewLaunch.swift", "FilePreviewLaunchCheck"),
    "drawer-first-reveal": ("DrawerFirstReveal.swift", "DrawerFirstRevealCheck"),
}


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("check", choices=CHECKS)
    parser.add_argument("--simulator", default="booted")
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
@main struct NativePresentationCheckApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Native presentation check").task {
                setbuf(stdout, nil)
                do {
                    try await CHECK_TYPE.main()
                    print("NATIVE_PRESENTATION_CHECK_COMPLETE")
                    exit(0)
                } catch {
                    print("NATIVE_PRESENTATION_CHECK_FAILED: \(error)")
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
        try:
            output = run(["xcrun", "simctl", "launch", "--console", "--terminate-running-process",
                          args.simulator, BUNDLE], capture_output=True, text=True, timeout=30)
            print(output.stdout + output.stderr)
            if "NATIVE_PRESENTATION_CHECK_COMPLETE" not in output.stdout:
                raise SystemExit("Native presentation check did not complete")
        finally:
            run(["xcrun", "simctl", "uninstall", args.simulator, BUNDLE])


if __name__ == "__main__":
    main()
