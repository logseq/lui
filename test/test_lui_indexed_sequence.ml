(* Indexed sequence against a list model. [move] removes the id first and
   then inserts at the requested index in the remaining sequence. *)

module Seq = Lui_indexed_sequence

type model = {
  ids : int list;
  weights : (int, int) Hashtbl.t;
}

let weight model id =
  match Hashtbl.find_opt model.weights id with
  | Some value -> value
  | None -> 1

let take count ids =
  let rec loop count ids acc =
    if count = 0 then (List.rev acc, ids)
    else
      match ids with
      | [] -> (List.rev acc, [])
      | id :: rest -> loop (count - 1) rest (id :: acc)
  in
  loop count ids []

let model_insert model index id =
  (* A fresh node starts at weight 1, even if this id was weighted before. *)
  Hashtbl.remove model.weights id;
  let left, right = take index model.ids in
  { model with ids = left @ (id :: right) }

let model_remove model id =
  { model with ids = List.filter (fun item -> item <> id) model.ids }

let model_move model id index =
  model_insert (model_remove model id) index id

let model_prefix model index =
  let rec sum count ids =
    match (count, ids) with
    | 0, _ | _, [] -> 0
    | count, id :: rest -> weight model id + sum (count - 1) rest
  in
  sum index model.ids

let empty_model () = { ids = []; weights = Hashtbl.create 16 }

let check_same label sequence model =
  Alcotest.(check (list int)) label model.ids (Seq.to_list sequence);
  Alcotest.(check int) (label ^ " length") (List.length model.ids) (Seq.length sequence);
  List.iteri
    (fun index id ->
      Alcotest.(check (option int)) (label ^ " index") (Some index) (Seq.index sequence id))
    model.ids;
  let visited = ref [] in
  Seq.iter (fun id -> visited := id :: !visited) sequence;
  Alcotest.(check (list int)) (label ^ " iter") model.ids (List.rev !visited);
  for index = 0 to List.length model.ids do
    Alcotest.(check int)
      (label ^ " prefix " ^ string_of_int index)
      (model_prefix model index)
      (Seq.prefix_weight sequence index)
  done

let raises name message run =
  Alcotest.check_raises name (Invalid_argument message) run

let test_bounds_and_identity () =
  let sequence = Seq.of_list [] in
  check_same "empty" sequence (empty_model ());
  raises "empty insert" "sequence insert index" (fun () -> Seq.insert sequence 1 1);
  raises "negative insert" "sequence insert index" (fun () -> Seq.insert sequence (-1) 1);
  raises "empty move" "sequence move index" (fun () -> Seq.move sequence 1 0);
  raises "empty prefix" "sequence prefix index" (fun () -> ignore (Seq.prefix_weight sequence 1));
  raises "negative prefix" "sequence prefix index" (fun () -> ignore (Seq.prefix_weight sequence (-1)));
  raises "missing remove" "unknown sequence id" (fun () -> Seq.remove sequence 1);
  Seq.set_weight sequence 1 5;
  Alcotest.(check int) "unknown weight is ignored" 0 (Seq.prefix_weight sequence 0);
  Seq.insert sequence 0 10;
  Seq.insert sequence 1 20;
  Seq.insert sequence 0 5;
  let model = model_insert (model_insert (model_insert (empty_model ()) 0 10) 1 20) 0 5 in
  check_same "insert ends and front" sequence model;
  raises "duplicate" "duplicate sequence id" (fun () -> Seq.insert sequence 1 10);
  raises "insert past end" "sequence insert index" (fun () -> Seq.insert sequence 4 1);
  Seq.remove sequence 20;
  let model = model_remove model 20 in
  check_same "remove tail" sequence model;
  Seq.insert sequence 1 (-3);
  let model = model_insert model 1 (-3) in
  check_same "negative id" sequence model;
  Seq.move sequence 10 0;
  let model = model_move model 10 0 in
  check_same "move to front" sequence model;
  Seq.move sequence (-3) 2;
  let model = model_move model (-3) 2 in
  check_same "move forward" sequence model;
  Seq.move sequence 5 1;
  let model = model_move model 5 1 in
  check_same "move onto itself" sequence model;
  raises "move out" "sequence move index" (fun () -> Seq.move sequence 5 3);
  raises "move negative" "sequence move index" (fun () -> Seq.move sequence 5 (-1));
  raises "move missing" "unknown sequence id" (fun () -> Seq.move sequence 99 0);
  Seq.set_weight sequence 10 0;
  Seq.set_weight sequence (-3) 4;
  Hashtbl.replace model.weights 10 0;
  Hashtbl.replace model.weights (-3) 4;
  check_same "weights" sequence model;
  Seq.set_weight sequence 404 9;
  check_same "unknown weight still ignored" sequence model;
  Seq.remove sequence 10;
  Seq.remove sequence 5;
  Seq.remove sequence (-3);
  check_same "cleared" sequence (empty_model ())

let test_documented_move () =
  let sequence = Seq.of_list [ 10; 20; 30; 40 ] in
  Seq.move sequence 20 3;
  Alcotest.(check (list int)) "forward move uses the post-removal index" [ 10; 30; 40; 20 ]
    (Seq.to_list sequence);
  Seq.move sequence 40 0;
  Alcotest.(check (list int)) "backward move" [ 40; 10; 30; 20 ] (Seq.to_list sequence);
  Alcotest.(check (option int)) "lookup" (Some 2) (Seq.index sequence 30);
  Alcotest.(check (option int)) "missing lookup" None (Seq.index sequence 99)

let test_random_model () =
  let state = ref 0x12345678l in
  let next () =
    state := Int32.(logxor !state (shift_left !state 13));
    state := Int32.(logxor !state (shift_right_logical !state 17));
    state := Int32.(logxor !state (shift_left !state 5));
    Int32.to_int !state land 0x7fffffff
  in
  for seed_case = 0 to 39 do
    state := Int32.of_int (0x51ED + (seed_case * 97));
    let sequence = Seq.of_list [] in
    let model = empty_model () in
    let model = ref model in
    for _ = 1 to 80 do
      let length = List.length !model.ids in
      match next () mod 5 with
      | 0 ->
        let index = if length = 0 then 0 else next () mod (length + 1) in
        let id = next () mod 30 in
        if List.mem id !model.ids then
          raises "duplicate random" "duplicate sequence id" (fun () -> Seq.insert sequence index id)
        else begin
          Seq.insert sequence index id;
          model := model_insert !model index id
        end
      | 1 when length > 0 ->
        let id = List.nth !model.ids (next () mod length) in
        Seq.remove sequence id;
        model := model_remove !model id
      | 2 when length > 0 ->
        let id = List.nth !model.ids (next () mod length) in
        let index = next () mod length in
        Seq.move sequence id index;
        model := model_move !model id index
      | 3 when length > 0 ->
        let id = List.nth !model.ids (next () mod length) in
        let value = next () mod 6 in
        Seq.set_weight sequence id value;
        Hashtbl.replace !model.weights id value
      | _ ->
        let index = next () mod (length + 1) in
        Alcotest.(check int) "random prefix" (model_prefix !model index)
          (Seq.prefix_weight sequence index);
        raises "random high prefix" "sequence prefix index" (fun () ->
            ignore (Seq.prefix_weight sequence (length + 1)))
    done;
    check_same ("seed " ^ string_of_int seed_case) sequence !model
  done

let test_large_sequence () =
  let count = 100_000 in
  let sequence = Seq.of_list (List.init count Fun.id) in
  Alcotest.(check int) "100k length" count (Seq.length sequence);
  Alcotest.(check (option int)) "first" (Some 0) (Seq.index sequence 0);
  Alcotest.(check (option int)) "middle" (Some 50_000) (Seq.index sequence 50_000);
  Alcotest.(check (option int)) "last" (Some 99_999) (Seq.index sequence 99_999);
  Alcotest.(check int) "full prefix" count (Seq.prefix_weight sequence count);
  Alcotest.(check int) "thousand prefix" 1_000 (Seq.prefix_weight sequence 1_000);
  Seq.set_weight sequence 50_000 5;
  Alcotest.(check int) "weighted prefix" (50_000 + 5) (Seq.prefix_weight sequence 50_001);
  Seq.remove sequence 0;
  Alcotest.(check (option int)) "shifted" (Some 0) (Seq.index sequence 1);
  Alcotest.(check int) "after remove" 99_999 (Seq.length sequence);
  Seq.insert sequence 0 0;
  Alcotest.(check (option int)) "reinserted" (Some 0) (Seq.index sequence 0);
  Seq.move sequence 99_999 0;
  Alcotest.(check (option int)) "moved large id" (Some 0) (Seq.index sequence 99_999);
  Alcotest.(check (option int)) "displaced zero" (Some 1) (Seq.index sequence 0);
  Seq.insert sequence 100_000 100_000;
  Alcotest.(check (option int)) "append" (Some 100_000) (Seq.index sequence 100_000);
  raises "large duplicate" "duplicate sequence id" (fun () -> Seq.insert sequence 0 1);
  raises "large bounds" "sequence insert index" (fun () -> Seq.insert sequence (-1) 7);
  let sample = ref [] in
  Seq.iter
    (fun id -> if List.length !sample < 3 then sample := id :: !sample)
    sequence;
  Alcotest.(check (list int)) "iteration starts at the moved tail" [ 99_999; 0; 1 ]
    (List.rev !sample)

let () =
  Alcotest.run "lui indexed sequence"
    [ ( "model"
      , [ Alcotest.test_case "bounds, identity, weights" `Quick test_bounds_and_identity
        ; Alcotest.test_case "move index is post-removal" `Quick test_documented_move
        ; Alcotest.test_case "random operations match a list" `Quick test_random_model
        ; Alcotest.test_case "100k insert delete move lookup" `Quick test_large_sequence
        ] )
    ]
