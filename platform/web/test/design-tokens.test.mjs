import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {chromium} from 'playwright';

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
  for (const color of ['primary', 'primary-foreground', 'accent-foreground']) {
    assert.equal(Util.web_color_value(true, color), `var(--color-${color})`);
  }
  assert.equal(Util.web_color_value(true, 'accent'), 'var(--color-accent-ink)');
  assert.equal(Util.web_color_value(false, 'accent'), 'var(--color-accent)');
  assert.equal(Util.web_color_value(true, '#123456'), '#123456');
  assert.equal(Util.web_color_value(undefined, ''), '');
  assert.equal(Util.web_color_value(undefined, 'custom-token'), 'custom-token');
});

test('accent ink contrasts with unchanged background, secondary and accent fills', async () => {
  const browser = await chromium.launch({headless: true});
  try {
    const page = await browser.newPage();
    const css = readFileSync(new URL('../dist/lui.css', import.meta.url), 'utf8');
    for (const mode of ['light', 'dark', 'system']) {
      await page.emulateMedia({colorScheme: mode === 'light' ? 'light' : 'dark'});
      await page.setContent(`<style>${css}</style><section data-kb-theme="${mode}"></section>`);
      const results = await page.evaluate(ink => {
        const scope = document.querySelector('section');
        const canvas = document.createElement('canvas').getContext('2d', {willReadFrequently: true});
        const luminance = color => {
          canvas.fillStyle = color;
          canvas.fillRect(0, 0, 1, 1);
          return [...canvas.getImageData(0, 0, 1, 1).data].slice(0, 3)
            .map(value => value / 255)
            .map(value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4)
            .reduce((sum, value, index) => sum + value * [0.2126, 0.7152, 0.0722][index], 0);
        };
        return ['background', 'secondary', 'accent'].map(fill => {
          scope.style.color = ink;
          scope.style.backgroundColor = `var(--color-${fill})`;
          const style = getComputedStyle(scope);
          const a = luminance(style.color), b = luminance(style.backgroundColor);
          return {fill, background: style.backgroundColor,
            contrast: (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)};
        });
      }, Util.web_color_value(true, 'accent'));
      assert.equal(results[1].background, results[2].background, 'accent fill stays secondary');
      for (const {fill, contrast} of results) {
        console.log(`${mode} accent ink on ${fill}: ${contrast.toFixed(2)}:1`);
        assert.ok(contrast >= 4.5, `${mode} ${fill}: ${contrast}`);
      }
    }
  } finally {
    await browser.close();
  }
});

test('built CSS retains semantic typography and single-line truncation', () => {
  const css = readFileSync(new URL('../dist/lui.css', import.meta.url), 'utf8');
  for (const name of [...vocabulary.textRoles, ...vocabulary.textModifiers]) {
    assert.match(css, new RegExp(`\\.${name}(?:[,{])`), name);
  }
  assert.match(css, /\.single-line\{[^}]*white-space:nowrap/);
  assert.match(css, /\.single-line\{[^}]*text-overflow:ellipsis/);
});
