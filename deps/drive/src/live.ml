(* Live attach driver: connect to a running app's MENG_DRIVE_SOCKET
   Unix socket. The app replays every patch batch emitted since start
   (one JSON object per line) then streams live ones — the exact same
   stream the native renderer sees. Events are injected as newline JSON
   { "event": "press", "id": N, ... }.

   Hosts that report node frames additionally interleave
   {"frames":[[id,x,y,w,h],...]} lines (window coordinates, top-left
   origin, full snapshot each time). Those feed [hit_test] so a
   coordinate `tap x,y` resolves to the node a real gesture recognizer
   would fire on. *)
open Lui_protocol

type t = {
  send_line : string -> unit;
  queue : string Queue.t;
  mu : Mutex.t;
  tree : Model.t;
  frames : (int, Model.rect) Hashtbl.t;
}

let enqueue t line =
  Mutex.lock t.mu;
  Queue.add line t.queue;
  Mutex.unlock t.mu

let connect ~socket_path =
  let sock = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  Unix.connect sock (Unix.ADDR_UNIX socket_path);
  let oc = Unix.out_channel_of_descr sock in
  let t =
    {
      send_line =
        (fun s ->
          output_string oc s;
          output_char oc '\n';
          flush oc);
      queue = Queue.create ();
      mu = Mutex.create ();
      tree = Model.create ();
      frames = Hashtbl.create 64;
    }
  in
  ignore
    (Thread.create
       (fun () ->
          let ic = Unix.in_channel_of_descr sock in
          try
            while true do
              enqueue t (input_line ic)
            done
          with _ -> ())
       ());
  t

(* Browser hosts cannot accept connections, so for web attach the page
   dials out: `drive --ws-listen <port>` accepts a WebSocket and speaks
   the same line protocol (each text message = one line). *)
let listen_ws ~port =
  let srv = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt srv Unix.SO_REUSEADDR true;
  Unix.bind srv (Unix.ADDR_INET (Unix.inet_addr_loopback, port));
  Unix.listen srv 1;
  Printf.eprintf
    "drive: ws listening on 127.0.0.1:%d — open the host page with\n\
     drive:   ?drive=ws://127.0.0.1:%d\n%!"
    port port;
  let conn, _ = Unix.accept srv in
  Unix.close srv;
  Unix.setsockopt conn Unix.TCP_NODELAY true;
  let ic = Unix.in_channel_of_descr conn
  and oc = Unix.out_channel_of_descr conn in
  if not (Ws.accept_handshake ic oc) then
    failwith "drive: bad websocket handshake";
  let t =
    {
      send_line = (fun s -> Ws.write_frame oc s);
      queue = Queue.create ();
      mu = Mutex.create ();
      tree = Model.create ();
      frames = Hashtbl.create 64;
    }
  in
  ignore
    (Thread.create
       (fun () ->
          try
            let frags = Buffer.create 4096 in
            let rec loop () =
              match Ws.read_frame ic with
              | `Text (payload, true) ->
                if Buffer.length frags = 0 then enqueue t payload
                else begin
                  Buffer.add_string frags payload;
                  enqueue t (Buffer.contents frags);
                  Buffer.clear frags
                end;
                loop ()
              | `Text (payload, false) ->
                Buffer.add_string frags payload;
                loop ()
              | `Cont (payload, fin) ->
                Buffer.add_string frags payload;
                if fin then begin
                  enqueue t (Buffer.contents frags);
                  Buffer.clear frags
                end;
                loop ()
              | `Ping payload ->
                Ws.write_frame oc ~opcode:10 payload;
                loop ()
              | `Pong | `Skip -> loop ()
              | `Close | `Eof -> ()
            in
            loop ()
          with _ -> ())
       ());
  t

(* One line from the socket: either a frames snapshot or a patch batch.
   Exposed for tests — the reader thread queues raw lines and drain
   applies them through here. *)
let ingest_line t line =
  let json = Yojson.Safe.from_string line in
  match Yojson.Safe.Util.member "frames" json with
  | `List entries ->
    Hashtbl.reset t.frames;
    List.iter
      (fun entry ->
        match entry with
        | `List (`Int id :: rest) -> (
          try
            match List.map Yojson.Safe.Util.to_number rest with
            | [ x; y; w; h ] ->
              Hashtbl.replace t.frames id
                { Model.rx = x; ry = y; rw = w; rh = h }
            | _ -> ()
          with _ -> ())
        | _ -> ())
      entries
  | _ -> Model.apply_wire_batch t.tree json

let drain t =
  Mutex.lock t.mu;
  let lines = List.of_seq (Queue.to_seq t.queue) in
  Queue.clear t.queue;
  Mutex.unlock t.mu;
  List.iter (ingest_line t) lines;
  lines <> []

let poll t = ignore (drain t)

let send t json = t.send_line (Yojson.Safe.to_string json)

let send_nav t hash =
  send t (`Assoc [ ("event", `String "nav"); ("hash", `String hash) ])

let wire_to_json = function
  | StringValue s -> `String s
  | BoolValue b -> `Bool b
  | IntValue i -> `Int i
  | FloatValue f -> `Float f

let id_fields name id = [ ("event", `String name); ("id", `Int id) ]

let detail_fields (d : pointer_detail) =
  [ ("x", `Float d.x); ("y", `Float d.y); ("modifiers", `Int d.modifiers)
  ; ("button", `Int d.button); ("target_class", `String d.target_class) ]

let send_event t = function
  | Press id -> send t (`Assoc (id_fields "press" id))
  | PressModifiers (id, modifiers) ->
    send t (`Assoc (id_fields "press-modifiers" id @ [ ("modifiers", `Int modifiers) ]))
  | PressDetail (id, d) ->
    send t (`Assoc (id_fields "press-detail" id @ detail_fields d))
  | PointerDown (id, d) ->
    send t (`Assoc (id_fields "pointer-down" id @ detail_fields d))
  | PointerUp (id, d) ->
    send t (`Assoc (id_fields "pointer-up" id @ detail_fields d))
  | PointerEnter id -> send t (`Assoc (id_fields "pointer-enter" id))
  | PointerLeave id -> send t (`Assoc (id_fields "pointer-leave" id))
  | ContextMenuPress (id, d) ->
    send t (`Assoc (id_fields "context-menu" id @ detail_fields d))
  | Load id -> send t (`Assoc (id_fields "load" id))
  | LongPress id -> send t (`Assoc (id_fields "long-press" id))
  | DoublePress id -> send t (`Assoc (id_fields "double-press" id))
  | Appear id -> send t (`Assoc (id_fields "appear" id))
  | Submit id -> send t (`Assoc (id_fields "submit" id))
  | Dismiss id -> send t (`Assoc (id_fields "dismiss" id))
  | Change id -> send t (`Assoc (id_fields "change" id))
  | TextChanged (id, value) ->
    send t (`Assoc (id_fields "text" id @ [ ("value", `String value) ]))
  | ToggleChanged (id, value) ->
    send t (`Assoc (id_fields "toggle" id @ [ ("value", `Bool value) ]))
  | ValueChanged (id, value) ->
    send t (`Assoc (id_fields "value" id @ [ ("value", `Float value) ]))
  | ScrollCompleted (id, offset, direction) ->
    send
      t
      (`Assoc
        (id_fields "scroll-completed" id
        @ [ ("offset", `Int offset); ("direction", `String direction) ]))
  | VisibleRange (id, first, last) ->
    send
      t
      (`Assoc
        (id_fields "visible-range" id
        @ [ ("first", `Int first); ("last", `Int last) ]))
  | Picked (id, value) ->
    send t (`Assoc (id_fields "picked" id @ [ ("value", `String value) ]))
  | ExtensionEvent (id, ident, name, fields) ->
    let fields_json =
      `Assoc
        (String_map.fold
           (fun k v acc -> (k, wire_to_json v) :: acc)
           fields [])
    in
    send
      t
      (`Assoc
         (id_fields "ext" id
         @ [ ("ident", `String ident); ("name", `String name); ("fields", fields_json) ]))

(* Resolve (x, y) against the latest reported frames, then press the
   node a gesture recognizer would fire on: deepest containing node,
   walking ancestors to the first pressable one. *)
let tap t ~x ~y =
  poll t;
  if Hashtbl.length t.frames = 0 then
    Error "no frames reported — is the host's frame reporting on?"
  else
    match Model.hit_test t.tree ~frames:t.frames ~x ~y with
    | Some id ->
      Printf.eprintf "[tap] (%.1f,%.1f) -> #%d\n%!" x y id;
      send t (`Assoc (id_fields "press" id));
      Ok id
    | None ->
      Error (Printf.sprintf "no pressable node at (%.1f, %.1f)" x y)

let frames_list t =
  Hashtbl.fold (fun id r acc -> (id, r) :: acc) t.frames []

let driver t =
  {
    Session.tree = t.tree;
    send_event = (fun ev -> send_event t ev; poll t);
    poll = (fun () -> poll t);
    tap = (fun ~x ~y -> tap t ~x ~y);
    frames = (fun () -> frames_list t);
    send_nav = (fun h -> send_nav t h);
  }
