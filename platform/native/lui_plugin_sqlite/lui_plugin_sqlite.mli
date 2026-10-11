(* SQLite plugin for the LUI native backend.

   Two layers share one connection implementation:

   - A typed OCaml API ([open_db], [exec], [query], [transaction])
     used directly by native code.
   - A [plugin] descriptor exposing the same operations as a JSON
     service so UI-side code can drive a database through the plugin
     service channel.  The descriptor's shape matches the plugin
     registry contract ({!Plugin.t}) and plugs into it unchanged once
     the registry module lands.

   The C side is resolved at run time (system SQLite library); on
   platforms where no library is found, every call returns an
   [Error] string and [available] is [false]. *)

type db
(** A connection handle.  Close explicitly with [close] or let the GC
    finalizer do it; statements outlive a closed connection safely. *)

type stmt
(** A prepared statement.  Exposed for completeness; [exec]/[query]
    prepare, bind, step and finalize internally. *)

(** A typed SQLite value, mirroring the storage classes. *)
type value =
  | Null
  | Int of int64
  | Real of float
  | Text of string
  | Blob of string

(** Statement parameter: positional (?NNN / anonymous ?) or named
    (:name, @name, $name — pass the name including its prefix). *)
type param =
  | Pos of value
  | Named of string * value

(** What [exec] reports after running one statement. *)
type exec_result = {
  changes : int;
  last_insert_id : int64;
}

(** One result row: (column name, value) pairs in column order. *)
type row = (string * value) list

val available : unit -> bool
(** Whether a system SQLite library could be resolved. *)

val load_error : unit -> string option
(** Why [available] is false, if it is. *)

val version : unit -> string option
(** SQLite library version string when available. *)

val open_db :
  ?path:string ->
  ?read_only:bool ->
  ?busy_timeout_ms:int ->
  unit ->
  (db, string) result
(** [open_db ()] opens [:memory:].  [busy_timeout_ms] defaults to
    5000; file-backed connections are put in WAL mode and foreign keys
    are enabled. *)

val close : db -> (unit, string) result

val exec :
  ?params:param list -> db -> string -> (exec_result, string) result
(** Prepare and run exactly one statement (SELECT rows are consumed
    and discarded).  Transaction-control statements (BEGIN, COMMIT,
    ROLLBACK, SAVEPOINT, RELEASE, END, VACUUM, ATTACH, DETACH) are
    rejected — use [transaction] and [exec_script]. *)

val exec_script : db -> string -> (unit, string) result
(** Run a multi-statement script (no parameters). *)

val query :
  ?params:param list -> db -> string -> (row list, string) result
(** Prepare and run exactly one statement, returning every row. *)

val transaction : db -> (unit -> ('a, string) result) -> ('a, string) result
(** [transaction db f] runs [f] inside BEGIN IMMEDIATE … COMMIT.
    [Error] rolls back; an exception rolls back and is re-raised. *)

val last_insert_rowid : db -> int64
val changes : db -> int

(** {1 Plugin descriptor} *)

(** The registry contract, mirrored so this library stays
    self-contained until the registry module lands. *)
module Plugin : sig
  type service_fn = string -> (string, string) result
  (** Each service takes a JSON-encoded argument object and returns a
      JSON-encoded result or an error string. *)

  type t = {
    name : string;
    services : (string * service_fn) list;
    setup : unit -> (unit, string) result;
    teardown : unit -> unit;
  }

  val call : t -> string -> string -> (string, string) result
  (** [call p method arg] dispatches to a named service. *)
end

val plugin : Plugin.t
(** Service methods (JSON in, JSON out):

    - ["open"]:   [{"id"?: string, "path"?: string, "readOnly"?: bool,
      "busyTimeoutMs"?: int}] → [{"id": string}]
    - ["close"]:  [{"id": string}] → [{}] (unknown ids are ignored)
    - ["exec"]:   [{"id": string, "sql": string, "params"?: [value]}]
      → [{"changes": int, "lastInsertId": string}]
    - ["query"]:  same input → [{"columns": [string],
      "rows": [{column: value}]}]
    - ["batch"]:  [{"id": string, "statements": [{"sql": string,
      "params"?: [value]}]}] → [{"results": [exec-result]}]; the batch
      runs atomically inside a transaction.
    - ["pragma"]: [{"id": string, "name": string, "value"?: string |
      int}] → same shape as ["query"].

    Wire [value]: [{"type": "null"}],
    [{"type": "integer", "integer": "…"}] (int64 as decimal string),
    [{"type": "real", "real": number}] (or [{"special": "NaN" |
    "Infinity" | "-Infinity"}]), [{"type": "text", "text": string}],
    [{"type": "blob", "blob": base64}]. *)

val value_of_json : Yojson.Safe.t -> (value, string) result
val json_of_value : value -> Yojson.Safe.t
