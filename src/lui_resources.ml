(* Resource session: keyed resources with dependency tracking and
   generation-ordered reload semantics. *)

type 'value committed_resource = {
  committed_resource_hash : string;
  committed_resource_value : 'value;
  committed_resource_generation : int;
}

type 'candidate prepare_result =
  | ResourcePrepared of 'candidate
  | ResourcePrepareRejected of string

type invalidation_result =
  | ResourceInvalidated
  | ResourceInvalidationRejected of string

type resource_status =
  | ResourceApplied of int
  | ResourceUnchanged of int
  | ResourceStale of int
  | ResourceRejected of int * string

type 'value resource_session = {
  resource_values : (string, 'value committed_resource) Hashtbl.t;
  resource_dependencies : (string, int list) Hashtbl.t;
  resource_completed_generation : int ref;
  invalidate_resource_dependents : int list -> unit;
  retire_resource : 'value -> unit;
}

let create invalidate_dependents retire =
  {
    resource_values = Hashtbl.create 16;
    resource_dependencies = Hashtbl.create 16;
    resource_completed_generation = ref 0;
    invalidate_resource_dependents = invalidate_dependents;
    retire_resource = retire;
  }

let register_dependency session resource_id node =
  let dependencies = session.resource_dependencies in
  let current =
    match Hashtbl.find_opt dependencies resource_id with
    | Some nodes -> nodes
    | None -> []
  in
  if not (List.exists (fun current -> current = node) current) then
    Hashtbl.replace dependencies resource_id (current @ [ node ]);
  true

let current session resource_id =
  match Hashtbl.find_opt session.resource_values resource_id with
  | Some resource -> Some resource.committed_resource_value
  | None -> None

let reject session generation message =
  session.resource_completed_generation := generation;
  ResourceRejected (generation, message)

let reload session generation resource_id source_hash payload prepare =
  let completed = !(session.resource_completed_generation) in
  let values = session.resource_values in
  let previous = Hashtbl.find_opt values resource_id in
  if generation <= completed then ResourceStale generation
  else if
    (match previous with
    | Some resource -> source_hash = resource.committed_resource_hash
    | None -> false)
  then begin
    session.resource_completed_generation := generation;
    ResourceUnchanged generation
  end
  else
    let prepared =
      try ResourcePrepared (prepare payload)
      with Invalid_argument message -> ResourcePrepareRejected message
    in
    match prepared with
    | ResourcePrepareRejected message ->
      reject session generation message
    | ResourcePrepared candidate ->
      let committed =
        {
          committed_resource_hash = source_hash;
          committed_resource_value = candidate;
          committed_resource_generation = generation;
        }
      in
      let dependents =
        match
          Hashtbl.find_opt session.resource_dependencies resource_id
        with
        | Some nodes -> nodes
        | None -> []
      in
      Hashtbl.replace values resource_id committed;
      let invalidation =
        try
          session.invalidate_resource_dependents dependents;
          ResourceInvalidated
        with Invalid_argument message ->
          ResourceInvalidationRejected message
      in
      (match invalidation with
      | ResourceInvalidationRejected message ->
        (match previous with
        | Some old -> Hashtbl.replace values resource_id old
        | None -> Hashtbl.remove values resource_id);
        session.retire_resource candidate;
        reject session generation message
      | ResourceInvalidated ->
        (match previous with
        | Some old ->
          session.retire_resource old.committed_resource_value
        | None -> ());
        session.resource_completed_generation := generation;
        ResourceApplied generation)
