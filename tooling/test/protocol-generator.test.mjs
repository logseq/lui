import assert from "node:assert/strict";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import test from "node:test";

const root = resolve(import.meta.dirname, "../..");

test("protocol generation works with a local switch and no global switch", () => {
  const directory = realpathSync(mkdtempSync(resolve(tmpdir(), "lui-local-switch-")));
  const repo = resolve(directory, "repo");
  const opamRoot = resolve(directory, "opam");
  try {
    mkdirSync(opamRoot);
    writeFileSync(resolve(opamRoot, "config"), `opam-version: "2.0"\nrepositories: []\ninstalled-switches: [${JSON.stringify(repo)}]\n`);
    for (const file of ["tooling/generate_gpui_protocol_rules.mjs", "schema/components.json", "src/lui_protocol.ml", "platform/gpui/crates/lui-core/src/protocol_rules.rs"]) {
      mkdirSync(resolve(repo, file, ".."), { recursive: true });
      cpSync(resolve(root, file), resolve(repo, file));
    }
    const prefix = execFileSync("opam", ["var", "prefix"], { cwd: root, encoding: "utf8" }).trim();
    const switchState = resolve(repo, "_opam/.opam-switch");
    mkdirSync(switchState, { recursive: true });
    for (const file of ["config", "switch-state", "environment"]) {
      cpSync(resolve(prefix, ".opam-switch", file), resolve(switchState, file), { recursive: true });
    }
    writeFileSync(resolve(switchState, "switch-config"), readFileSync(resolve(prefix, ".opam-switch/switch-config"), "utf8")
      .replace(/^opam-root:.*$/m, `opam-root: ${JSON.stringify(opamRoot)}`));
    for (const directory of ["bin", "lib"]) symlinkSync(resolve(prefix, directory), resolve(repo, "_opam", directory), "dir");
    symlinkSync(resolve(prefix, ".opam-switch/packages"), resolve(switchState, "packages"), "dir");
    const env = { ...process.env, OPAMROOT: opamRoot };
    delete env.OPAMSWITCH;
    delete env.OPAM_SWITCH_PREFIX;
    const available = spawnSync("opam", ["exec", "--", "ocamlc", "-version"], { cwd: repo, env, encoding: "utf8" });
    assert.equal(available.status, 0, available.stderr);
    const result = spawnSync(process.execPath, ["tooling/generate_gpui_protocol_rules.mjs", "--check"], { cwd: repo, env, encoding: "utf8" });
    assert.equal(result.status, 0, result.stdout + result.stderr);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
