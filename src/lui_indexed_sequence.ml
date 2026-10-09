(* Batch-local order statistics. Handles locate ids without scanning siblings;
   subtree weights also translate retained indexes into visible DOM indexes. *)
type node = {
  id : int;
  priority : int;
  mutable left : node option;
  mutable right : node option;
  mutable parent : node option;
  mutable size : int;
  mutable weight : int;
  mutable total_weight : int;
}

type t = { mutable root : node option; handles : (int, node) Hashtbl.t }

let size = function None -> 0 | Some node -> node.size
let weight = function None -> 0 | Some node -> node.total_weight
let length sequence = size sequence.root
let attach parent = function None -> () | Some node -> node.parent <- parent

let update node =
  attach (Some node) node.left;
  attach (Some node) node.right;
  node.size <- 1 + size node.left + size node.right;
  node.total_weight <- node.weight + weight node.left + weight node.right

let rooted root =
  attach None root;
  root

let rec merge left right =
  match (left, right) with
  | None, other | other, None -> rooted other
  | Some left, Some right ->
      if left.priority <= right.priority then begin
        left.right <- merge left.right (Some right);
        update left;
        rooted (Some left)
      end
      else begin
        right.left <- merge (Some left) right.left;
        update right;
        rooted (Some right)
      end

let rec split root index =
  match root with
  | None -> (None, None)
  | Some node ->
      let left_size = size node.left in
      if index <= left_size then begin
        let left, middle = split node.left index in
        node.left <- middle;
        update node;
        (rooted left, rooted (Some node))
      end
      else begin
        let middle, right = split node.right (index - left_size - 1) in
        node.right <- middle;
        update node;
        (rooted (Some node), rooted right)
      end

let rank node =
  let rec climb node index =
    match node.parent with
    | None -> index
    | Some parent ->
        let index =
          match parent.right with
          | Some right when right == node -> index + size parent.left + 1
          | _ -> index
        in
        climb parent index
  in
  climb node (size node.left)

let index sequence id = Option.map rank (Hashtbl.find_opt sequence.handles id)

let insert sequence index id =
  if index < 0 || index > length sequence then
    invalid_arg "sequence insert index";
  if Hashtbl.mem sequence.handles id then invalid_arg "duplicate sequence id";
  let node =
    {
      id;
      priority = Hashtbl.hash id;
      left = None;
      right = None;
      parent = None;
      size = 1;
      weight = 1;
      total_weight = 1;
    }
  in
  let left, right = split sequence.root index in
  sequence.root <- merge (merge left (Some node)) right;
  Hashtbl.replace sequence.handles id node

let remove sequence id =
  match index sequence id with
  | None -> invalid_arg "unknown sequence id"
  | Some index ->
      let left, rest = split sequence.root index in
      let _, right = split rest 1 in
      sequence.root <- merge left right;
      Hashtbl.remove sequence.handles id

let move sequence id index =
  if index < 0 || index >= length sequence then
    invalid_arg "sequence move index";
  remove sequence id;
  insert sequence index id

let of_list ids =
  let sequence = { root = None; handles = Hashtbl.create (List.length ids) } in
  List.iteri (fun index id -> insert sequence index id) ids;
  sequence

let to_list sequence =
  let rec collect root tail =
    match root with
    | None -> tail
    | Some node -> collect node.left (node.id :: collect node.right tail)
  in
  collect sequence.root []

let set_weight sequence id value =
  match Hashtbl.find_opt sequence.handles id with
  | None -> ()
  | Some node ->
      node.weight <- value;
      let rec refresh node =
        update node;
        Option.iter refresh node.parent
      in
      refresh node

let prefix_weight sequence index =
  if index < 0 || index > length sequence then
    invalid_arg "sequence prefix index";
  let rec sum root count =
    match root with
    | None -> 0
    | Some node ->
        let left_size = size node.left in
        if count <= left_size then sum node.left count
        else
          weight node.left + node.weight + sum node.right (count - left_size - 1)
  in
  sum sequence.root index
