(* Persistent indexed sequences. Rotations keep inserts and removals logarithmic. *)
type 'a t = Empty | Node of 'a t * 'a * 'a t * int * int
let empty = Empty
let length = function Empty -> 0 | Node (_, _, _, _, size) -> size
let height = function Empty -> 0 | Node (_, _, _, height, _) -> height
let node left value right =
  Node (left, value, right, 1 + max (height left) (height right), 1 + length left + length right)
let balance left value right =
  if height left > height right + 2 then
    match left with
    | Node (ll, lv, lr, _, _) ->
      if height ll >= height lr then node ll lv (node lr value right)
      else (match lr with
        | Node (lrl, lrv, lrr, _, _) -> node (node ll lv lrl) lrv (node lrr value right)
        | Empty -> assert false)
    | Empty -> assert false
  else if height right > height left + 2 then
    match right with
    | Node (rl, rv, rr, _, _) ->
      if height rr >= height rl then node (node left value rl) rv rr
      else (match rl with
        | Node (rll, rlv, rlr, _, _) -> node (node left value rll) rlv (node rlr rv rr)
        | Empty -> assert false)
    | Empty -> assert false
  else node left value right
let rec insert tree index value =
  if index < 0 || index > length tree then invalid_arg "sequence insert index";
  match tree with
  | Empty -> node Empty value Empty
  | Node (left, current, right, _, _) ->
    let size = length left in
    if index <= size then balance (insert left index value) current right
    else balance left current (insert right (index - size - 1) value)
let rec get tree index =
  if index < 0 || index >= length tree then invalid_arg "sequence index";
  match tree with
  | Empty -> assert false
  | Node (left, value, right, _, _) ->
    let size = length left in
    if index < size then get left index
    else if index = size then value else get right (index - size - 1)
let rec index_from tree target base =
  match tree with
  | Empty -> None
  | Node (left, value, right, _, _) ->
    let left_len = length left in
    if value = target then Some (base + left_len)
    else
      match index_from left target base with
      | Some found -> Some found
      | None -> index_from right target (base + left_len + 1)

let index tree target = index_from tree target 0

let rec remove tree index =
  if index < 0 || index >= length tree then invalid_arg "sequence remove index";
  match tree with
  | Empty -> assert false
  | Node (left, value, right, _, _) ->
    let size = length left in
    if index < size then balance (remove left index) value right
    else if index > size then balance left value (remove right (index - size - 1))
    else match left, right with
      | Empty, other | other, Empty -> other
      | _ -> balance left (get right 0) (remove right 0)
let to_list tree =
  let rec loop tree tail = match tree with
    | Empty -> tail
    | Node (left, value, right, _, _) -> loop left (value :: loop right tail) in
  loop tree []
let of_list values =
  let rec build count values =
    if count = 0 then Empty, values else
    let left_size = count / 2 in
    let left, rest = build left_size values in
    match rest with
    | [] -> assert false
    | value :: rest ->
      let right, rest = build (count - left_size - 1) rest in
      node left value right, rest in
  fst (build (List.length values) values)
let map f tree = of_list (List.map f (to_list tree))
let iter f tree = List.iter f (to_list tree)
let fold_left f initial tree = List.fold_left f initial (to_list tree)
