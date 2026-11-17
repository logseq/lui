(* Built-in apps a JSON scenario can mount with {"app": "name"}. Each
   app is boxed into a record of closures so scenarios of different
   model/action types share one registry. *)

open Lui_elements

type boxed = {
  start : unit -> bool;
  flush : unit -> bool;
  dispatch : Lui_protocol.event -> bool;
  dispose : unit -> bool;
}

let boxed app =
  { start = (fun () -> Lui_app.start app)
  ; flush = (fun () -> Lui_app.flush app)
  ; dispatch = (fun e -> Lui_app.dispatch_event app e)
  ; dispose = (fun () -> Lui_app.dispose app) }

(* ---------- "menu": the input-suite menu app ----------

   Mirrors the textarea + menu-button + context-menu app the hand
   written input tests drive, plus a text node mirroring [picked] so a
   scenario can assert the pick result through the store. *)
module Menu_app = struct
  type model = { area : string; menu : string list; picked : string }

  type action =
    | Area of string
    | Open
    | Pick of string

  let init = { area = ""; menu = []; picked = "" }

  let update m = function
    | Area s -> { m with area = s }
    | Open -> { m with menu = [ "copy"; "paste" ] }
    | Pick s -> { m with picked = s; menu = [] }

  let view _ctx ms send : Lui_elements.t =
    column ~padding:8
      [ textarea ~width:200 ~height:40
          ~text_signal:(reactive (fun m -> m.area) ms)
          ~on_context_menu:(press send Open)
          ~on_input:(on_input send (fun s -> Area s)) []
      ; button ~text:"menu" ~on_press:(press send Open)
          ~on_context_menu:(press send Open) []
      ; text ~value:(reactive (fun m -> "picked:" ^ m.picked) ms) []
      ; context_menu
          [ keyed ~source:(map (fun m -> m.menu) ms) ~key:(fun s -> s)
              ~cmp:String.compare
              ~mount:(fun s ->
                let item = sample s in
                menu_item ~text_signal:(reactive (fun v -> v) s)
                  ~on_press:(press send (Pick item)) []) ] ]
end

(* [make name backend] returns a constructor for the boxed app. *)
let make name (backend : Lui_protocol.backend) : (unit -> boxed) option =
  match name with
  | "e2e" ->
    Some
      (fun () ->
        boxed
          (Lui_app.create backend Lui_e2e.E2e_app.initial
             Lui_e2e.E2e_app.update Lui_e2e.E2e_app.view))
  | "menu" ->
    Some
      (fun () ->
        boxed
          (Lui_app.create backend Menu_app.init Menu_app.update
             Menu_app.view))
  | _ -> None
