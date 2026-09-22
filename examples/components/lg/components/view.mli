(* ns components.view *)

val card_copy : gallery_model -> string

val gallery_view_with_option : ui_context -> gallery_model signal -> (gallery_action -> bool) -> bool signal -> int

val gallery_view : ui_context -> gallery_model signal -> (gallery_action -> bool) -> int

val gallery_view_with_extensions : ui_context -> gallery_model signal -> (gallery_action -> bool) -> int

