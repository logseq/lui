import assert from "node:assert/strict"
import { mkdtempSync, writeFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { spawnSync } from "node:child_process"
import test from "node:test"
import { fileURLToPath } from "node:url"

const root = fileURLToPath(new URL("../../", import.meta.url))
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
