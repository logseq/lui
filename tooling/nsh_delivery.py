#!/usr/bin/env python3
"""Build and package the pinned NSH shell with its matching OCaml library."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PureWindowsPath
import platform
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import tomllib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_APP = ROOT / "platform/nsh"
RECEIPT = "lui-delivery.json"
CLI_RECEIPT = "nsh-cli-receipt.json"


class DeliveryError(RuntimeError):
    """A release cannot be produced from the supplied inputs."""


def run(command, *, cwd=None, capture=False):
    environment = os.environ.copy()
    if platform.system() == "Darwin":
        # Rust #157750: stripped proc-macro dylibs can fail macOS dyld alignment checks.
        environment["CARGO_PROFILE_RELEASE_STRIP"] = "none"
    result = subprocess.run([str(part) for part in command], cwd=cwd, check=True,
                            env=environment, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def digest(path):
    hasher = hashlib.sha256()
    with Path(path).open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def shared_icon_assets():
    return [(ROOT / "platform/web/src/icons" / name, f"licenses/lui-icons/{name}")
            for name in ("NOTICE", "LICENSE-APACHE-2.0")]


def input_snapshot(app):
    files = [app / name for name in ("Cargo.toml", "Cargo.lock", "nsh.json")]
    files.extend(sorted((app / "src").rglob("*.rs")))
    for name in ("build.rs", "contract.json"):
        if (app / name).is_file():
            files.append(app / name)
    if app.resolve() == DEFAULT_APP.resolve():
        files.extend(sorted((ROOT / "platform/web/src/icons").glob("*.svg")))
    snapshot = {Path(os.path.relpath(path, app)).as_posix(): digest(path) for path in files}
    snapshot.update({f"shared/icon-licenses/{path.name}": digest(path)
                     for path, _ in shared_icon_assets()})
    return snapshot


def require_snapshot(app, snapshot):
    if input_snapshot(app) != snapshot:
        raise DeliveryError("Application sources or manifests changed during packaging; rebuild from stable inputs")


def pinned_source(app):
    manifest = tomllib.loads((Path(app) / "Cargo.toml").read_text(encoding="utf-8"))
    dependencies = list(manifest.get("dependencies", {}).items())
    dependencies += list(manifest.get("dev-dependencies", {}).items())
    for target in manifest.get("target", {}).values():
        dependencies += list(target.get("dependencies", {}).items())
    sources = set()
    for name, declaration in dependencies:
        if not name.startswith("nsh-"):
            continue
        if not isinstance(declaration, dict) or not declaration.get("git"):
            raise DeliveryError(f"{name} must use the immutable NSH Git pin")
        revision = declaration.get("rev", "")
        if not re.fullmatch(r"[0-9a-f]{40}", revision):
            raise DeliveryError(f"{name} requires a full commit SHA, not a branch or tag")
        sources.add((declaration["git"].removesuffix(".git"), revision))
    if len(sources) != 1:
        raise DeliveryError("All NSH crates must use exactly one repository and revision")
    url, revision = sources.pop()
    return {"repository": url, "revision": revision}


def checkout_root(manifest):
    for parent in Path(manifest).resolve().parents:
        if (parent / "crates/nsh-core/Cargo.toml").is_file():
            return parent
    raise DeliveryError(f"No NSH source checkout owns {manifest}")


def verify_checkout(checkout, source):
    head = run(["git", "-C", checkout, "rev-parse", "HEAD"], capture=True)
    if head != source["revision"]:
        raise DeliveryError(f"NSH checkout is {head}, expected {source['revision']}")
    changed = run(["git", "-C", checkout, "status", "--porcelain", "--untracked-files=normal"], capture=True)
    marker = checkout / ".cargo-ok"
    if marker.is_file() and not marker.is_symlink() and marker.stat().st_size == 0:
        # Cargo adds this empty completion marker to its Git source checkouts.
        changed = "\n".join(line for line in changed.splitlines() if line != "?? .cargo-ok")
    if changed:
        raise DeliveryError("NSH checkout contains uncommitted source files")


def verify_graph(metadata, source):
    """Accept the Git pin or the CLI's path patch to that exact clean checkout."""
    packages = []
    checkouts = set()
    for package in metadata["packages"]:
        name = package["name"]
        if not name.startswith("nsh-") or name.startswith("nsh-app-"):
            continue
        resolved = package.get("source")
        if resolved:
            if not resolved.startswith("git+") or "#" not in resolved:
                raise DeliveryError(f"{name} resolves from a registry instead of the NSH pin")
            repository, revision = resolved[4:].rsplit("#", 1)
            repository = repository.split("?", 1)[0].removesuffix(".git")
            if (repository, revision) != (source["repository"], source["revision"]):
                raise DeliveryError(f"{name} resolves from a different NSH source")
        else:
            checkout = checkout_root(package["manifest_path"])
            if checkout not in checkouts:
                verify_checkout(checkout, source)
                checkouts.add(checkout)
        packages.append(name)
    if "nsh-core" not in packages or "nsh-engine" not in packages:
        raise DeliveryError("The runner graph does not contain NSH core and engine")
    return sorted(set(packages))


def cargo_metadata(cargo, manifest):
    return json.loads(run([cargo, "metadata", "--locked", "--format-version", "1",
                           "--manifest-path", manifest], capture=True))


def lui_source_snapshot(metadata):
    adapters = [Path(package["manifest_path"]).resolve().parent
                for package in metadata["packages"]
                if package["name"] == "lui-nsh" and package.get("source") is None]
    if not adapters:
        return {}
    if len(adapters) != 1:
        raise DeliveryError("Expected exactly one local LUI adapter source")
    app = adapters[0]
    snapshot = input_snapshot(app)
    # A thin fixture root still compiles the path dependency's shared SVGs.
    icons = app.parent / "web/src/icons"
    snapshot.update({f"../web/src/icons/{path.name}": digest(path)
                     for path in sorted(icons.glob("*.svg"))})
    return snapshot


def require_tested_registry(app, runner):
    def packages(metadata):
        return {(package["name"], package["version"], package["source"])
                for package in metadata["packages"]
                if (package.get("source") or "").startswith("registry+")}
    missing = packages(app) - packages(runner)
    if missing:
        differences = ", ".join(f"{name}@{version}" for name, version, _ in sorted(missing))
        raise DeliveryError(
            f"Generated runner registry dependencies differ from the tested app lock: {differences}; "
            "requalify the application Cargo.lock with the runner's features before packaging")


def require_cli_version(observed, version, source):
    match = re.fullmatch(r"nsh (\S+)(?: \(([0-9a-f]{7,40})\))?", observed)
    if not match or match[1] != version:
        raise DeliveryError(f"CLI reports {observed!r}, expected nsh {version}")
    if match[2] and not source["revision"].startswith(match[2]):
        raise DeliveryError("CLI version reports a different NSH source revision")


def setup(args):
    app = args.app.resolve()
    source = pinned_source(app)
    checkout = args.checkout.resolve()
    verify_checkout(checkout, source)
    manifest = tomllib.loads((checkout / "Cargo.toml").read_text(encoding="utf-8"))
    version = manifest["workspace"]["package"]["version"]
    run([args.cargo, "build", "--locked", "--release", "--package", "nsh-cli",
         "--manifest-path", checkout / "Cargo.toml"])
    metadata = json.loads(run([args.cargo, "metadata", "--no-deps", "--format-version", "1",
                               "--manifest-path", checkout / "Cargo.toml"], capture=True))
    verify_checkout(checkout, source)
    executable = "nsh.exe" if os.name == "nt" else "nsh"
    binary = Path(metadata["target_directory"]) / "release" / executable
    args.destination.mkdir(parents=True, exist_ok=True)
    installed = args.destination / executable
    shutil.copy2(binary, installed)
    observed = run([installed, "--version"], capture=True)
    require_cli_version(observed, version, source)
    write_json(args.destination / CLI_RECEIPT, {
        "schemaVersion": 1, "source": source, "version": version,
        "binary": executable, "sha256": digest(installed),
        "releaseProfile": {"strip": "none"} if platform.system() == "Darwin" else {},
    })
    print(installed.resolve())


def verified_cli(directory, source):
    receipt = json.loads((directory / CLI_RECEIPT).read_text(encoding="utf-8"))
    if receipt.get("source") != source:
        raise DeliveryError("CLI receipt does not match the app's NSH pin; run setup again")
    binary = directory / receipt["binary"]
    if digest(binary) != receipt["sha256"]:
        raise DeliveryError("CLI binary differs from its setup receipt")
    observed = run([binary, "--version"], capture=True)
    require_cli_version(observed, receipt["version"], source)
    return binary.resolve(), receipt


def host_target():
    return {"Darwin": "macos", "Linux": "linux", "Windows": "windows"}.get(platform.system())


def host_architecture():
    machine = platform.machine().lower()
    return {"arm64": "aarch64", "amd64": "x86_64"}.get(machine, machine)


def architectures(path, target):
    """Read the actual executable format, rather than trusting its extension."""
    with Path(path).open("rb") as file:
        header = file.read(4096)
        if target == "macos":
            magic = header[:4]
            if magic in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
                count = struct.unpack_from(">I", header, 4)[0]
                stride = 32 if magic[-1] == 0xBF else 20
                if count > 64 or len(header) < 8 + count * stride:
                    raise DeliveryError(f"Malformed Mach-O architecture table: {path}")
                cpus = [struct.unpack_from(">I", header, 8 + index * stride)[0] for index in range(count)]
            elif magic in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe"):
                cpus = [struct.unpack_from("<I", header, 4)[0]]
            elif magic in (b"\xfe\xed\xfa\xcf", b"\xfe\xed\xfa\xce"):
                cpus = [struct.unpack_from(">I", header, 4)[0]]
            else:
                raise DeliveryError(f"Not a Mach-O file: {path}")
            names = {0x0100000C: "aarch64", 0x01000007: "x86_64"}
        elif target == "linux":
            if header[:4] != b"\x7fELF" or len(header) < 20 or header[5] not in (1, 2):
                raise DeliveryError(f"Not an ELF file: {path}")
            cpus = [struct.unpack_from("<H" if header[5] == 1 else ">H", header, 18)[0]]
            names = {183: "aarch64", 62: "x86_64"}
        else:
            if header[:2] != b"MZ" or len(header) < 64:
                raise DeliveryError(f"Not a PE file: {path}")
            offset = struct.unpack_from("<I", header, 60)[0]
            file.seek(offset)
            pe = file.read(6)
            if pe[:4] != b"PE\0\0" or len(pe) != 6:
                raise DeliveryError(f"Malformed PE header: {path}")
            cpus = [struct.unpack_from("<H", pe, 4)[0]]
            names = {0xAA64: "aarch64", 0x8664: "x86_64"}
    try:
        return {names[cpu] for cpu in cpus}
    except KeyError as error:
        raise DeliveryError(f"Unsupported binary architecture in {path}: {error}") from error


def package_layout(directory, config, target):
    name = config["name"]
    if not name or name in (".", "..") or any(character in name for character in '/\\\0'):
        raise DeliveryError("Package name must be a single nonempty path component")
    if target == "macos":
        root = directory / f"{name}.app"
        executable = "".join(character for character in name if character.isascii() and character.isalnum()) or "App"
        return root, root / "Contents/MacOS" / executable, root / "Contents/Resources/lui"
    root = directory / name
    if target == "windows":
        executable = "".join(c for c in name if not ord(c) < 32 and c not in '<>:"/\\|?*').rstrip(". ").lstrip() or "App"
        executable += ".exe"
    else:
        executable = "".join(character for character in name if character.isascii() and character.isalnum()) or "App"
    return root, root / executable, root / "lui"


def copy_payload(resources, library, dependencies, assets, target):
    resources.mkdir(parents=True, exist_ok=True)
    name = {"macos": "liblui_app.dylib", "linux": "liblui_app.so", "windows": "lui_app.dll"}[target]
    destinations = {name}
    copied = [resources / name]
    shutil.copy2(library, copied[0])
    for dependency in dependencies:
        if dependency.name in destinations:
            raise DeliveryError(f"Duplicate native library name: {dependency.name}")
        destinations.add(dependency.name)
        destination = resources / dependency.name
        shutil.copy2(dependency, destination)
        copied.append(destination)
    for source, relative in assets:
        relative = Path(relative)
        if relative.is_absolute() or PureWindowsPath(str(relative)).drive or not relative.parts or any(part in ("..", ".") for part in relative.parts) or "\\" in str(relative):
            raise DeliveryError(f"Asset destination must stay inside package resources: {relative}")
        destination = resources / "assets" / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    return copied


def installed_code_hashes(root, executable, resources, target, dependencies):
    library = {"macos": "liblui_app.dylib", "linux": "liblui_app.so", "windows": "lui_app.dll"}[target]
    paths = [executable, resources / library, *[resources / path.name for path in dependencies]]
    return {path.relative_to(root).as_posix(): digest(path) for path in paths}


def relocate_macos(root, executable, libraries):
    """Keep non-system links inside the complete application before signing."""
    destinations = {path.name: path for path in libraries}
    for code in [*libraries, executable]:
        identity = run(["otool", "-D", code], capture=True).splitlines()[1:]
        own = {line.strip() for line in identity}
        links = run(["otool", "-L", code], capture=True).splitlines()[1:]
        for line in links:
            dependency = line.strip().split(" (compatibility version", 1)[0]
            if dependency in own or dependency.startswith(("/usr/lib/", "/System/Library/")):
                continue
            name = Path(dependency).name
            if name in destinations:
                relative = os.path.relpath(destinations[name], code.parent)
                run(["install_name_tool", "-change", dependency, f"@loader_path/{relative}", code])
                continue
            resolved = None
            if dependency.startswith("@loader_path/"):
                resolved = code.parent / dependency.removeprefix("@loader_path/")
            elif dependency.startswith("@executable_path/"):
                resolved = executable.parent / dependency.removeprefix("@executable_path/")
            if resolved and resolved.resolve().is_relative_to(root.resolve()) and resolved.is_file():
                continue
            raise DeliveryError(f"Unbundled non-system dependency {dependency} in {code.name}; pass its file with --dependency")


def find_iscc():
    for name in ("ISCC.exe", "iscc.exe", "iscc"):
        found = shutil.which(name)
        if found:
            return Path(found)
    for variable in ("ProgramFiles(x86)", "ProgramFiles", "LOCALAPPDATA"):
        base = os.environ.get(variable)
        if base:
            for relative in ("Inno Setup 6/ISCC.exe", "Programs/Inno Setup 6/ISCC.exe"):
                candidate = Path(base) / relative
                if candidate.is_file():
                    return candidate
    return None


def sign_macos(root, executable, libraries, args):
    identity = args.macos_identity or "-"
    timestamp = ["--timestamp=none"] if identity == "-" else ["--timestamp"]
    for code in [*libraries, executable]:
        run(["codesign", "--force", "--sign", identity, *timestamp, code])
    command = ["codesign", "--force", "--sign", identity, *timestamp]
    if identity != "-":
        command += ["--options", "runtime"]
    if args.entitlements:
        command += ["--entitlements", args.entitlements]
    run([*command, root])
    run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", root])
    if args.notary_profile:
        if identity == "-":
            raise DeliveryError("Notarization requires a Developer ID identity")
        with tempfile.TemporaryDirectory(prefix="lui-notary-") as temporary:
            submission = Path(temporary) / "submission.zip"
            run(["ditto", "-c", "-k", "--keepParent", root, submission])
            run(["xcrun", "notarytool", "submit", submission, "--keychain-profile", args.notary_profile, "--wait"])
        run(["xcrun", "stapler", "staple", root])
        run(["xcrun", "stapler", "validate", root])
        run(["spctl", "--assess", "--type", "execute", "--verbose=2", root])
    return "ad-hoc" if identity == "-" else "developer-id"


def sign_windows(files, args):
    if not args.windows_thumbprint:
        return "unsigned"
    if not args.timestamp_url or not args.timestamp_url.startswith("https://"):
        raise DeliveryError("Authenticode signing requires an HTTPS timestamp URL")
    for path in files:
        run([args.signtool, "sign", "/sha1", args.windows_thumbprint, "/fd", "SHA256",
             "/tr", args.timestamp_url, "/td", "SHA256", path])
        run([args.signtool, "verify", "/pa", "/all", path])
    return "authenticode"


def archive_package(root, output, config, target, wanted):
    slug = "".join(character if character.isascii() and character.isalnum() else "-" for character in config["name"])
    paths = []
    for architecture in sorted(wanted):
        extension = "zip" if target == "windows" else "tar.gz"
        archive = output / f"{slug}-{config['version']}-{target}-{architecture}.{extension}"
        if target == "windows":
            with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as file:
                for path in sorted(root.rglob("*")):
                    if path.is_file():
                        file.write(path, path.relative_to(root.parent))
        else:
            with tarfile.open(archive, "w:gz") as file:
                file.add(root, arcname=root.name)
        paths.append(archive)
    return paths


def finalize(root, executable, resources, config, target, wanted, args, receipt):
    library = args.library.resolve()
    verified_digest = receipt.get("ocamlArtifactSha256")
    if verified_digest is not None and digest(library) != verified_digest:
        raise DeliveryError("OCaml library changed after its build receipt was verified")
    code = [library, *args.dependency]
    for path in [executable, *code]:
        if not wanted <= architectures(path, target):
            raise DeliveryError(f"{path} does not contain all requested architectures {sorted(wanted)}")
    libraries = copy_payload(resources, library, args.dependency,
                             [*args.asset, *shared_icon_assets()], target)
    if verified_digest is not None and digest(libraries[0]) != verified_digest:
        raise DeliveryError("Copied OCaml library does not match its verified build receipt")
    receipt.update({"application": {key: config[key] for key in ("name", "id", "version", "build")},
                    "target": target, "architectures": sorted(wanted),
                    "ocaml": {"librarySha256": digest(library),
                              "dependencies": {p.name: digest(p) for p in args.dependency}}})
    write_json(resources / RECEIPT, receipt)
    signing = "unsigned"
    if target == "macos":
        relocate_macos(root, executable, libraries)
        signing = sign_macos(root, executable, libraries, args)
    elif target == "windows":
        signing = sign_windows([executable, *libraries], args)
    # Signing may change code bytes. Record the final digest outside the signed bundle.
    return signing


def validate_application(config):
    for key in ("name", "id", "version", "build"):
        if key not in config:
            raise DeliveryError(f"nsh.json must declare {key}")
    name = config["name"]
    if not isinstance(name, str) or not name or name in (".", "..") or any(c in name for c in '/\\\0'):
        raise DeliveryError("Package name must be a single nonempty path component")
    if not isinstance(config["id"], str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", config["id"]):
        raise DeliveryError("Application ID must be a safe bundle identifier")
    numeric = r"(?:0|[1-9][0-9]*)"
    prerelease = rf"(?:{numeric}|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
    build = r"[0-9A-Za-z-]+"
    semver = rf"{numeric}\.{numeric}\.{numeric}(?:-{prerelease}(?:\.{prerelease})*)?(?:\+{build}(?:\.{build})*)?"
    if not isinstance(config["version"], str) or not re.fullmatch(semver, config["version"]):
        raise DeliveryError("Application version must be a semantic version")
    if isinstance(config["build"], bool) or not isinstance(config["build"], int) or not 0 <= config["build"] < 1 << 32:
        raise DeliveryError("Application build must be an unsigned 32-bit integer")


def package(args):
    app = args.app.resolve()
    args.output = args.output.resolve()
    if args.iscc:
        args.iscc = args.iscc.resolve()
    snapshot = input_snapshot(app)
    target = args.target or host_target()
    if target != host_target():
        raise DeliveryError("Desktop packages must be built and verified on their target OS")
    if target != "macos" and (args.macos_identity or args.entitlements or args.notary_profile):
        raise DeliveryError("macOS signing options require the macOS target")
    if target != "windows" and (args.windows_thumbprint or args.timestamp_url or args.iscc):
        raise DeliveryError("Windows signing/installer options require the Windows target")
    wanted = {"aarch64", "x86_64"} if args.arch == "universal" else {args.arch or host_architecture()}
    if target != "macos" and wanted != {host_architecture()}:
        raise DeliveryError("Linux and Windows packaging requires the matching native toolchain")
    source = pinned_source(app)
    run([args.node, ROOT / "tooling/lui_build_receipt.mjs", "check", "--artifact", args.library.resolve()])
    ocaml_receipt = json.loads(Path(str(args.library.resolve()) + ".lui-build.json").read_text(encoding="utf-8"))
    verified_digest = ocaml_receipt.get("artifactDigest", "")
    if not isinstance(verified_digest, str) or not re.fullmatch(r"[0-9a-f]{64}", verified_digest):
        raise DeliveryError("OCaml build receipt has no valid artifact digest")
    cli, cli_receipt = verified_cli(args.cli_directory.resolve(), source)
    config = json.loads((app / "nsh.json").read_text(encoding="utf-8"))
    validate_application(config)
    if config.get("updater", {}).get("packages"):
        raise DeliveryError("Compiled LUI applications require whole-app updates, not TSX packages")
    if any(os.environ.get(key) for key in ("NSH_RUNTIME", "NSH_RUNTIME_DIR", "LUI_OCAML_LIBRARY")):
        raise DeliveryError("Unset development runner/library overrides before packaging")
    graph = cargo_metadata(args.cargo, app / "Cargo.toml")
    packages = verify_graph(graph, source)
    lui_snapshot = lui_source_snapshot(graph)
    generated = app / ".nsh/rust/Cargo.toml"
    generated.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(app / "Cargo.lock", generated.parent / "Cargo.lock")
    # Describing the Rust root writes and builds the generated workspace first.
    run([cli, "build", app], cwd=app)
    generated_graph = cargo_metadata(args.cargo, generated)
    generated_packages = verify_graph(generated_graph, source)
    require_tested_registry(graph, generated_graph)
    generated_lock = digest(generated.parent / "Cargo.lock")
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".lui-package-", dir=args.output) as temporary:
        staged = Path(temporary)
        command = [cli, "package", app, "--target", target, "-o", staged]
        if target == "macos" and args.arch:
            command += ["--arch", args.arch]
        run(command, cwd=app)
        # Check again after packaging: NSH may regenerate its runner workspace.
        packaged_graph = cargo_metadata(args.cargo, generated)
        verify_graph(packaged_graph, source)
        require_tested_registry(graph, packaged_graph)
        if lui_source_snapshot(packaged_graph) != lui_snapshot:
            raise DeliveryError("Local LUI adapter sources changed during packaging; rebuild from stable inputs")
        if digest(generated.parent / "Cargo.lock") != generated_lock:
            raise DeliveryError("Generated runner lock changed during packaging; requalify the application lock before retrying")
        require_snapshot(app, snapshot)
        run([args.node, ROOT / "tooling/lui_build_receipt.mjs", "check", "--artifact", args.library.resolve()])
        root, executable, resources = package_layout(staged, config, target)
        if target == "macos" and not args.entitlements:
            inherited = staged / f"{executable.name}.entitlements"
            if inherited.is_file():
                args.entitlements = inherited
        receipt = {"schemaVersion": 1, "nsh": source, "cliSha256": cli_receipt["sha256"],
                   "applicationSourceHashes": snapshot,
                   "luiSourceHashes": lui_snapshot,
                   "releaseProfile": {"strip": "none"} if platform.system() == "Darwin" else {},
                   "applicationCrates": packages, "runnerCrates": generated_packages,
                   "cargoLockSha256": digest(app / "Cargo.lock"),
                   "generatedLockSha256": digest(generated.parent / "Cargo.lock"),
                   "ocamlArtifactSha256": verified_digest,
                   "ocamlSourceHashes": ocaml_receipt["files"]}
        signing = finalize(root, executable, resources, config, target, wanted, args, receipt)
        installer = None
        iscc = (args.iscc or find_iscc()) if target == "windows" else None
        if iscc:
            scripts = list(staged.glob("*.iss"))
            if len(scripts) != 1:
                raise DeliveryError("Expected exactly one NSH Inno Setup script")
            # Compile again after the OCaml DLLs and final code signatures are present.
            run([iscc, "/Q", f"/O{staged}", scripts[0]], cwd=staged)
            installers = list(staged.glob("*-setup.exe"))
            if len(installers) != 1:
                raise DeliveryError("Inno Setup did not produce exactly one installer")
            installer = installers[0]
            sign_windows([installer], args)
        archives = archive_package(root, staged, config, target, wanted)
        external = dict(receipt, signing=signing, notarized=bool(args.notary_profile),
                        runnerSha256=digest(executable),
                        installedCodeSha256=installed_code_hashes(root, executable, resources, target, args.dependency),
                        archives={p.name: digest(p) for p in archives})
        if installer:
            external["installer"] = {"name": installer.name, "sha256": digest(installer)}
        require_snapshot(app, snapshot)
        if lui_source_snapshot(packaged_graph) != lui_snapshot:
            raise DeliveryError("Local LUI adapter sources changed before publication; rebuild from stable inputs")
        for path in [root, *archives, *([installer] if installer else [])]:
            destination = args.output / path.name
            if destination.exists():
                raise DeliveryError(f"Refusing to overwrite an existing release: {destination}")
        for path in [root, *archives, *([installer] if installer else [])]:
            shutil.move(str(path), args.output / path.name)
        write_json(args.output / f"{config['id']}-{config['version']}-{target}-receipt.json", external)
    print(json.dumps(external, indent=2, sort_keys=True))


def manifest(args):
    app = args.app.resolve()
    source = pinned_source(app)
    cli, _ = verified_cli(args.cli_directory.resolve(), source)
    config = json.loads((app / "nsh.json").read_text(encoding="utf-8"))
    for archive in args.archives:
        matching = []
        for receipt_path in archive.parent.glob(f"{config['id']}-{config['version']}-*-receipt.json"):
            receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
            if (receipt.get("nsh") == source and
                    receipt.get("archives", {}).get(archive.name) == digest(archive)):
                matching.append(receipt)
        if len(matching) != 1:
            raise DeliveryError(f"{archive}: no unique matching complete-application release receipt")
    command = [cli, "update-manifest", *[p.resolve() for p in args.archives],
               "--entry", app, "--key", args.key.resolve(), "-o", args.output.resolve()]
    if args.notes:
        command += ["--notes", args.notes.resolve()]
    if args.base_url:
        command += ["--base-url", args.base_url]
    run(command, cwd=app)


def asset(value):
    source, separator, destination = value.partition("=")
    if not separator or not source or not destination:
        raise argparse.ArgumentTypeError("expected SOURCE=relative/destination")
    return Path(source).resolve(), destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    setup_parser = commands.add_parser("setup", help="Build a CLI from the app's exact NSH pin")
    setup_parser.add_argument("--app", type=Path, default=DEFAULT_APP)
    setup_parser.add_argument("--cargo", default="cargo")
    setup_parser.add_argument("--checkout", type=Path, required=True)
    setup_parser.add_argument("--destination", type=Path, default=DEFAULT_APP / ".nsh/toolchain")
    setup_parser.set_defaults(action=setup)
    package_parser = commands.add_parser("package", help="Package the complete compiled application")
    package_parser.add_argument("--app", type=Path, default=DEFAULT_APP)
    package_parser.add_argument("--cargo", default="cargo")
    package_parser.add_argument("--node", default="node")
    package_parser.add_argument("--cli-directory", type=Path, default=DEFAULT_APP / ".nsh/toolchain")
    package_parser.add_argument("--target", choices=("macos", "linux", "windows"))
    package_parser.add_argument("--arch", choices=("aarch64", "x86_64", "universal"))
    package_parser.add_argument("--library", type=Path, required=True)
    package_parser.add_argument("--dependency", type=Path, action="append", default=[])
    package_parser.add_argument("--asset", type=asset, action="append", default=[])
    package_parser.add_argument("--output", type=Path, default=ROOT / "_build/nsh-packages")
    package_parser.add_argument("--macos-identity")
    package_parser.add_argument("--entitlements", type=Path)
    package_parser.add_argument("--notary-profile")
    package_parser.add_argument("--windows-thumbprint")
    package_parser.add_argument("--timestamp-url")
    package_parser.add_argument("--signtool", default="signtool")
    package_parser.add_argument("--iscc", type=Path)
    package_parser.set_defaults(action=package)
    manifest_parser = commands.add_parser("manifest", help="Sign a manifest after all target packages are final")
    manifest_parser.add_argument("archives", type=Path, nargs="+")
    manifest_parser.add_argument("--app", type=Path, default=DEFAULT_APP)
    manifest_parser.add_argument("--cli-directory", type=Path, default=DEFAULT_APP / ".nsh/toolchain")
    manifest_parser.add_argument("--key", type=Path, required=True)
    manifest_parser.add_argument("--notes", type=Path)
    manifest_parser.add_argument("--base-url")
    manifest_parser.add_argument("--output", type=Path, required=True)
    manifest_parser.set_defaults(action=manifest)
    args = parser.parse_args()
    try:
        args.action(args)
    except (DeliveryError, OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"NSH delivery failed: {error}\n")


if __name__ == "__main__":
    main()
