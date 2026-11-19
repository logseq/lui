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
