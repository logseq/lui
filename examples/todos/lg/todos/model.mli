(* ns todos.model *)

type todo = { todo_id : int ; todo_title : string ; todo_done : bool }

type todo_model = { model_items : todo Rrbvec.t ; model_draft : string ; model_notes : string ; model_next_id : int }

type todo_action =
  | ChangeDraft of string
  | ChangeNotes of string
  | AddTodo
  | ToggleTodo of int
  | MoveTodoUp of int
  | DeleteTodo of int

val initial : unit -> todo_model

val update : todo_model -> todo_action -> todo_model

val toggle_one : todo -> int -> todo

val toggle_items : todo Rrbvec.t -> int -> todo Rrbvec.t

val remove_item : todo Rrbvec.t -> int -> todo Rrbvec.t

val move_item_up : todo Rrbvec.t -> int -> todo Rrbvec.t

