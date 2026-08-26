import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repository = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const generator = join(repository, 'tooling/generate_component_schema.mjs');

function runGenerator(arguments_) {
  return spawnSync(process.execPath, [generator, ...arguments_], {
    cwd: repository,
    encoding: 'utf8',
  });
}

test('committed protocol artifacts match the canonical component schema', () => {
  const result = runGenerator(['--check']);
  assert.equal(result.status, 0, result.stderr || result.stdout);
});

test('schema summary preserves the pinned public API boundary', () => {
  const result = runGenerator(['--summary']);
  assert.equal(result.status, 0, result.stderr || result.stdout);

  const summary = JSON.parse(result.stdout);
  assert.equal(
    summary.referenceRevision,
    '4e015e925fc9974e2ab92840d6f8bb5a8f201c2d',
  );
  assert.deepEqual(summary.excluded, [
    'chart',
    'code',
    'markdown',
    'series',
    'span',
  ]);
  assert.ok(summary.supported.includes('button'));
  assert.ok(summary.supported.includes('toggle-button'));
  assert.ok(summary.supported.includes('toggle'));
  assert.ok(summary.supported.includes('radio-group'));
  assert.ok(summary.supported.includes('radio'));
  assert.ok(summary.supported.includes('slider'));
  assert.ok(summary.supported.includes('progress'));
  assert.ok(summary.supported.includes('text-field'));
  assert.ok(summary.supported.includes('secure-field'));
  assert.ok(summary.supported.includes('input'));
  assert.ok(summary.supported.includes('search-field'));
  assert.ok(summary.supported.includes('select'));
  assert.ok(summary.supported.includes('combobox'));
  assert.ok(summary.supported.includes('dropdown-menu'));
  assert.ok(summary.supported.includes('menu-item'));
  assert.ok(summary.supported.includes('list-item'));
  assert.ok(summary.supported.includes('avatar'));
  assert.ok(summary.supported.includes('image'));
  assert.ok(summary.supported.includes('media-surface'));
  assert.ok(summary.supported.includes('stepper'));
  assert.ok(summary.supported.includes('step'));
  assert.ok(summary.supported.includes('timeline'));
  assert.ok(summary.supported.includes('timeline-item'));
  assert.ok(summary.supported.includes('input-group'));
  assert.ok(summary.supported.includes('input-group-actions'));
  assert.ok(summary.supported.includes('tabs'));
  assert.ok(summary.supported.includes('button-group'));
  assert.ok(summary.supported.includes('toggle-group'));
  assert.ok(summary.supported.includes('breadcrumb'));
  assert.ok(summary.supported.includes('pagination'));
  assert.ok(summary.supported.includes('dialog'));
  assert.ok(summary.supported.includes('drawer'));
  assert.ok(summary.supported.includes('sheet'));
  assert.ok(summary.supported.includes('tooltip'));
  assert.ok(summary.supported.includes('toast'));
  assert.ok(summary.supported.includes('toolbar'));
  assert.ok(summary.supported.includes('accordion'));
  assert.ok(summary.supported.includes('table'));
  assert.ok(summary.supported.includes('table-row'));
  assert.ok(summary.supported.includes('table-cell'));
  assert.ok(summary.supported.includes('tree'));
  assert.ok(summary.supported.includes('resizable'));
  assert.ok(summary.supported.includes('split'));
  assert.ok(summary.supported.includes('context-menu'));
  assert.ok(summary.supported.includes('alert'));
  assert.ok(summary.supported.includes('bubble'));
  assert.ok(summary.supported.includes('reactions'));
  assert.ok(summary.supported.includes('status-bar'));
  assert.ok(summary.supported.includes('textarea'));
  assert.ok(!summary.pending.includes('dialog'));
  assert.ok(!summary.pending.includes('drawer'));
  assert.ok(!summary.pending.includes('sheet'));
  assert.ok(!summary.pending.includes('tooltip'));
  assert.ok(!summary.pending.includes('toast'));
  assert.ok(!summary.pending.includes('toolbar'));
  assert.ok(!summary.pending.includes('accordion'));
  assert.ok(!summary.pending.includes('table'));
  assert.ok(!summary.pending.includes('table-row'));
  assert.ok(!summary.pending.includes('table-cell'));
  assert.ok(!summary.pending.includes('tree'));
  assert.ok(!summary.pending.includes('resizable'));
  assert.ok(!summary.pending.includes('split'));
  assert.ok(!summary.pending.includes('context-menu'));
  assert.ok(!summary.pending.includes('alert'));
  assert.ok(!summary.pending.includes('bubble'));
  assert.ok(!summary.pending.includes('reactions'));
  assert.ok(!summary.pending.includes('status-bar'));
  assert.ok(!summary.pending.includes('image'));
  assert.ok(!summary.pending.includes('media-surface'));
  assert.ok(!summary.pending.includes('stepper'));
  assert.ok(!summary.pending.includes('step'));
  assert.ok(!summary.pending.includes('timeline'));
  assert.ok(!summary.pending.includes('timeline-item'));
  assert.ok(!summary.pending.includes('input-group'));
  assert.ok(!summary.pending.includes('input-group-actions'));
});

test('schema reserves one internal transparent root node', () => {
  const schema = JSON.parse(
    readFileSync(join(repository, 'schema/components.json'), 'utf8'),
  );
  const root = schema.nodeKinds.find((kind) => kind.wire === 'root');

  assert.deepEqual(root, {
    lg: 'Root',
    wire: 'root',
    dart: 'root',
    swift: 'root',
    container: true,
  });
  assert.ok(
    !schema.publicElements.some((element) => element.name === 'root'),
    'the runtime root must not become an authorable UI element',
  );
});

test('schema validation rejects duplicate wire names before generation', () => {
  const directory = mkdtempSync(join(tmpdir(), 'lui-component-schema-'));
  const manifest = join(directory, 'duplicate.json');
  writeFileSync(
    manifest,
    JSON.stringify({
      schemaVersion: 1,
      reference: { revision: 'test', excluded: [] },
      publicElements: [],
      nodeKinds: [
        {
          lg: 'First',
          wire: 'duplicate',
          dart: 'first',
          swift: 'first',
          container: false,
        },
        {
          lg: 'Second',
          wire: 'duplicate',
          dart: 'second',
          swift: 'second',
          container: false,
        },
      ],
      properties: [],
      events: [],
    }),
  );

  const result = runGenerator(['--manifest', manifest, '--validate']);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /duplicate node-kind wire name: duplicate/);
});
