#!/usr/bin/env python3
"""Qualify production JNI with real JVM/OCaml libraries, including optional ABI loading.

Pass the directory produced by tooling/test/build_bounded_virtual_fixture.sh.
All compiled fixtures live in a TemporaryDirectory outside the source tree.
This is a native API test; Compose and OS keyboard tests are separate qualifiers.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]


class Runtime:
    def __init__(self, java, classes, library):
        self.process = subprocess.Popen(
            [str(java), "-cp", str(classes), "dev.lui.LuiBridge", str(library)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
        )
        self.nodes = {}
        self.version = None
        assert self.receive() == 1

    def receive(self, snapshot=False):
        while True:
            line = self.process.stdout.readline()
            assert line, f"JVM exited unexpectedly: {self.process.poll()}"
            if line.startswith("VERSION "):
                self.version = int(line[8:])
            elif line.startswith("PATCH "):
                batch = json.loads(line[6:])
                if snapshot:
                    self.nodes = {}
                for op in batch["ops"]:
                    self.apply(op)
            elif line.startswith("RESULT "):
                return int(line[7:])

    def apply(self, op):
        kind = op["op"]
        if kind == "create-node":
            self.nodes[op["id"]] = {"kind": op["kind"], "props": {}, "children": []}
        elif kind == "set-prop":
            self.nodes[op["id"]]["props"][op["property"]] = op["value"]
        elif kind == "remove-prop":
            self.nodes[op["id"]]["props"].pop(op["property"], None)
        elif kind in ("insert-child", "move-child"):
            children = self.nodes[op["parent"]]["children"]
            if kind == "move-child":
                children.remove(op["child"])
            children.insert(op["index"], op["child"])
        elif kind == "remove-child":
            self.nodes[op["parent"]]["children"].remove(op["child"])
        elif kind == "drop-node":
            self.nodes.pop(op["id"])
        elif kind == "detach-subtree":
            target = op["id"]
            for node in self.nodes.values():
                if target in node["children"]:
                    node["children"].remove(target)
            def drop(node_id):
                for child in self.nodes[node_id]["children"]:
                    drop(child)
                self.nodes.pop(node_id)
            drop(target)
        else:
            raise AssertionError(f"unexpected operation {kind}")

    def call(self, command, snapshot=False):
        self.process.stdin.write(command + "\n")
        self.process.stdin.flush()
        return self.receive(snapshot)

    def named(self, name):
        return next(node_id for node_id, node in self.nodes.items()
                    if node["props"].get("accessibility-identifier") == name)

    def close(self):
        try:
            assert self.call("stop") == 1
            self.process.stdin.close()
            assert self.process.wait(timeout=10) == 0
        finally:
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait()


def run(fixture):
    jdk = Path(os.environ["JAVA_HOME"])
    ocaml = Path(subprocess.check_output(["opam", "var", "lib"], text=True).strip()) / "ocaml"
    darwin = sys.platform == "darwin"
    suffix = "dylib" if darwin else "so"
    shared = ["-dynamiclib"] if darwin else ["-shared", "-fPIC"]
    system_libraries = [] if darwin else ["-pthread", "-lm", "-ldl"]
    java_source = ROOT / "platform/android/lui/src/test/native/LuiBridge.java"
    jni_source = ROOT / "platform/android/lui/src/main/cpp/lui_jni_bridge.c"
    with tempfile.TemporaryDirectory(prefix="lui-real-jni-") as directory:
        output = Path(directory)
        subprocess.run([str(jdk / "bin/javac"), "-d", str(output), str(java_source)], check=True)
        for marker in (False, True):
            name = "current" if marker else "legacy"
            component = output / f"liblui_component_{name}.{suffix}"
            component_inputs = [str(fixture / "bounded_virtual_complete.o"), str(ocaml / "libthreadsnat.a")]
            if marker:
                component_inputs.append(str(fixture / "lui_ocaml_bridge.o"))
            subprocess.run(["cc", *shared, *component_inputs, *system_libraries, "-o", str(component)], check=True)
            library = output / f"liblui_jni_{name}.{suffix}"
            linker = ["-Wl,-undefined,dynamic_lookup"] if darwin else [f"-Wl,-rpath,{output}"]
            subprocess.run(["cc", *shared, "-Werror", f"-I{jdk / 'include'}",
                            f"-I{jdk / 'include' / ('darwin' if darwin else 'linux')}",
                            f"-I{ocaml}", str(jni_source), str(component), *linker, *system_libraries,
                            "-o", str(library)], check=True)
            runtime = Runtime(jdk / "bin/java", output, library)
            try:
                assert runtime.version == (1 if marker else 0)
                list_id = runtime.named("sparse-list")
                props = runtime.nodes[list_id]["props"]
                assert ("virtual-total-count" in props) == marker
                if not marker:
                    print("PASS: new JNI loads component without capability marker and uses eager Kotlin profile")
                    continue
                assert runtime.call(f"press {runtime.named('sparse-load')}") == 1
                props = runtime.nodes[list_id]["props"]
                generation = props["virtual-generation"]
                assert props["virtual-total-count"] == 100000
                assert len(runtime.nodes) < 150
                assert runtime.call(f"window {list_id} {generation} 0 8") == 1
                row = runtime.nodes[list_id]["children"][2]
                assert runtime.call(f"window {list_id} {generation} 99990 100000 {row}") == 1
                assert row in runtime.nodes[list_id]["children"]
                assert len(runtime.nodes) < 150
                assert runtime.call(f"press {runtime.named('sparse-reorder')}") == 1
                new_generation = runtime.nodes[list_id]["props"]["virtual-generation"]
                assert new_generation > generation
                assert runtime.call(f"window {list_id} {generation} 0 8") == 1
                assert runtime.nodes[list_id]["props"]["virtual-generation"] == new_generation
                assert runtime.call(f"window {list_id} {new_generation} 99990 100000 {row}") == 1
                indices = json.loads(runtime.nodes[list_id]["props"]["virtual-indices"])
                children = runtime.nodes[list_id]["children"]
                assert indices[children.index(row)] == 99999
                for command in (
                    "null", f"window -1 1 0 1", f"window {list_id} 0 0 1",
                    f"window {list_id} {new_generation} -1 1", f"window {list_id} {new_generation} 2 1",
                    f"window {list_id} {new_generation} 0 1 0", f"window {list_id} {new_generation} 0 1 -1",
                    f"window {list_id} {new_generation} 0 1 9223372036854775807",
                    f"window {list_id} 9223372036854775807 0 1",
                ):
                    assert runtime.call(command) == 0, command
                assert runtime.call("resync", snapshot=True) == 1
                assert len(runtime.nodes) < 150
                assert runtime.call(f"press {runtime.named('sparse-clear')}") == 1
                assert runtime.nodes[list_id]["props"]["virtual-total-count"] == 0
                assert runtime.nodes[list_id]["children"] == []
                assert len(runtime.nodes) < 30
                print("PASS: real JNI/OCaml 100000-row load, bounded windows, far pin, reorder identity, stale generation, invalid arrays, resync and clear")
            finally:
                runtime.close()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: test_native_virtual_rows.py NATIVE_FIXTURE_DIRECTORY")
    run(Path(sys.argv[1]).resolve())
