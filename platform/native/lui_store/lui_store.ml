(* Retained mirror of LUI patch batches for the native backend.

   The store keeps the node tree the patch stream describes and marks
   nodes dirty as their props or children change, so paint and layout
   can invalidate incrementally. Kinds and props are keyed by their wire
   names (Lui_wire_schema names), matching the convention used elsewhere
   so a prop lookup like [bool_prop t id "enabled"] reads the same key
   every backend sees. *)

open Lui_protocol

type node = {
  id : int;
  kind : string; (* node_kind_name, or "extension:<identifier>" *)
  mutable ext_id : string option;
  props : (string, wire_value) Hashtbl.t;
  mutable parent : int option;
  mutable children : int list;
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
let new_node id kind = { id; kind; ext_id = None; props = Hashtbl.create 8; parent = None; children = []; revision = 0 }

(* Drop a subtree: remove every descendant from the table and unlink the
   node from its parent. Marks the parent's children changed and every
   removed id dirty so repaint can forget it. *)
let rec drop t id =
  match Hashtbl.find_opt t.nodes id with
  | None -> ()
  | Some node ->
    List.iter (drop t) node.children;
    (match node.parent with
     | Some pid -> (
       match Hashtbl.find_opt t.nodes pid with
       | Some p -> p.children <- List.filter (fun c -> c <> id) p.children
       | None -> ())
     | None -> ());
    Hashtbl.remove t.nodes id;
    mark_dirty t id

(* Insert child at index within parent, detaching it from its previous
   parent first so a move never leaves the id listed twice. *)
let insert_child t parent child index =
  match (Hashtbl.find_opt t.nodes parent, Hashtbl.find_opt t.nodes child) with
  | Some p, Some c ->
    (match c.parent with
     | Some old_pid when old_pid <> parent -> (
       match Hashtbl.find_opt t.nodes old_pid with
       | Some op ->
         op.children <- List.filter (fun x -> x <> child) op.children;
         mark_dirty t old_pid
       | None -> ())
     | _ -> ());
    p.children <- List.filter (fun x -> x <> child) p.children;
    let rec insert_at i acc = function
      | [] -> List.rev (child :: acc)
      | rest when i <= 0 -> List.rev_append acc (child :: rest)
      | x :: tl -> insert_at (i - 1) (x :: acc) tl
    in
    p.children <- insert_at index [] p.children;
    c.parent <- Some parent;
    mark_dirty t parent;
    mark_dirty t child
  | _ -> ()

let apply_op t = function
  | CreateNode (id, k) ->
    Hashtbl.replace t.nodes id (new_node id (Lui_wire_schema.node_kind_name k));
    mark_dirty t id
  | CreateExtension (id, identifier, _fp) ->
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
      p.children <- List.filter (fun x -> x <> child) p.children;
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
let node_children n = n.children
let node_prop n name = Hashtbl.find_opt n.props name
let node_revision (n : node) = n.revision

let kind t id = match find_opt t id with Some n -> n.kind | None -> ""
let ext_id t id = match find_opt t id with Some n -> n.ext_id | None -> None
let parent t id = match find_opt t id with Some n -> n.parent | None -> None
let children t id =
  match find_opt t id with
  | Some n -> List.filter_map (Hashtbl.find_opt t.nodes) n.children
  | None -> []

let child_ids t id = match find_opt t id with Some n -> n.children | None -> []
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
    | Some n -> List.fold_left (fun acc c -> walk c acc) (id :: acc) n.children
  in
  let roots = match root with Some id -> [ id ] | None -> root_ids t in
  List.rev (List.fold_left (fun acc id -> walk id acc) [] roots)

let all_nodes t =
  Hashtbl.fold (fun _ n acc -> n :: acc) t.nodes []
  |> List.sort (fun a b -> compare a.id b.id)
