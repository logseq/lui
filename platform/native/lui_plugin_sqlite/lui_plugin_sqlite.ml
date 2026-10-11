(* SQLite plugin: typed OCaml API plus a JSON service descriptor. *)

(* ---------- externals (all arity <= 5, shared native/bytecode) ---- *)

type db
type stmt

external c_probe : unit -> int = "lui_sq_probe"
external c_load_error : unit -> string = "lui_sq_load_error"
external c_version : unit -> string = "lui_sq_version"
external c_open : string -> int -> (db, string) result = "lui_sq_open"
external c_close : db -> (unit, string) result = "lui_sq_close"
external c_prepare : db -> string -> (stmt, string) result
  = "lui_sq_prepare"
external c_finalize : stmt -> (unit, string) result = "lui_sq_finalize"
external c_bind_index : stmt -> string -> int = "lui_sq_bind_index"
external c_bind_null : stmt -> int -> (unit, string) result
  = "lui_sq_bind_null"
external c_bind_i64 : stmt -> int -> int64 -> (unit, string) result
  = "lui_sq_bind_i64"
external c_bind_double : stmt -> int -> float -> (unit, string) result
  = "lui_sq_bind_double"
external c_bind_text : stmt -> int -> string -> (unit, string) result
  = "lui_sq_bind_text"
external c_bind_blob : stmt -> int -> string -> (unit, string) result
  = "lui_sq_bind_blob"
external c_step : stmt -> int = "lui_sq_step"
external c_stmt_errcode : stmt -> int = "lui_sq_stmt_errcode"
external c_stmt_errmsg : stmt -> string = "lui_sq_stmt_errmsg"
external c_column_count : stmt -> int = "lui_sq_column_count"
external c_column_name : stmt -> int -> string = "lui_sq_column_name"
external c_column_type : stmt -> int -> int = "lui_sq_column_type"
external c_column_i64 : stmt -> int -> int64 = "lui_sq_column_i64"
external c_column_double : stmt -> int -> float = "lui_sq_column_double"
external c_column_text : stmt -> int -> string = "lui_sq_column_text"
external c_column_blob : stmt -> int -> string = "lui_sq_column_blob"
external c_exec : db -> string -> (unit, string) result = "lui_sq_exec"
external c_last_rowid : db -> int64 = "lui_sq_last_rowid"
external c_changes : db -> int = "lui_sq_changes"
external c_busy_timeout : db -> int -> (unit, string) result
  = "lui_sq_busy_timeout"

(* ---------- public types ---------- *)

type value =
  | Null
  | Int of int64
  | Real of float
  | Text of string
  | Blob of string

type param =
  | Pos of value
  | Named of string * value

type exec_result = {
  changes : int;
  last_insert_id : int64;
}

type row = (string * value) list

(* ---------- availability ---------- *)

let available () = c_probe () = 1

let load_error () =
  match c_load_error () with
  | "" -> None
  | s -> Some s

let version () =
  match c_version () with
  | "" -> None
  | s -> Some s

(* ---------- open / close ---------- *)

let sqlite_open_readwrite_create_fullmutex = 0x10006
let sqlite_open_readonly_fullmutex = 0x10001

let open_db ?(path = ":memory:") ?(read_only = false)
    ?(busy_timeout_ms = 5000) () =
  let flags =
    if read_only then sqlite_open_readonly_fullmutex
    else sqlite_open_readwrite_create_fullmutex
  in
  match c_open path flags with
  | Error _ as e -> e
  | Ok db ->
    (match c_busy_timeout db busy_timeout_ms with
     | Error _ as e -> e
     | Ok () ->
       let setup =
         if read_only then Ok ()
         else if path = ":memory:" then
           c_exec db "PRAGMA foreign_keys = ON"
         else
           c_exec db
             "PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON"
       in
       (match setup with
        | Error _ as e -> e
        | Ok () -> Ok db))

let close db = c_close db

(* ---------- statements ---------- *)

let stmt_error st =
  let code = c_stmt_errcode st in
  let msg = c_stmt_errmsg st in
  Printf.sprintf "sqlite: %s (code %d)" msg code

let bind_value st idx v =
  match v with
  | Null -> c_bind_null st idx
  | Int i -> c_bind_i64 st idx i
  | Real f -> c_bind_double st idx f
  | Text s -> c_bind_text st idx s
  | Blob b -> c_bind_blob st idx b

let bind_params st params =
  let pos = ref 0 in
  let rec loop = function
    | [] -> Ok ()
    | Pos v :: rest ->
      incr pos;
      (match bind_value st !pos v with
       | Ok () -> loop rest
       | Error _ as e -> e)
    | Named (name, v) :: rest ->
      let idx = c_bind_index st name in
      if idx = 0 then
        Error (Printf.sprintf "sqlite: no parameter named %s" name)
      else
        (match bind_value st idx v with
         | Ok () -> loop rest
         | Error _ as e -> e)
  in
  loop params

let column_value st i =
  match c_column_type st i with
  | 1 -> Int (c_column_i64 st i)
  | 2 -> Real (c_column_double st i)
  | 4 -> Blob (c_column_blob st i)
  | 5 -> Null
  | _ -> Text (c_column_text st i)

let current_row st =
  let n = c_column_count st in
  let rec go i acc =
    if i >= n then List.rev acc
    else go (i + 1) ((c_column_name st i, column_value st i) :: acc)
  in
  go 0 []

(* Step through every row.  [take] maps each row into [acc]; exec passes
   a sink, query collects. *)
let run_rows st acc take =
  let rec loop acc =
    match c_step st with
    | 100 (* SQLITE_ROW *) -> loop (take st acc)
    | 101 (* SQLITE_DONE *) -> Ok acc
    | _ -> Error (stmt_error st)
  in
  loop acc

let with_stmt db sql params ~acc ~take ~finish =
  match c_prepare db sql with
  | Error _ as e -> e
  | Ok st ->
    let out =
      match bind_params st params with
      | Error _ as e -> e
      | Ok () -> run_rows st acc take
    in
    let fin = c_finalize st in
    (match out, fin with
     | Error _ as e, _ -> e
     | Ok _, Error e -> Error e
     | Ok a, Ok () -> finish a)

(* Transaction-control statements rejected in exec/query. *)
let is_tx_control sql =
  let n = String.length sql in
  let i = ref 0 in
  while !i < n && (sql.[!i] = ' ' || sql.[!i] = '\t' || sql.[!i] = '\n'
                   || sql.[!i] = '\r' || sql.[!i] = '(') do
    incr i
  done;
  let j = ref !i in
  while !j < n && ((sql.[!j] >= 'a' && sql.[!j] <= 'z')
                   || (sql.[!j] >= 'A' && sql.[!j] <= 'Z')) do
    incr j
  done;
  match String.uppercase_ascii (String.sub sql !i (!j - !i)) with
  | "BEGIN" | "COMMIT" | "ROLLBACK" | "SAVEPOINT" | "RELEASE" | "END"
  | "VACUUM" | "ATTACH" | "DETACH" -> true
  | _ -> false

let reject_tx_control sql =
  if is_tx_control sql then
    Error
      "sqlite: transaction control is not allowed here — use \
       transaction or exec_script"
  else Ok ()

let exec_raw ?(params = []) db sql =
  with_stmt db sql params ~acc:() ~take:(fun _ () -> ())
    ~finish:(fun () ->
      Ok { changes = c_changes db; last_insert_id = c_last_rowid db })

let exec ?(params = []) db sql =
  match reject_tx_control sql with
  | Error _ as e -> e
  | Ok () -> exec_raw ~params db sql

let query_raw db sql params =
  with_stmt db sql params ~acc:[] ~take:(fun st rows -> current_row st :: rows)
    ~finish:(fun rows -> Ok (List.rev rows))

let query ?(params = []) db sql =
  match reject_tx_control sql with
  | Error _ as e -> e
  | Ok () -> query_raw db sql params

let exec_script db sql = c_exec db sql

let transaction db f =
  match exec_raw db "BEGIN IMMEDIATE" with
  | Error e -> Error e
  | Ok _ ->
    (match f () with
     | Ok _ as ok ->
       (match exec_raw db "COMMIT" with
        | Ok _ -> ok
        | Error e ->
          ignore (exec_raw db "ROLLBACK");
          Error (Printf.sprintf "sqlite: commit failed: %s" e))
     | Error e ->
       (match exec_raw db "ROLLBACK" with
        | Ok _ -> Error e
        | Error r ->
          Error
            (Printf.sprintf "%s (rollback also failed: %s)" e r))
     | exception exn ->
       let bt = Printexc.get_raw_backtrace () in
       ignore (exec_raw db "ROLLBACK");
       Printexc.raise_with_backtrace exn bt)

let last_insert_rowid db = c_last_rowid db
let changes db = c_changes db

(* ---------- base64 (self-contained blob codec) ---------- *)

let b64_encode s =
  let tbl = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" in
  let n = String.length s in
  let out = Bytes.create (((n + 2) / 3) * 4) in
  let i = ref 0 and o = ref 0 in
  while !i < n do
    let a = Char.code s.[!i] in
    let b = if !i + 1 < n then Char.code s.[!i + 1] else 0 in
    let c = if !i + 2 < n then Char.code s.[!i + 2] else 0 in
    Bytes.set out !o tbl.[a lsr 2];
    Bytes.set out (!o + 1) tbl.[((a land 3) lsl 4) lor (b lsr 4)];
    Bytes.set out (!o + 2)
      (if !i + 1 < n then tbl.[((b land 15) lsl 2) lor (c lsr 6)]
       else '=');
    Bytes.set out (!o + 3)
      (if !i + 2 < n then tbl.[c land 63] else '=');
    i := !i + 3;
    o := !o + 4
  done;
  Bytes.unsafe_to_string out

let b64_decode s =
  let inv = Array.make 256 (-1) in
  String.iteri
    (fun i c ->
      inv.(Char.code c) <- i)
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  let n = String.length s in
  let buf = Buffer.create (n * 3 / 4) in
  let i = ref 0 in
  let error = ref false in
  while !i + 3 < n && not !error do
    let d k =
      let ch = s.[!i + k] in
      if ch = '=' then -2 else inv.(Char.code ch)
    in
    let a, b, c, e = d 0, d 1, d 2, d 3 in
    if a < 0 || b < 0 || c = -1 || e = -1 then error := true
    else begin
      Buffer.add_char buf
        (Char.chr (((a lsl 2) lor (b lsr 4)) land 0xff));
      if c >= 0 then begin
        Buffer.add_char buf
          (Char.chr (((b lsl 4) lor (c lsr 2)) land 0xff));
        if e >= 0 then
          Buffer.add_char buf
            (Char.chr (((c lsl 6) lor e) land 0xff))
      end
    end;
    i := !i + 4
  done;
  if !error || !i < n then Error "sqlite: invalid base64 blob"
  else Ok (Buffer.contents buf)

(* ---------- JSON wire codec ---------- *)

let json_of_value = function
  | Null -> `Assoc [ ("type", `String "null") ]
  | Int i ->
    `Assoc
      [ ("type", `String "integer");
        ("integer", `String (Int64.to_string i)) ]
  | Real f ->
    if Float.classify_float f = Float.FP_nan then
      `Assoc [ ("type", `String "real"); ("special", `String "NaN") ]
    else if f = Float.infinity then
      `Assoc
        [ ("type", `String "real"); ("special", `String "Infinity") ]
    else if f = Float.neg_infinity then
      `Assoc
        [ ("type", `String "real"); ("special", `String "-Infinity") ]
    else `Assoc [ ("type", `String "real"); ("real", `Float f) ]
  | Text s -> `Assoc [ ("type", `String "text"); ("text", `String s) ]
  | Blob b ->
    `Assoc [ ("type", `String "blob"); ("blob", `String (b64_encode b)) ]

let value_of_json j =
  let open Yojson.Safe.Util in
  match member "type" j with
  | `String "null" -> Ok Null
  | `String "integer" ->
    (match member "integer" j with
     | `String s ->
       (try Ok (Int (Int64.of_string s))
        with _ -> Error "sqlite: invalid integer wire value")
     | `Int i -> Ok (Int (Int64.of_int i))
     | `Intlit s ->
       (try Ok (Int (Int64.of_string s))
        with _ -> Error "sqlite: invalid integer wire value")
     | _ -> Error "sqlite: integer wire value must be a string")
  | `String "real" ->
    (match member "special" j with
     | `String "NaN" -> Ok (Real Float.nan)
     | `String "Infinity" -> Ok (Real Float.infinity)
     | `String "-Infinity" -> Ok (Real Float.neg_infinity)
     | _ ->
       (match member "real" j with
        | `Float f -> Ok (Real f)
        | `Int i -> Ok (Real (float_of_int i))
        | _ -> Error "sqlite: real wire value must be a number"))
  | `String "text" ->
    (match member "text" j with
     | `String s -> Ok (Text s)
     | _ -> Error "sqlite: text wire value must be a string")
  | `String "blob" ->
    (match member "blob" j with
     | `String s ->
       (match b64_decode s with
        | Ok b -> Ok (Blob b)
        | Error _ as e -> e)
     | _ -> Error "sqlite: blob wire value must be a base64 string")
  | `String t -> Error (Printf.sprintf "sqlite: unknown value type %S" t)
  | _ -> Error "sqlite: value must be an object with a type field"

let params_of_json j =
  let open Yojson.Safe.Util in
  match member "params" j with
  | `Null -> Ok []
  | `List items ->
    let rec go i acc = function
      | [] -> Ok (List.rev acc)
      | v :: rest ->
        (match value_of_json v with
         | Ok w -> go (i + 1) (Pos w :: acc) rest
         | Error e ->
           Error (Printf.sprintf "sqlite: parameter %d: %s" (i + 1) e))
    in
    go 0 [] items
  | _ -> Error "sqlite: params must be an array"

(* ---------- service layer ---------- *)

module Registry = struct
  let mu = Mutex.create ()
  let handles : (string, db) Hashtbl.t = Hashtbl.create 8
  let counter = ref 0

  let with_lock f =
    Mutex.lock mu;
    match f () with
    | v ->
      Mutex.unlock mu;
      v
    | exception e ->
      Mutex.unlock mu;
      raise e

  let add db =
    with_lock (fun () ->
        incr counter;
        let id = Printf.sprintf "db-%d" !counter in
        Hashtbl.replace handles id db;
        id)

  let add_named id db =
    with_lock (fun () ->
        if Hashtbl.mem handles id then Error "handle already in use"
        else begin
          Hashtbl.replace handles id db;
          Ok id
        end)

  let find id = with_lock (fun () -> Hashtbl.find_opt handles id)

  let remove id =
    with_lock (fun () ->
        match Hashtbl.find_opt handles id with
        | None -> None
        | Some db ->
          Hashtbl.remove handles id;
          Some db)

  let clear () =
    with_lock (fun () ->
        let all = Hashtbl.fold (fun _ db acc -> db :: acc) handles [] in
        Hashtbl.reset handles;
        all)
end

let find_db j =
  let open Yojson.Safe.Util in
  match member "id" j with
  | `String id ->
    (match Registry.find id with
     | Some db -> Ok db
     | None -> Error (Printf.sprintf "sqlite: unknown handle %S" id))
  | _ -> Error "sqlite: \"id\" must be a string"

let svc_open input =
  let open Yojson.Safe.Util in
  let path_r =
    match member "path" input with
    | `String s -> Ok s
    | `Null -> Ok ":memory:"
    | _ -> Error "sqlite: \"path\" must be a string"
  in
  match path_r with
  | Error _ as e -> e
  | Ok path ->
    let read_only =
      match member "readOnly" input with
      | `Bool b -> b
      | _ -> false
    in
    let busy =
      match member "busyTimeoutMs" input with
      | `Int i -> i
      | _ -> 5000
    in
    (match open_db ~path ~read_only ~busy_timeout_ms:busy () with
     | Error _ as e -> e
     | Ok db ->
       (match member "id" input with
        | `String id ->
          (match Registry.add_named id db with
           | Ok id -> Ok (`Assoc [ ("id", `String id) ])
           | Error e ->
             ignore (close db);
             Error (Printf.sprintf "sqlite: %s" e))
        | _ -> Ok (`Assoc [ ("id", `String (Registry.add db)) ])))
    |> Result.map Yojson.Safe.to_string

let svc_close input =
  let open Yojson.Safe.Util in
  match member "id" input with
  | `String id ->
    (match Registry.remove id with
     | None -> Ok "{}"
     | Some db ->
       (match close db with
        | Ok () -> Ok "{}"
        | Error _ as e -> e))
  | _ -> Error "sqlite: \"id\" must be a string"

let result_json db =
  `Assoc
    [ ("changes", `Int (c_changes db));
      ("lastInsertId", `String (Int64.to_string (c_last_rowid db))) ]

let svc_exec input =
  let open Yojson.Safe.Util in
  match find_db input, member "sql" input with
  | Error _ as e, _ -> e
  | _, `Null -> Error "sqlite: \"sql\" is required"
  | Ok db, `String sql ->
    (match params_of_json input with
     | Error _ as e -> e
     | Ok params ->
       (match exec ~params db sql with
        | Error _ as e -> e
        | Ok _ -> Ok (Yojson.Safe.to_string (result_json db))))
  | Ok _, _ -> Error "sqlite: \"sql\" must be a string"

let rows_json rows =
  `Assoc
    [ ("columns",
       `List
         (match rows with
          | [] -> []
          | r :: _ -> List.map (fun (k, _) -> `String k) r));
      ("rows",
       `List
         (List.map
            (fun r ->
              `Assoc (List.map (fun (k, v) -> (k, json_of_value v)) r))
            rows)) ]

let svc_query input =
  let open Yojson.Safe.Util in
  match find_db input, member "sql" input with
  | Error _ as e, _ -> e
  | _, `Null -> Error "sqlite: \"sql\" is required"
  | Ok db, `String sql ->
    (match params_of_json input with
     | Error _ as e -> e
     | Ok params ->
       (match query ~params db sql with
        | Error _ as e -> e
        | Ok rows -> Ok (Yojson.Safe.to_string (rows_json rows))))
  | Ok _, _ -> Error "sqlite: \"sql\" must be a string"

let svc_batch input =
  let open Yojson.Safe.Util in
  match find_db input, member "statements" input with
  | Error _ as e, _ -> e
  | _, `Null -> Error "sqlite: \"statements\" is required"
  | Ok db, `List stmts ->
    (match
       transaction db (fun () ->
           let rec go acc = function
             | [] -> Ok (List.rev acc)
             | s :: rest ->
               (match member "sql" s with
                | `String sql ->
                  (match params_of_json s with
                   | Error _ as e -> e
                   | Ok params ->
                     (match exec ~params db sql with
                      | Error _ as e -> e
                      | Ok _ -> go (result_json db :: acc) rest))
                | _ -> Error "sqlite: statement \"sql\" must be a string")
           in
           go [] stmts)
     with
     | Error _ as e -> e
     | Ok results ->
       Ok (Yojson.Safe.to_string (`Assoc [ ("results", `List results) ])))
  | Ok _, _ -> Error "sqlite: \"statements\" must be an array"

let pragma_suffix input =
  let open Yojson.Safe.Util in
  match member "value" input with
  | `Null -> Ok ""
  | `String s ->
    (* Single quotes doubled per SQL string-literal escaping; NUL
       bytes dropped since C strings cannot carry them. *)
    let no_nul = String.concat "" (String.split_on_char (Char.chr 0) s) in
    Ok
      (Printf.sprintf " = '%s'"
         (String.concat "''" (String.split_on_char '\'' no_nul)))
  | `Int i -> Ok (Printf.sprintf " = %d" i)
  | `Float f -> Ok (Printf.sprintf " = %g" f)
  | `Bool b -> Ok (Printf.sprintf " = %d" (if b then 1 else 0))
  | _ -> Error "sqlite: invalid pragma value"

let svc_pragma input =
  let open Yojson.Safe.Util in
  match find_db input, member "name" input with
  | Error _ as e, _ -> e
  | Ok db, `String name ->
    (* Pragma names are identifiers: reject anything else. *)
    let ident_ok =
      name <> ""
      && String.for_all
           (fun ch ->
             (ch >= 'a' && ch <= 'z')
             || (ch >= 'A' && ch <= 'Z')
             || (ch >= '0' && ch <= '9')
             || ch = '_' || ch = '.')
           name
    in
    if not ident_ok then Error "sqlite: invalid pragma name"
    else
      (match pragma_suffix input with
       | Error _ as e -> e
       | Ok suffix ->
         (match query_raw db ("PRAGMA " ^ name ^ suffix) [] with
          | Error _ as e -> e
          | Ok rows -> Ok (Yojson.Safe.to_string (rows_json rows))))
  | _, _ -> Error "sqlite: \"name\" must be a string"

(* ---------- plugin descriptor ---------- *)

module Plugin = struct
  type service_fn = string -> (string, string) result

  type t = {
    name : string;
    services : (string * service_fn) list;
    setup : unit -> (unit, string) result;
    teardown : unit -> unit;
  }

  let call p method_ arg =
    match List.assoc_opt method_ p.services with
    | None -> Error (Printf.sprintf "sqlite: unknown service %S" method_)
    | Some f -> f arg
end

let parse_input arg =
  match Yojson.Safe.from_string arg with
  | `Assoc _ as j -> Ok j
  | _ -> Error "sqlite: service input must be a JSON object"
  | exception Yojson.Json_error e ->
    Error (Printf.sprintf "sqlite: invalid JSON input: %s" e)

let json_service f arg =
  match parse_input arg with
  | Error _ as e -> e
  | Ok j -> f j

let plugin : Plugin.t =
  {
    name = "Sqlite";
    services =
      [ ("open", json_service svc_open);
        ("close", json_service svc_close);
        ("exec", json_service svc_exec);
        ("query", json_service svc_query);
        ("batch", json_service svc_batch);
        ("pragma", json_service svc_pragma) ];
    setup = (fun () -> Ok ());
    teardown =
      (fun () ->
        List.iter
          (fun db -> ignore (close db))
          (Registry.clear ()));
  }
