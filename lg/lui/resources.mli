(* ns lui.resources *)

type resource_reload_status =
  | ResourceApplied of int
  | ResourceUnchanged of int
  | ResourceRejected of int * string
  | ResourceStale of int

type 'resource resource_prepare_result =
  | ResourcePrepared of 'resource
  | ResourcePrepareRejected of string

type resource_invalidation_result =
  | ResourceInvalidated
  | ResourceInvalidationRejected of string

type 'resource committed_resource = { committed_resource_hash : string ; committed_resource_value : 'resource ; committed_resource_generation : int }

type 'resource resource_session = { resource_values : (string, 'resource committed_resource) Lg_runtime.Runtime_map.t ref ; resource_dependencies : (string, int Rrbvec.t) Lg_runtime.Runtime_map.t ref ; resource_completed_generation : int ref ; invalidate_resource_dependents : int Rrbvec.t -> bool ; retire_resource : 'resource -> bool }

val create : (int Rrbvec.t -> bool) -> ('resource -> bool) -> 'resource resource_session

val contains_node_ : int Rrbvec.t -> int -> bool

val reject_bang : 'resource resource_session -> int -> string -> resource_reload_status

val register_dependency_bang : 'resource resource_session -> string -> int -> bool

val current : 'resource resource_session -> string -> 'resource option

val reload_bang : 'resource resource_session -> int -> string -> string -> string -> (string -> 'resource) -> resource_reload_status

