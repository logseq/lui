#!/usr/bin/env python3
"""Build and qualify test-key N1-to-N2 packages containing the real LUI runtime.

This local gate authenticates staged assets without an HTTP server. It closes
and restarts the native applications as an external driver; it does not qualify
HTTPS delivery, the standalone update menu or platform-managed restart.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import socket
import subprocess
import sys
import tempfile
import time

import nsh_delivery as delivery
import test_nsh_packaged_app as launch

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "platform/nsh"
FIXTURES = APP / "tests/fixtures"
VERSIONS = ("1.0.0", "2.0.0")
# Deterministic public fixture material, never a distribution credential.
SECRET = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE="
PUBLIC = "iojj3XQJ8ZX9UtstPLpdcspnCb8dlBIb83SIAbQPb1w="


def run(command, env, log):
    with log.open("wb") as output:
        subprocess.run([str(part) for part in command], cwd=ROOT, env=env,
                       stdout=output, stderr=subprocess.STDOUT, check=True)


def prepare_app(directory, version, source):
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "src").mkdir(exist_ok=True)
    (directory / "Cargo.toml").write_text(
        '[package]\nname="lui-upgrade-fixture"\nversion=' + json.dumps(version) +
        '\nedition="2024"\n[lib]\npath="src/lib.rs"\n[dependencies]\n' +
        'lui-nsh={path=' + json.dumps(str(APP)) + '}\n' +
        'nsh-core={git=' + json.dumps(source["repository"]) + ',rev=' +
        json.dumps(source["revision"]) + '}\n[workspace]\n', encoding="utf-8")
    (directory / "src/lib.rs").write_text('''use nsh_core::prelude::*;

#[native_module("upgrade/fixture")]
fn native(registry: &mut Registry) {
    registry.register::<UpgradeFixture>();
}

#[component]
pub fn UpgradeFixture() -> impl IntoElement {
    eprintln!("lui-upgrade-rust={}", env!("CARGO_PKG_VERSION"));
    view().flex_1().flex_col()
        .child(text(format!("Rust upgrade {}", env!("CARGO_PKG_VERSION"))))
        .child(lui_nsh::app::desktop())
}
''', encoding="utf-8")
    (directory / "nsh.json").write_text(json.dumps({
        "name": "LUI Upgrade Fixture", "id": "com.logseq.lui.upgrade-fixture",
        "version": version, "build": int(version.split(".")[0]),
        "rust": ".", "root": "UpgradeFixture",
        "updater": {"url": "https://updates.example.invalid/latest.json", "publicKey": PUBLIC},
    }, indent=2) + "\n", encoding="utf-8")
    if not (directory / "Cargo.lock").exists():
        shutil.copy2(APP / "Cargo.lock", directory / "Cargo.lock")


def observe(package, version, logs, timeout=45):
    _, executable, receipt = launch.locate_package(package.resolve())
    if receipt["application"]["version"] != version:
        raise launch.QualificationError("Package receipt has the wrong fixture version")
    logs.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    for name in ("LUI_OCAML_LIBRARY", "NSH_RUNTIME", "NSH_RUNTIME_DIR", "LD_LIBRARY_PATH",
                 "DYLD_LIBRARY_PATH", "DYLD_FALLBACK_LIBRARY_PATH", "DYLD_INSERT_LIBRARIES"):
        env.pop(name, None)
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        address = reservation.getsockname()
    env["LUI_AGENT_LISTEN"] = f"{address[0]}:{address[1]}"
    agent = None
    with tempfile.TemporaryDirectory(prefix="lui-upgrade-launch-") as outside, \
            (logs / "stdout.log").open("wb") as stdout, \
            (logs / "stderr.log").open("wb") as stderr, \
            (logs / "agent.jsonl").open("w", encoding="utf-8") as transcript:
        if Path(outside).resolve().is_relative_to(ROOT):
            raise launch.QualificationError("TMPDIR must be outside the checkout")
        deadline = time.monotonic() + timeout
        process = subprocess.Popen([str(executable)], cwd=outside, env=env,
                                   stdout=stdout, stderr=stderr, start_new_session=os.name == "posix")
        try:
            agent = launch.Agent(launch.connect(process, address, deadline), deadline, transcript)
            hello = agent.request(op="hello")
            if hello.get("protocol") != "lui-agent" or hello.get("host") != "Upgrade fixture " + version:
                raise launch.QualificationError(f"Wrong compiled OCaml fixture: {hello}")
            tree = agent.request(op="tree")
            if not any(node.get("props", {}).get("text") == "OCaml upgrade " + version for node in launch.nodes(tree)):
                raise launch.QualificationError("The actual OCaml version marker is missing")
            agent.request(op="type", selector="prop:accessibility-label=Upgrade editor", text="Edited " + version)
            draft = agent.request(op="prop", selector="prop:accessibility-label=Upgrade editor", name="text")
            if draft.get("value") != "Edited " + version:
                raise launch.QualificationError("The real OCaml reducer did not accept input")
            agent.request(op="press", selector="kind:button&text:Increment")
            count = agent.request(op="prop", selector="prop:accessibility-identifier=upgrade-count", name="text")
            if count.get("value") != "Count 1":
                raise launch.QualificationError("The real OCaml counter did not update")
            tree = agent.request(op="tree")
            (logs / "tree.json").write_text(json.dumps(tree, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            if process.poll() is not None:
                raise launch.QualificationError("The native fixture exited during qualification")
        finally:
            try:
                if agent:
                    agent.close()
            finally:
                launch.stop(process)
    if "lui-upgrade-rust=" + version not in (logs / "stderr.log").read_text(encoding="utf-8"):
        raise launch.QualificationError("The compiled Rust version marker is missing")
    return {"version": version, "rustMarker": True, "ocamlMarker": True,
            "realReducerEditAndPress": True, "workingDirectory": outside}


def qualify(args):
    if platform.system() not in ("Darwin", "Linux"):
        raise delivery.DeliveryError("The real OCaml upgrade fixture is qualified on macOS/Linux only")
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    logs = work / "logs"
    logs.mkdir(exist_ok=True)
    env = os.environ.copy()
    env["RUSTUP_TOOLCHAIN"] = "1.97.0"
    env["CARGO_BUILD_JOBS"] = "2"
    env["CARGO_TARGET_DIR"] = str(APP / "target")
    env["PATH"] = str(Path.home() / ".cargo/bin") + os.pathsep + env.get("PATH", "")
    if platform.system() == "Darwin":
        env["CARGO_PROFILE_RELEASE_STRIP"] = "none"
    for name in ("LUI_OCAML_LIBRARY", "NSH_RUNTIME", "NSH_RUNTIME_DIR"):
        env.pop(name, None)
    source = delivery.pinned_source(APP)
    application_snapshot = delivery.input_snapshot(APP)
    delivery.write_json(work / "lui-source-snapshot.json", application_snapshot)
    delivery.verified_cli(args.cli_directory.resolve(), source)
    spec = importlib.util.spec_from_file_location("build_nsh_fixture", FIXTURES / "build_virtual.py")
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    packages = []
    for version in VERSIONS:
        app = work / ("app-" + version)
        output = work / ("package-" + version)
        prepare_app(app, version, source)
        if not args.reuse_packages:
            # Seed from the tested application lock, then qualify the tiny fixture's graph.
            run([args.cargo, "check", "--manifest-path", app / "Cargo.toml"], env, logs / f"check-{version}.log")
            library = builder.build_fixture("upgrade", version=version)
            run(["node", ROOT / "tooling/lui_build_receipt.mjs", "write", "--root", ROOT,
                 "--artifact", library, "--command", f"python3 platform/nsh/tests/fixtures/build_virtual.py --fixture upgrade --version {version}",
                 "--input", "src", "--input", "ppx", "--input", "platform/bridge",
                 "--input", "platform/nsh/tests/fixtures/upgrade_app.ml",
                 "--input", "platform/nsh/tests/fixtures/build_virtual.py"], env, logs / f"receipt-{version}.log")
            run([sys.executable, ROOT / "tooling/nsh_delivery.py", "package", "--app", app,
                 "--cargo", args.cargo, "--cli-directory", args.cli_directory.resolve(),
                 "--library", library, "--output", output], env, logs / f"package-{version}.log")
        packages.append((app, output))
    delivery.require_snapshot(APP, application_snapshot)
    for _, output in packages:
        _, _, receipt = launch.locate_package(output)
        if receipt.get("luiSourceHashes") != application_snapshot:
            raise delivery.DeliveryError("Both compiled packages must retain the exact qualified LUI source snapshot")
    before = observe(packages[0][1], VERSIONS[0], logs / "before")
    key = work / "TEST-ONLY-update-secret.txt"
    key.write_text(SECRET + "\n", encoding="utf-8")
    key.chmod(0o600)
    archives = list(packages[1][1].glob("*.tar.gz"))
    if len(archives) != 1:
        raise delivery.DeliveryError("Expected one native N2 archive")
    manifest_output = work / "manifest"
    run([sys.executable, ROOT / "tooling/nsh_delivery.py", "manifest", archives[0],
         "--app", packages[1][0], "--cli-directory", args.cli_directory.resolve(),
         "--key", key, "--output", manifest_output], env, logs / "manifest.log")
    installed, executable, _ = launch.locate_package(packages[0][1])
    replacement, new_executable, _ = launch.locate_package(packages[1][1])
    relative = "Contents/Resources/lui/liblui_app.dylib" if platform.system() == "Darwin" else "lui/liblui_app.so"
    receipts = list(packages[1][1].glob("*-receipt.json"))
    if len(receipts) != 1:
        raise delivery.DeliveryError("Expected one complete N2 release receipt")
    final_code = json.loads(receipts[0].read_text(encoding="utf-8"))["installedCodeSha256"]
    binary_hash = final_code[new_executable.relative_to(replacement).as_posix()]
    library_hash = final_code[relative]
    if binary_hash != delivery.digest(new_executable) or library_hash != delivery.digest(replacement / relative):
        raise delivery.DeliveryError("Final N2 code does not match its installed-code receipt")
    result_path = work / "install-result.json"
    result_path.unlink(missing_ok=True)
    installation = {
        "executable": str(executable), "library": str(installed / relative),
        "archive": str(archives[0]), "manifest": str(manifest_output / "latest.json"),
        "signature": str(manifest_output / "latest.json.sig"), "cache": str(work / "verified-cache"),
        "expectedBinarySha256": binary_hash,
        "expectedLibrarySha256": library_hash, "result": str(result_path),
    }
    specification = work / "install-specification.json"
    specification.write_text(json.dumps(installation, indent=2) + "\n", encoding="utf-8")
    env["LUI_NSH_PACKAGED_UPGRADE_SPEC"] = str(specification)
    run([args.cargo, "test", "--locked", "--manifest-path", APP / "Cargo.toml", "--lib",
         "update::tests::native_signed_fixture_replaces_both_halves_and_restarts_at_the_new_version", "--", "--exact", "--nocapture"], env, logs / "install.log")
    installed_result = json.loads(result_path.read_text(encoding="utf-8"))
    if installed_result.get("qualified") is not True:
        raise delivery.DeliveryError("The actual-package updater fixture did not complete")
    after = observe(packages[0][1], VERSIONS[1], logs / "after")
    delivery.require_snapshot(APP, application_snapshot)
    result = {"qualified": True, "nsh": source, "luiSourceHashes": application_snapshot,
              "before": before, "installation": installed_result,
              "after": after, "boundary": "local signed assets; driver-managed native quit/restart; no HTTPS or native-menu restart qualification"}
    (work / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, default=ROOT / "_build/nsh/upgrade-qualification")
    parser.add_argument("--cargo", default="cargo")
    parser.add_argument("--cli-directory", type=Path, default=APP / ".nsh/toolchain")
    parser.add_argument("--reuse-packages", action="store_true", help="Reuse N1/N2 packages from a failed pre-install attempt")
    args = parser.parse_args()
    try:
        print(json.dumps(qualify(args), indent=2))
    except (OSError, ValueError, delivery.DeliveryError, launch.QualificationError, subprocess.SubprocessError) as error:
        print(f"LUI upgrade qualification failed: {error}; logs: {args.work.resolve() / 'logs'}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
