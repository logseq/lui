(* Real application timers exercised through the desktop host and C ABI. *)
open Lui_elements

type model = {
  delayed : int;
  nested : int;
  repeating : int;
  pending : int;
  paused : bool;
  clock_ms : float;
}

type action =
  | Reset
  | Delayed
  | Nested
  | Repeated
  | Observe of int * bool * float

let initial = {
  delayed = 0; nested = 0; repeating = 0; pending = 0;
  paused = false; clock_ms = 0.;
}

let update model = function
  | Reset -> { model with delayed = 0; nested = 0; repeating = 0 }
  | Delayed -> { model with delayed = model.delayed + 1 }
  | Nested -> { model with nested = model.nested + 1 }
  | Repeated -> { model with repeating = model.repeating + 1 }
  | Observe (pending, paused, clock_ms) -> { model with pending; paused; clock_ms }

let status model =
  Printf.sprintf "clock-state delayed=%d nested=%d repeat=%d pending=%d paused=%b clock=%.3f"
    model.delayed model.nested model.repeating model.pending model.paused model.clock_ms

let view _context model_source send =
  scoped (fun context ->
    let clock = Lui_ui.clock context in
    let delayed = ref None in
    let repeating = ref None in
    let observe () =
      ignore (send (Observe (Lui_clock.pending clock, Lui_clock.paused clock,
                             Lui_clock.now clock)))
    in
    let stop () =
      Option.iter Lui_clock.cancel !delayed;
      Option.iter Lui_clock.cancel !repeating;
      delayed := None;
      repeating := None
    in
    let start_delayed delay () =
      stop ();
      ignore (send Reset);
      delayed := Some (Lui_ui.after context delay (fun () ->
        ignore (send Delayed);
        delayed := Some (Lui_ui.after context 80. (fun () ->
          delayed := None;
          ignore (send Nested);
          observe ()));
        observe ()));
      observe ()
    in
    let start_repeating () =
      stop ();
      ignore (send Reset);
      let remaining = ref 3 in
      repeating := Some (Lui_ui.every context 100. (fun () ->
        decr remaining;
        ignore (send Repeated);
        if !remaining = 0 then stop ();
        observe ()));
      observe ()
    in
    let control identifier label run =
      button ~text:label ~accessibility_identifier:identifier
        ~on_press:(fun _event -> run ()) []
    in
    column ~gap:8 ~padding:16
      [ text ~value:"Clock qualification" []
      ; control "clock-delayed" "Start delayed" (start_delayed 120.)
      ; control "clock-long" "Start long timer" (start_delayed 60_000.)
      ; control "clock-repeat" "Start repeating" start_repeating
      ; control "clock-cancel" "Cancel timers" (fun () -> stop (); observe ())
      ; control "clock-pause" "Pause clock" (fun () -> Lui_clock.pause clock; observe ())
      ; control "clock-resume" "Resume clock" (fun () -> Lui_clock.resume clock; observe ())
      ; control "clock-advance-50" "Advance 50" (fun () ->
          ignore (Lui_clock.advance clock 50.); observe ())
      ; control "clock-advance-250" "Advance 250" (fun () ->
          ignore (Lui_clock.advance clock 250.); observe ())
      ; control "clock-advance-60000" "Advance 60000" (fun () ->
          ignore (Lui_clock.advance clock 60_000.); observe ())
      ; control "clock-sample" "Sample clock" observe
      ; text ~accessibility_identifier:"clock-status"
          ~value:(reactive status model_source) []
      ])

let bridge = Lui_native_bridge.create "Clock qualification"

let initialize platform_code host_code =
  let backend = Lui_native_bridge.backend bridge
    (Lui_native_bridge.profile platform_code host_code) in
  let app = Lui_app.create backend initial update view in
  Lui_native_bridge.boot bridge app

let () =
  Callback.register "lui_ocaml_init" initialize;
  Lui_native_bridge.register ~register_named:Callback.register "lui_ocaml" bridge
