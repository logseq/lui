(* ns todos.view *)

val item_label : todo -> string

val content_padding : operating_system -> int

val content_gap : operating_system -> int

val summary_label : todo_model -> string

val todo_row : ui_context -> todo signal -> (todo_action -> bool) -> int

val todos_view : ui_context -> todo_model signal -> (todo_action -> bool) -> int

