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
  mutable agent : Lui_agent.target option;
  mutable last_failure : string option;
  mutable clock : Lui_clock.t option;
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
    agent = None;
    last_failure = None;
    clock = None;
  }

let clear bridge = bridge.session.patches <- []

(* A failed call leaves the host mirror behind the runtime: batches recorded
   before the exception are never delivered. The diagnostic tells the host
   what failed so it can report it and request [resync] instead of rendering
   whatever mounted before the throw. *)
let failure_json bridge ~phase ?node failure =
  let message = match failure with
    | Invalid_argument message | Failure message -> message
    | failure -> Printexc.to_string failure
  in
  let buffer = Buffer.create 160 in
  Buffer.add_string buffer "{\"bridge\":";
  Lui_wire.add_quoted buffer bridge.name;
  Buffer.add_string buffer ",\"phase\":";
  Lui_wire.add_quoted buffer phase;
  (match node with
  | Some node ->
    Buffer.add_string buffer ",\"node\":";
    Buffer.add_string buffer (string_of_int node)
  | None -> ());
  Buffer.add_string buffer ",\"message\":";
  Lui_wire.add_quoted buffer message;
  Buffer.add_string buffer ",\"recovery\":\"resync\"}";
  Buffer.contents buffer

let guarded bridge ~phase ?node run =
  bridge.last_failure <- None;
  match run () with
  | result -> result
  | exception failure ->
    clear bridge;
    bridge.last_failure <- Some (failure_json bridge ~phase ?node failure);
    raise failure

let last_failure bridge = bridge.last_failure

let take_failure bridge =
  let failure = bridge.last_failure in
  bridge.last_failure <- None;
  Option.value failure ~default:""

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
  | 2 | 258 -> SwiftUIHost
  | 4 | 260 -> KotlinHost
  | 5 -> MyGoHost
  | _ -> GenericHost

let profile platform_code host_code =
  Lui_protocol.profile (operating_system platform_code) (host_kind host_code)

let virtual_rows_supported = function
  | 1 | 5 | 258 | 260 -> true
  | _ -> false

let backend bridge host_profile =
  {backend_profile = host_profile; apply_batch = record bridge}

let attach bridge (app : ('model, 'action) Lui_app.reducer_app) =
  bridge.dispatch <- Some (fun event -> Lui_app.dispatch_event app event);
  bridge.flush <- Some (fun () -> Lui_app.flush app);
  bridge.dispose_current <- Some (fun () -> Lui_app.dispose app);
  bridge.root <- Some (fun () -> Lui_app.root_node app);
  bridge.clock <- Some (Lui_app.clock app);
  bridge.resync <-
    Some
      (fun () ->
        Lui_wire.encode_batch (Lui_runtime.resync_batch (Lui_app.runtime app)));
  bridge.agent <- Some (Lui_agent.app_target ~host:bridge.name app)

(* Replace a running app. Dispose patches are dropped so the host receives
   only the new app's startup batches. *)
let boot bridge app =
  guarded bridge ~phase:"boot" (fun () ->
    (match bridge.dispose_current with
    | Some dispose -> ignore (dispose ())
    | None -> ());
    clear bridge;
    attach bridge app;
    ignore (Lui_app.start app);
    ignore (Lui_app.flush app);
    take bridge)

let require_started bridge =
  match bridge.dispatch, bridge.flush with
  | Some dispatch, Some flush -> (dispatch, flush)
  | _ -> invalid_arg (bridge.name ^ " bridge is not started")

let dispatch_event bridge event =
  guarded bridge ~phase:"dispatch" ~node:(event_node event) (fun () ->
    let dispatch, flush = require_started bridge in
    clear bridge;
    ignore (dispatch event);
    ignore (flush ());
    take bridge)

let detach bridge =
  bridge.dispatch <- None;
  bridge.flush <- None;
  bridge.dispose_current <- None;
  bridge.root <- None;
  bridge.resync <- None;
  bridge.clock <- None;
  bridge.agent <- None

let dispose bridge =
  guarded bridge ~phase:"dispose" (fun () ->
    clear bridge;
    (match bridge.dispose_current with
    | Some dispose -> ignore (dispose ())
    | None -> ());
    detach bridge;
    take bridge)

let resync bridge =
  guarded bridge ~phase:"resync" (fun () ->
    match bridge.resync with Some resync -> resync () | None -> "")

let require_clock bridge =
  match bridge.clock with
  | Some clock -> clock
  | None -> invalid_arg (bridge.name ^ " bridge is not started")

let step_clock bridge step =
  guarded bridge ~phase:"clock" (fun () ->
    let _, flush = require_started bridge in
    let clock = require_clock bridge in
    clear bridge;
    ignore (step clock : int);
    ignore (flush ());
    take bridge)

let clock_tick bridge now = step_clock bridge (Lui_clock.tick ~now)

let clock_advance bridge ms = step_clock bridge (fun clock -> Lui_clock.advance clock ms)

let clock_set_paused bridge paused =
  guarded bridge ~phase:"clock" (fun () ->
    let clock = require_clock bridge in
    if paused then Lui_clock.pause clock else Lui_clock.resume clock;
    "")

(* Milliseconds until the host should tick again; negative when no wakeup
   is needed. *)
let clock_next_delay bridge =
  match bridge.clock with
  | Some clock -> Option.value (Lui_clock.next_delay clock) ~default:(-1.)
  | None -> -1.

(* The reply is the first line; patch batches produced by the request's
   action follow it, one per line, for the host to apply as after a
   dispatch. *)
let agent bridge request =
  guarded bridge ~phase:"agent" (fun () ->
    let target =
      match bridge.agent with
      | Some target -> target
      | None -> invalid_arg (bridge.name ^ " bridge is not started")
    in
    clear bridge;
    let reply = Lui_agent.handle target request in
    match take bridge with
    | "" -> reply
    | patches -> reply ^ "\n" ^ patches)

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
  register "navigate_previous" (node (fun id -> NavigatePrevious id));
  register "navigate_next" (node (fun id -> NavigateNext id));
  register "navigation_key" (fun id key shift ->
    dispatch_event bridge (NavigationKey (id, key, shift)));
  register "dismiss" (node (fun id -> Dismiss id));
  register "picked" (fun id payload ->
      dispatch_event bridge (Picked (id, payload)));
  register "double_press" (node (fun id -> DoublePress id));
  register "focus_within_changed" (fun id within ->
      dispatch_event bridge (FocusWithinChanged (id, within)));
  register "toggle_changed" (fun id checked ->
      dispatch_event bridge (ToggleChanged (id, checked)));
  register "toggle_changed_detail" (fun id checked modifiers ->
      dispatch_event bridge (ToggleChangedDetail (id, checked, modifiers)));
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
  register "pointer_move" (fun id x y modifiers button target_class ->
      dispatch_event bridge
        (PointerMove (id, pointer_detail x y modifiers button target_class)));
  register "pointer_cancel" (fun id x y modifiers button target_class ->
      dispatch_event bridge
        (PointerCancel (id, pointer_detail x y modifiers button target_class)));
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
  register "scroll_edges" (fun id at_start at_end ->
      dispatch_event bridge (ScrollEdges (id, at_start, at_end)));
  register "virtual_window" (fun id generation first last pins ->
      dispatch_event bridge (VirtualWindow (id, generation, first, last, pins)));
  register "extension_event" (fun id identifier name json_values ->
      (match bridge.note_extension with
      | Some note -> note name json_values
      | None -> ());
      let values =
        guarded bridge ~phase:"dispatch" ~node:id (fun () ->
          match Lui_json.parse_values json_values with
          | values -> values
          | exception Lui_json.Parse_error message ->
            invalid_arg ("invalid extension event payload: " ^ message))
      in
      dispatch_event bridge (ExtensionEvent (id, identifier, name, values)));
  register "dispose" (fun () -> dispose bridge);
  register "root_node" (fun () ->
      match bridge.root with
      | Some root -> root ()
      | None -> invalid_arg (bridge.name ^ " bridge is not started"));
  register "resync" (fun () -> resync bridge);
  register "last_error" (fun () -> take_failure bridge);
  register "clock_tick" (fun now -> clock_tick bridge now);
  register "clock_advance" (fun ms -> clock_advance bridge ms);
  register "clock_set_paused" (fun paused -> clock_set_paused bridge paused);
  register "clock_next_delay" (fun () -> clock_next_delay bridge);
  register "agent" (fun request -> agent bridge request)
