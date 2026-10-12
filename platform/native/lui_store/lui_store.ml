(* Retained mirror of LUI patch batches for the native backend.

   The store keeps the node tree the patch stream describes and marks
   nodes dirty as their props or children change, so paint and layout
   can invalidate incrementally. Kinds and props are keyed by their wire
   names (Lui_wire_schema names), matching the convention used elsewhere
   so a prop lookup like [bool_prop t id "enabled"] reads the same key
   every backend sees. *)

open Lui_protocol

(* Children of a node live in a growable array: patch streams append
   children one op at a time and a list made every [InsertChild] an
   O(fan-out) rewalk, which made 100k mounts quadratic. The vec keeps
   appends O(1) amortized; readers materialize lists on demand (a
   snapshot, which is also safer than sharing the live order). *)
type child_vec = { mutable arr : int array; mutable len : int }

let vec_create () = { arr = [||]; len = 0 }

let vec_grow v =
  let cap = max 8 (2 * Array.length v.arr) in
  let arr' = Array.make cap 0 in
  Array.blit v.arr 0 arr' 0 v.len;
  v.arr <- arr'

let vec_insert_at v i x =
  (* Out-of-range indices clamp the way insert_at on a list did:
     i <= 0 prepends, i >= len appends. *)
  let i = max 0 (min i v.len) in
  if v.len = Array.length v.arr then vec_grow v;
  Array.blit v.arr i v.arr (i + 1) (v.len - i);
  v.arr.(i) <- x;
  v.len <- v.len + 1

let vec_remove v x =
  (* Compacts in place; removes every occurrence like
     List.filter (fun c -> c <> x). *)
  let w = ref 0 in
  for i = 0 to v.len - 1 do
    let c = v.arr.(i) in
    if c <> x then (
      v.arr.(!w) <- c;
      incr w)
  done;
  v.len <- !w

let vec_to_list v =
  let rec go i acc = if i < 0 then acc else go (i - 1) (v.arr.(i) :: acc) in
  go (v.len - 1) []

let vec_fold f acc v =
  let acc = ref acc in
  for i = 0 to v.len - 1 do
    acc := f !acc v.arr.(i)
  done;
  !acc

let vec_last v = if v.len = 0 then None else Some v.arr.(v.len - 1)

type node = {
  id : int;
  kind : string; (* node_kind_name, or "extension:<identifier>" *)
  mutable ext_id : string option;
  props : (string, wire_value) Hashtbl.t;
  mutable parent : int option;
  children : child_vec;
  mutable revision : int; (* last store revision that touched this node *)
}

type t = {
  nodes : (int, node) Hashtbl.t;
  dirty : (int, unit) Hashtbl.t;
  mutable generation : int;
  mutable revision : int;
}

let create () =
  { nodes = Hashtbl.create 64; dirty = Hashtbl.create 64; generation = 0; revision = 0 }

let node_count t = Hashtbl.length t.nodes
let generation t = t.generation
let revision t = t.revision
let find_opt t id = Hashtbl.find_opt t.nodes id
let mem t id = Hashtbl.mem t.nodes id

let mark_dirty t id =
  t.revision <- t.revision + 1;
  Hashtbl.replace t.dirty id ();
  match Hashtbl.find_opt t.nodes id with
  | Some (n : node) -> n.revision <- t.revision
  | None -> ()

(* Ids touched since the last drain, in application order (unstable). *)
let drain_dirty t =
  let ids = Hashtbl.fold (fun id () acc -> id :: acc) t.dirty [] in
  Hashtbl.reset t.dirty;
  List.sort compare ids

let peek_dirty t id = Hashtbl.mem t.dirty id
let new_node id kind = { id; kind; ext_id = None; props = Hashtbl.create 8; parent = None; children = vec_create (); revision = 0 }

(* Drop a subtree: remove every descendant from the table and unlink the
   node from its parent. Marks the parent's children changed and every
   removed id dirty so repaint can forget it. *)
let rec drop t id =
  match Hashtbl.find_opt t.nodes id with
  | None -> ()
  | Some node ->
    (* Snapshot first: dropping a child unlinks it from this vec, and
       mutating the vec mid-iteration would skip siblings. *)
    List.iter (drop t) (vec_to_list node.children);
    (match node.parent with
     | Some pid -> (
       match Hashtbl.find_opt t.nodes pid with
       | Some p ->
         vec_remove p.children id;
         mark_dirty t pid
       | None -> ())
     | None -> ());
    Hashtbl.remove t.nodes id;
    mark_dirty t id

(* Insert child at index within parent, detaching it from its previous
   parent first so a move never leaves the id listed twice.

   The detach consults the child's recorded parent instead of filtering
   the target's children unconditionally: [c.parent = None] means the id
   sits in no children vec, so the common first-attach path skips the
   O(fan-out) scan entirely. *)
let insert_child t parent child index =
  match (Hashtbl.find_opt t.nodes parent, Hashtbl.find_opt t.nodes child) with
  | Some p, Some c ->
    (match c.parent with
     | Some pid -> (
       match Hashtbl.find_opt t.nodes pid with
       | Some op ->
         vec_remove op.children child;
         if pid <> parent then mark_dirty t pid
       | None -> ())
     | None -> ());
    vec_insert_at p.children index child;
    c.parent <- Some parent;
    mark_dirty t parent;
    mark_dirty t child
  | _ -> ()

let apply_op t = function
  | CreateNode (id, k) ->
    (* Recreate must drop the previous subtree first: a bare
       Hashtbl.replace leaves former children with parent=Some id while
       the new node starts with an empty child_vec — orphans. *)
    if Hashtbl.mem t.nodes id then drop t id;
    Hashtbl.replace t.nodes id (new_node id (Lui_wire_schema.node_kind_name k));
    mark_dirty t id
  | CreateExtension (id, identifier, _fp) ->
    if Hashtbl.mem t.nodes id then drop t id;
    let n = new_node id ("extension:" ^ identifier) in
    n.ext_id <- Some identifier;
    Hashtbl.replace t.nodes id n;
    mark_dirty t id
  | DropNode id | DetachSubtree id -> drop t id
  | SetProp (id, p, v) -> (
    match Hashtbl.find_opt t.nodes id with
    | Some n ->
      Hashtbl.replace n.props (Lui_wire_schema.property_name p) v;
      mark_dirty t id
    | None -> ())
  | RemoveProp (id, p) -> (
    match Hashtbl.find_opt t.nodes id with
    | Some n ->
      Hashtbl.remove n.props (Lui_wire_schema.property_name p);
      mark_dirty t id
    | None -> ())
  | SetExtensionProp (id, name, v) -> (
    match Hashtbl.find_opt t.nodes id with
    | Some n ->
      Hashtbl.replace n.props name v;
      mark_dirty t id
    | None -> ())
  | RemoveExtensionProp (id, name) -> (
    match Hashtbl.find_opt t.nodes id with
    | Some n ->
      Hashtbl.remove n.props name;
      mark_dirty t id
    | None -> ())
  | InsertChild (parent, child, index) | MoveChild (parent, child, index) ->
    insert_child t parent child index
  | RemoveChild (parent, child) -> (
    match (Hashtbl.find_opt t.nodes parent, Hashtbl.find_opt t.nodes child) with
    | Some p, Some c ->
      vec_remove p.children child;
      c.parent <- None;
      mark_dirty t parent;
      mark_dirty t child
    | _ -> ())

let apply_batch t (batch : patch_batch) =
  t.generation <- batch.generation;
  List.iter (apply_op t) batch.ops

(* ---------- queries ---------- *)

let node_id n = n.id
let node_kind n = n.kind
let node_ext_id n = n.ext_id
let node_parent n = n.parent
let node_children n = vec_to_list n.children
let node_prop n name = Hashtbl.find_opt n.props name
let node_revision (n : node) = n.revision

let kind t id = match find_opt t id with Some n -> n.kind | None -> ""
let is_editable_text_kind = function
  | "text-field" | "secure-field" | "input" | "search-field"
  | "textarea" -> true
  | _ -> false

let ext_id t id = match find_opt t id with Some n -> n.ext_id | None -> None
let parent t id = match find_opt t id with Some n -> n.parent | None -> None
let children t id =
  match find_opt t id with
  | Some n ->
    vec_fold
      (fun acc c ->
        match Hashtbl.find_opt t.nodes c with
        | Some child -> child :: acc
        | None -> acc)
      [] n.children
    |> List.rev
  | None -> []

let child_ids t id =
  match find_opt t id with
  | Some n -> vec_to_list n.children
  | None -> []

let last_child_id t id =
  match find_opt t id with
  | Some n -> vec_last n.children
  | None -> None
let prop t id name =
  match find_opt t id with
  | Some n -> Hashtbl.find_opt n.props name
  | None -> None

let bool_prop t id name = match prop t id name with Some (BoolValue b) -> b | _ -> false
let string_prop t id name = match prop t id name with Some (StringValue s) -> Some s | _ -> None
let float_prop t id name = match prop t id name with Some (FloatValue f) -> Some f | _ -> None
let int_prop t id name = match prop t id name with Some (IntValue i) -> Some i | _ -> None

let rec depth t id =
  match find_opt t id with
  | Some { parent = Some p; _ } -> 1 + depth t p
  | _ -> 0

(* Ids whose parent chain reaches no stored node: the forest roots. *)
let root_ids t =
  Hashtbl.fold
    (fun id n acc ->
      match n.parent with
      | None -> id :: acc
      | Some pid when not (Hashtbl.mem t.nodes pid) -> id :: acc
      | Some _ -> acc)
    t.nodes []
  |> List.sort compare

(* Preorder ids under [root] (or the whole forest when None). *)
let preorder ?root t =
  let rec walk id acc =
    match find_opt t id with
    | None -> acc
    | Some n -> vec_fold (fun acc c -> walk c acc) (id :: acc) n.children
  in
  let roots = match root with Some id -> [ id ] | None -> root_ids t in
  List.rev (List.fold_left (fun acc id -> walk id acc) [] roots)

let all_nodes t =
  Hashtbl.fold (fun _ n acc -> n :: acc) t.nodes []
  |> List.sort (fun a b -> compare a.id b.id)
