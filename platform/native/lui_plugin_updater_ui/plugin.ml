(* The plugin descriptor: the "updater" plugin the host registers.

   Its shape matches the plugin registry contract — [name], a
   [services] table of [string -> (string, string) result] methods,
   and [setup]. The services talk to a {!Session.t} bound with
   {!configure}; state transitions are pushed to the host as JSON
   events drained by the ["events"] service (poll-based push, the
   mechanism the registry allows).

   Wire-up:
   {[
     let s = Session.create ~feed ~bundle ~exe () in
     Plugin.configure_default s;  (* bind + start event push *)
     registry := Plugin.plugin :: !registry
   ]}

   A host may run several updaters — {!host} makes a fresh binding
   whose services come from {!services}. *)

type t = {
  name : string;
  services : (string * (string -> (string, string) result)) list;
  setup : unit -> unit;
}

(** A binding between the service table and one session. *)
type host = {
  session : Session.t option ref;
  events : string Queue.t;   (** pending transition events *)
}

let host () = { session = ref None; events = Queue.create () }

(* ---- JSON out ----------------------------------------------------------- *)

let quote s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t"
      | c when Char.code c < 0x20 ->
        Buffer.add_string b
          (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

let json_object fields =
  "{"
  ^ String.concat ","
      (List.map (fun (k, v) -> quote k ^ ":" ^ v) fields)
  ^ "}"

let string_of_error_kind = function
  | Session.Check_failed -> "check_failed"
  | Session.Download_failed -> "download_failed"
  | Session.Verify_failed -> "verify_failed"
  | Session.Stage_failed -> "stage_failed"
  | Session.Swap_failed -> "swap_failed"
  | Session.Cancelled -> "cancelled"
  | Session.Internal -> "internal"

let json_of_model (m : Session.model) : string =
  let extra =
    match m.Session.phase with
    | Session.Available o ->
      [ ("version", quote o.Session.version);
        ("size", string_of_int o.Session.size);
        ("notes", quote o.Session.notes) ]
    | Session.Downloading d ->
      [ ("version", quote d.Session.offer.Session.version);
        ("bytes_done", string_of_int d.Session.bytes_done);
        ("total", string_of_int d.Session.total);
        ( "eta",
          match d.Session.eta with
          | Some e -> Printf.sprintf "%.0f" e
          | None -> "null" ) ]
    | Session.Verifying o | Session.Staged { Session.offer = o; _ } ->
      [ ("version", quote o.Session.version) ]
    | Session.Ready_to_restart r ->
      [ ("version", quote r.Session.version);
        ("exe", quote r.Session.exe) ]
    | Session.Error e ->
      [ ("kind", quote (string_of_error_kind e.Session.kind));
        ("message", quote e.Session.message);
        ("retryable", string_of_bool e.Session.retryable) ]
    | Session.Idle | Session.Checking | Session.Up_to_date
    | Session.Closed ->
      []
  in
  json_object
    (("phase", quote (Session.phase_name m.Session.phase)) :: extra)

(* ---- the binding --------------------------------------------------------- *)

(* Subscribing before the host may poll: every model change lands in
   the event queue as it happens. *)
let configure ~h (s : Session.t) : host =
  h.session := Some s;
  let _unsub : unit -> unit =
    Session.on_change s (fun m -> Queue.add (json_of_model m) h.events)
  in
  h

(* ---- the service table ---------------------------------------------------- *)

let with_session h f =
  match !(h.session) with
  | None -> Stdlib.Error "updater: no session configured"
  | Some s -> f s

let services (h : host)
    : (string * (string -> (string, string) result)) list =
  [
    ( "check",
      fun _ -> with_session h (fun s -> Session.check ~user:true s; Stdlib.Ok "{}") );
    ( "download",
      fun _ -> with_session h (fun s -> Session.download s; Stdlib.Ok "{}") );
    ( "install",
      fun _ -> with_session h (fun s -> Session.install s; Stdlib.Ok "{}") );
    ( "cancel",
      fun _ -> with_session h (fun s -> Session.cancel s; Stdlib.Ok "{}") );
    ( "retry",
      fun _ -> with_session h (fun s -> Session.retry s; Stdlib.Ok "{}") );
    ( "relaunch",
      fun _ -> with_session h (fun s -> Session.relaunch s; Stdlib.Ok "{}") );
    ( "dismiss",
      fun _ -> with_session h (fun s -> Session.dismiss s; Stdlib.Ok "{}") );
    ( "status",
      fun _ -> with_session h (fun s -> Stdlib.Ok (json_of_model (Session.model s))) );
    ( "events",
      fun _ ->
        (* drain: everything since the last poll, oldest first *)
        let evts = Queue.fold (fun acc e -> e :: acc) [] h.events in
        Queue.clear h.events;
        Stdlib.Ok
          ("[" ^ String.concat "," (List.rev evts) ^ "]") );
  ]

let setup () = ()

(* ---- the shipped descriptor ------------------------------------------------ *)

(* The default binding most apps want: one updater, services over
   [default_host]; call [configure] to attach the session. *)
let default_host = host ()

let configure_default s = ignore (configure ~h:default_host s)

let plugin : t =
  { name = "updater"; services = services default_host; setup }
