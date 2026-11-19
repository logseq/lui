import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { typedViewFunctions } from '../typed_view_schema.mjs';

const repository = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const generator = join(repository, 'tooling/generate_component_schema.mjs');

test('element constructors expose only admitted properties and events', () => {
  const schema = JSON.parse(readFileSync(join(repository, 'schema/components.json'), 'utf8'));
  const admission = JSON.parse(readFileSync(join(repository, 'schema/apple-property-admission.json'), 'utf8'));
  const functions = typedViewFunctions(readFileSync(join(repository, 'src/lui_elements.mli'), 'utf8'));
  const nesting = readFileSync(join(repository, 'ppx/lui_nesting_schema.ml'), 'utf8');
  const mapping = nesting.match(/let constructor = function([\s\S]*?)\nlet exports/)[1];
  const kinds = new Map(schema.nodeKinds.map(({ lg, wire }) => [lg, wire]));
  const constructors = [...mapping.matchAll(/^\s*\| (.+?) -> Some \((\w+), (\w+),/gm)]
    .flatMap(([, names, root, children]) => [...names.matchAll(/"(\w+)"/g)]
      .map(([, name]) => [name, kinds.get(root), kinds.get(children)]));
  assert.equal(new Set(constructors.map(([, kind]) => kind)).size, schema.nodeKinds.length - 3);
  const aliases = {
    as_: ['as'], label: ['accessibility-label'], disabled: ['enabled'],
    shortcut_hint: ['tooltip-keys'], kind: ['input-type'], fit: ['image-fit'],
    first_width: ['first-pane-width'], point_size: ['width', 'height'],
    resizable_width: ['width'], accordion_height: ['height'],
    toolbar_gap: ['gap'], toolbar_class: ['style-class'], toast_class: ['style-class'],
    list_marker: ['list-style'], at: ['x', 'y'], level: ['heading-level'],
  };
  const eventAliases = {
    input: 'TextChanged', toggle: 'ToggleChanged', toggle_detail: 'ToggleChangedDetail',
    value_changed: 'ValueChanged', resize: 'ValueChanged', navigation_key: 'NavigationKey',
    context_menu: 'ContextMenuPress', focus_within: 'FocusWithinChanged',
  };
  assert.equal(functions.has('apply_universal'), false, 'apply_universal must stay internal');
  for (const [constructor, parameters] of Object.entries(schema.mandatoryParameters)) {
    for (const parameter of parameters) {
      assert.ok(functions.get(constructor)?.some(argument => argument.startsWith(`${parameter}:`)),
        `${constructor}.${parameter} must be mandatory`);
    }
  }
  assert.deepEqual(Object.keys(admission.events).sort(), schema.events.map(({ lg }) => lg).sort());
  const violations = [];
  for (const [constructor, kind, childKind] of constructors) {
    assert.ok(admission.kinds[kind], `unknown kind for ${constructor}`);
    assert.ok(functions.has(constructor), `missing constructor ${constructor}`);
    for (const argument of functions.get(constructor).slice(0, -1)) {
      const match = /^\??(\w+):(.*)$/.exec(argument);
      if (!match) continue;
      const [, parameter, type] = match;
      const base = parameter.replace(/_signal$/, '');
      if (base === 'key' || /^(t|\w+_el)( list)?$/.test(type)) continue;
      if (constructor === 'scroll' && base === 'virtual_owner' && type === 'Lui_virtual.owner') continue;
      if (constructor === 'virtual_list' && base === 'viewport' && type === 'Lui_virtual.source') continue;
      if (parameter.startsWith('on_')) {
        const handler = parameter.slice(3);
        const event = handler === 'change' && constructor === 'slider' ? 'ValueChanged'
          : handler === 'navigate' ? (['button', 'row', 'box'].includes(constructor) ? 'NavigationKey' : 'NavigateNext')
          : eventAliases[handler] ?? handler.split('_').map(word => word[0].toUpperCase() + word.slice(1)).join('');
        const eventKind = handler === 'dismiss' ? childKind : kind;
        assert.ok(admission.events[event], `unknown event parameter ${constructor}.${parameter}`);
        if (!admission.events[event].includes(eventKind)) {
          violations.push(`${constructor}.${parameter}: ${event} unsupported on ${eventKind}`);
        }
        continue;
      }
      let properties = base === 'value' && type.startsWith('string') ? ['text']
        : aliases[base] ?? [base.replaceAll('_', '-')];
      if (base === 'checked' && ['toggle_button', 'menu_item'].includes(constructor)) properties = ['selected'];
      if (base === 'selected' && constructor === 'radio') properties = ['checked'];
      if (base === 'title' && ['sheet', 'accordion'].includes(constructor)) properties = ['text'];
      if (constructor === 'virtual_list' && ['overscan', 'item_extent'].includes(base)) properties = ['data-attrs'];
      for (const property of properties) {
        assert.ok(schema.properties.some(({ wire }) => wire === property), `unknown property ${constructor}.${parameter}`);
        if (!admission.kinds[kind].includes(property)) {
          violations.push(`${constructor}.${parameter}: ${property} unsupported on ${kind}`);
        }
      }
    }
  }
  assert.deepEqual(violations, []);
});

test('Android kind predicates derive from the canonical admission export', () => {
  const admission = JSON.parse(readFileSync(join(repository, 'schema/apple-property-admission.json'), 'utf8'));
  const schema = JSON.parse(readFileSync(join(repository, 'schema/components.json'), 'utf8'));
  const kotlin = readFileSync(join(repository, 'platform/android/lui/src/main/kotlin/dev/lui/LuiWireSchema.kt'), 'utf8');
  const kinds = name => schema.nodeKinds.find(k => k.wire === name).swift;
  const generated = name => [...kotlin.match(new RegExp(`val ${name}:.*?setOf\\(([^)]*)\\)`))[1].matchAll(/LuiNodeKind\.(\w+)/g)].map(m => m[1]);
  assert.deepEqual(generated('mainCrossKinds'), Object.entries(admission.kinds).filter(([, props]) => props.includes('main')).map(([kind]) => kinds(kind)));
  assert.deepEqual(generated('modalSurfaceKinds'), admission.modalKinds.map(kinds));
  assert.deepEqual(schema.properties.filter(p => p.webOnly).map(p => p.wire), ['focus-within-enabled', 'shrink']);
});

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
    'br',
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
  assert.ok(summary.supported.includes('virtual-list'));
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
  assert.ok(summary.supported.includes('bottom-tabs'));
  assert.ok(summary.supported.includes('bottom-tab'));
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

test('Bottom Tabs reserve distinct retained navigation node kinds', () => {
  const schema = JSON.parse(
    readFileSync(join(repository, 'schema/components.json'), 'utf8'),
  );

  assert.deepEqual(
    schema.nodeKinds.filter((kind) =>
      kind.wire === 'bottom-tabs' || kind.wire === 'bottom-tab'),
    [
      {
        lg: 'BottomTabs',
        wire: 'bottom-tabs',
        swift: 'bottomTabs',
        container: true,
      },
      {
        lg: 'BottomTab',
        wire: 'bottom-tab',
        swift: 'bottomTab',
        container: true,
      },
    ],
  );
});

test('schema reserves one internal transparent root node', () => {
  const schema = JSON.parse(
    readFileSync(join(repository, 'schema/components.json'), 'utf8'),
  );
  const root = schema.nodeKinds.find((kind) => kind.wire === 'root');

  assert.deepEqual(root, {
    lg: 'Root',
    wire: 'root',
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
          swift: 'first',
          container: false,
        },
        {
          lg: 'Second',
          wire: 'duplicate',
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
