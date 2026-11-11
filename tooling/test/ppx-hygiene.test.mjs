import assert from "node:assert/strict"
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { spawnSync } from "node:child_process"
import test from "node:test"
import { fileURLToPath } from "node:url"

const root = fileURLToPath(new URL("../../", import.meta.url))

test("PPX nesting diagnostics reject static illegal edges without guessing opaque values", () => {
  const dir = mkdtempSync(join(tmpdir(), "lui-nesting-"))
  const run = args => spawnSync("opam", ["exec", "--", ...args], {cwd: root, encoding: "utf8"})
  const success = args => {
    const result = run(args)
    assert.equal(result.status, 0, result.stdout + result.stderr)
  }
  try {
    success(["dune", "build", "ppx/lui_ppx.cmxa", "src/lui.cmxa"])
    writeFileSync(join(dir, "driver.ml"), "let () = Ppxlib.Driver.standalone ()\n")
    success(["ocamlfind", "ocamlopt", "-package", "ppxlib", "-linkpkg", "-linkall",
      "_build/default/ppx/lui_ppx.cmxa", join(dir, "driver.ml"), "-o", join(dir, "driver")])
    const cases = [
      ["context_menu [button []]", "context-menu", "button"],
      ["dropdown_menu [column []]", "dropdown-menu", "column"],
      ["toolbar [column []]", "toolbar", "column"],
      ['tree [text ~value:"bad" []]', "tree", "text"],
      ["menu_trigger [menu_item []]", "menu-trigger", "menu-item"],
      ["input_group (text_field [])", "input-group", "text-field"],
      ["input [button []]", "input", "button"],
      ["context_menu [if_ ~test:source (button [])]", "context-menu", "button"],
      ["context_menu [reactive (fun _ -> button []) source]", "context-menu", "button"],
      ["context_menu [keyed ~source:items ~key:Fun.id ~cmp:compare ~mount:(fun _ -> button [])]", "context-menu", "button"],
      ["context_menu [align `center (button [])]", "context-menu", "button"],
      ["context_menu [scoped (fun _ -> button [])]", "context-menu", "button"],
      ["context_menu (List.map (fun _ -> button []) [1])", "context-menu", "button"],
      ["context_menu ([menu_item []] @ [button []])", "context-menu", "button"],
      ["context_menu [if true then menu_item [] else button []]", "context-menu", "button"],
      ["context_menu [match true with true -> menu_item [] | false -> button []]", "context-menu", "button"],
      ["Lui_elements.context_menu [Lui_elements.button []]", "context-menu", "button"],
      ["Lui_elements.(context_menu [button []])", "context-menu", "button"],
      ["let child = button [] in context_menu [child]", "context-menu", "button"],
      ["let build child = context_menu [child] in build (button [])", "context-menu", "button"],
      ["let build = context_menu ~disabled:false in build [button []]", "context-menu", "button"],
      ["context_menu [if_ ~test:source (if_ ~test:source (menu_item []))]", "context-menu", "box"],
      ["context_menu [virtual_rows ~source:items ~key:Fun.id ~cmp:compare ~mount:(fun _ -> row []) ()]", "context-menu", "virtual-rows"],
      ["context_menu [menu_item []; divider []]"],
      ["dropdown_menu [menu_trigger [dropdown_menu [menu_item []]]]"],
      ['toolbar [button []; text ~value:"ok" []; spacer []]'],
      ['tree [row [text ~value:"ok" []]; virtual_list []]'],
      ["input [context_menu [menu_item []]]"],
      ["context_menu [reactive (fun _ -> menu_item []) source]"],
      ['list [list_section ~header:(text ~value:"Title" []) [list_item []]]'],
      ["let button _ = menu_item [] in context_menu [button []]"],
      ["(fun button -> context_menu [button []]) (fun _ -> menu_item [])"],
      ["let module Other = struct let button _ = menu_item [] end in context_menu [Other.button []]"],
      ["(fun opaque -> context_menu [opaque ()]) (fun () -> menu_item [])"],
      ["let child = menu_item [] in context_menu [child]"],
      ["virtual_list [virtual_rows ~source:items ~key:Fun.id ~cmp:compare ~mount:(fun _ -> row []) ()]"],
      ["let module E = Lui_elements in E.context_menu [E.menu_item []]"],
    ]
    // Reactive prop scopes must retain every restricted abstract child family.
    const typedFamilies = [
      ["step", "text", "string_of_bool", "[]", child => `stepper [${child}]`],
      ["timeline_item", "title", "string_of_bool", "[]", child => `timeline [${child}]`],
      ["bottom_tab", "selected", "Fun.id", "[]", child => `bottom_tabs [${child}]`],
      ["table_row", "selected", "Fun.id", "[table_cell []]", child => `table [${child}]`],
      ["table_cell", "text", "string_of_bool", "[]", child => `table [table_row [${child}]]`],
      ["radio", "checked", "Fun.id", "[]", child => `radio_group [${child}]`],
      ["input_group_actions", "background", '(fun value -> if value then "background" else "surface")',
        "[button []]", child => `input_group ~actions:(${child}) (textarea [])`],
      ["swipe_action", "text", "string_of_bool", "[]", child => `swipe_actions [${child}]`],
    ]
    for (const prefix of ["", "Lui_elements."]) {
      for (const [family, property, project, children, parent] of typedFamilies) {
        cases.push([parent(`${prefix}${family} ~${property}:(reactive ${project} source) ${children}`)])
        if (family !== "input_group_actions") {
          cases.push([parent(`${prefix}keyed_${family}
            ~source:(reactive (fun shown -> if shown then [1] else [2]) source)
            ~key:Fun.id ~cmp:Int.compare
            ~mount:(fun _item -> ${prefix}${family}
              ~${property}:(reactive ${project} source) ${children})`)])
        }
      }
    }
    cases.push(
      ['column [button ~text:(reactive string_of_bool source) []]'],
      ['let radio ~text_signal:_ _ = button [] in column [radio ~text:(reactive string_of_bool source) []]'],
      ['(fun radio -> column [radio ~text:(reactive string_of_bool source) []]) (fun ~text_signal:_ _ -> button [])'],
      ['(fun radio ?(child = radio ~text:(reactive string_of_bool source) []) () -> column [child]) (fun ~text_signal:_ _ -> button []) ()'],
      ['(fun radio -> function () -> column [radio ~text:(reactive string_of_bool source) []]) (fun ~text_signal:_ _ -> button []) ()'],
      ['match (fun ~text_signal:_ _ -> button []) with radio -> column [radio ~text:(reactive string_of_bool source) []]'],
      ['let radio ~text_signal:_ _ = button [] in radio_group [Lui_elements.radio ~checked:(reactive Fun.id source) []]'],
      ['let radio ~text_signal:_ _ = button [] in Lui_elements.(radio_group [radio ~checked:(reactive Fun.id source) []])'],
      ['bottom_tabs [table_cell ~text:(reactive string_of_bool source) []]', "bottom-tabs", "table-cell"],
      ['table [bottom_tab ~selected:(reactive Fun.id source) []]', "table", "bottom-tab"],
      ['context_menu [scoped_bottom_tab (fun _ -> bottom_tab ~selected:(reactive Fun.id source) [])]', "context-menu", "bottom-tab"],
    )
    for (const [expression, parent, child] of cases) {
      writeFileSync(join(dir, "probe.ml"), `open Lui_elements
let probe (source : bool Signal.signal)
    (items : int list Signal.signal) =
  let _ = ${expression} in ()
`)
      const result = run(["ocamlfind", "ocamlc", "-package", "ocaml-signal", "-c",
        "-ppx", `${join(dir, "driver")} --as-ppx`,
        "-I", "_build/default/src/.lui.objs/byte", join(dir, "probe.ml")])
      if (parent) {
        assert.notEqual(result.status, 0, `${expression} unexpectedly compiled`)
        assert.match(result.stderr, /LUI nesting:/, result.stderr)
        assert.ok(result.stderr.includes(`parent=${parent} child=${child}`), result.stderr)
        assert.match(result.stderr, /probe.ml.*line 4/s, result.stderr)
      } else {
        assert.equal(result.status, 0, `${expression}\n${result.stdout}${result.stderr}`)
      }
    }
    for (const program of [
      `open Lui_elements
let radio ~text_signal:_ _ = button []
let probe (source : bool Signal.signal) =
  column [radio ~text:(reactive string_of_bool source) []]`,
      `let radio ~text_signal:_ _ = Lui_elements.button []
open Lui_elements
let probe (source : bool Signal.signal) =
  radio_group [radio ~checked:(reactive Fun.id source) []]`,
    ]) {
      writeFileSync(join(dir, "probe.ml"), program)
      success(["ocamlfind", "ocamlc", "-package", "ocaml-signal", "-c",
        "-ppx", `${join(dir, "driver")} --as-ppx`,
        "-I", "_build/default/src/.lui.objs/byte", join(dir, "probe.ml")])
    }
    for (const [expression, expectedType] of [
      ["(scoped_bottom_tab (fun _ -> bottom_tab []) : t)", /bottom_tab_el/],
      ["scoped_bottom_tab (fun _ -> button [])", /bottom_tab_el/],
      ["radio_group [keyed_radio ~source:(reactive (fun _ -> [1]) source) ~key:Fun.id ~cmp:Int.compare ~mount:(fun _ -> button [])]", /radio_el/],
    ]) {
      writeFileSync(join(dir, "probe.ml"), `open Lui_elements\nlet invalid (source : bool Signal.signal) = ${expression}\n`)
      const result = run(["ocamlfind", "ocamlc", "-package", "ocaml-signal", "-c",
        "-ppx", `${join(dir, "driver")} --as-ppx`,
        "-I", "_build/default/src/.lui.objs/byte", join(dir, "probe.ml")])
      assert.notEqual(result.status, 0, `abstract child scope was weakened: ${expression}`)
      assert.match(result.stderr, expectedType, result.stderr)
    }
  } finally { rmSync(dir, {recursive: true, force: true}) }
})

test("nesting properties exhaust constructor pairs and generate static syntax and scopes", () => {
  const dir = mkdtempSync(join(tmpdir(), "lui-nesting-properties-"))
  const run = args => {
    const result = spawnSync("opam", ["exec", "--", ...args], {cwd: root, encoding: "utf8"})
    assert.equal(result.status, 0, result.stdout + result.stderr)
    return result.stdout
  }
  const schema = JSON.parse(readFileSync(join(root, "schema/components.json"), "utf8"))
  const constructors = schema.nodeKinds.filter(({wire}) => ![
    "root", "list-section-header", "list-section-footer",
  ].includes(wire)).map(({wire, lg}) => {
    const name = wire === "switch" ? "switch_" : wire.replaceAll("-", "_")
    const arity = name === "input_group" ? 1 : ["drawer", "split"].includes(name) ? 2 : 0
    return `(${JSON.stringify(name)}, Lui_protocol.${lg}, Lui_protocol.${lg}, ${arity})`
  })
  constructors.push('( "separator", Lui_protocol.Divider, Lui_protocol.Divider, 0)',
    '("menu", Lui_protocol.MenuTrigger, Lui_protocol.DropdownMenu, 0)',
    '("submenu", Lui_protocol.MenuTrigger, Lui_protocol.DropdownMenu, 0)')
  try {
    run(["dune", "build", "ppx/lui_ppx.cmxa", "src/lui.cmxa"])
    writeFileSync(join(dir, "properties.ml"), `
open Ppxlib
let constructors = [${constructors.join(";\n")}]
let checks = ref 0 and failures = ref 0
let contains text part =
  let n = String.length part in
  let rec loop i = i + n <= String.length text &&
    (String.sub text i n = part || loop (i + 1)) in
  loop 0
let admitted source =
  let input = Lexing.from_string source in
  Location.init input "property.ml";
  try ignore (Driver.map_structure (Parse.implementation input)); true with exn ->
    match Location.Error.of_exn exn with
    | Some error when contains (Location.Error.message error) "LUI nesting:" -> false
    | _ -> raise exn
let check expected source =
  incr checks;
  if admitted source <> expected then begin
    incr failures;
    if !failures <= 16 then Printf.eprintf "expected %s: %s\\n"
      (if expected then "admitted" else "rejected") source
  end
let element (name, _, _, arity) =
  match arity with
  | 0 -> name ^ " []"
  | 1 -> name ^ " (textarea [])"
  | _ -> name ^ " (column []) (column [])"
let parent (name, _, _, arity) child list =
  match arity with
  | 0 -> name ^ " (" ^ list ^ ")"
  | 1 -> name ^ " (" ^ child ^ ")"
  | _ -> name ^ " (" ^ child ^ ") (" ^ child ^ ")"
type shape = Node of Lui_protocol.node_kind | Dynamic of shape
let allowed parent child = Lui_protocol.can_contain_children parent &&
  Lui_protocol.child_kind_supported parent child
let rec mounted detached = function
  | Node kind -> kind, true
  | Dynamic child ->
    let kind, valid = mounted true child in
    if detached then Lui_protocol.Box, (valid && allowed Lui_protocol.Box kind)
    else kind, valid
let expected parent shape =
  let kind, valid = mounted false shape in valid && allowed parent kind
let static wrap = wrap, Fun.id
let dynamic wrap = wrap, (fun child -> Dynamic child)
let wrappers = [|
  static (fun e -> e);
  static (fun e -> "if flag then (" ^ e ^ ") else (" ^ e ^ ")");
  static (fun e -> "match flag with true -> (" ^ e ^ ") | false -> (" ^ e ^ ")");
  static (fun e -> "let child = (" ^ e ^ ") in child");
  static (fun e -> "let build () = (" ^ e ^ ") in build ()");
  static (fun e -> "(fun () -> (" ^ e ^ ")) ()");
  dynamic (fun e -> "reactive (fun _ -> (" ^ e ^ ")) source");
  dynamic (fun e -> "if_ ~test:source (" ^ e ^ ")");
  static (fun e -> "align \\x60center (" ^ e ^ ")");
  static (fun e -> "scoped (fun _ -> (" ^ e ^ "))");
  static (fun e -> "themed (" ^ e ^ ")");
  static (fun e -> "try (" ^ e ^ ") with Not_found -> (" ^ e ^ ")");
  dynamic (fun e -> "keyed ~source ~key:Fun.id ~cmp:compare ~mount:(fun _ -> (" ^ e ^ "))");
  static (fun e -> "let make = fun () -> (" ^ e ^ ") in make ()");
  static (fun e -> "((" ^ e ^ ") : Lui_elements.t)");
  static (fun e -> "let identity child = child in identity (" ^ e ^ ")");
  static (fun e -> "let child = (" ^ e ^ ") in Lui_elements.(child)");
  static (fun e -> "match (" ^ e ^ ") with child -> child");
  static (fun e -> "let a, child = (), (" ^ e ^ ") in child");
  static (fun e -> "(if flag then (fun () -> (" ^ e ^ ")) else (fun () -> (" ^ e ^ "))) ()");
  static (fun e -> "(match flag with true -> (fun () -> (" ^ e ^ ")) | false -> (fun () -> (" ^ e ^ "))) ()");
|]
let lists = [|
  (fun e -> "[" ^ e ^ "]");
  (fun e -> "let children = [" ^ e ^ "] in children");
  (fun e -> "List.map (fun _ -> (" ^ e ^ ")) [1]");
  (fun e -> "[" ^ e ^ "] @ []");
  (fun e -> "List.append [] [" ^ e ^ "]");
  (fun e -> "if flag then [" ^ e ^ "] else []");
  (fun e -> "match flag with true -> [] | false -> [" ^ e ^ "]");
  (fun e -> "try [" ^ e ^ "] with Not_found -> []");
  (fun e -> "List.map (fun child -> child) [" ^ e ^ "]");
  (fun e -> "List.concat_map (fun child -> [child]) [" ^ e ^ "]");
|]
let () =
  List.iter (fun p -> List.iter (fun c ->
    let _, _, parent_kind, _ = p and _, child_kind, _, _ = c in
    Array.iter (fun (wrap, model) ->
      let e = wrap (element c) in
      check (expected parent_kind (model (Node child_kind)))
        ("open Lui_elements let _ = " ^ parent p e ("[" ^ e ^ "]"))) wrappers;
    Array.iter (fun children ->
      let e = element c in
      check (allowed parent_kind child_kind) ("open Lui_elements let _ = " ^ parent p e (children e))) lists
  ) constructors) constructors;
  let seed = 0x51a71c in
  let random = Random.State.make [|seed|] in
  for _ = 1 to 2000 do
    let p = List.nth constructors (Random.State.int random (List.length constructors)) in
    let c = List.nth constructors (Random.State.int random (List.length constructors)) in
    let _, _, pk, _ = p and _, ck, _, _ = c in
    let e = ref (element c) and shape = ref (Node ck) in
    for _ = 1 to 1 + Random.State.int random 4 do
      let wrap, model = wrappers.(Random.State.int random (Array.length wrappers)) in
      e := wrap !e; shape := model !shape
    done;
    let children = lists.(Random.State.int random (Array.length lists)) !e in
    check (expected pk !shape)
      ("open Lui_elements let _ = " ^ parent p !e children)
  done;
  List.iter (fun (name, _, _, _) ->
    check true ("open Lui_elements let " ^ name ^ " _ = menu_item [] let _ = context_menu [" ^ name ^ " []]");
    check true ("open Lui_elements let rec " ^ name ^ " _ = context_menu [" ^ name ^ " []] let _ = ()");
    check true ("open Lui_elements let _ = let module Lui_elements = struct let " ^ name ^ " _ = menu_item [] end in context_menu [Lui_elements." ^ name ^ " []]")
    ; check true ("open Lui_elements module type S = sig val " ^ name ^ " : unit -> t end let f (module Lui_elements : S) = context_menu [Lui_elements." ^ name ^ " ()]")
    ; check true ("open Lui_elements let _ = object val " ^ name ^ " = fun _ -> menu_item [] method view = context_menu [" ^ name ^ " []] end")
    ; check true ("open Lui_elements type element = t module rec Lui_elements : sig val " ^ name ^ " : unit -> element end = struct let " ^ name ^ " () = menu_item [] end let _ = context_menu [Lui_elements." ^ name ^ " ()]")
  ) constructors;
  check false ("open Lui_elements let _ = context_menu [" ^
    String.concat ";" (List.init 200 (fun _ -> "menu_item []")) ^ ";button []]");
  check false "open Lui_elements let _ = let child = button [] in Lui_elements.(context_menu [child])";
  check false "module E = Lui_elements let _ = E.context_menu [E.button []]";
  check false "open Lui_elements let wrap child = context_menu [child] let _ = wrap (button [])";
  check false "open Lui_elements let make = context_menu ~disabled:false let _ = make [button []]";
  check true "open Lui_elements module List = struct let map _ _ = [menu_item []] end let _ = context_menu (List.map (fun _ -> button []) [1])";
  let rows = "virtual_rows ~source ~key:Fun.id ~cmp:compare ~mount:(fun _ -> row []) ()" in
  List.iter (fun (name, _, _, _) ->
    let p = List.find (fun (candidate, _, _, _) -> candidate = name) constructors in
    check (name = "virtual_list") ("open Lui_elements let _ = " ^ parent p rows ("[" ^ rows ^ "]"))
  ) constructors;
  check false ("open Lui_elements let _ = virtual_list [row []; " ^ rows ^ "]");
  check false ("open Lui_elements let _ = virtual_list (List.map (fun _ -> " ^ rows ^ ") [1;2])");
  check true ("open Lui_elements let _ = virtual_list (if flag then [" ^ rows ^ "] else [row []; row []])");
  check false ("open Lui_elements let _ = virtual_list [if_ ~test:source (" ^ rows ^ ")]");
  check false "open Lui_elements let _ = context_menu [if_ ~test:source (if_ ~test:source (menu_item []))]";
  check true "open Lui_elements let _ = column [if_ ~test:source (if_ ~test:source (menu_item []))]";
  check true "open Lui_elements let f flag = let child = if flag then dropdown_menu [] else context_menu [] in if flag then menu_trigger [child] else button [child]";
  check true "open Lui_elements let f context = let child = if Lui_ui.host context = KotlinHost then dropdown_menu [] else context_menu [] in if Lui_ui.host context = KotlinHost then menu_trigger [child] else button [child]";
  check true "open Lui_elements let f flag = let child = if flag then dropdown_menu [] else context_menu [] in let same = flag in if not same then button [child] else menu_trigger [child]";
  check true "open Lui_elements let f flag = let child = if flag then dropdown_menu [] else context_menu [] in match flag with true -> menu_trigger [child] | false -> button [child]";
  check false "open Lui_elements let f flag other = let child = if flag then dropdown_menu [] else context_menu [] in let flag = other in if flag then menu_trigger [child] else button [child]";
  check false "open Lui_elements let f () = let child = if Random.bool () then dropdown_menu [] else context_menu [] in if Random.bool () then menu_trigger [child] else button [child]";
  check false "open Lui_elements let f flag = let child = if flag then context_menu [] else dropdown_menu [] in if flag then menu_trigger [child] else button [child]";
  for _ = 1 to 2000 do
    let pick () = List.nth constructors (Random.State.int random (List.length constructors)) in
    let p1 = pick () and p2 = pick () and c1 = pick () and c2 = pick () in
    let _, _, pk1, _ = p1 and _, _, pk2, _ = p2 in
    let _, ck1, _, _ = c1 and _, ck2, _, _ = c2 in
    let source = "open Lui_elements let f flag = let child = if flag then (" ^ element c1 ^
      ") else (" ^ element c2 ^ ") in if flag then (" ^ parent p1 "child" "[child]" ^
      ") else (" ^ parent p2 "child" "[child]" ^ ")" in
    check (allowed pk1 ck1 && allowed pk2 ck2) source
  done;
  Printf.printf "%d property checks; seed=%d; failures=%d\\n" !checks seed !failures;
  if !failures <> 0 then exit 1
`)
    run(["ocamlfind", "ocamlopt", "-package", "ppxlib,ocaml-signal,yojson", "-linkpkg", "-linkall",
      "-I", "_build/default/src/.lui.objs/byte", "-I", "_build/default/src/.lui.objs/native",
      "_build/default/src/lui.cmxa", "_build/default/ppx/lui_ppx.cmxa",
      join(dir, "properties.ml"), "-o", join(dir, "properties")])
    const result = run([join(dir, "properties")])
    assert.match(result, /failures=0/)
    console.log(result.trim())
  } finally { rmSync(dir, {recursive: true, force: true}) }
})

test("reactive expansion preserves closure variables and source expressions", () => {
  const dir = mkdtempSync(join(tmpdir(), "lui-ppx-test-"))
  const run = (args) => {
    const result = spawnSync("opam", ["exec", "--", ...args], { cwd: root, encoding: "utf8" })
    assert.equal(result.status, 0, result.stdout + result.stderr)
    return result.stdout
  }
  try {
    run(["dune", "build", "--root", root, "ppx/lui_ppx.cmxa", "src/lui.cmxa"])
    writeFileSync(join(dir, "driver.ml"), "let () = Ppxlib.Driver.standalone ()\n")
    run(["ocamlfind", "ocamlopt", "-package", "ppxlib", "-linkpkg", "-linkall",
      "_build/default/ppx/lui_ppx.cmxa", join(dir, "driver.ml"), "-o", join(dir, "driver")])
    writeFileSync(join(dir, "probe.ml"), `
let consume ~test = test
let () =
  let scheduler = Signal.scheduler () in
  let source n = Signal.value (Signal.state scheduler n) in
  let v1 = 100 and v2 = 200 and v3 = 300 in
  let result = consume ~test:(reactive (fun a b c -> v1 + v2 + v3 + a + b + c)
    (source 1) (source 2) (source 3)) in
  assert (Signal.sample result = v1 + v2 + v3 + 6);
  print_endline "ok"
`)
    run(["ocamlfind", "ocamlopt", "-package", "ocaml-signal", "-linkpkg", "-ppx",
      `${join(dir, "driver")} --as-ppx`, join(dir, "probe.ml"), "-o", join(dir, "probe")])
    assert.equal(run([join(dir, "probe")]).trim(), "ok")
    writeFileSync(join(dir, "ownership.ml"), `
let () =
  let observed = ref None in
  let conversions = ref 0 in
  let render_value value = incr conversions; string_of_int value in
  let backend = { Lui_protocol.backend_profile = Lui_protocol.generic_profile ();
    apply_batch = (fun _ -> true) } in
  let view _context model_source _send =
    observed := Some model_source;
    Lui_elements.column [
      (fun context parent ->
        Lui_elements.text ~value:(reactive render_value model_source) [] context parent);
      reactive (fun _ ->
        Lui_elements.text ~value:(reactive render_value model_source) []) model_source
    ] in
  let app = Lui_app.create backend 0 (fun _ next -> next) view in
  ignore (Lui_app.start app); ignore (Lui_app.flush app);
  let source = Option.get !observed in
  let baseline = ref None in
  for version = 1 to 20 do
    let before = !conversions in
    ignore (Lui_app.send app version); ignore (Lui_app.flush app);
    let work = !conversions - before in
    (match !baseline with
    | None -> baseline := Some work
    | Some initial when work <> initial ->
      failwith (Printf.sprintf "PPX branch derivations leak: %d -> %d" initial work)
    | Some _ -> ())
  done;
  if Signal.get source <> 20 then failwith "source stopped propagating";
  ignore (Lui_app.dispose app);
  print_endline "owned"
`)
    run(["ocamlfind", "ocamlopt", "-package", "ocaml-signal", "-linkpkg", "-ppx",
      `${join(dir, "driver")} --as-ppx`, "-I", "_build/default/src/.lui.objs/byte",
      "-I", "_build/default/src/.lui.objs/native", "_build/default/src/lui.cmxa",
      join(dir, "ownership.ml"), "-o", join(dir, "ownership")])
    assert.equal(run([join(dir, "ownership")]).trim(), "owned")

  } finally { rmSync(dir, { recursive: true, force: true }) }
})


test("reactive column layout updates retain children and mount-owned derivations", () => {
  const dir = mkdtempSync(join(tmpdir(), "lui-layout-signal-test-"))
  const run = args => {
    const result = spawnSync("opam", ["exec", "--", ...args], {cwd: root, encoding: "utf8"})
    assert.equal(result.status, 0, result.stdout + result.stderr)
    return result.stdout
  }
  try {
    run(["dune", "build", "--root", root, "ppx/lui_ppx.cmxa", "src/lui.cmxa"])
    writeFileSync(join(dir, "driver.ml"), "let () = Ppxlib.Driver.standalone ()\n")
    run(["ocamlfind", "ocamlopt", "-package", "ppxlib", "-linkpkg", "-linkall",
      "_build/default/ppx/lui_ppx.cmxa", join(dir, "driver.ml"), "-o", join(dir, "driver")])
    writeFileSync(join(dir, "layout.ml"), `
let () =
  let batches = ref [] in
  let conversions = ref 0 in
  let display visible = incr conversions; if visible then \`inline_flex else \`none in
  let backend = { Lui_protocol.backend_profile = Lui_protocol.generic_profile ();
    apply_batch = (fun batch -> batches := batch :: !batches; true) } in
  let view _context source _send =
    Lui_elements.column
      ~grow:(reactive (fun visible -> if visible then 1. else 0.) source)
      ~display:(reactive display source)
      [Lui_elements.input ~text:"Retained draft" []] in
  let app = Lui_app.create backend true (fun _ next -> next) view in
  ignore (Lui_app.start app); ignore (Lui_app.flush app);
  let initial_conversions = !conversions in
  List.iteri (fun index visible ->
    batches := [];
    ignore (Lui_app.send app visible); ignore (Lui_app.flush app);
    let ops = List.concat_map (fun (b : Lui_protocol.patch_batch) -> b.ops) !batches in
    let shown = if visible then "inline-flex" else "none" in
    let growth = if visible then 1. else 0. in
    assert (List.exists (function
      | Lui_protocol.SetProp (_, Lui_protocol.DisplayValue, Lui_protocol.StringValue value) -> value = shown
      | _ -> false) ops);
    assert (List.exists (function
      | Lui_protocol.SetProp (_, Lui_protocol.GrowValue, Lui_protocol.FloatValue value) -> value = growth
      | _ -> false) ops);
    assert (not (List.exists (function
      | Lui_protocol.CreateNode _ | Lui_protocol.DropNode _ -> true
      | _ -> false) ops));
    assert (!conversions = initial_conversions + index + 1)
  ) [false; true; false; true];
  ignore (Lui_app.dispose app);
  print_endline "retained"
`)
    run(["ocamlfind", "ocamlopt", "-package", "ocaml-signal", "-linkpkg", "-ppx",
      `${join(dir, "driver")} --as-ppx`, "-I", "_build/default/src/.lui.objs/byte",
      "-I", "_build/default/src/.lui.objs/native", "_build/default/src/lui.cmxa",
      join(dir, "layout.ml"), "-o", join(dir, "layout")])
    assert.equal(run([join(dir, "layout")]).trim(), "retained")
  } finally { rmSync(dir, {recursive: true, force: true}) }
})

test("virtual_rows owns reactive sources for each mount and borrows caller signals", () => {
  const dir = mkdtempSync(join(tmpdir(), "lui-virtual-source-test-"))
  const run = args => {
    const result = spawnSync("opam", ["exec", "--", ...args], {cwd: root, encoding: "utf8"})
    assert.equal(result.status, 0, result.stdout + result.stderr)
    return result.stdout
  }
  try {
    run(["dune", "build", "--root", root, "ppx/lui_ppx.cmxa", "src/lui.cmxa"])
    writeFileSync(join(dir, "driver.ml"), "let () = Ppxlib.Driver.standalone ()\n")
    run(["ocamlfind", "ocamlopt", "-package", "ppxlib", "-linkpkg", "-linkall",
      "_build/default/ppx/lui_ppx.cmxa", join(dir, "driver.ml"), "-o", join(dir, "driver")])
    writeFileSync(join(dir, "virtual_source.ml"), `
let observed_sources : string list Signal.signal list ref = ref []
module Actual_elements = Lui_elements
module Lui_elements = struct
  include Actual_elements
  let virtual_rows ?scroll_key ~source ~key ~cmp ~mount () =
    observed_sources := source :: !observed_sources;
    Actual_elements.virtual_rows ?scroll_key ~source ~key ~cmp ~mount ()
end
open Lui_elements
let () =
  List.iter (fun fully_applied ->
    observed_sources := [];
    let conversions = ref 0 and borrowed = ref None in
    let project rows = incr conversions; rows in
    let backend = { Lui_protocol.backend_profile =
      Lui_protocol.profile Lui_protocol.WebOS Lui_protocol.WebHost;
      apply_batch = (fun _ -> true) } in
    let view context shown _send =
      let rows = Signal.state context.Lui_ui.ui_scheduler ["initial"] in
      borrowed := Some rows;
      let child =
        if fully_applied then
          (fun context parent ->
            Lui_elements.virtual_rows ~source:(reactive project (Signal.value rows))
              ~key:(fun row -> row) ~cmp:String.compare
              ~mount:(fun source -> text ~value_signal:source []) () context parent)
        else
          virtual_rows ~source:(reactive project (Signal.value rows))
            ~key:(fun row -> row) ~cmp:String.compare
            ~mount:(fun source -> text ~value_signal:source []) () in
      column [if_ ~test:shown (virtual_list ~height:100 ~item_extent:20. [child])] in
    let app = Lui_app.create backend true (fun _ shown -> shown) view in
    ignore (Lui_app.start app); ignore (Lui_app.flush app);
    let rows = Option.get !borrowed in
    for cycle = 1 to 20 do
      ignore (Lui_app.send app false); ignore (Lui_app.flush app);
      if not (List.for_all Signal.signal_is_disposed !observed_sources) then
        failwith "unmounted virtual_rows did not dispose its derived source";
      let before = !conversions in
      Signal.set rows ["hidden-" ^ string_of_int cycle];
      ignore (Lui_app.flush app);
      if !conversions <> before then failwith "unmounted virtual source is retained";
      ignore (Lui_app.send app true); ignore (Lui_app.flush app);
      let before = !conversions in
      Signal.set rows ["visible-" ^ string_of_int cycle];
      ignore (Lui_app.flush app);
      if !conversions - before <> 1 then failwith "virtual source derivations accumulate"
    done;
    ignore (Lui_app.dispose app);
    Signal.set rows ["borrowed survives"];
    Signal.stabilize app.Lui_app.app_scheduler;
    if Signal.sample (Signal.value rows) <> ["borrowed survives"] then
      failwith "virtual_rows disposed borrowed signal";
    Signal.dispose_signal (Signal.value rows)
  ) [false; true];
  print_endline "owned"
`)
    run(["ocamlfind", "ocamlopt", "-package", "ocaml-signal", "-linkpkg", "-ppx",
      `${join(dir, "driver")} --as-ppx`, "-I", "_build/default/src/.lui.objs/byte",
      "-I", "_build/default/src/.lui.objs/native", "_build/default/src/lui.cmxa",
      join(dir, "virtual_source.ml"), "-o", join(dir, "virtual_source")])
    assert.equal(run([join(dir, "virtual_source")]).trim(), "owned")
  } finally { rmSync(dir, {recursive: true, force: true}) }
})
