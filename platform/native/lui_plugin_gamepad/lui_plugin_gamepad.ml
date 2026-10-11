(* Gamepad plugin service for the native backend.

   Binds ["plugin:gamepad"] with JSON methods:

   - ["list"]   -> connected controllers (id, name, kind, live state)
   - ["state"]  -> {"id": n} state for one controller, or all
   - ["events"] -> drains one {!Lui_gamepad.pump} frame into events
   - ["map"]    -> {"mapping": "<sdl db line>"} registers a mapping
   - ["mapfile"]-> {"path": p} SDL_GameControllerAddMappingsFromFile *)

open Lui_gamepad

(* ---------- JSON helpers ---------- *)

let controller_json (c : controller) =
  `Assoc
    [ ("id", `Int c.id);
      ("name", `String c.name);
      ("kind", `String (string_of_kind c.kind)) ]

let state_json (st : state) =
  `Assoc
    [ ("buttons",
       `List (List.map (fun b -> `String (string_of_button b)) st.pressed));
      ("axes",
       `Assoc
         (List.map (fun (a, v) -> (string_of_axis a, `Float v)) st.axes)) ]

let event_json = function
  | Connected c ->
    `Assoc ([ ("type", `String "connected") ]
            @ match controller_json c with
              | `Assoc kvs -> kvs
              | _ -> [])
  | Disconnected id ->
    `Assoc [ ("type", `String "disconnected"); ("id", `Int id) ]
  | Button (id, b, p) ->
    `Assoc
      [ ("type", `String "button");
        ("id", `Int id);
        ("button", `String (string_of_button b));
        ("state",
         `String (match p with Pressed -> "pressed" | Released -> "released")) ]
  | Axis_move (id, a, v) ->
    `Assoc
      [ ("type", `String "axis");
        ("id", `Int id);
        ("axis", `String (string_of_axis a));
        ("value", `Float v) ]

(* ---------- service methods ---------- *)

let svc_list _j =
  let ctrls =
    List.map
      (fun c ->
        match controller_json c with
        | `Assoc kvs ->
          `Assoc
            (kvs
             @ [ ("state",
                  match Lui_gamepad.state c.id with
                  | Some st -> state_json st
                  | None -> `Null) ])
        | j -> j)
      (Lui_gamepad.controllers ())
  in
  Ok (Yojson.Safe.to_string (`Assoc [ ("controllers", `List ctrls) ]))

let svc_state j =
  let open Yojson.Safe.Util in
  match j |> member "id" |> to_option to_int with
  | Some id ->
    (match Lui_gamepad.state id with
     | Some st -> Ok (Yojson.Safe.to_string (state_json st))
     | None -> Error (Printf.sprintf "gamepad: no controller %d" id))
  | None ->
    `Assoc
      (List.map
         (fun c ->
           ( string_of_int c.id,
             match Lui_gamepad.state c.id with
             | Some st -> state_json st
             | None -> `Null ))
         (Lui_gamepad.controllers ()))
    |> fun j -> Ok (Yojson.Safe.to_string j)

let svc_events _j =
  (* One pump frame: connect/disconnect, button, axis events. *)
  let evs = Lui_gamepad.pump () in
  Ok
    (Yojson.Safe.to_string
       (`Assoc [ ("events", `List (List.map event_json evs)) ]))

let svc_map j =
  let open Yojson.Safe.Util in
  match j |> member "mapping" |> to_option to_string with
  | Some m ->
    (match Lui_gamepad.add_mapping m with
     | Ok _ -> Ok (Yojson.Safe.to_string (`Assoc [ ("added", `Int 1) ]))
     | Error e -> Error e)
  | None -> Error "gamepad: \"mapping\" must be a string"

let svc_mapfile j =
  let open Yojson.Safe.Util in
  match j |> member "path" |> to_option to_string with
  | Some p ->
    let n = Lui_gamepad.add_mappings_from_file p in
    Ok (Yojson.Safe.to_string (`Assoc [ ("added", `Int n) ]))
  | None -> Error "gamepad: \"path\" must be a string"

(* ---------- descriptor ---------- *)

let parse_input arg =
  match Yojson.Safe.from_string arg with
  | `Assoc _ as j -> Ok j
  | `Null -> Ok (`Assoc [])
  | _ -> Error "gamepad: service input must be a JSON object"
  | exception Yojson.Json_error e ->
    Error (Printf.sprintf "gamepad: invalid JSON input: %s" e)

let json_service f arg =
  match parse_input arg with
  | Error _ as e -> e
  | Ok j -> f j

let plugin : Lui_plugin.t =
  Lui_plugin.v "gamepad"
    ~setup:(fun () -> Lui_gamepad.init ())
    [ ("list", json_service svc_list);
      ("state", json_service svc_state);
      ("events", json_service svc_events);
      ("map", json_service svc_map);
      ("mapfile", json_service svc_mapfile) ]
