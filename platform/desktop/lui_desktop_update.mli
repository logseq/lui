(** Authenticated, whole-application desktop updates. No renderer dependency. *)
type artifact = private { url : string; size : int; sha256 : string }
type release = private {
  version : string;
  build : int;
  notes : string;
  full : artifact;
  delta : artifact option;
}

val authenticate :
  public_key:string -> app_id:string -> platform:string -> current_build:int ->
  string -> release option
(** Verify the signed envelope before reading its release metadata. *)

val download : artifact -> string -> unit
val verify_file : artifact -> string -> unit
val stage : package:string -> installed:string -> destination:string -> unit
(** Reconstruct a complete tree, checking every file. [destination] must not
    exist. Paths, links, duplicate entries and overlapping payloads are rejected. *)

type installation

val install : staged:string -> target:string -> installation
(** Same-filesystem replacement, restoring the previous tree if rename fails.
    The caller must first wait for the installed application to exit.
    Retains the previous tree until [confirm] or [rollback]. *)

val confirm : installation -> unit
val rollback : installation -> unit

val read_file : limit:int -> string -> string
val write_file : string -> string -> unit
val remove_tree : string -> unit
