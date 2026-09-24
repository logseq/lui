(* Yojson-backed parser producing [Lui_json_view] view-models.

   Kept out of the [lui] library on purpose: yojson has no melange build,
   and [parse] is a convenience for native hosts — melange callers feed
   [Lui_json_view.value] directly. *)

module V = Lui_json_view

(* hard cap on view-model nesting — pathological input must not exhaust
   the stack during conversion or rendering *)
let max_depth = 512

let rec value_of_yojson : Yojson.Basic.t -> V.value = function
  | `Null -> Null
  | `Bool b -> Bool b
  | `Int i -> Num (float_of_int i)
  | `Float f -> Num f
  | `String s -> Str s
  | `List l -> Arr (List.map value_of_yojson l)
  | `Assoc a -> Obj (List.map (fun (k, v) -> (k, value_of_yojson v)) a)

let too_deep (v : Yojson.Basic.t) : bool =
  let stack = Stack.create () in
  Stack.push (v, 0) stack;
  try
    while not (Stack.is_empty stack) do
      let node, d = Stack.pop stack in
      if d > max_depth then raise Exit;
      match node with
      | `Assoc a -> List.iter (fun (_, x) -> Stack.push (x, d + 1) stack) a
      | `List l -> List.iter (fun x -> Stack.push (x, d + 1) stack) l
      | _ -> ()
    done;
    false
  with Exit -> true

let parse (s : string) : (V.value, string) result =
  try
    let v = Yojson.Basic.from_string s in
    if too_deep v then Error "nesting too deep"
    else Ok (value_of_yojson v)
  with e -> Error (Printexc.to_string e)
