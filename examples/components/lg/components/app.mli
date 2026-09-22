(* ns components.app *)

val create : backend -> (gallery_model, gallery_action) reducer_app

val create_with_extensions : backend -> extension_registry -> (gallery_model, gallery_action) reducer_app

val model : (gallery_model, gallery_action) reducer_app -> gallery_model

