#!/usr/bin/env python3
"""Exercise installed macOS release upgrades over authenticated local HTTPS.

The fixture app uses the production OCaml host, WebKit bridge and updater.
Only its application handlers and frontend automation are fixture code.
No system trust, production feed, signing identity or existing install changes.
"""
import argparse
import http.server
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import ssl
import subprocess
import tempfile
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("desktop", ROOT / "tooling/desktop.py")
desktop = importlib.util.module_from_spec(spec)
spec.loader.exec_module(desktop)


def wait_until(test, *, timeout=20, label="condition", tick=None):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if tick:
            tick()
        result = test()
        if result:
            return result
        time.sleep(0.05)
    raise RuntimeError(f"Timed out waiting for {label}")


def events(path):
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line]


def app_processes(executable):
    output = subprocess.check_output(["ps", "-axo", "pid=,command="], text=True)
    return {int(parts[0]): parts[1] for line in output.splitlines()
            if len(parts := line.strip().split(None, 1)) == 2
            and (parts[1] == str(executable) or parts[1].startswith(str(executable) + " "))}


def tree_hashes(app):
    return {path.relative_to(app).as_posix(): desktop.digest(path) for path in desktop.tree_files(app)}


NATIVE_COMMANDS = r'''
module C = Lui_command
let command name request response =
  C.v ~name:(Result.get_ok (C.Name.of_string name)) ~request ~response
let commands () =
  let output = Sys.getenv "LUI_QUALIFY_EVENTS" in
  let mutex = Mutex.create () in
  let record fields =
    Mutex.lock mutex;
    Fun.protect ~finally:(fun () -> Mutex.unlock mutex) (fun () ->
      let channel = open_out_gen [Open_wronly; Open_creat; Open_append; Open_text] 0o600 output in
      Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
        output_string channel (Yojson.Basic.to_string (`Assoc (
          ["pid", `Int (Unix.getpid ()); "build", `Int BUILD] @ fields)) ^ "\n")))
  in
  record ["event", `String "native_start"];
  let gate = Mutex.create () and changed = Condition.create () in
  let released = ref false in
  [ Lui_desktop_commands.handle (command "test.report" C.Codec.string C.Codec.unit)
      (fun payload -> record ["event", `String "page"; "payload", Yojson.Basic.from_string payload]; Ok ())
  ; Lui_desktop_commands.handle (command "test.begin" C.Codec.unit C.Codec.bool)
      (fun () -> let marker = output ^ ".begun" in
        if Sys.file_exists marker then Ok false else (
          let channel = open_out marker in close_out channel; Ok true))
  ; Lui_desktop_commands.handle (command "test.echo" C.Codec.string C.Codec.string)
      (fun payload -> Ok (payload ^ " native:" ^ string_of_int BUILD))
  ; Lui_desktop_commands.handle (command "test.number" C.Codec.int32 C.Codec.int32) (fun value -> Ok value)
  ; Lui_desktop_commands.handle (command "test.fail" C.Codec.unit C.Codec.unit)
      (fun () -> Error (C.error Command_failed "fixture refusal"))
  ; Lui_desktop_commands.handle (command "test.throw" C.Codec.unit C.Codec.unit)
      (fun () -> failwith "private fixture details")
  ; Lui_desktop_commands.handle (command "test.wait" C.Codec.unit C.Codec.unit)
      (fun () -> Mutex.lock gate; while not !released do Condition.wait changed gate done;
        Mutex.unlock gate; Ok ())
  ; Lui_desktop_commands.handle (command "test.release" C.Codec.unit C.Codec.unit)
      (fun () -> Mutex.lock gate; released := true; Condition.broadcast changed;
        Mutex.unlock gate; Ok ())
  ]
'''

FRONTEND = r'''
"use strict";
const build = BUILD;
const broken = BROKEN;
if (broken) document.getElementById("app").setAttribute("data-error", "true");
window.addEventListener("load", async () => {
  const invoke = (name,payload="") => window.luiDesktop.invoke(name,payload);
  const report = payload => invoke("test.report",JSON.stringify(payload));
  const assert = (condition,message) => {if(!condition)throw new Error(message);};
  try {
    await report({event:"loaded",build,broken,origin:location.href});
    if (build === 1 && await invoke("test.begin") === "true") {
      const text = "Unicode 中文 … \" \\ \n";
      assert(await invoke("test.echo",text) === text+" native:1", "Unicode RPC mismatch");
      for (const [name,payload,code] of [["test.missing","","unknown_command"],
          ["test.number","bad","invalid_arguments"],["test.fail","","command_failed"],
          ["test.throw","","internal_error"]]) {
        let refused=false;
        try { await invoke(name,payload); } catch(error) {
          assert(error.code===code,"Wrong RPC error: "+error.code);
          assert(!error.message.includes("private fixture"),"Leaked handler exception"); refused=true;
        }
        assert(refused,"Invalid command succeeded");
      }
      let finished=false;
      const blocked=invoke("test.wait").then(()=>{finished=true;});
      await window.luiDesktop.request("state");
      assert(!finished,"Native handler blocked the UI thread");
      await invoke("test.release"); await blocked;
      await report({event:"commands_passed"});
      await window.luiDesktop.checkForUpdates();
    }
  } catch(error) { await report({event:"failure",message:error.message}); }
});
'''

UPDATER_DRIVER = r'''
// Fixture automation drives the unchanged update controls through their events.
(async () => {
  const deadline=Date.now()+20000;
  async function until(statuses) {
    while(Date.now()<deadline) {
      const state=await window.luiDesktop.request("state");
      if(statuses.includes(state.status))return state;
      await new Promise(resolve=>setTimeout(resolve,50));
    }
    throw new Error("Updater did not reach the expected state");
  }
  const found=await until(["available","error"]);
  if(found.status==="error") { await window.__lui_later(); return; }
  await refresh();
  if(element("install").hidden || element("install").disabled) throw new Error("Install action unavailable");
  element("install").click();
  const prepared=await until(["ready","error"]);
  if(prepared.status==="error")throw new Error(prepared.message);
  await refresh();
  if(element("restart").hidden || element("restart").disabled) throw new Error("Restart action unavailable");
  element("restart").click();
})().catch(error=>{document.getElementById("message").textContent="Fixture failure: "+error.message;});
'''


def qualify(output):
    if platform.system() != "Darwin":
        raise RuntimeError("This qualification requires macOS")
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    identity = "dev.lui.qualification.q" + uuid.uuid4().hex[:12]
    storage = Path.home() / "Library/Application Support" / identity
    source = output / "host-source"
    shutil.copytree(desktop.SOURCE, source)
    updater = source / "updater.js"
    updater.write_text(updater.read_text() + "\n" + UPDATER_DRIVER)
    desktop.SOURCE = source
    logs = []
    active_directory = {"path": output}

    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=str(active_directory["path"]), **kwargs)

        def do_GET(self):
            logs.append(self.path)
            super().do_GET()

        def log_message(self, *_args):
            pass

    cert = output / "localhost.crt"
    key = output / "localhost.key"
    desktop.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                 "-subj", "/CN=127.0.0.1", "-addext", "subjectAltName=IP:127.0.0.1",
                 "-keyout", key, "-out", cert], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    key.chmod(0o600)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base_url = f"https://127.0.0.1:{server.server_port}"
    signing = argparse.Namespace(private=output / "update.pem", public=output / "update.pub")
    desktop.keygen(signing)
    report = {"platform": desktop.host_target(), "cases": [], "native_source_sha256": {}}
    for name in ["lui_desktop.ml", "lui_desktop_update.ml", "lui_desktop_commands.ml", "macos_scheme.mm", "lui_desktop_reply.cc"]:
        report["native_source_sha256"][name] = desktop.digest(source / name)
    apps = {}
    try:
        for label, build, broken in [("v1", 1, False), ("v2", 2, False), ("broken-v2", 2, True)]:
            directory = output / label
            frontend = directory / "frontend"
            frontend.mkdir(parents=True)
            (frontend / "index.html").write_text('<!doctype html><html><head><meta charset="utf-8"><title>LUI Upgrade Fixture</title></head><body><main id="app">Upgrade fixture</main><script src="./app.js"></script></body></html>')
            (frontend / "app.js").write_text(FRONTEND.replace("BUILD", str(build)).replace("BROKEN", str(broken).lower()))
            (frontend / "unchanged.data").write_bytes(b"Retained application resource\n" * 120000)
            (frontend / ("removed.txt" if build == 1 else "added.txt")).write_text(label)
            native = directory / "commands.ml"
            native.write_text(NATIVE_COMMANDS.replace("BUILD", str(build)))
            config = directory / "config.json"
            config.write_text(json.dumps({"name": "LUI Upgrade Fixture", "slug": "lui-upgrade-fixture",
                "identifier": identity, "version": "1.0.0" if build == 1 else "1.1.0", "build": build,
                "updates": {"url": base_url + "/update-" + desktop.host_target() + ".json",
                            "public_key": signing.public.read_text().strip()}}))
            app = directory / "Fixture.app"
            desktop.build(argparse.Namespace(config=config, frontend=frontend, output=app, cxx="c++",
                webview2_headers=None, commands=native, ocaml_source=[]))
            desktop.run(["codesign", "--force", "--options", "runtime", "--sign", "-", app])
            desktop.run(["codesign", "--verify", "--deep", "--strict", app])
            apps[label] = app
        package_output = output / "initial-package"
        package_output.mkdir()
        desktop.package_macos(argparse.Namespace(output=package_output, identity=None, notary_profile=None),
                              apps["v1"], desktop.app_config(apps["v1"]))
        image = next(package_output.glob("*.dmg"))
        with tempfile.TemporaryDirectory(prefix="lui-installed-qualification-") as installed:
            installed = Path(installed).resolve()
            target = installed / "Applications/Fixture.app"
            target.parent.mkdir()
            executable = target / "Contents/MacOS/app"
            mount = installed / "volume"
            desktop.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, image],
                        stdout=subprocess.DEVNULL)
            try:
                desktop.run(["ditto", mount / "Fixture.app", target])
            finally:
                desktop.run(["hdiutil", "detach", mount], stdout=subprocess.DEVNULL)
            initial = installed / "initial.app"
            shutil.copytree(target, initial)
            storage.mkdir(parents=True, exist_ok=True)
            sentinel = storage / "user-note.txt"
            sentinel.write_text("preserve this user data")
            for case in ["full", "delta", "damaged-delta", "invalid-signature", "failed-start"]:
                print("Qualifying " + case, flush=True)
                if target.exists():
                    shutil.rmtree(target)
                shutil.copytree(initial, target)
                release = output / ("release-" + case)
                selected = apps["broken-v2"] if case == "failed-start" else apps["v2"]
                desktop.release(argparse.Namespace(app=selected, output=release, key=signing.private,
                    base_url=base_url, previous=[] if case == "full" else [apps["v1"]], notes=None))
                if case == "damaged-delta":
                    delta = next(release.glob("*.lui-delta"))
                    with delta.open("r+b") as stream:
                        stream.seek(-1, 2)
                        value = stream.read(1)
                        stream.seek(-1, 2)
                        stream.write(bytes([value[0] ^ 1]))
                if case == "invalid-signature":
                    feed = release / ("update-" + desktop.host_target() + ".json")
                    envelope = json.loads(feed.read_text())
                    envelope["signature"] = "00" * 64
                    feed.write_text(json.dumps(envelope))
                active_directory["path"] = release
                logs.clear()
                event_file = output / (case + ".events.jsonl")
                environment = os.environ.copy()
                environment["CURL_CA_BUNDLE"] = str(cert)
                environment["LUI_QUALIFY_EVENTS"] = str(event_file)
                native_log = (output / (case + ".native.log")).open("w")
                process = subprocess.Popen([executable], cwd=installed, env=environment,
                                            stdout=native_log, stderr=native_log)
                tick = lambda: process.poll()
                try:
                    def commands_finished():
                        recorded = events(event_file)
                        failures = [event for event in recorded if event.get("payload", {}).get("event") == "failure"]
                        if failures:
                            raise RuntimeError("Frontend command assertion failed: " + json.dumps(failures))
                        return any(event.get("payload", {}).get("event") == "commands_passed" for event in recorded)

                    wait_until(commands_finished, label="real WebKit command round trips", tick=tick)
                    if case == "invalid-signature":
                        wait_until(lambda: any(".json" in path for path in logs), label="signed feed request", tick=tick)
                        wait_until(lambda: not any("--lui-updater" in command for command in app_processes(executable).values()),
                                   label="refused-update window closure", tick=tick)
                        if process.poll() is not None or tree_hashes(target) != tree_hashes(initial):
                            raise RuntimeError("A rejected signature changed the installed application")
                        if any(".lui-update" in path or ".lui-delta" in path for path in logs):
                            raise RuntimeError("Unauthenticated artifacts were downloaded")
                    else:
                        expected = [1, 2, 1] if case == "failed-start" else [1, 2]
                        wait_until(lambda: [event["build"] for event in events(event_file)
                                   if event.get("event") == "native_start"] == expected,
                                   timeout=50, label="replacement/rollback application startup", tick=tick)
                        expected_app = initial if case == "failed-start" else selected
                        wait_until(lambda: not Path(str(target) + ".lui-previous").exists(),
                                   label="startup acknowledgement and previous-tree settlement", tick=tick)
                        if tree_hashes(target) != tree_hashes(expected_app):
                            raise RuntimeError("Installed tree differs from the finalized application")
                        desktop.run(["codesign", "--verify", "--deep", "--strict", target])
                        if case == "delta" and any(".lui-update" in path for path in logs):
                            raise RuntimeError("Valid delta unexpectedly fell back to a full package")
                        if case == "damaged-delta" and not all(any(extension in path for path in logs)
                                                               for extension in [".lui-delta", ".lui-update"]):
                            raise RuntimeError("Damaged delta did not fall back to the authenticated full package")
                    if sentinel.read_text() != "preserve this user data":
                        raise RuntimeError("User data changed during replacement")
                    failures = [event for event in events(event_file) if event.get("payload", {}).get("event") == "failure"]
                    if failures:
                        raise RuntimeError("Frontend command assertion failed: " + json.dumps(failures))
                    report["cases"].append({"case": case, "passed": True, "requests": list(logs),
                        "native_builds": [event["build"] for event in events(event_file) if event.get("event") == "native_start"]})
                    (output / "report.json").write_text(json.dumps(report, indent=2))
                finally:
                    for pid in app_processes(executable):
                        try:
                            os.kill(pid, signal.SIGTERM)
                        except ProcessLookupError:
                            pass
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                    native_log.close()
        print(json.dumps(report, indent=2), flush=True)
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
        if storage.exists():
            shutil.rmtree(storage)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    qualify(parser.parse_args().output)
