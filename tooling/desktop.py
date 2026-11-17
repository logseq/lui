#!/usr/bin/env python3
"""Build, package and sign an OCaml-owned WebView application.

No Go, Rust, Electron or Node runtime is shipped. Build tools are invoked with
argument arrays, and third-party sources stay inside the ignored build tree.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shlex
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "platform/desktop"
PACKAGES = "unix,threads,yojson,uri,digestif.c,mirage-crypto-ec,mirage-crypto-rng.unix,ohex"


def run(args, **kwargs):
    return subprocess.run([arg.as_posix() if isinstance(arg, Path) else str(arg) for arg in args], check=True, **kwargs)


def capture(args):
    return run(args, stdout=subprocess.PIPE, text=True).stdout.strip()


def digest(path):
    with open(path, "rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def host_target():
    systems = {"Darwin": "darwin", "Linux": "linux", "Windows": "windows"}
    machines = {"arm64": "arm64", "aarch64": "arm64", "x86_64": "amd64", "amd64": "amd64"}
    return systems[platform.system()] + "-" + machines[platform.machine().lower()]


def https(url):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
        raise ValueError("A credential-free HTTPS URL is required")
    return url


def ocaml_string(value):
    return '"' + "".join(chr(byte) if 32 <= byte < 127 and byte not in (34, 92)
                          else "\\%03d" % byte for byte in value.encode("utf-8")) + '"'


def configuration(path, target=None):
    config = json.loads(Path(path).read_text())
    required = {"name", "slug", "identifier", "version", "build"}
    missing = required - config.keys()
    if missing:
        raise ValueError(f"Missing configuration fields: {sorted(missing)}")
    for key, pattern in [("slug", r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*"),
                         ("identifier", r"[a-zA-Z][a-zA-Z0-9]*(?:\.[a-zA-Z][a-zA-Z0-9-]*)+"),
                         ("version", r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?")]:
        if not re.fullmatch(pattern, config[key]):
            raise ValueError(f"Invalid {key}")
    if not isinstance(config["name"], str) or not config["name"] or any(c in config["name"] for c in "/\\\r\n\0"):
        raise ValueError("Invalid application name")
    for key in ("description", "maintainer", "license"):
        if key in config and (not isinstance(config[key], str) or any(c in config[key] for c in "\r\n\0")):
            raise ValueError(f"Invalid {key}")
    if type(config["build"]) is not int or not 1 <= config["build"] <= 2_000_000_000:
        raise ValueError("build must be a positive monotonically increasing integer")
    for key, default in [("width", 1100), ("height", 760)]:
        config.setdefault(key, default)
        if type(config[key]) is not int or not 200 <= config[key] <= 16384:
            raise ValueError(f"Invalid window {key}")
    web = config.get("web", {})
    if not isinstance(web, dict) or set(web) - {"wasm"} or type(web.get("wasm", False)) is not bool:
        raise ValueError("web accepts only the boolean wasm option")
    if "updates" in config:
        updates = config["updates"]
        https(updates["url"])
        if not re.fullmatch(r"[0-9a-f]{64}", updates["public_key"]):
            raise ValueError("updates.public_key must be a 32-byte Ed25519 key in lowercase hex")
    config["platform"] = target or host_target()
    return config


def source_dependency(cache):
    dependency = json.loads((SOURCE / "dependencies.json").read_text())["webview"]
    destination = cache / dependency["revision"]
    if destination.exists():
        # Re-hash the archive, and re-extract it on each build. A modified
        # downloaded source directory must never become an implicit fork.
        shutil.rmtree(destination)
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / (dependency["revision"] + ".tar.gz")
    if not archive.exists():
        with urllib.request.urlopen(dependency["url"], timeout=60) as response, archive.open("wb") as output:
            shutil.copyfileobj(response, output)
    if digest(archive) != dependency["sha256"]:
        raise ValueError("WebView dependency checksum mismatch")
    with tarfile.open(archive) as source:
        source.extractall(cache, filter="data")
    extracted = cache / ("webview-" + dependency["revision"])
    extracted.rename(destination)
    return destination


def tree_files(root):
    files = []
    for directory, dirs, names in os.walk(root, followlinks=False):
        for name in dirs + names:
            item = Path(directory) / name
            if item.is_symlink():
                raise ValueError(f"Symbolic links are not supported inside the application: {item}")
            if not item.is_dir() and not item.is_file():
                raise ValueError(f"Non-regular application file: {item}")
        files.extend(Path(directory) / name for name in names)
    return sorted(files, key=lambda item: item.relative_to(root).as_posix())


def windows_runtime_libraries(binary, compiler):
    """Bundle the native toolchain's non-system DLL closure, or fail the build."""
    def native_path(path):
        if path.startswith("/"):
            cygpath = Path(shutil.which(compiler) or compiler).parent / "cygpath.exe"
            if cygpath.is_file():
                path = capture([cygpath, "-w", path])
        return Path(path)

    objdump = native_path(capture([compiler, "-print-prog-name=objdump"]))
    system = {name + ".dll" for name in [
        "advapi32", "bcrypt", "comctl32", "comdlg32", "crypt32", "d2d1", "d3d11",
        "dcomp", "dbghelp", "dnsapi", "dwmapi", "dxgi", "gdi32", "imm32", "iphlpapi",
        "kernel32", "msvcrt", "ncrypt", "ntdll", "ole32", "oleaut32", "opengl32",
        "psapi", "rpcrt4", "secur32", "setupapi", "shell32", "shcore", "shlwapi",
        "ucrtbase", "user32", "userenv", "usp10", "uxtheme", "version", "winhttp",
        "wininet", "winmm", "winspool", "ws2_32", "wtsapi32"]}
    pending = [binary]
    seen = set()
    while pending:
        executable = pending.pop()
        imports = re.findall(r"DLL Name:\s*(\S+)", capture([objdump, "-p", executable]))
        for name in imports:
            folded = name.lower()
            if folded in seen or folded in system or folded.startswith(("api-ms-", "ext-ms-")):
                continue
            seen.add(folded)
            candidates = [binary.parent / name]
            candidates.extend(native_path(capture([compiler, "-print-file-name=" + relative]))
                              for relative in (name, "../bin/" + name))
            candidates.extend(Path(directory) / name for directory in os.get_exec_path())
            source = next((item.resolve() for item in candidates if item.is_file()), None)
            if source is None:
                raise ValueError(f"Cannot locate required native runtime library {name}")
            destination = binary.parent / name
            if source != destination.resolve():
                shutil.copy2(source, destination)
            pending.append(destination)


def build(args):
    extra_packages = getattr(args, "ocaml_package", [])
    if any(not re.fullmatch(r"[A-Za-z][A-Za-z0-9_.-]*", name) for name in extra_packages):
        raise ValueError("Invalid application OCaml package name")
    packages = ",".join([PACKAGES, *extra_packages])
    config = configuration(args.config)
    target = config["platform"]
    output = args.output.resolve()
    if output.exists():
        raise ValueError(f"Build output already exists: {output}; choose a new output directory")
    frontend = args.frontend.resolve()
    if not (frontend / "index.html").is_file():
        raise ValueError("Frontend must contain a built index.html")
    tree_files(frontend)
    if target.startswith("darwin-") and output.suffix != ".app":
        raise ValueError("macOS build output must end in .app")
    output.parent.mkdir(parents=True, exist_ok=True)
    webview = source_dependency(ROOT / "_build/desktop-dependencies")
    with tempfile.TemporaryDirectory(prefix="lui-desktop-", dir=output.parent) as temporary:
        work = Path(temporary)
        objects = []
        for name in ["lui_command", "lui_desktop_update", "lui_desktop_commands", "lui_desktop"]:
            for suffix in [".mli", ".ml"]:
                directory = ROOT / "src" if name == "lui_command" else SOURCE
                shutil.copy2(directory / (name + suffix), work)
                run(["opam", "exec", "--", "ocamlfind", "ocamlopt", "-O3", "-thread", "-package", packages,
                     "-c", name + suffix], cwd=work)
            objects.append(work / (name + ".cmx"))
        reserved = {"main", "desktop_app", "lui_command", "lui_desktop", "lui_desktop_update", "lui_desktop_commands"}
        for source in args.ocaml_source:
            if source.suffix != ".ml" or source.stem in reserved or not re.fullmatch(r"[a-z][A-Za-z0-9_]*", source.stem):
                raise ValueError(f"Invalid or duplicate application module: {source}")
            reserved.add(source.stem)
            shutil.copy2(source, work / source.name)
            interface = source.with_suffix(".mli")
            if interface.exists():
                shutil.copy2(interface, work / interface.name)
                run(["opam", "exec", "--", "ocamlfind", "ocamlopt", "-O3", "-thread", "-package", packages,
                     "-c", interface.name], cwd=work)
            run(["opam", "exec", "--", "ocamlfind", "ocamlopt", "-O3", "-thread", "-package", packages,
                 "-c", source.name], cwd=work)
            objects.append(work / (source.stem + ".cmx"))
        runner = "Lui_desktop.run"
        if args.commands:
            shutil.copy2(args.commands, work / "desktop_app.ml")
            run(["opam", "exec", "--", "ocamlfind", "ocamlopt", "-O3", "-thread", "-package", packages,
                 "-c", "desktop_app.ml"], cwd=work)
            objects.append(work / "desktop_app.cmx")
            runner = "Lui_desktop.run_with_commands ~commands:Desktop_app.commands"
        embedded = ("let () = " + runner + " ~config:%s ~updater_html:%s ~updater_js:%s\n") % tuple(
            ocaml_string(value) for value in [
                json.dumps(config), (SOURCE / "updater.html").read_text(), (SOURCE / "updater.js").read_text()])
        (work / "main.ml").write_text(embedded)
        include = capture(["opam", "exec", "--", "ocamlc", "-where"])
        compile_flags = []
        link_flags = []
        if target.startswith("darwin-"):
            link_flags = ["-lc++", "-framework", "WebKit", "-framework", "Cocoa"]
        elif target.startswith("linux-"):
            for libs in (["gtk+-3.0", "webkit2gtk-4.1"], ["gtk+-3.0", "webkit2gtk-4.0"]):
                try:
                    compile_flags = shlex.split(capture(["pkg-config", "--cflags", *libs]))
                    link_flags = ["-lstdc++", "-ldl"] + shlex.split(capture(["pkg-config", "--libs", *libs]))
                    break
                except subprocess.CalledProcessError:
                    continue
            else:
                raise ValueError("Linux builds require GTK 3 and WebKitGTK 4.1 (or 4.0) development files")
        elif target.startswith("windows-"):
            if not args.webview2_headers:
                raise ValueError("Windows builds require --webview2-headers pointing to WebView2.h from Microsoft.Web.WebView2 1.0.1150.38")
            compile_flags = ["-I", args.webview2_headers.resolve()]
            link_flags = ["-lstdc++", "-ladvapi32", "-lole32", "-lshell32", "-lshlwapi", "-luser32", "-lversion"]
        stub = work / "webview_stubs.o"
        run([args.cxx, "-std=c++17", "-O2", "-fPIC", "-I", webview / "core/include", "-I", include,
             *compile_flags, "-c", SOURCE / "webview_stubs.cc", "-o", stub])
        reply = work / "lui_desktop_reply.o"
        run([args.cxx, "-std=c++17", "-O2", "-fPIC", "-I", include,
             "-c", SOURCE / "lui_desktop_reply.cc", "-o", reply])
        native_objects = [stub, reply]
        if target.startswith("darwin-"):
            scheme = work / "macos_scheme.o"
            run([args.cxx, "-std=c++17", "-O2", "-fPIC", "-I", include,
                 "-c", SOURCE / "macos_scheme.mm", "-o", scheme])
            native_objects.append(scheme)
        staged = work / "application"
        macos = target.startswith("darwin-")
        binary = staged / ("Contents/MacOS/app" if macos else "app.exe" if target.startswith("windows-") else "app")
        binary.parent.mkdir(parents=True, exist_ok=True)
        linker = []
        for flag in link_flags:
            linker.extend(["-cclib", flag])
        run(["opam", "exec", "--", "ocamlfind", "ocamlopt", "-O3", "-thread", "-package", packages, "-linkpkg",
             *objects, work / "main.ml", *native_objects, *linker, "-o", binary], cwd=work)
        if target.startswith("windows-"):
            windows_runtime_libraries(binary, args.cxx)
        resources = staged / ("Contents/Resources" if macos else ".")
        resources.mkdir(parents=True, exist_ok=True)
        shutil.copytree(frontend, resources / "frontend")
        shutil.copy2(SOURCE / "desktop.css", resources / "frontend/__lui-desktop.css")
        shutil.copy2(webview / "LICENSE", resources / "webview-LICENSE")
        (resources / "lui-desktop.json").write_text(json.dumps(config, indent=2) + "\n")
        if macos:
            (staged / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleExecutable": "app", "CFBundleIdentifier": config["identifier"],
                "CFBundleName": config["name"], "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": config["version"], "CFBundleVersion": str(config["build"]),
                "NSHighResolutionCapable": True, "LSMinimumSystemVersion": "12.0",
                "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
            }))
        staged.rename(output)
    print(output)


def app_config(app):
    candidates = [app / "Contents/Resources/lui-desktop.json", app / "lui-desktop.json"]
    for candidate in candidates:
        if candidate.is_file():
            return json.loads(candidate.read_text())
    raise ValueError(f"Not a built OCaml desktop application: {app}")


def keygen(args):
    if args.private.resolve() == args.public.resolve() or args.private.exists() or args.public.exists():
        raise ValueError("Refusing to overwrite a signing key")
    args.private.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(args.private, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.close(descriptor)
    run(["openssl", "genpkey", "-algorithm", "ED25519", "-out", args.private])
    der = run(["openssl", "pkey", "-in", args.private, "-pubout", "-outform", "DER"], stdout=subprocess.PIPE).stdout
    if len(der) != 44 or der[:12].hex() != "302a300506032b6570032100":
        raise ValueError("Unexpected Ed25519 public key encoding")
    args.public.parent.mkdir(parents=True, exist_ok=True)
    args.public.write_text(der[12:].hex() + "\n")
    print(f"Created private key {args.private} and public key {args.public}")


def write_package(app, destination, previous=None):
    entries = []
    payloads = []
    offset = 0
    for path in tree_files(app):
        relative = path.relative_to(app).as_posix()
        sha256 = digest(path)
        size = path.stat().st_size
        copy = previous is not None and (previous / relative).is_file() and digest(previous / relative) == sha256
        entries.append({"path": relative, "size": size, "sha256": sha256,
                        "mode": 0o755 if path.stat().st_mode & 0o111 else 0o644,
                        "offset": None if copy else offset})
        if not copy:
            payloads.append(path)
            offset += size
    index = json.dumps({"schema": 1, "files": entries}, separators=(",", ":")).encode()
    if len(index) > 8_388_608 or offset + len(index) + 12 > 2_000_000_000:
        raise ValueError("Update package exceeds runtime limits")
    with destination.open("wb") as output:
        output.write(b"LUIUPD1\n" + struct.pack(">I", len(index)) + index)
        for path in payloads:
            with path.open("rb") as source:
                shutil.copyfileobj(source, output)


def release(args):
    app = args.app.resolve()
    config = app_config(app)
    if "updates" not in config:
        raise ValueError("Build the application with updates.url and updates.public_key first")
    https(args.base_url)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    stem = f'{config["slug"]}-{config["version"]}-{config["build"]}-{config["platform"]}'

    def descriptor(path):
        return {"url": args.base_url.rstrip("/") + "/" + path.name,
                "size": path.stat().st_size, "sha256": digest(path)}

    full = output / (stem + ".lui-update")
    if full.exists():
        raise ValueError("Release output already exists")
    write_package(app, full)
    deltas = []
    seen = set()
    for previous in args.previous:
        old = app_config(previous)
        tree_files(previous)
        if (old["identifier"], old["platform"]) != (config["identifier"], config["platform"]):
            raise ValueError("Delta base belongs to another application or platform")
        if old["build"] >= config["build"] or old["build"] in seen:
            raise ValueError("Delta base builds must be unique and lower than the new build")
        seen.add(old["build"])
        delta = output / (stem + f'-from-{old["build"]}.lui-delta')
        write_package(app, delta, previous)
        if delta.stat().st_size < full.stat().st_size:
            deltas.append({"from_build": old["build"], "artifact": descriptor(delta)})
        else:
            delta.unlink()
    payload = json.dumps({"schema": 1, "app_id": config["identifier"], "platform": config["platform"],
                          "version": config["version"], "build": config["build"],
                          "notes": args.notes.read_text() if args.notes else "",
                          "full": descriptor(full), "deltas": deltas}, separators=(",", ":"))
    with tempfile.TemporaryDirectory() as work:
        message = Path(work) / "message"
        signature = Path(work) / "signature"
        message.write_bytes(b"lui desktop update v1\n" + payload.encode())
        run(["openssl", "pkeyutl", "-sign", "-rawin", "-inkey", args.key, "-in", message, "-out", signature])
        der = run(["openssl", "pkey", "-in", args.key, "-pubout", "-outform", "DER"], stdout=subprocess.PIPE).stdout
        if der[12:].hex() != config["updates"]["public_key"]:
            raise ValueError("Signing key does not match the public key embedded in the app")
        envelope = {"payload": payload, "signature": signature.read_bytes().hex()}
    feed = output / f'update-{config["platform"]}.json'
    temporary = feed.with_suffix(".tmp")
    temporary.write_text(json.dumps(envelope) + "\n")
    temporary.replace(feed)
    print(feed)


def notarize(path, profile):
    run(["xcrun", "notarytool", "submit", path, "--keychain-profile", profile, "--wait"])


def package_macos(args, app, config):
    if platform.system() != "Darwin":
        raise ValueError("macOS signing, disk images and notarization require macOS")
    identity = args.identity or "-"
    sign = ["codesign", "--force", "--options", "runtime", "--sign", identity]
    if args.identity:
        sign.append("--timestamp")
    run([*sign, app])
    run(["codesign", "--verify", "--deep", "--strict", app])
    if args.notary_profile:
        if not args.identity:
            raise ValueError("Notarization requires a Developer ID signing identity")
        with tempfile.TemporaryDirectory() as work:
            archive = Path(work) / "app.zip"
            run(["ditto", "-c", "-k", "--keepParent", app, archive])
            notarize(archive, args.notary_profile)
        run(["xcrun", "stapler", "staple", app])
    dmg = args.output / f'{config["slug"]}-{config["version"]}-{config["platform"]}.dmg'
    with tempfile.TemporaryDirectory() as work:
        shutil.copytree(app, Path(work) / app.name)
        (Path(work) / "Applications").symlink_to("/Applications", target_is_directory=True)
        run(["hdiutil", "create", "-volname", config["name"], "-srcfolder", work,
             "-format", "UDZO", dmg])
    run([*sign, dmg])
    if args.notary_profile:
        notarize(dmg, args.notary_profile)
        run(["xcrun", "stapler", "staple", dmg])


def nsis_string(value):
    return str(value).replace("$", "$$").replace('"', '$\\"').replace("\n", "$\\n")


def package_windows(args, app, config):
    if platform.system() != "Windows":
        raise ValueError("Windows installers require the native Windows toolchain")
    def sign(path):
        if args.thumbprint:
            run(["signtool", "sign", "/sha1", args.thumbprint, "/fd", "SHA256", "/tr",
                 "https://timestamp.digicert.com", "/td", "SHA256", path])
            run(["signtool", "verify", "/pa", path])
    installer = args.output / f'{config["slug"]}-{config["version"]}-setup.exe'
    quote = nsis_string
    with tempfile.TemporaryDirectory() as work:
        script = Path(work) / "installer.nsi"
        uninstall = f'''Section "Uninstall"
  Delete "$SMPROGRAMS\\{quote(config['name'])}.lnk"
  DeleteRegKey HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{config['identifier']}"
  RMDir /r "$INSTDIR"
SectionEnd
'''
        generator = Path(work) / "uninstaller.exe"
        generator_script = Path(work) / "uninstaller.nsi"
        generator_script.write_text(f'''Unicode true
RequestExecutionLevel user
SilentInstall silent
OutFile "{quote(generator)}"
InstallDir "$LOCALAPPDATA\\Programs\\{config['slug']}"
UninstPage uninstConfirm
UninstPage instfiles
Function .onInit
  WriteUninstaller "{quote(app / 'uninstall.exe')}"
  IfErrors failed
  SetErrorLevel 0
  Quit
failed:
  SetErrorLevel 1
  Quit
FunctionEnd
Section
SectionEnd
{uninstall}''')
        run(["makensis", generator_script])
        run([generator])
        for file in tree_files(app):
            if file.suffix.lower() in (".exe", ".dll"):
                sign(file)
        script.write_text(f'''
Unicode true
RequestExecutionLevel user
Name "{quote(config['name'])}"
OutFile "{quote(installer)}"
InstallDir "$LOCALAPPDATA\\Programs\\{config['slug']}"
Page directory
Page instfiles
Section
  SetOutPath "$INSTDIR"
  File /r "{quote(app)}\\*"
  CreateShortcut "$SMPROGRAMS\\{quote(config['name'])}.lnk" "$INSTDIR\\app.exe"
  WriteRegStr HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{config['identifier']}" "DisplayName" "{quote(config['name'])}"
  WriteRegStr HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{config['identifier']}" "DisplayVersion" "{config['version']}"
  WriteRegStr HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{config['identifier']}" "UninstallString" '$\\"$INSTDIR\\uninstall.exe$\\"'
SectionEnd
''')
        run(["makensis", script])
    sign(installer)


def package_linux(args, app, config):
    slug = config["slug"]
    version = config["version"]
    architecture = config["platform"].split("-")[1]
    archive = args.output / f'{slug}-{version}-{config["platform"]}.tar.gz'
    with tarfile.open(archive, "w:gz") as output:
        output.add(app, arcname=slug)
    checksum = digest(archive)
    install = args.output / "install.sh"
    download = ""
    if args.base_url:
        https(args.base_url)
        download = f'curl --fail --location --proto "=https" --proto-redir "=https" --output "$archive" --url {shlex.quote(args.base_url.rstrip("/") + "/" + archive.name)}'
    install.write_text(f'''#!/bin/sh
set -eu
destination="$HOME/.local/opt/{slug}"
archive="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/{archive.name}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
if [ ! -f "$archive" ]; then
  archive="$work/{archive.name}"
  {download or 'echo "Place the release archive beside install.sh" >&2; exit 1'}
fi
echo "{checksum}  $archive" | sha256sum --check --status
if [ -e "$destination" ]; then
  echo "Already installed; use the signed updater in the app." >&2; exit 1
fi
tar -xzf "$archive" -C "$work"
mkdir -p "$HOME/.local/opt" "$HOME/.local/bin" "$HOME/.local/share/applications"
mv "$work/{slug}" "$destination"
ln -s "$destination/app" "$HOME/.local/bin/{slug}"
printf '[Desktop Entry]\\nType=Application\\nName=%s\\nExec="%s/app"\\nTerminal=false\\nCategories=Utility;\\n' {shlex.quote(config['name'])} "$destination" > "$HOME/.local/share/applications/{slug}.desktop"
echo "Installed $destination"
''')
    install.chmod(0o755)
    with tempfile.TemporaryDirectory() as work:
        tree = Path(work) / "root"
        installed = tree / "opt" / slug
        shutil.copytree(app, installed)
        (installed / ".lui-package-managed").touch()
        applications = tree / "usr/share/applications"
        applications.mkdir(parents=True)
        (applications / (slug + ".desktop")).write_text(
            f'[Desktop Entry]\nType=Application\nName={config["name"]}\nExec=/opt/{slug}/app\nTerminal=false\nCategories=Utility;\n')
        binary = tree / "usr/bin"
        binary.mkdir(parents=True)
        (binary / slug).symlink_to(f"/opt/{slug}/app")
        if "deb" in args.formats:
            control = tree / "DEBIAN"
            control.mkdir()
            (control / "control").write_text(
                f'Package: {slug}\nVersion: {version.replace("-", "~")}\nArchitecture: {"arm64" if architecture == "arm64" else "amd64"}\n'
                f'Maintainer: {config.get("maintainer", "LUI contributors")}\n'
                'Depends: libgtk-3-0, libwebkit2gtk-4.1-0, curl, ca-certificates\n'
                f'Description: {config.get("description", config["name"])}\n')
            run(["dpkg-deb", "--build", "--root-owner-group", tree, args.output / f'{slug}_{version}_{architecture}.deb'])
            shutil.rmtree(control)
        if "rpm" in args.formats:
            top = Path(work) / "rpm"
            for directory in ["BUILD", "BUILDROOT", "RPMS", "SOURCES", "SPECS", "SRPMS"]:
                (top / directory).mkdir(parents=True)
            source = top / "SOURCES/application.tar.gz"
            with tarfile.open(source, "w:gz") as output:
                output.add(tree, arcname=".")
            spec = top / "SPECS/application.spec"
            spec.write_text(f'''Name: {slug}
Version: {version.replace('-', '~')}
Release: 1
Summary: {config.get('description', config['name']).replace('%', '%%')}
License: {config.get('license', 'MIT').replace('%', '%%')}
Source0: application.tar.gz
Requires: gtk3, webkit2gtk4.1, curl, ca-certificates
%description
{config.get('description', config['name']).replace('%', '%%')}
%install
mkdir -p %{{buildroot}}
tar -xzf %{{SOURCE0}} -C %{{buildroot}}
%files
/opt/{slug}
/usr/bin/{slug}
/usr/share/applications/{slug}.desktop
''')
            run(["rpmbuild", "-bb", "--define", f"_topdir {top}", spec])
            for rpm in (top / "RPMS").rglob("*.rpm"):
                shutil.copy2(rpm, args.output)
    if "pkgbuild" in args.formats:
        pkgbuild = args.output / f"PKGBUILD-{architecture}"
        pkgbuild.write_text(f'''pkgname={slug}
pkgver={shlex.quote(version.replace('-', '_'))}
pkgrel=1
pkgdesc={shlex.quote(config.get('description', config['name']))}
arch=({'aarch64' if architecture == 'arm64' else 'x86_64'})
license=({shlex.quote(config.get('license', 'MIT'))})
depends=('gtk3' 'webkit2gtk-4.1' 'curl' 'ca-certificates')
source=('{archive.name}')
sha256sums=('{checksum}')
package() {{
  install -d "$pkgdir/opt" "$pkgdir/usr/bin" "$pkgdir/usr/share/applications"
  cp -a "$srcdir/{slug}" "$pkgdir/opt/"
  touch "$pkgdir/opt/{slug}/.lui-package-managed"
  ln -s /opt/{slug}/app "$pkgdir/usr/bin/{slug}"
  printf '[Desktop Entry]\\nType=Application\\nName=%s\\nExec=/opt/{slug}/app\\nTerminal=false\\nCategories=Utility;\\n' {shlex.quote(config['name'])} > "$pkgdir/usr/share/applications/{slug}.desktop"
}}
''')


def package(args):
    app = args.app.resolve()
    config = app_config(app)
    tree_files(app)
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    target = config["platform"]
    if target.startswith("darwin-"):
        package_macos(args, app, config)
    elif target.startswith("windows-"):
        package_windows(args, app, config)
    elif target.startswith("linux-"):
        package_linux(args, app, config)
    else:
        raise ValueError("Unsupported platform")
    print(args.output)


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    create = commands.add_parser("build", help="Compile the OCaml host and copy a built Web frontend")
    create.add_argument("--config", type=Path, required=True)
    create.add_argument("--frontend", type=Path, required=True)
    create.add_argument("--output", type=Path, required=True)
    create.add_argument("--cxx", default=os.environ.get("CXX", "c++"))
    create.add_argument("--webview2-headers", type=Path)
    create.add_argument("--commands", type=Path, help="Native OCaml module exporting commands : unit -> binding list")
    create.add_argument("--ocaml-source", type=Path, action="append", default=[], help="Additional shared/native OCaml module, in dependency order")
    create.add_argument("--ocaml-package", action="append", default=[], help="Additional installed findlib application package")
    create.set_defaults(action=build)
    keys = commands.add_parser("keygen", help="Create an Ed25519 signing key outside the repository")
    keys.add_argument("--private", type=Path, required=True)
    keys.add_argument("--public", type=Path, required=True)
    keys.set_defaults(action=keygen)
    packages = commands.add_parser("package", help="Create OS packages; finalize signing before making update feeds")
    packages.add_argument("--app", type=Path, required=True)
    packages.add_argument("--output", type=Path, required=True)
    packages.add_argument("--identity", help="macOS Developer ID identity; defaults to ad hoc signing")
    packages.add_argument("--notary-profile", help="macOS notarytool keychain profile")
    packages.add_argument("--thumbprint", help="Windows certificate thumbprint in the signing certificate store")
    packages.add_argument("--formats", nargs="*", choices=["deb", "rpm", "pkgbuild"], default=["deb", "rpm", "pkgbuild"])
    packages.add_argument("--base-url", help="HTTPS directory for the Linux first-install archive")
    packages.set_defaults(action=package)
    updates = commands.add_parser("release", help="Write signed full/delta updates; does not upload or publish")
    updates.add_argument("--app", type=Path, required=True)
    updates.add_argument("--output", type=Path, required=True)
    updates.add_argument("--key", type=Path, required=True)
    updates.add_argument("--base-url", required=True)
    updates.add_argument("--previous", type=Path, action="append", default=[])
    updates.add_argument("--notes", type=Path)
    updates.set_defaults(action=release)
    return result


if __name__ == "__main__":
    arguments = parser().parse_args()
    try:
        arguments.action(arguments)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"desktop: {error}", file=sys.stderr)
        sys.exit(1)
