(* In-process driver: mounts a real LUI app (view + reducer) against a
   recording backend that replays every patch op into a queryable Model.
   Events are injected through Lui_app.dispatch_event — the same path the
   native host uses — so tests exercise the real view/reducer wiring. *)

open Lui_protocol

(* Minimal driver surface shared by the in-process session and the FFI
   target: scenarios only need these. [tap] injects a coordinate-space
   press resolved against host-reported frames — only live attach has
   them; other drivers report an error. [frames] exposes the latest
   reported frames for `dump-frames`. *)
type driver = {
  tree : Model.t;
  send_event : event -> unit;
  poll : unit -> unit;
  tap : x:float -> y:float -> (int, string) result;
  frames : unit -> (int * Model.rect) list;
  (* live attach only: ask the host page to navigate (location.hash).
     In-process drivers have no location; this is a no-op there. *)
  send_nav : string -> unit;
}

let no_frames () = []

let tap_unsupported ~x:_ ~y:_ =
  Error "coordinate tap needs host-reported frames (live attach only)"

type ('model, 'action) t = {
  app : ('model, 'action) Lui_app.reducer_app;
  tree : Model.t;
  drain : unit -> 'action list;
}

let mount ?(drain = fun () -> []) ?registry ~profile ~initial ~reducer ~view () =
  let tree = Model.create () in
  let backend =
    { backend_profile = profile; apply_batch = (fun b -> Model.apply_batch tree b; true) }
  in
  let app =
    match registry with
    | Some r -> Lui_app.create_with_extensions backend r initial reducer view
    | None -> Lui_app.create backend initial reducer view
  in
  ignore (Lui_app.start app);
  ignore (Lui_app.flush app);
  { app; tree; drain }

let flush s = ignore (Lui_app.flush s.app)

(* drain external actions, then ALWAYS flush: event handlers are run by
   the scheduler during flush, so skipping it leaves effects queued. *)
let poll s =
  List.iter (fun a -> ignore (Lui_app.send s.app a)) (s.drain ());
  flush s

let dispatch s ev =
  ignore (Lui_app.dispatch_event s.app ev);
  poll s

let press s node = dispatch s (Press node)
let long_press s node = dispatch s (LongPress node)
let double_press s node = dispatch s (DoublePress node)
let text_changed s node text = dispatch s (TextChanged (node, text))
let submit s node = dispatch s (Submit node)
let dismiss s node = dispatch s (Dismiss node)
let appear s node = dispatch s (Appear node)
let toggle s node checked = dispatch s (ToggleChanged (node, checked))
let change s node = dispatch s (Change node)
let value_changed s node v = dispatch s (ValueChanged (node, v))
let extension_event s ~node ~identifier ~name ~fields =
  dispatch s (ExtensionEvent (node, identifier, name, fields))

let read_model s = Lui_app.model s.app
let root_node s = Lui_app.root_node s.app

let driver s =
  {
    tree = s.tree;
    send_event = (fun ev -> dispatch s ev);
    poll = (fun () -> poll s);
    tap = tap_unsupported;
    frames = no_frames;
    send_nav = (fun _ -> ());
  }

let dispose s = ignore (Lui_app.dispose s.app)

(* Resolve a selector to a single node, erroring with a tree dump. *)
let resolve (d : driver) sel =
  match Model.first d.tree sel with
  | Some n -> n
  | None ->
    failwith
      (Printf.sprintf "drive: no node matches selector; tree:\n%s" (Model.dump d.tree))
