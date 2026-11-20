import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = fileURLToPath(new URL('../../', import.meta.url));

test('menu-item styling preserves slot capabilities and reactive properties', () => {
  const dir = mkdtempSync(join(tmpdir(), 'lui-menu-style-'));
  const run = args => spawnSync('opam', ['exec', '--', ...args], { cwd: root, encoding: 'utf8' });
  const success = args => {
    const result = run(args);
    assert.equal(result.status, 0, result.stdout + result.stderr);
  };
  const props = [
    ['font_size', 'FontSize', '"14px"', 'StringValue "14px"'],
    ['font_weight', 'FontWeight', '500', 'IntValue 500'],
    ['font_family', 'FontFamily', '"sans-serif"', 'StringValue "sans-serif"'],
    ['font_style', 'FontStyle', '`italic', 'StringValue "italic"'],
    ['line_height', 'LineHeight', '"20px"', 'StringValue "20px"'],
    ['letter_spacing', 'LetterSpacing', '0.5', 'FloatValue 0.5'],
    ['text_decoration', 'TextDecoration', '"underline"', 'StringValue "underline"'],
    ['white_space', 'WhiteSpace', '`nowrap', 'StringValue "nowrap"'],
    ['text_overflow', 'TextOverflow', '`ellipsis', 'StringValue "ellipsis"'],
    ['overflow', 'Overflow', '`hidden', 'StringValue "hidden"'],
    ['hover_background', 'HoverBackground', '"red"', 'StringValue "red"'],
    ['hover_foreground', 'HoverForeground', '"blue"', 'StringValue "blue"'],
    ['focus_within_background', 'FocusWithinBackground', '"green"', 'StringValue "green"'],
    ['focus_within_border', 'FocusWithinBorder', '"black"', 'StringValue "black"'],
    ['focus_shadow', 'FocusShadow', '"inset 0 0 0 2px blue"', 'StringValue "inset 0 0 0 2px blue"'],
  ];
  try {
    success(['dune', 'build', 'ppx/lui_ppx.cmxa', 'src/lui.cmxa']);
    writeFileSync(join(dir, 'driver.ml'), 'let () = Ppxlib.Driver.standalone ()\n');
    success(['ocamlfind', 'ocamlopt', '-package', 'ppxlib', '-linkpkg', '-linkall',
      '_build/default/ppx/lui_ppx.cmxa', join(dir, 'driver.ml'), '-o', join(dir, 'driver')]);
    const staticProps = props.map(([name, , value]) => `~${name}:(${value})`).join(' ');
    const initial = {
      font_size: ['"12px"', 'StringValue "12px"'],
      font_weight: ['400', 'IntValue 400'],
      font_family: ['"serif"', 'StringValue "serif"'],
      font_style: ['`normal', 'StringValue "normal"'],
      line_height: ['"18px"', 'StringValue "18px"'],
      letter_spacing: ['0.25', 'FloatValue 0.25'],
      text_decoration: ['"none"', 'StringValue "none"'],
      white_space: ['`normal', 'StringValue "normal"'],
      text_overflow: ['`clip', 'StringValue "clip"'],
      overflow: ['`visible', 'StringValue "visible"'],
      hover_background: ['"yellow"', 'StringValue "yellow"'],
      hover_foreground: ['"white"', 'StringValue "white"'],
      focus_within_background: ['"orange"', 'StringValue "orange"'],
      focus_within_border: ['"gray"', 'StringValue "gray"'],
      focus_shadow: ['"none"', 'StringValue "none"'],
    };
    const reactiveProps = '~font_size:"999px" ' + props.map(([name, , value]) =>
      `~${name}:(reactive (fun active -> if active then ${value} else ${initial[name][0]}) source)`).join(' ');
    const checks = props.map(([name, wire, , value]) =>
      `check label (property node ${wire} = Some (if reactive && not active then ${initial[name][1]} else ${value}));`).join('\n');
    const jsonProps = props.map(([name, , , wire]) => {
      const value = wire.startsWith('StringValue')
        ? `Lui_json_view.Str ${wire.slice('StringValue '.length)}`
        : `Lui_json_view.Num ${Number(wire.split(' ')[1]).toFixed(1)}`;
      return `("${name.replaceAll('_', '-')}", ${value})`;
    }).join('; ');
    writeFileSync(join(dir, 'probe.ml'), `open Lui_elements
open Lui_protocol
let batches = ref []
let backend = {backend_profile = generic_profile ();
  apply_batch = (fun batch -> batches := batch :: !batches; true)}
let ops () = List.concat_map (fun batch -> batch.ops) (List.rev !batches)
let check label condition = if not condition then failwith label
let node label = List.fold_left (fun result -> function
  | SetProp (id, TextValue, StringValue value) when value = label -> id
  | _ -> result) (-1) (ops ())
let property node prop = List.fold_left (fun result -> function
  | SetProp (id, key, value) when id = node && key = prop -> Some value
  | _ -> result) None (ops ())
let json_item label = Lui_json_view.Obj
  (["kind", Lui_json_view.Str "menu-item"; "text", Lui_json_view.Str label]
   @ [${jsonProps}])
let json = Lui_json_view.Obj ["kind", Lui_json_view.Str "column";
  "children", Lui_json_view.Arr [json_item "json-ordinary";
    Lui_json_view.Obj ["kind", Lui_json_view.Str "toolbar";
      "label", Lui_json_view.Str "Actions";
      "children", Lui_json_view.Arr [json_item "json-toolbar"]];
    Lui_json_view.Obj ["kind", Lui_json_view.Str "dropdown-menu";
      "children", Lui_json_view.Arr [json_item "json-dropdown"]]]]
let view _ source _ = column [
  menu_item ~text:"static" ${staticProps} [];
  menu_item ~text:"ordinary" ${reactiveProps} [];
  toolbar ~label:"Actions" [toolbar_menu_item ~text:"toolbar" ${reactiveProps} []];
  dropdown_menu_view (dropdown_menu [
    dropdown_menu_item ~text:"dropdown" ${reactiveProps} [];
    reactive_dropdown_menu_item (fun _ -> dropdown_menu_item ~text:"adapter"
      ${staticProps} []) source;
    dropdown_menu_item ~text:"default" []]);
  dropdown_menu_view (dropdown_menu []);
  Lui_json_view.render ~on_event:(fun ~id:_ ~kind:_ ~fields:_ -> ()) json]
let () =
  let app = Lui_app.create backend false (fun _ value -> value) view in
  check "start" (Lui_app.start app);
  ignore (Lui_app.flush app);
  let verify active =
    List.iter (fun label -> let node = node label in check label (node >= 0);
      let reactive = List.mem label ["ordinary"; "toolbar"; "dropdown"] in
      ${checks}
      ()) ["static"; "ordinary"; "toolbar"; "dropdown"; "adapter";
        "json-ordinary"; "json-toolbar"; "json-dropdown"];
    let node = node "default" in
    check "default font untouched" (property node FontSize = None);
    check "default hover untouched" (property node HoverBackground = None)
  in
  verify false;
  let retained = node "dropdown" in
  check "send" (Lui_app.send app true);
  ignore (Lui_app.flush app);
  check "retained node" (retained = node "dropdown");
  verify true;
  check "dispose" (Lui_app.dispose app)
`);
    const compile = ['ocamlfind', 'ocamlopt', '-package', 'ocaml-signal', '-linkpkg',
      '-I', '_build/default/src/.lui.objs/byte', '-I', '_build/default/src/.lui.objs/native',
      '_build/default/src/lui.cmxa', '-ppx', `${join(dir, 'driver')} --as-ppx`];
    success([...compile, join(dir, 'probe.ml'), '-o', join(dir, 'probe')]);
    const executed = spawnSync(join(dir, 'probe'), [], { cwd: root, encoding: 'utf8' });
    assert.equal(executed.status, 0, executed.stdout + executed.stderr);
    for (const expression of [
      'dropdown_menu_item ~font_weight:"bold" []',
      'dropdown_menu_item ~font_style:`invalid []',
      'dropdown_menu [menu_item ~font_size:"14px" []]',
    ]) {
      writeFileSync(join(dir, 'invalid.ml'), `open Lui_elements\nlet _ = ${expression}\n`);
      const result = run([...compile, '-c', join(dir, 'invalid.ml')]);
      assert.notEqual(result.status, 0, expression);
      assert.match(result.stderr, /Error:/);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
