(* Node tree replayed from LUI patch ops. Kinds and props are keyed by
   their wire names (Lui_wire_schema names) so the same model is fed
   either from decoded OCaml ops (in-process) or wire JSON (FFI driver). *)

open Lui_protocol

type node = {
  id : int;
  mutable kind : string; (* node_kind_name, or "extension:<identifier>" *)
  props : (string, wire_value) Hashtbl.t;
  mutable parent : int option;
  mutable children : int list;
}

type t = {
  nodes : (int, node) Hashtbl.t;
  mutable generation : int;
}

let create () = { nodes = Hashtbl.create 64; generation = 0 }
let node_count t = Hashtbl.length t.nodes
let generation t = t.generation

let new_node id kind = { id; kind; props = Hashtbl.create 8; parent = None; children = [] }

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
    Hashtbl.remove t.nodes id

let insert_child t parent child index =
  match Hashtbl.find_opt t.nodes parent, Hashtbl.find_opt t.nodes child with
  | Some p, Some c ->
    p.children <- List.filter (fun x -> x <> child) p.children;
    let rec insert_at i acc = function
      | [] -> List.rev (child :: acc)
      | rest when i <= 0 -> List.rev_append acc (child :: rest)
      | x :: tl -> insert_at (i - 1) (x :: acc) tl
    in
    p.children <- insert_at index [] p.children;
    c.parent <- Some parent
  | _ -> ()

(* ---------- in-process ops ---------- *)

let apply_op t = function
  | CreateNode (id, k) ->
    Hashtbl.replace t.nodes id (new_node id (Lui_wire_schema.node_kind_name k))
  | CreateExtension (id, identifier, _fp) ->
    Hashtbl.replace t.nodes id (new_node id ("extension:" ^ identifier))
  | DropNode id -> drop t id
  | DetachSubtree id -> drop t id
  | SetProp (id, p, v) -> (
    match Hashtbl.find_opt t.nodes id with
    | Some n -> Hashtbl.replace n.props (Lui_wire_schema.property_name p) v
    | None -> ())
  | RemoveProp (id, p) -> (
    match Hashtbl.find_opt t.nodes id with
    | Some n -> Hashtbl.remove n.props (Lui_wire_schema.property_name p)
    | None -> ())
  | SetExtensionProp (id, name, v) -> (
    match Hashtbl.find_opt t.nodes id with
    | Some n -> Hashtbl.replace n.props name v
    | None -> ())
  | RemoveExtensionProp (id, name) -> (
    match Hashtbl.find_opt t.nodes id with
    | Some n -> Hashtbl.remove n.props name
    | None -> ())
  | InsertChild (parent, child, index) -> insert_child t parent child index
  | RemoveChild (parent, child) -> (
    match Hashtbl.find_opt t.nodes parent, Hashtbl.find_opt t.nodes child with
    | Some p, Some c ->
      p.children <- List.filter (fun x -> x <> child) p.children;
      c.parent <- None
    | _ -> ())
  | MoveChild (parent, child, index) -> insert_child t parent child index

let apply_batch t (batch : patch_batch) =
  t.generation <- batch.generation;
  List.iter (apply_op t) batch.ops

(* ---------- wire JSON (FFI) ---------- *)

let wire_value_of_json = function
  | `String s -> Some (StringValue s)
  | `Bool b -> Some (BoolValue b)
  | `Int i -> Some (IntValue i)
  | `Float f -> Some (FloatValue f)
  | `Intlit s -> (try Some (IntValue (int_of_string s)) with _ -> None)
  | _ -> None

let apply_wire_op t (json : Yojson.Safe.t) =
  let open Yojson.Safe.Util in
  let id = member "id" json |> to_int_option |> Option.value ~default:(-1) in
  let str name = match member name json with `String s -> s | _ -> "" in
  let set name v =
    match Hashtbl.find_opt t.nodes id with
    | Some n -> Hashtbl.replace n.props name v
    | None -> ()
  in
  match str "op" with
  | "create-node" -> Hashtbl.replace t.nodes id (new_node id (str "kind"))
  | "create-extension" ->
    Hashtbl.replace t.nodes id (new_node id ("extension:" ^ str "identifier"))
  | "drop-node" -> drop t id
  | "detach-subtree" -> drop t id
  | "set-prop" | "set-extension-prop" -> (
    match wire_value_of_json (member "value" json) with
    | Some v -> set (str "property") v
    | None -> ())
  | "remove-prop" | "remove-extension-prop" -> (
    match Hashtbl.find_opt t.nodes id with
    | Some n -> Hashtbl.remove n.props (str "property")
    | None -> ())
  | "insert-child" | "move-child" ->
    let parent = member "parent" json |> to_int_option |> Option.value ~default:(-1) in
    let child = member "child" json |> to_int_option |> Option.value ~default:(-1) in
    let index = member "index" json |> to_int_option |> Option.value ~default:0 in
    insert_child t parent child index
  | "remove-child" ->
    let parent = member "parent" json |> to_int_option |> Option.value ~default:(-1) in
    let child = member "child" json |> to_int_option |> Option.value ~default:(-1) in
    (match Hashtbl.find_opt t.nodes parent with
     | Some p -> p.children <- List.filter (fun x -> x <> child) p.children
     | None -> ())
  | _ -> ()

let apply_wire_batch t (json : Yojson.Safe.t) =
  let open Yojson.Safe.Util in
  (match member "generation" json with
   | `Int g -> t.generation <- g
   | _ -> ());
  match member "ops" json with
  | `List ops -> List.iter (apply_wire_op t) ops
  | _ -> ()

(* ---------- queries ---------- *)

type selector =
  | Id of int
  | Kind of string (* matches kind name: "dialog", "text-field", ... *)
  | Ext of string (* extension identifier *)
  | Text of string (* any string prop containing the needle *)
  | Prop of string * wire_value
  | PropPrefix of string * string (* prop:name=prefix* — trailing star *)
  | All of selector list (* conjunction: kind:button&text:Save *)

let all_nodes t =
  let acc = Hashtbl.fold (fun _ n acc -> n :: acc) t.nodes [] in
  List.sort (fun a b -> compare a.id b.id) acc

let string_prop node name =
  match Hashtbl.find_opt node.props name with
  | Some (StringValue s) -> Some s
  | _ -> None

let rec matches node = function
  | Id id -> node.id = id
  | Kind name -> node.kind = name
  | Ext identifier -> node.kind = "extension:" ^ identifier
  | Text needle ->
    let needle = String.lowercase_ascii needle in
    Hashtbl.fold
      (fun _ v acc ->
        acc
        ||
        match v with
        | StringValue s ->
          let s = String.lowercase_ascii s in
          let len_s = String.length s and len_n = String.length needle in
          len_n <= len_s
          && (let rec go i =
                i <= len_s - len_n
                && (String.sub s i len_n = needle || go (i + 1))
              in
              go 0)
        | _ -> false)
      node.props false
  | Prop (name, v) -> (
    match Hashtbl.find_opt node.props name with
    | Some v' -> v' = v
    | None -> false)
  | PropPrefix (name, prefix) -> (
    match Hashtbl.find_opt node.props name with
    | Some (StringValue s) ->
      let ls = String.length s and lp = String.length prefix in
      lp <= ls && String.sub s 0 lp = prefix
    | _ -> false)
  | All sels -> List.for_all (matches node) sels

let find t sel = List.filter (fun n -> matches n sel) (all_nodes t)
let first t sel = match find t sel with n :: _ -> Some n | [] -> None
let exists t sel = Option.is_some (first t sel)

let prop t id name = match Hashtbl.find_opt t.nodes id with
  | Some n -> Hashtbl.find_opt n.props name
  | None -> None

let children t id = match Hashtbl.find_opt t.nodes id with
  | Some n -> List.filter_map (fun c -> Hashtbl.find_opt t.nodes c) n.children
  | None -> []

(* ---------- coordinate hit-testing (live attach) ---------- *)

(* A host-reported frame: node id -> rect in window/scene coordinates
   (points, top-left origin). Hosts report the full map on each layout
   flush, so stale ids disappear on replace. *)
type rect = { rx : float; ry : float; rw : float; rh : float }

let contains { rx; ry; rw; rh } x y =
  rw > 0.0 && rh > 0.0 && x >= rx && x < rx +. rw && y >= ry
  && y < ry +. rh

let rec depth t id =
  match Hashtbl.find_opt t.nodes id with
  | Some { parent = Some p; _ } -> 1 + depth t p
  | _ -> 0

let parent_of t id =
  match Hashtbl.find_opt t.nodes id with
  | Some { parent = Some p; _ } -> Some p
  | _ -> None

let bool_prop t id name =
  match prop t id name with
  | Some (BoolValue b) -> Some b
  | _ -> None

(* A node is tap-able when it (or an ancestor — a real gesture recognizer
   on a button fires for taps on its label) has press-enabled=true or is
   an inherently pressable control kind, and is not enabled=false.
   Deepest containing node wins. *)
let pressable_kind node = node.kind = "button"

(* Preorder index over the live tree. Later siblings paint on top, so
   this breaks equal-depth overlaps the way a real compositor does. *)
let doc_order t =
  let order = Hashtbl.create (Hashtbl.length t.nodes) in
  let i = ref 0 in
  let rec dfs id =
    match Hashtbl.find_opt t.nodes id with
    | Some n ->
      incr i;
      Hashtbl.replace order id !i;
      List.iter dfs n.children
    | None -> ()
  in
  Hashtbl.iter
    (fun id n -> match n.parent with None -> dfs id | Some _ -> ())
    t.nodes;
  order

let hit_test t ~frames ~x ~y =
  let order = doc_order t in
  let rank id =
    match Hashtbl.find_opt order id with Some i -> i | None -> -1
  in
  let hits =
    Hashtbl.fold
      (fun id r acc ->
        (* only nodes reachable from a root can be hit: a frame can
           outlive its node between snapshots, and a stale rect must not
           mask whatever is now behind it *)
        if Hashtbl.mem order id && contains r x y then id :: acc else acc)
      frames []
  in
  let deepest =
    List.fold_left
      (fun best id ->
        match best with
        | None -> Some id
        | Some b ->
          let db = depth t b and di = depth t id in
          if di > db || (di = db && rank id > rank b) then Some id
          else best)
      None hits
  in
  let rec pressable id =
    if bool_prop t id "enabled" = Some false then None
    else if
      bool_prop t id "press-enabled" = Some true
      ||
      match Hashtbl.find_opt t.nodes id with
      | Some n -> pressable_kind n
      | None -> false
    then Some id
    else
      match parent_of t id with
      | Some p -> pressable p
      | None -> None
  in
  match deepest with
  | Some id -> pressable id
  | None -> None


let string_of_wire_value = function
  | StringValue s -> Printf.sprintf "%S" s
  | BoolValue b -> string_of_bool b
  | IntValue i -> string_of_int i
  | FloatValue f -> string_of_float f

(* Interesting props to show in dumps / failures. *)
let describe t node =
  let texts =
    Hashtbl.fold
      (fun k v acc ->
        match v with
        | StringValue s when k = "text" || k = "label" || k = "value" || k = "placeholder" ->
          (k ^ "=" ^ Printf.sprintf "%S" s) :: acc
        | _ -> acc)
      node.props []
  in
  let kids = children t node.id |> List.length in
  Printf.sprintf "#%d %s%s%s" node.id node.kind
    (if texts = [] then "" else " " ^ String.concat " " texts)
    (if kids = 0 then "" else Printf.sprintf " (%d children)" kids)

let dump ?root t =
  let buf = Buffer.create 1024 in
  let rec walk depth node =
    Buffer.add_string buf
      (Printf.sprintf "%s%s\n" (String.make (2 * depth) ' ') (describe t node));
    List.iter (walk (depth + 1)) (children t node.id)
  in
  let roots =
    match root with
    | Some id -> List.filter (fun n -> n.id = id) (all_nodes t)
    | None ->
      List.filter
        (fun n -> match n.parent with None -> true | Some pid -> not (Hashtbl.mem t.nodes pid))
        (all_nodes t)
  in
  List.iter (walk 0) roots;
  Buffer.contents buf

(* Parse "kind:dialog" | "ext:web-view" | "text:foo" | "id:12" | "prop:name=value";
   "&" combines conjuncts, e.g. kind:button&text:Save *)
let rec selector_of_string s =
  match String.split_on_char '&' s with
  | [one] -> selector_one one
  | parts ->
    let sels = List.filter_map selector_one parts in
    if List.length sels = List.length parts then Some (All sels) else None

and selector_one s =
  match String.index_opt s ':' with
  | None -> (
    match int_of_string_opt s with
    | Some id -> Some (Id id)
    | None -> Some (Text s))
  | Some i ->
    let head = String.sub s 0 i in
    let rest = String.sub s (i + 1) (String.length s - i - 1) in
    let unquote v =
      let n = String.length v in
      if n >= 2 && v.[0] = '"' && v.[n - 1] = '"' then String.sub v 1 (n - 2) else v
    in
    (match head with
     | "id" -> (match int_of_string_opt rest with Some i -> Some (Id i) | None -> None)
     | "kind" -> Some (Kind rest)
     | "ext" -> Some (Ext rest)
     | "text" -> Some (Text (unquote rest))
     | "prop" -> (
       match String.index_opt rest '=' with
       | Some j ->
         let name = String.sub rest 0 j in
         let v = String.sub rest (j + 1) (String.length rest - j - 1) |> unquote in
         let n = String.length v in
         if n > 0 && v.[n - 1] = '*' then
           Some (PropPrefix (name, String.sub v 0 (n - 1)))
         else Some (Prop (name, StringValue v))
       | None -> None)
     | _ -> None)
