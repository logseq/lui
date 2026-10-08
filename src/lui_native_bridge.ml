(* Shared native-host bridge: patch accumulation and the standard
   lui_<prefix>_* callback table.

   A dispatch can flush more than once. Batches are kept in arrival order
   and joined with newlines so the C bridge can deliver each one; a single
   string slot used to drop every batch but the last when flush re-entered.
   A second init disposes the previous app before installing the new one.

   Pure OCaml (no C primitive, no [Callback] reference) so the lui library
   can still compile to Melange. Host dylibs pass [Callback.register]. *)

open Lui_protocol

type session = {mutable patches : string list}

type bridge = {
  name : string;
  session : session;
  mutable trace : (patch_batch -> unit) option;
  mutable note_extension : (string -> string -> unit) option;
  mutable dispatch : (event -> bool) option;
  mutable flush : (unit -> bool) option;
  mutable dispose_current : (unit -> bool) option;
  mutable root : (unit -> int) option;
  mutable resync : (unit -> string) option;
}

let create name =
  {
    name;
    session = {patches = []};
    trace = None;
    note_extension = None;
    dispatch = None;
    flush = None;
    dispose_current = None;
    root = None;
    resync = None;
  }

let clear bridge = bridge.session.patches <- []

let take bridge =
  let text =
    match bridge.session.patches with
    | [] -> ""
    | [only] -> only
    | many -> String.concat "\n" (List.rev many)
  in
  bridge.session.patches <- [];
  text

let record bridge batch =
  (match bridge.trace with Some trace -> trace batch | None -> ());
  bridge.session.patches <- Lui_wire.encode_batch batch :: bridge.session.patches;
  true

let operating_system = function
  | 1 -> MacOS
  | 2 -> IOS
  | 3 -> AndroidOS
  | 4 -> LinuxOS
  | 5 -> WindowsOS
  | _ -> GenericOS

let host_kind = function
  | 1 -> WebHost
  | 2 -> SwiftUIHost
  | 4 -> KotlinHost
  | 6 -> GPUIHost
  | _ -> GenericHost

let profile platform_code host_code =
  Lui_protocol.profile (operating_system platform_code) (host_kind host_code)

let backend bridge host_profile =
  {backend_profile = host_profile; apply_batch = record bridge}

let attach bridge (app : ('model, 'action) Lui_app.reducer_app) =
  bridge.dispatch <- Some (fun event -> Lui_app.dispatch_event app event);
  bridge.flush <- Some (fun () -> Lui_app.flush app);
  bridge.dispose_current <- Some (fun () -> Lui_app.dispose app);
  bridge.root <- Some (fun () -> Lui_app.root_node app);
  bridge.resync <-
    Some
      (fun () ->
        Lui_wire.encode_batch (Lui_runtime.resync_batch (Lui_app.runtime app)))

(* Replace a running app. Dispose patches are dropped so the host receives
   only the new app's startup batches. *)
let boot bridge app =
  (match bridge.dispose_current with
  | Some dispose -> ignore (dispose ())
  | None -> ());
  clear bridge;
  attach bridge app;
  ignore (Lui_app.start app);
  ignore (Lui_app.flush app);
  take bridge

let require_started bridge =
  match bridge.dispatch, bridge.flush with
  | Some dispatch, Some flush -> (dispatch, flush)
  | _ -> invalid_arg (bridge.name ^ " bridge is not started")

let dispatch_event bridge event =
  let dispatch, flush = require_started bridge in
  clear bridge;
  ignore (dispatch event);
  ignore (flush ());
  take bridge

let dispose bridge =
  clear bridge;
  (match bridge.dispose_current with
  | Some dispose -> ignore (dispose ())
  | None -> ());
  bridge.dispatch <- None;
  bridge.flush <- None;
  bridge.dispose_current <- None;
  bridge.root <- None;
  bridge.resync <- None;
  take bridge

let pointer_detail x y modifiers button target_class =
  {x; y; modifiers; button; target_class}

let register ~(register_named : 'a. string -> 'a -> unit) prefix bridge =
  let register suffix value = register_named (prefix ^ "_" ^ suffix) value in
  let node make node_id = dispatch_event bridge (make node_id) in
  register "appear" (node (fun id -> Appear id));
  register "press" (node (fun id -> Press id));
  register "press_ex" (fun id modifiers ->
      dispatch_event bridge (PressModifiers (id, modifiers)));
  register "long_press" (node (fun id -> LongPress id));
  register "text_changed" (fun id text ->
      dispatch_event bridge (TextChanged (id, text)));
  register "submit" (node (fun id -> Submit id));
  register "dismiss" (node (fun id -> Dismiss id));
  register "picked" (fun id payload ->
      dispatch_event bridge (Picked (id, payload)));
  register "double_press" (node (fun id -> DoublePress id));
  register "toggle_changed" (fun id checked ->
      dispatch_event bridge (ToggleChanged (id, checked)));
  register "radio_changed" (node (fun id -> Change id));
  register "slider_changed" (fun id value ->
      dispatch_event bridge (ValueChanged (id, value)));
  register "press_detail" (fun id x y modifiers button target_class ->
      dispatch_event bridge
        (PressDetail (id, pointer_detail x y modifiers button target_class)));
  register "pointer_down" (fun id x y modifiers button target_class ->
      dispatch_event bridge
        (PointerDown (id, pointer_detail x y modifiers button target_class)));
  register "pointer_up" (fun id x y modifiers button target_class ->
      dispatch_event bridge
        (PointerUp (id, pointer_detail x y modifiers button target_class)));
  register "pointer_enter" (node (fun id -> PointerEnter id));
  register "pointer_leave" (node (fun id -> PointerLeave id));
  register "context_menu_press" (fun id x y modifiers button target_class ->
      dispatch_event bridge
        (ContextMenuPress
           (id, pointer_detail x y modifiers button target_class)));
  register "load" (node (fun id -> Load id));
  register "visible_range" (fun id first last ->
      dispatch_event bridge (VisibleRange (id, first, last)));
  register "scroll_completed" (fun id token outcome ->
      dispatch_event bridge (ScrollCompleted (id, token, outcome)));
  register "extension_event" (fun id identifier name json_values ->
      (match bridge.note_extension with
      | Some note -> note name json_values
      | None -> ());
      let values =
        match Lui_json.parse_values json_values with
        | values -> values
        | exception Lui_json.Parse_error message ->
          invalid_arg ("invalid extension event payload: " ^ message)
      in
      dispatch_event bridge (ExtensionEvent (id, identifier, name, values)));
  register "dispose" (fun () -> dispose bridge);
  register "root_node" (fun () ->
      match bridge.root with
      | Some root -> root ()
      | None -> invalid_arg (bridge.name ^ " bridge is not started"));
  register "resync" (fun () ->
      match bridge.resync with Some resync -> resync () | None -> "")
