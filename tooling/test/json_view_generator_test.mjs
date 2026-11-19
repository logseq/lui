import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

test('JSON generator preserves nested callback arrows when parsing arguments', () => {
  const generator = fileURLToPath(new URL('../../tools/gen_json_view.py', import.meta.url));
  const result = spawnSync('python3', ['-c', `
import runpy
import sys
module = runpy.run_path(sys.argv[1])
parse = module['parse_args']
extra = module['extra_arg']
assert parse('') == []
assert parse('?text:string -> t list -> t') == [('text', 'string')]
arguments = parse('''?on_press:(unit -> unit) ->
    ?on_input:(string -> unit) -> ?on_toggle:(bool -> unit) ->
    ?on_resize:(float -> unit) -> ?nested:((int -> unit) -> unit) -> t list -> t''')
assert arguments == [
    ('on_press', '(unit -> unit)'), ('on_input', '(string -> unit)'),
    ('on_toggle', '(bool -> unit)'), ('on_resize', '(float -> unit)'),
    ('nested', '((int -> unit) -> unit)')]
for (name, typ), decoder in zip(arguments, ['ev', 'ev_input', 'ev_toggle', 'ev_value']):
    assert extra(name, typ, 'button').startswith('?' + name + ':(' + decoder + ' ')
for malformed in ['?on_press:(unit -> unit', '?on_press:unit) -> unit']:
    try:
        parse(malformed)
    except ValueError:
        pass
    else:
        raise AssertionError('accepted unbalanced type')
` , generator], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr || result.stdout);
});
