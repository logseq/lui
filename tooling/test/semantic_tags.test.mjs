import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));

test('semantic tag constructor types agree with every canonical kind/tag pair', () => {
  const protocol = readFileSync(join(root, 'src/lui_protocol.ml'), 'utf8');
  const signature = readFileSync(join(root, 'src/lui_elements.mli'), 'utf8');
  const predicate = protocol.slice(protocol.indexOf('let element_tag_supported '),
    protocol.indexOf('let element_tag_known '));
  const vocabulary = signature.match(/type element_tag =\s*\[([\s\S]*?)\]/);
  assert.ok(vocabulary, 'full raw tag vocabulary remains public');
  const tags = [...vocabulary[1].matchAll(/`(\w+)/g)].map(([, tag]) => tag);
  const families = [...predicate.matchAll(/\| (\w+) ->\s*List.mem tag\s*\[([^\]]*)\]/g)]
    .map(([, kind, values]) => [kind.toLowerCase(), [...values.matchAll(/"([^"]+)"/g)].map(([, value]) => value)]);
  assert.equal(families.length, 6, 'every semantic-tag constructor is covered');
  const dir = mkdtempSync(join(tmpdir(), 'lui-semantic-tags-'));
  const run = args => spawnSync('opam', ['exec', '--', ...args], { cwd: root, encoding: 'utf8' });
  const success = args => {
    const result = run(args);
    assert.equal(result.status, 0, result.stdout + result.stderr);
  };
  try {
    success(['dune', 'build', 'ppx/lui_ppx.cmxa', 'src/lui.cmxa']);
    writeFileSync(join(dir, 'driver.ml'), 'let () = Ppxlib.Driver.standalone ()\n');
    success(['ocamlfind', 'ocamlopt', '-package', 'ppxlib', '-linkpkg', '-linkall',
      '_build/default/ppx/lui_ppx.cmxa', join(dir, 'driver.ml'), '-o', join(dir, 'driver')]);
    const compile = source => {
      writeFileSync(join(dir, 'probe.ml'), `open Lui_elements\n${source}\n`);
      return run(['ocamlfind', 'ocamlc', '-package', 'ocaml-signal', '-c',
        '-ppx', `${join(dir, 'driver')} --as-ppx`,
        '-I', '_build/default/src/.lui.objs/byte', join(dir, 'probe.ml')]);
    };
    for (const [kind, accepted] of families) {
      for (const prefix of ['', 'Lui_elements.']) {
        for (const tag of tags) {
          const expression = `${prefix}${kind} ~as_:\`${tag} []`;
          const result = compile(`let probe = ${expression}`);
          if (accepted.includes(tag.toLowerCase())) {
            assert.equal(result.status, 0, `${expression}\n${result.stderr}`);
          } else {
            assert.notEqual(result.status, 0, `${expression} unexpectedly compiled`);
            assert.match(result.stderr, /Error:.*type/s, result.stderr);
            assert.match(result.stderr, /variant|tag/i, result.stderr);
            assert.doesNotMatch(result.stderr, /LUI nesting:/, 'OCaml rejects the argument type');
          }
        }
      }
      const valid = tags.find(tag => accepted.includes(tag.toLowerCase()));
      const invalid = tags.find(tag => !accepted.includes(tag.toLowerCase()));
      for (const source of [
        `let alias = Lui_elements.${kind}\nlet probe = alias ~as_:\`${valid} []`,
        `let wrap ?as_ children = Lui_elements.${kind} ?as_ children\nlet probe = wrap ~as_:\`${valid} []`,
        `let tag : ${kind}_tag = \`${valid}\nlet probe = ${kind} ~as_:tag []`,
        `let probe (source : bool Signal.signal) = reactive (fun _ -> ${kind} ~as_:\`${valid} []) source`,
      ]) {
        const result = compile(source);
        assert.equal(result.status, 0, `${source}\n${result.stderr}`);
      }
      for (const source of [
        `let alias = Lui_elements.${kind}\nlet probe = alias ~as_:\`${invalid} []`,
        `let wrap ?as_ children = Lui_elements.${kind} ?as_ children\nlet probe = wrap ~as_:\`${invalid} []`,
        `let tag : element_tag = \`${valid}\nlet probe = ${kind} ~as_:tag []`,
      ]) {
        const result = compile(source);
        assert.notEqual(result.status, 0, `${source} unexpectedly compiled`);
        assert.match(result.stderr, /Error:.*type/s, result.stderr);
      }
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
