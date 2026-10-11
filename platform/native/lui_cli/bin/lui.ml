(* The `lui` developer CLI: scaffolding, watch-mode dev loop, builds,
   packaging via the Lui_pkg* libraries, toolchain checks and
   update-signing keys. All logic lives in Lui_cli; this entry point
   only hands it argv and forwards its exit code. *)

let () = exit (Lui_cli.main (List.tl (Array.to_list Sys.argv)))
