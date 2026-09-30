import assert from 'node:assert/strict';
import test from 'node:test';
import { stripVTControlCharacters } from 'node:util';
import { hasDuneWatchReadyMessage } from '../dev_web_readiness.mjs';

test('Dune watch readiness matches colorized output split across chunks', () => {
  const chunks = [
    '\u001b[1;',
    '32mSuccess\u001b[0m, waiting for ',
    'filesystem changes...\n',
  ];
  const readiness = [];
  let output = '';

  for (const chunk of chunks) {
    output += chunk;
    readiness.push(
      hasDuneWatchReadyMessage(stripVTControlCharacters(output)),
    );
  }

  assert.deepEqual(readiness, [false, false, true]);
});
