import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const vocabulary = JSON.parse(read('schema/components.json')).designTokens;
const web = read('platform/web/melange/core/lui_web_util.ml');
const css = read('platform/web/src/lui.css');
const apple = read('platform/apple/Sources/LUIAppleBackend/LUIThemePolicy.swift');
const appleView = read('platform/apple/Sources/LUIAppleBackend/LUISwiftUIRoot.swift');
const android = read('platform/android/lui/src/main/kotlin/dev/lui/LuiTheme.kt');
const androidView = read('platform/android/lui/src/main/kotlin/dev/lui/LuiNodeView.kt');
const native = read('platform/native/lui_theme/lui_theme.ml');
const paint = read('platform/native/lui_paint/lui_paint.ml');
const between = (source, start, end) => {
  assert.ok(source.includes(start), `missing table: ${start}`);
  const tail = source.slice(source.indexOf(start) + start.length);
  assert.ok(tail.includes(end), `missing end of table: ${end}`);
  return tail.slice(0, tail.indexOf(end));
};
const quoted = source => [...source.matchAll(/"([^"]+)"/g)].map(m => m[1]);
const keys = source => [...source.matchAll(/"([^"]+)"\s*[:,]/g)].map(m => m[1]);
const clauses = (source, pattern) => [...source.matchAll(pattern)].flatMap(m => quoted(m[1]));
const covers = (backend, category, actual) => {
  const missing = vocabulary[category].filter(name => !actual.includes(name));
  assert.deepEqual(missing, [], `${backend} missing canonical ${category}`);
};

const colorTables = {
  TypedAPI: quoted(between(read('src/lui_tokens.ml'), 'let color_value', 'let space_value')),
  Web: [...quoted(between(web, 'let semantic_color_names =', 'let foreground_tokens')),
    ...clauses(web, /color = ("[^"]+")/g)],
  Apple: clauses(between(apple, 'private static func semanticColor(', 'private static func registeredColor('), /case ((?:"[^"]+"\s*,?\s*)+):/g),
  Android: clauses(between(android, 'return when (token)', "/** LUI's Material"), /((?:"[^"]+"\s*,?\s*)+)->/g),
  NativeLight: keys(between(native, 'let light_tokens', 'let dark_tokens')),
  NativeDark: keys(between(native, 'let dark_tokens', 'let tokens =')),
};

test('every canonical color resolves in each backend and both native palettes', () => {
  for (const [backend, names] of Object.entries(colorTables)) covers(backend, 'colors', names);
  covers('Web CSS variables', 'colors', [...css.matchAll(/--lui-([\w-]+)\s*:/g)].map(m => m[1]));
});

test('container colors have admitted foreground counterparts rather than raw fills', () => {
  const nonContainers = new Set(['primary', 'accent', 'foreground', 'muted-foreground', 'border', 'input', 'ring', 'transparent']);
  const containers = vocabulary.colors.filter(name => !nonContainers.has(name));
  const tables = {
    Web: [between(web, 'let foreground_tokens =', 'let space_tokens'), /"([^"]+)",\s*"([^"]+)"/g],
    Apple: [between(apple, 'static let foregroundTokens =', 'static func color('), /"([^"]+)":\s*"([^"]+)"/g],
    Android: [between(android, 'internal val luiForegroundTokens =', 'internal val luiSpaceTokens'), /"([^"]+)" to "([^"]+)"/g],
    Native: [between(paint, 'let foreground_tokens =', 'let foreground_token '), /"([^"]+)",\s*"([^"]+)"/g],
  };
  for (const [backend, [source, pattern]] of Object.entries(tables)) {
    const pairs = new Map([...source.matchAll(pattern)].map(m => [m[1], m[2]]));
    for (const name of ['primary', 'accent']) {
      assert.equal(pairs.get(name), undefined, `${backend} keeps ${name} as accent ink`);
    }
    const admitted = colorTables[backend === 'Native' ? 'NativeLight' : backend];
    for (const name of containers) {
      const target = pairs.get(name);
      assert.ok(target && target !== name && admitted.includes(target), `${backend} foreground ${name} -> ${target}`);
    }
  }
  assert.match(read('platform/web/melange/render/lui_web_props.ml'), /web_color_value ~foreground:true foreground/);
  assert.match(androidView, /luiThemeColor\(node.propString\("foreground"\), foreground = true\)/);
  assert.match(appleView, /foreground: true/);
  assert.match(paint, /then foreground_token s/);
});

test('spacing and radius scales are complete backend lookup tables', () => {
  const tables = [
    ['Web', 'spaces', between(web, 'let space_tokens =', 'let radius_tokens')],
    ['Web', 'radii', between(web, 'let radius_tokens =', 'let web_color_value')],
    ['Apple', 'spaces', between(apple, 'static let spaces:', 'static let radii:')],
    ['Apple', 'radii', between(apple, 'static let radii:', 'static let textRoles:')],
    ['Android', 'spaces', between(android, 'internal val luiSpaceTokens =', 'internal val luiRadiusTokens')],
    ['Android', 'radii', between(android, 'internal val luiRadiusTokens =', 'internal fun resolveLuiThemeColor')],
    ['Native', 'spaces', between(native, 'let space_tokens =', 'let radius_tokens')],
    ['Native', 'radii', between(native, 'let radius_tokens =', 'let space_of')],
  ];
  for (const [backend, category, source] of tables) {
    covers(backend, category, quoted(source));
    const values = [...source.matchAll(/"([^"]+)"\s*(?::|,|to)\s*([\d.]+)/g)];
    assert.equal(values.length, vocabulary[category].length, `${backend} ${category} has numeric metrics`);
    assert.ok(values.every(m => Number(m[2]) >= 0));
  }
  for (const [category, prefix] of [['spaces', 'space'], ['radii', 'radius']]) {
    covers('Web CSS', category, [...css.matchAll(new RegExp(`--lui-${prefix}-([\\w-]+)\\s*:`, 'g'))].map(m => m[1]));
  }
});

test('typography roles and modifiers are implemented, not just declared', () => {
  const roles = {
    TypedAPI: quoted(read('src/lui_tokens.ml').split('let text_role_value')[1]),
    Web: [...css.matchAll(/\.([\w-]+)(?:\s*,|\s*\{)/g)].map(m => m[1]),
    Apple: keys(between(apple, 'static let textRoles:', 'static func role(')),
    Android: [...android.matchAll(/classes.contains\("([^"]+)"\)/g)].map(m => m[1]),
    Native: keys(between(paint, 'let text_roles =', 'let text_classes')),
  };
  for (const [backend, names] of Object.entries(roles)) covers(backend, 'textRoles', names);
  for (const modifier of vocabulary.textModifiers) {
    assert.match(css, new RegExp(`\\.${modifier}\\s*\\{[^}]+\\}`));
    assert.ok(appleView.includes(`"${modifier}"`));
    assert.ok(android.includes(`"${modifier}"`));
    assert.ok(paint.includes(`"${modifier}"`));
  }
  assert.match(appleView, /LUIDesignTokens.textRoles\[role\]/);
  assert.match(androidView, /LuiTypography.singleLine/);
  assert.match(native, /let text_roles = Lui_paint.text_roles/);
  for (const host of ['lui_window', 'lui_window_linux', 'lui_window_windows']) {
    const source = read(`platform/native/${host}/lui_window_text.ml`);
    assert.match(source, /Lui_paint.text_class_number/);
    assert.match(source, /Lui_paint.text_class_string/);
  }
});

test('the parity checker rejects removal of any canonical color or role', () => {
  for (const category of ['colors', 'textRoles']) {
    for (const name of vocabulary[category]) {
      assert.throws(() => covers('mutated backend', category, vocabulary[category].filter(n => n !== name)), /missing canonical/);
    }
  }
});
