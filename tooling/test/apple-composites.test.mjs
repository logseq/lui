import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const apple = readFileSync(new URL('../../platform/apple/Sources/LUIAppleBackend/LUISwiftUIRoot.swift', import.meta.url), 'utf8');

test('Apple roleless heading, paragraph and label apply the single-line policy', () => {
  for (const [kind, next] of [['heading', 'paragraph'], ['paragraph', 'label'], ['label', 'button']]) {
    const branch = apple.slice(apple.indexOf(`case .${kind}:`), apple.indexOf(`case .${next}:`));
    const legacy = branch.slice(branch.indexOf('LUIQueryableText('));
    assert.match(legacy, /\.lineLimit\(LUITextLinePolicy\.lineLimit\(\s*styleClass: model\.derived\.styleClass\)\)/, kind);
  }
});

test('Apple navigation forms consume explicit sections and their slot content', () => {
  const form = apple.slice(apple.indexOf('private struct LUINavigationFormRows:'),
    apple.indexOf('enum LUINavigationFormSectionPolicy'));
  assert.match(form, /LUIListSectionPolicy\.explicitSections\(/);
  assert.match(form, /sectionSlot\(header\)/);
  assert.match(form, /sectionSlot\(footer\)/);
});

test('Apple navigation forms retain authored lists that own lifecycle or scrolling callbacks', () => {
  const start = apple.indexOf('if content.children.count == 1,');
  const condition = apple.slice(start, apple.indexOf('sectionContent = child', start));
  for (const flag of ['supportsAppear', 'supportsPointer', 'tracksVisibleRange']) {
    assert.ok(condition.includes(`!child.${flag}`), `list flattening must preserve ${flag}`);
  }
});
