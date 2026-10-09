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
    run(["dune", "build", "ppx/lui_ppx.cmxa", "src/lui.cmxa"])
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
