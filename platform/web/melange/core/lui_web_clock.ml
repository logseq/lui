(* Browser driver for the application clock: one timeout armed for the next
   deadline, ticked from performance.now(). *)

external performance_now : unit -> float = "now" [@@mel.scope "performance"]

let drive app =
  let timeout = ref None in
  let tick () =
    ignore (Lui_app.tick_clock app ~now:(performance_now ()) : int);
    ignore (Lui_app.flush app : bool)
  in
  let wake delay =
    Option.iter Js.Global.clearTimeout !timeout;
    timeout :=
      Some
        (Js.Global.setTimeout
           ~f:(fun () ->
             timeout := None;
             tick ())
           (int_of_float (Float.ceil delay)))
  in
  tick ();
  Lui_clock.set_wakeup (Lui_app.clock app) (Some wake)
