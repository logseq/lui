(* Todo list model: pure data + reducer. *)

type todo = {
  id : int;
  title : string;
  done_ : bool;
}

type t = {
  items : todo list;
  draft : string;
  notes : string;
  next_id : int;
}

type action =
  | ChangeDraft of string
  | ChangeNotes of string
  | AddTodo
  | ToggleTodo of int
  | MoveTodoUp of int
  | DeleteTodo of int

let initial = { items = []; draft = ""; notes = ""; next_id = 0 }

let toggle_items items id =
  List.map
    (fun item ->
       if item.id = id then { item with done_ = not item.done_ } else item)
    items

let remove_item items id = List.filter (fun item -> item.id <> id) items

let move_item_up items id =
  let rec loop acc items =
    match items with
    | [] -> List.rev acc
    | [ x ] -> List.rev (x :: acc)
    | prev :: (cur :: rest as tail) ->
      if cur.id = id then List.rev_append (cur :: acc) (prev :: rest)
      else loop (prev :: acc) tail
  in
  loop [] items

let update model action =
  match action with
  | ChangeDraft text -> { model with draft = text }
  | ChangeNotes text -> { model with notes = text }
  | AddTodo ->
    if model.draft = "" then model
    else
      let id = model.next_id + 1 in
      {
        items = model.items @ [ { id; title = model.draft; done_ = false } ];
        draft = "";
        notes = model.notes;
        next_id = id;
      }
  | ToggleTodo id -> { model with items = toggle_items model.items id }
  | MoveTodoUp id -> { model with items = move_item_up model.items id }
  | DeleteTodo id -> { model with items = remove_item model.items id }

let change_draft text = ChangeDraft text
let change_notes text = ChangeNotes text

let items model = model.items
let draft model = model.draft
let notes model = model.notes
