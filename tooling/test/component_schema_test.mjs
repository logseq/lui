import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  parseSlotStyle,
  parseSlotStyleBucket,
  typedViewFunctions,
  typedViewSchema,
} from '../typed_view_schema.mjs';
import { callbackContract, renderEventPayloads } from '../event_payload_schema.mjs';

const repository = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const generator = join(repository, 'tooling/generate_component_schema.mjs');

test('element constructors expose only admitted properties and events', () => {
  const schema = JSON.parse(readFileSync(join(repository, 'schema/components.json'), 'utf8'));
  const admission = JSON.parse(readFileSync(join(repository, 'schema/apple-property-admission.json'), 'utf8'));
  const signature = readFileSync(join(repository, 'src/lui_elements.mli'), 'utf8');
  const functions = typedViewFunctions(signature);
  const slotStyle = parseSlotStyle(signature);
  assert.ok(slotStyle, 'missing Slot_style module signature');
  assert.equal(slotStyle.bucketProperties.get('base')?.length, 12);
  assert.equal(slotStyle.bucketProperties.get('typography_caps')?.length, 20);
  assert.equal(slotStyle.bucketProperties.get('text_caps')?.length, 22);
  assert.equal(slotStyle.bucketProperties.get('surface_caps')?.length, 21);
  const nesting = readFileSync(join(repository, 'ppx/lui_nesting_schema.ml'), 'utf8');
  const mapping = nesting.match(/let constructor = function([\s\S]*?)\nlet mandatory_labels/)[1];
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
  assert.equal(functions.has('button_impl'), false, 'button_impl must stay internal');
  assert.deepEqual(schema.mandatoryParameters.button, ['text']);
  assert.deepEqual(schema.mandatoryParameters.icon_button, ['icon', 'label']);
  assert.ok(functions.get('button').includes('?size:button_size'));
  assert.ok(functions.get('icon_button').includes('?size:control_size'));
  assert.ok(constructors.some(([name, kind]) => name === 'icon_button' && kind === 'button'));
  for (const [constructor, parameters] of Object.entries(schema.mandatoryParameters)) {
    for (const parameter of parameters) {
      assert.ok(functions.get(constructor)?.some(argument => argument.startsWith(`${parameter}:`)),
        `${constructor}.${parameter} must be mandatory`);
    }
  }
  assert.deepEqual(Object.keys(admission.events).sort(), schema.events.map(({ lg }) => lg).sort());
  const violations = [];
  for (const [constructor, kind, childKind] of constructors) {
    const original = schema.slotConstructors?.[constructor]?.constructor ?? constructor;
    assert.ok(admission.kinds[kind], `unknown kind for ${constructor}`);
    assert.ok(functions.has(constructor), `missing constructor ${constructor}`);
    for (const argument of functions.get(constructor).slice(0, -1)) {
      const match = /^\??(\w+):(.*)$/.exec(argument);
      if (!match) continue;
      const [, parameter, type] = match;
      const base = parameter.replace(/_signal$/, '');
      if (base === 'style' && type.startsWith('Slot_style.')) {
        const bucket = parseSlotStyleBucket(type);
        assert.ok(bucket && slotStyle.bucketProperties.has(bucket),
          `un-indexed or unknown Slot_style capability on ${constructor}.${parameter}: ${type}`);
        const styleKind = ['menu', 'submenu'].includes(original) ? childKind : kind;
        for (const property of slotStyle.bucketProperties.get(bucket)) {
          assert.ok(schema.properties.some(({ wire }) => wire === property),
            `unknown Slot_style property ${constructor}.${parameter}: ${property}`);
          if (!admission.kinds[styleKind].includes(property)) {
            violations.push(`${constructor}.${parameter} (Slot_style.${bucket}): ${property} unsupported on ${styleKind}`);
          }
        }
        continue;
      }
      if (base === 'key' || /^(t|\w+_el)( list)?$/.test(type)) continue;
      if (constructor === 'scroll' && base === 'virtual_owner' && type === 'Lui_virtual.owner') continue;
      if (original === 'virtual_list' && base === 'viewport' && type === 'Lui_virtual.source') continue;
      if (parameter.startsWith('on_')) {
        assert.notEqual(type, '(Lui_protocol.event -> unit)',
          `${constructor}.${parameter} exposes a raw event callback`);
        const contract = callbackContract(schema, constructor, parameter);
        assert.ok(contract, `missing payload contract for ${constructor}.${parameter}`);
        assert.equal(type, `(${contract.payload} -> unit)`,
          `incorrect payload type for ${constructor}.${parameter}`);
        const handler = parameter.slice(3);
        const event = handler === 'change' && original === 'slider' ? 'ValueChanged'
          : handler === 'navigate' ? (['button', 'icon_button', 'row', 'box'].includes(original) ? 'NavigationKey' : 'NavigateNext')
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
      if (constructor === 'popover' && base === 'target') properties =
        ['x', 'y', 'anchor', 'anchor-target', 'anchor-rect', 'anchor-alignment', 'anchor-offset', 'anchor-alignment-offset'];
      if (constructor === 'dropdown_menu' && base === 'target') {
        assert.ok(type === 'dropdown_target' || type === 'dropdown_target Signal.signal',
          `unexpected dropdown_menu.${parameter} type: ${type}`);
        properties = ['x', 'y', 'anchor', 'anchor-alignment', 'anchor-offset'];
      }
      if (constructor === 'split' && base === 'sizing') properties = ['value', 'first-pane-width'];
      if (constructor === 'split' && base === 'motion') properties = ['resize-duration', 'resize-easing', 'resize-origin'];
      if (['text', 'heading', 'paragraph', 'label'].includes(original) && base === 'role') properties = ['style-class'];
      if (['text', 'heading', 'paragraph', 'label'].includes(original) && base === 'truncate')
        properties = ['white-space', 'text-overflow', 'overflow', 'line-clamp', 'min-width'];
      if (base === 'checked' && ['toggle_button', 'menu_item'].includes(original)) properties = ['selected'];
      if (base === 'selected' && constructor === 'radio') properties = ['checked'];
      if (base === 'title' && ['sheet', 'accordion'].includes(constructor)) properties = ['text'];
      if (original === 'virtual_list' && ['overscan', 'item_extent'].includes(base)) properties = ['data-attrs'];
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

test('raw constructor callbacks and schema payload drift are rejected', () => {
  const schema = JSON.parse(readFileSync(join(repository, 'schema/components.json'), 'utf8'));
  const signature = readFileSync(join(repository, 'src/lui_elements.mli'), 'utf8');
  const implementation = readFileSync(join(repository, 'src/lui_elements.ml'), 'utf8');
  const raw = signature.replace('?on_press:(unit -> unit)', '?on_press:(Lui_protocol.event -> unit)');
  assert.notEqual(raw, signature);
  const admission = JSON.parse(readFileSync(join(repository, 'schema/apple-property-admission.json'), 'utf8'));
  assert.throws(() => typedViewSchema(schema, raw, implementation, {admission}), /unknown event type: table-cell.on_press/);
  const changed = structuredClone(schema);
  changed.events.find(event => event.lg === 'ValueChanged').fields[1] = ':int';
  assert.throws(() => renderEventPayloads(changed), /incompatible callback scalar on_resize/);
  const unindexedStyle = signature.replace('?style:Slot_style.base Slot_style.t', '?style:Slot_style.t');
  assert.notEqual(unindexedStyle, signature);
  assert.throws(() => typedViewSchema(schema, unindexedStyle, implementation, {admission}),
    /unknown Slot_style capability bucket/);
  const overbroadStyle = signature.replace(
    /val switch_ :\n\s*\?style:Slot_style\.base Slot_style\.t/,
    'val switch_ :\n  ?style:Slot_style.text_caps Slot_style.t',
  );
  assert.notEqual(overbroadStyle, signature);
  assert.throws(() => typedViewSchema(schema, overbroadStyle, implementation, {admission}),
    /Slot_style\.text_caps property .* unsupported on switch/);
});

test('nesting schema registers Ui.form_section and polymorphic scoped adapters', () => {
  const nesting = readFileSync(join(repository, 'ppx/lui_nesting_schema.ml'), 'utf8');
  const scopedSection = nesting.match(/let scoped_adapter = function([\s\S]*?)\nlet dynamic_adapter/)[1];
  for (const polymorphic of ['button', 'row', 'dropdown_menu', 'menu_item', 'divider', 'list_item']) {
    assert.equal(scopedSection.includes(`"${polymorphic}"`), false,
      `${polymorphic} should fall through to polymorphic "scoped" adapter`);
  }
  assert.ok(scopedSection.includes('"scoped_dropdown_menu" -> "scoped_dropdown_menu"'));
  assert.ok(scopedSection.includes('"scoped_toolbar" -> "scoped_toolbar"'));
  assert.ok(scopedSection.includes('| _ -> "scoped"'));
  const uiSection = nesting.match(/let ui_constructor = function([\s\S]*?)$/)[1];
  assert.ok(uiSection.includes('| "form_section" -> Some (ListSection, ListSection, Children_list)'));
  assert.ok(uiSection.includes('| "form_sheet" -> Some (Sheet, ListContainer, Children_list)'));
});

test('validation and rendering reject unknown callback events', () => {
  const schema = JSON.parse(readFileSync(join(repository, 'schema/components.json'), 'utf8'));
  const directory = mkdtempSync(join(tmpdir(), 'lui-callback-schema-'));
  const manifest = join(directory, 'callbacks.json');
  assert.equal(runGenerator(['--validate']).status, 0);
  schema.eventCallbacks.on_press.events.push('MissingPress');
  writeFileSync(manifest, JSON.stringify(schema));
  const result = runGenerator(['--manifest', manifest, '--validate']);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /unknown callback event MissingPress/);
  assert.throws(() => renderEventPayloads(schema), /unknown callback event MissingPress/);
});

test('press registration filters exactly the schema decoder events', () => {
  const schema = JSON.parse(readFileSync(join(repository, 'schema/components.json'), 'utf8'));
  const implementation = readFileSync(join(repository, 'src/lui_elements.ml'), 'utf8');
  const filter = implementation.match(/let is_press = function([\s\S]*?)\nlet /)[1];
  const accepted = [...filter.matchAll(/\b([A-Z]\w*) _/g)].map(([, event]) => event);
  assert.deepEqual(accepted.sort(), [...schema.eventCallbacks.on_press.events].sort());
  const registration = implementation.match(/let register_press\b([\s\S]*?)\nlet /)[1];
  assert.match(registration, /on_event context node is_press/);
  assert.match(registration, /Lui_event_payloads\.on_press/);
});

test('semantic tag families exactly match emit-time validation', () => {
  const signature = readFileSync(join(repository, 'src/lui_elements.mli'), 'utf8');
  const protocol = readFileSync(join(repository, 'src/lui_protocol.ml'), 'utf8');
  const functions = typedViewFunctions(signature);
  for (const [constructor, kind, type] of [
    ['text', 'Text', 'phrasing_tag'], ['heading', 'Heading', 'heading_tag'],
    ['paragraph', 'Paragraph', 'paragraph_tag'], ['label', 'Label', 'label_tag'],
    ['column', 'Column', 'list_container_tag'], ['row', 'Row', 'row_tag'],
  ]) {
    assert.ok(functions.get(constructor).includes(`?as_:${type}`));
    const body = signature.match(new RegExp(`type ${type} = \\[([^\\]]+)\\]`))[1];
    const tags = [...body.matchAll(/`(\w+)/g)].map(([, tag]) => tag.toLowerCase()).sort();
    const accepted = protocol.match(new RegExp(`\\| ${kind} ->\\s*List.mem tag\\s*\\[([^\\]]+)\\]`))[1];
    assert.deepEqual(tags, [...accepted.matchAll(/"([^"]+)"/g)].map(([, tag]) => tag).sort());
  }
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

test('slot builders retain abstract results and mandatory arguments', () => {
  const schema = JSON.parse(readFileSync(join(repository, 'schema/components.json'), 'utf8'));
  const functions = typedViewFunctions(readFileSync(join(repository, 'src/lui_elements.mli'), 'utf8'));
  for (const [name, {constructor, result}] of Object.entries(schema.slotConstructors)) {
    const args = functions.get(name);
    assert.equal(args?.at(-1), result, name);
    for (const label of schema.mandatoryParameters[constructor] ?? []) {
      assert.ok(args.some(arg => arg.startsWith(`${label}:`)), `${name}.${label}`);
    }
  }
  for (const [name, capability] of Object.entries(schema.dynamicAdapters)) {
    const {result, single} = typeof capability === 'string' ? {result: capability} : capability;
    for (const prefix of single ? ['reactive_'] : ['if_', 'reactive_']) {
      assert.equal(functions.get(prefix + name)?.at(-1), result, prefix + name);
    }
    if (single) {
      assert.equal(functions.has('if_' + name), false);
      assert.equal(functions.has('keyed_' + name), false);
    }
  }
  const metadata = functions.get('context_menu_item').slice(0, -2);
  assert.deepEqual(metadata.map(arg => arg.replace(/^\??(\w+):.*$/, '$1')), [
    'text', 'text_signal', 'icon', 'icon_signal', 'foreground', 'foreground_signal',
    'variant', 'selected', 'selected_signal', 'checked', 'checked_signal',
    'disabled', 'disabled_signal', 'accessibility_identifier', 'accessibility_identifier_signal', 'on_press',
  ]);
  assert.ok(metadata.includes('on_press:(unit -> unit)'));
  assert.equal(functions.get('context_menu_item').at(-2), 'unit');
});

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
  assert.ok(summary.supported.includes('icon-button'));
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
