val check : Ppxlib.structure -> unit
(** Check statically resolved DSL edges before reactive expansion. Local values,
    nonrecursive helpers and module aliases are followed with a bounded walk;
    opaque and recursive results remain subject to runtime validation. *)
