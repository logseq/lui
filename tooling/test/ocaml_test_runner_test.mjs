import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const makefile = resolve(dirname(fileURLToPath(import.meta.url)), '../../Makefile');

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'lui-test-runner-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const write = (path, body) => {
    const destination = join(root, path);
    mkdirSync(dirname(destination), { recursive: true });
    writeFileSync(destination, body);
  };
  write('dune-project', '(lang dune 3.17)\n');
  const run = () => spawnSync('make', ['--no-print-directory', '-f', makefile, 'test-ocaml'], {
    cwd: root,
    env: { ...process.env, DUNE_JOBS: '2' },
    encoding: 'utf8',
    timeout: 60_000,
  });
  const build = (targets) => {
    const result = spawnSync('opam', ['exec', '--', 'dune', 'build', ...targets], {
      cwd: root,
      encoding: 'utf8',
      timeout: 60_000,
    });
    assert.equal(result.status, 0, result.stderr || result.stdout);
  };
  return { root, write, run, build };
}

test('OCaml test processes run separately so performance budgets do not compete', (t) => {
  const { root, write, run, build } = fixture(t);
  write('test/dune', '(tests (names first second) (libraries unix))\n');
  const program = (name) => `
let () =
  let marker = ${JSON.stringify(join(root, 'running'))} in
  Unix.mkdir marker 0o700;
  Fun.protect ~finally:(fun () -> Unix.rmdir marker)
    (fun () ->
      let channel = open_out (marker ^ ".${name}") in
      close_out channel;
      Unix.sleepf 1.)
`;
  write('test/first.ml', program('first'));
  write('test/second.ml', program('second'));
  build(['test/first.exe', 'test/second.exe']);
  const result = run();
  assert.equal(result.status, 0, result.stderr || result.stdout);
});
