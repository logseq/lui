import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = fileURLToPath(new URL('../../', import.meta.url));

test('surface and toolbar styling preserves capabilities, defaults and reactive identity', () => {
  const dir = mkdtempSync(join(tmpdir(), 'lui-surface-style-'));
  const run = args => spawnSync('opam', ['exec', '--', ...args], { cwd: root, encoding: 'utf8' });
  const success = args => {
    const result = run(args);
    assert.equal(result.status, 0, result.stdout + result.stderr);
  };
  const props = [
    ['font_size', 'FontSize', '"14px"', 'StringValue "14px"', 'typography'],
    ['font_weight', 'FontWeight', '500', 'IntValue 500', 'typography'],
    ['font_family', 'FontFamily', '"sans-serif"', 'StringValue "sans-serif"', 'typography'],
    ['font_style', 'FontStyle', '`italic', 'StringValue "italic"', 'typography'],
    ['line_height', 'LineHeight', '"20px"', 'StringValue "20px"', 'typography'],
    ['letter_spacing', 'LetterSpacing', '0.5', 'FloatValue 0.5', 'typography'],
    ['text_decoration', 'TextDecoration', '"underline"', 'StringValue "underline"', 'typography'],
    ['white_space', 'WhiteSpace', '`nowrap', 'StringValue "nowrap"', 'text_flow'],
    ['text_overflow', 'TextOverflow', '`ellipsis', 'StringValue "ellipsis"', 'text_flow'],
    ['overflow', 'Overflow', '`hidden', 'StringValue "hidden"', 'make'],
    ['hover_background', 'HoverBackground', '"red"', 'StringValue "red"', 'make'],
    ['hover_foreground', 'HoverForeground', '"blue"', 'StringValue "blue"', 'make'],
    ['focus_within_background', 'FocusWithinBackground', '"green"', 'StringValue "green"', 'make'],
    ['focus_within_border', 'FocusWithinBorder', '"black"', 'StringValue "black"', 'make'],
    ['focus_shadow', 'FocusShadow', '"inset 0 0 0 2px blue"', 'StringValue "inset 0 0 0 2px blue"', 'make'],
    ['shadow', 'Shadow', '"0 2px 4px black"', 'StringValue "0 2px 4px black"', 'make'],
    ['cursor', 'Cursor', '`pointer', 'StringValue "pointer"', 'make'],
    ['user_select', 'UserSelect', '`none', 'StringValue "none"', 'typography'],
    ['disabled_opacity', 'DisabledOpacity', '0.5', 'FloatValue 0.5', 'make'],
    ['pressed_opacity', 'PressedOpacity', '0.7', 'FloatValue 0.7', 'make'],
    ['hover_opacity', 'HoverOpacity', '0.9', 'FloatValue 0.9', 'make'],
    ['max_height_viewport', 'MaxHeightViewport', '0.75', 'FloatValue 0.75', 'make'],
  ];
  const buildStyle = (entries, formatArg, extraByCtor = {}) => {
    const groups = new Map();
    for (const [ctor, args] of Object.entries(extraByCtor)) {
      groups.set(ctor, [...args]);
    }
    for (const entry of entries) {
      const ctor = entry[4];
      if (!groups.has(ctor)) groups.set(ctor, []);
      groups.get(ctor).push(formatArg(entry));
    }
    const parts = [...groups.entries()].map(
      ([ctor, args]) => `(Slot_style.${ctor} ${args.join(' ')} ())`
    );
    return `~style:${parts.reduce((acc, part) => `(Slot_style.merge ${acc} ${part})`)}`;
  };
  try {
    success(['dune', 'build', 'ppx/lui_ppx.cmxa', 'src/lui.cmxa']);
    writeFileSync(join(dir, 'driver.ml'), 'let () = Ppxlib.Driver.standalone ()\n');
    success(['ocamlfind', 'ocamlopt', '-package', 'ppxlib', '-linkpkg', '-linkall',
      '_build/default/ppx/lui_ppx.cmxa', join(dir, 'driver.ml'), '-o', join(dir, 'driver')]);
    const staticProps = buildStyle(props, ([name, , value]) => `~${name}:(${value})`);
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
      shadow: ['"none"', 'StringValue "none"'],
      cursor: ['`default', 'StringValue "default"'],
      user_select: ['`text', 'StringValue "text"'],
      disabled_opacity: ['0.4', 'FloatValue 0.4'],
      pressed_opacity: ['0.6', 'FloatValue 0.6'],
      hover_opacity: ['0.8', 'FloatValue 0.8'],
      max_height_viewport: ['0.5', 'FloatValue 0.5'],
    };
    const reactiveProps = buildStyle(
      props,
      ([name, , value]) =>
        `~${name}:(reactive (fun active -> if active then ${value} else ${initial[name][0]}) source)`,
      { typography: ['~font_size:"999px"'] }
    );
    const surfaceProps = props.filter(([name]) => !['white_space', 'text_overflow'].includes(name));
    const surfaceStaticProps = buildStyle(surfaceProps, ([name, , value]) => `~${name}:(${value})`);
    const surfaceReactiveProps = buildStyle(
      surfaceProps,
      ([name, , value]) =>
        `~${name}:(reactive (fun active -> if active then ${value} else ${initial[name][0]}) source)`,
      {
        collision: [
          '~collision_padding:99.',
          '~collision_padding:(reactive (fun active -> if active then 5. else 2.) source)',
        ],
      }
    );
    const checks = props.map(([name, wire, , value]) =>
      `${['white_space', 'text_overflow'].includes(name) ? 'if not (List.mem label ["surface"; "surface-adapter"; "json-surface"]) then ' : ''}check label (property node ${wire} = Some (if reactive && not active then ${initial[name][1]} else ${value}));`).join('\n');
    const jsonProps = props.map(([name, , , wire]) => {
      const value = wire.startsWith('StringValue')
        ? `Lui_json_view.Str ${wire.slice('StringValue '.length)}`
        : `Lui_json_view.Num ${Number(wire.split(' ')[1])}${Number.isInteger(Number(wire.split(' ')[1])) ? '.0' : ''}`;
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
  | SetProp (id, (TextValue | AccessibilityIdentifier | AccessibilityLabel), StringValue value) when value = label -> id
  | _ -> result) (-1) (ops ())
let property node prop = List.fold_left (fun result -> function
  | SetProp (id, key, value) when id = node && key = prop -> Some value
  | _ -> result) None (ops ())
let json_item label = Lui_json_view.Obj
  (["kind", Lui_json_view.Str (if label = "json-dropdown" then "menu-item" else "button"); "text", Lui_json_view.Str label]
   @ [${jsonProps}])
let json_icon label = Lui_json_view.Obj
  (["kind", Lui_json_view.Str "button"; "icon", Lui_json_view.Str "app:dots";
    "label", Lui_json_view.Str label] @ [${jsonProps}])
let json = Lui_json_view.Obj ["kind", Lui_json_view.Str "column";
  "children", Lui_json_view.Arr [json_item "json-ordinary"; json_icon "json-icon";
    Lui_json_view.Obj ["kind", Lui_json_view.Str "toolbar";
      "label", Lui_json_view.Str "Actions";
      "children", Lui_json_view.Arr [json_item "json-toolbar"; json_icon "json-toolbar-icon"]];
    Lui_json_view.Obj ["kind", Lui_json_view.Str "dropdown-menu";
      "children", Lui_json_view.Arr [json_item "json-dropdown"]]]]
let view _ source _ = column [
  button ~text:"lazy-merge"
    ~style:(Slot_style.merge
      (Slot_style.typography
        ~font_size:(reactive (fun active -> if active then "14px" else "12px") source)
        ~font_weight:(reactive (fun _ -> failwith "overridden projection evaluated") source) ())
      (Slot_style.typography ~font_weight:600 ())) [];
  button ~text:"merged"
    ~style:(Slot_style.merge
      (Slot_style.merge
        (Slot_style.typography ~font_size:(reactive (fun active -> if active then "12px" else "10px") source) ())
        (Slot_style.make ~hover_foreground:"red" ()))
      (Slot_style.typography ~font_size:"20px" ())) [];
  button ~text:"static" ${staticProps} [];
  button ~text:"ordinary" ${reactiveProps} [];
  toolbar ~label:"Actions" [toolbar_button ~text:"toolbar" ${reactiveProps} []];
  dropdown_menu_view (dropdown_menu [
    dropdown_menu_item ~text:"dropdown" ${reactiveProps} [];
    reactive_dropdown_menu_item (fun _ -> dropdown_menu_item ~text:"adapter"
      ${staticProps} []) source;
    dropdown_menu_item ~text:"default" [];
    dropdown_menu_item ~text:"empty" ~style:(Slot_style.make ()) []]);
  toolbar ~label:"Additional controls" [
    toolbar_text ~value:"toolbar-text" ${reactiveProps} [];
    toolbar_icon_button ~label:"toolbar-icon" ~icon:(\`app "dots") ${reactiveProps} []];
  dropdown_menu_view (dropdown_menu ~accessibility_identifier:"surface" ${surfaceReactiveProps}
     []);
  dropdown_menu_view (reactive_dropdown_menu (fun _ ->
    dropdown_menu ~accessibility_identifier:"surface-adapter" ${surfaceStaticProps} []) source);
  Lui_json_view.render ~on_event:(fun ~id:_ ~kind:_ ~fields:_ -> ())
    (Lui_json_view.Obj (["kind", Lui_json_view.Str "dropdown-menu";
      "accessibility-identifier", Lui_json_view.Str "json-surface"] @ [${jsonProps}]));
  dropdown_menu_view (dropdown_menu []);
  Lui_json_view.render ~on_event:(fun ~id:_ ~kind:_ ~fields:_ -> ()) json]
let () =
  let app = Lui_app.create backend false (fun _ value -> value) view in
  check "start" (Lui_app.start app);
  ignore (Lui_app.flush app);
  let verify active =
    List.iter (fun label -> let node = node label in check label (node >= 0);
      let reactive = List.mem label ["ordinary"; "toolbar"; "dropdown"; "toolbar-text"; "toolbar-icon"; "surface"] in
      ${checks}
      ()) ["static"; "ordinary"; "toolbar"; "dropdown"; "adapter";
        "json-ordinary"; "json-icon"; "json-toolbar"; "json-toolbar-icon"; "json-dropdown"; "toolbar-text"; "toolbar-icon";
        "surface"; "surface-adapter"; "json-surface"];
    check "collision padding" (property (node "surface") CollisionPadding = Some (FloatValue (if active then 5. else 2.)));
    check "merged override" (property (node "merged") FontSize = Some (StringValue "20px"));
    check "merged base" (property (node "merged") HoverForeground = Some (StringValue "red"));
    check "lazy merged projection" (property (node "lazy-merge") FontSize = Some (StringValue (if active then "14px" else "12px")));
    check "lazy merged override" (property (node "lazy-merge") FontWeight = Some (IntValue 600));
    check "empty font untouched" (property (node "empty") FontSize = None);
    check "empty hover untouched" (property (node "empty") HoverBackground = None);
    let node = node "default" in
    check "default font untouched" (property node FontSize = None);
    check "default hover untouched" (property node HoverBackground = None)
  in
  verify false;
  let retained = node "dropdown" in
  let retained_surface = node "surface" in
  let retained_control = node "toolbar" in
  check "send" (Lui_app.send app true);
  ignore (Lui_app.flush app);
  check "retained node" (retained = node "dropdown");
  check "retained surface identity" (node "surface" = retained_surface);
  check "retained control identity" (node "toolbar" = retained_control);
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
      'popover ~style:(Slot_style.collision ~collision_padding:8. ()) ~target:Cover []',
      'menu ~style:(Slot_style.collision ~collision_padding:8. ()) []',
      'submenu ~style:(Slot_style.collision ~collision_padding:8. ()) []',
      'switch_ ~style:(Slot_style.make ~cursor:`pointer ()) []',
      'checkbox ~style:(Slot_style.typography ~font_size:"14px" ()) []',
    ]) {
      writeFileSync(join(dir, 'accepted.ml'), `open Lui_elements\nlet _ = ${expression}\n`);
      const result = run([...compile, '-c', join(dir, 'accepted.ml')]);
      assert.equal(result.status, 0, `${expression}\n${result.stdout}${result.stderr}`);
    }
    for (const expression of [
      'toolbar_button ~text:"Copy" ~font_weight:"bold" []',
      'dropdown_menu ~shadow:1 []',
      'toolbar ~label:"Actions" [column []]',
      'dropdown_menu_item ~font_style:`invalid []',
      'dropdown_menu [menu_item ~font_size:"14px" []]',
      'button ~text:"x" ~style:(Slot_style.collision ~collision_padding:5. ()) []',
      'switch_ ~style:(Slot_style.typography ~font_size:"14px" ()) []',
      'switch_ ~style:(Slot_style.text_flow ~white_space:`nowrap ()) []',
      'switch_ ~style:(Slot_style.collision ~collision_padding:5. ()) []',
      'checkbox ~style:(Slot_style.text_flow ~white_space:`nowrap ()) []',
      'checkbox ~style:(Slot_style.collision ~collision_padding:5. ()) []',
      'popover ~target:Cover ~style:(Slot_style.text_flow ~white_space:`nowrap ()) []',
      'dropdown_menu ~style:(Slot_style.text_flow ~white_space:`nowrap ()) []',
      'menu ~style:(Slot_style.text_flow ~white_space:`nowrap ()) []',
      'submenu ~style:(Slot_style.text_flow ~white_space:`nowrap ()) []',
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
