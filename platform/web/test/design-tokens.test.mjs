import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const build = process.env.LUI_TEST_BUILD_DIR ?? '_build';
const Util = await import(new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/lui.web.dom/core/lui_web_util.js`, import.meta.url));
const vocabulary = JSON.parse(readFileSync(new URL('../../../schema/components.json', import.meta.url))).designTokens;

test('canonical colors resolve as CSS values and container foregrounds resolve as ink', () => {
  for (const color of vocabulary.colors) {
    const value = Util.web_color_value(undefined, color);
    assert.ok(value === 'transparent' || value.startsWith('var(--color-') || value.startsWith('color-mix('), `${color}: ${value}`);
  }
  assert.equal(Util.web_color_value(true, 'secondary'), 'var(--color-secondary-foreground)');
  assert.equal(Util.web_color_value(undefined, 'secondary'), 'var(--color-secondary)');
  assert.equal(Util.web_color_value(true, 'surface'), 'var(--color-surface-foreground)');
  for (const color of ['primary', 'accent', 'primary-foreground', 'accent-foreground']) {
    assert.equal(Util.web_color_value(true, color), `var(--color-${color})`);
  }
  assert.equal(Util.web_color_value(true, '#123456'), '#123456');
  assert.equal(Util.web_color_value(undefined, ''), '');
  assert.equal(Util.web_color_value(undefined, 'custom-token'), 'custom-token');
});

test('built CSS retains semantic typography and single-line truncation', () => {
  const css = readFileSync(new URL('../dist/lui.css', import.meta.url), 'utf8');
  for (const name of [...vocabulary.textRoles, ...vocabulary.textModifiers]) {
    assert.match(css, new RegExp(`\\.${name}(?:[,{])`), name);
  }
  assert.match(css, /\.single-line\{[^}]*white-space:nowrap/);
  assert.match(css, /\.single-line\{[^}]*text-overflow:ellipsis/);
});
