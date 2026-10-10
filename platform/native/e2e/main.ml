(* Manual driver: mounts the e2e app on the stub renderer and prints the
   store mirror and recorded scene ops after every step, so the whole
   patch_batch → store → paint → renderer pipeline can be eyeballed.
   Run with `dune exec platform/native/e2e/main.exe`. *)

open Lui_e2e
open Lui_protocol

let show_store store label =
  Printf.printf "== %s (nodes=%d gen=%d)\n%!" label
    (Lui_store.node_count store) (Lui_store.generation store);
  List.iter
    (fun id ->
      Printf.printf "  id=%-3d kind=%-11s parent=%-3s kids=[%s] text=%s\n%!"
        id (Lui_store.kind store id)
        (match Lui_store.parent store id with
         | Some p -> string_of_int p
         | None -> "-")
        (String.concat "," (List.map string_of_int
            (Lui_store.child_ids store id)))
        (match Lui_store.prop store id "text" with
         | Some (StringValue s) -> s
         | _ -> "-"))
    (Lui_store.preorder store)

let show_scene h label =
  let ops = E2e_harness.repaint h in
  Printf.printf "== %s ops=[ %s ] frames=%d bytes=%d\n%!" label
    (String.concat " " (E2e_harness.op_names ops))
    (E2e_harness.cap h).frames (E2e_harness.cap h).bytes

let require = function
  | Some id -> id
  | None -> failwith "node not found"

let () =
  let h = E2e_harness.create () in
  let backend = E2e_harness.backend h (generic_profile ()) in
  let app = Lui_app.create backend E2e_app.initial E2e_app.update E2e_app.view in
  let store = E2e_harness.store h in
  ignore (Lui_app.start app);
  ignore (Lui_app.flush app);
  show_store store "boot";
  show_scene h "repaint";

  let fid =
    match E2e_harness.kind_nodes store "text-field" with
    | id :: _ -> id
    | [] -> failwith "no text-field"
  in
  ignore (Lui_app.dispatch_event app (TextChanged (fid, "gamma")));
  ignore (Lui_app.flush app);
  show_store store "after TextChanged gamma";

  let add = require (E2e_harness.find_text_id store "button" "add") in
  ignore (Lui_app.dispatch_event app (Press add));
  ignore (Lui_app.flush app);
  show_store store "after Press add";
  show_scene h "repaint";

  let del = require (E2e_harness.find_text_id store "button" "x-beta") in
  ignore (Lui_app.dispatch_event app (Press del));
  ignore (Lui_app.flush app);
  show_store store "after Press x-beta";
  show_scene h "repaint";

  let up = require (E2e_harness.find_text_id store "button" "^-gamma") in
  ignore (Lui_app.dispatch_event app (Press up));
  ignore (Lui_app.flush app);
  show_store store "after Press ^-gamma";

  ignore (Lui_app.dispose app);
  show_store store "after dispose"
