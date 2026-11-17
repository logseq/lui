(* The updater window as LUI nodes — the self-drawn UI the demo app's
   widget/patch idiom describes: a [model] reducer-owned by [Lui_app],
   [view] building element trees per {!Session.phase}, events
   dispatching {!Session.action}s through [send].

   Every text comes out of [Strings] by key; every state has its own
   section so the tree's shape tracks the machine — header, body,
   buttons — matching the window-config table {!window_spec}. *)

open Lui_elements

module S = Session
module T = Strings

(* ---- palette: dark, matching the demo app's ------------------------- *)

let bg = "#161720"
and card = "#1b1c28"
and field_border = "#383b4c"
and fg = "#e4e6ee"
and dim = "#989eb2"
and faint = "#5f6478"
and accent = "#4c74f6"
and ok = "#3ecf8e"
and bad = "#ef4444"

(* ---- window spec ----------------------------------------------------- *)

(** The window-config spec: what the host sizes and permits per state.
    Status views are compact; the offer carrying release notes gets the
    larger "release" window — the reference dialog's two sizes. Closing
    mid-transfer cancels it ([aborts_on_close]); a quiescent close ends
    the session. *)
type window_spec = {
  width : int;
  height : int;
  resizable : bool;
  closable : bool;
  aborts_on_close : bool;
}

let status_width = 480
and status_height = 148
and release_width = 620
and release_height = 440

let window_spec (m : S.model) : window_spec =
  let release =
    match m.phase with
    | S.Available o -> o.notes <> ""
    | _ -> false
  in
  {
    width = (if release then release_width else status_width);
    height = (if release then release_height else status_height);
    resizable = false;
    closable = true;
    aborts_on_close =
      (match m.phase with
       | S.Downloading _ | S.Verifying _ | S.Staged _ -> true
       | _ -> false);
  }

(* ---- small helpers ---------------------------------------------------- *)

let s m k = T.get_text m.S.text k
let fmt m k args = T.format m.S.text k args

let on_toggle send wrap (event : Lui_protocol.event) =
  match event with
  | Lui_protocol.ToggleChanged (_, b) -> ignore (send (wrap b))
  | _ -> ()

let caption v = text ~value:v ~foreground:faint ~font_size:"12" []

let primary_btn send label act =
  button ~text:label ~background:accent ~foreground:"#ffffff"
    ~corner_radius:6 ~padding_horizontal:12 ~on_press:(press send act) []

let ghost_btn send label act =
  button ~text:label ~background:"#2c2e3e" ~foreground:fg
    ~border_color:field_border ~border_width:1 ~corner_radius:6
    ~padding_horizontal:12 ~on_press:(press send act) []

let btn_row children =
  row ~gap:8 ~padding_horizontal:16 ~padding_vertical:10 ~main:`end_
    ~background:"#13141b" ~cross:`center children

(* The indeterminate-status body: spinner + line + optional button. *)
let status_body ~title ~detail children =
  column ~gap:10 ~padding:16
    ([ row ~gap:10 ~cross:`center
         [ spinner ~size:`sm [];
           text ~value:title ~foreground:fg ~font_size:"13" [] ] ]
    @ (match detail with
      | "" -> []
      | d -> [ caption d ])
    @ children)

(* ---- per-state sections ------------------------------------------------ *)

let checking_view m send =
  status_body ~title:(s m T.Checking) ~detail:""
    [ row ~main:`end_ [ ghost_btn send (s m T.Cancel) S.Cancel_download ] ]

let up_to_date_view m send =
  column ~gap:10 ~padding:16
    [ row ~gap:10 ~cross:`center
        [ icon ~name:`check_circle ~foreground:ok [];
          text ~value:(s m T.Up_to_date) ~foreground:fg ~font_size:"13" [] ];
      caption
        (fmt m T.Up_to_date_message
           [| m.S.app_name; m.S.current_version |]);
      row ~main:`end_ [ primary_btn send (s m T.Ok) S.Dismiss ] ]

let notes_scroll ~height notes =
  scroll ~height ~background:card ~corner_radius:8 ~padding:10
    ~orientation:`vertical
    [ column ~gap:4
        (String.split_on_char '\n' notes
        |> List.map (fun line ->
             text ~value:line ~foreground:dim ~font_size:"12" [])) ]

let available_view m model_s send (o : S.offer) =
  let title = fmt m T.Available [| m.S.app_name |] in
  let message =
    fmt m T.Available_message
      [| m.S.app_name; o.S.version; m.S.current_version |]
  in
  let has_notes = String.trim o.S.notes <> "" in
  column ~gap:10 ~padding:16 ~grow:1.
    ([ text ~value:title ~foreground:fg ~font_size:"14"
         ~font_weight:600 [];
       caption message ]
    @ (if has_notes then
         [ text ~value:(s m T.Release_notes) ~foreground:dim
             ~font_size:"12" ~font_weight:600 [];
           notes_scroll ~height:180 o.S.notes ]
       else [])
    @ [ checkbox ~text:(s m T.Automatic_downloads)
          ~checked:(reactive (fun m -> m.S.auto_downloads) model_s)
          ~on_toggle:(on_toggle send (fun b -> S.Set_auto_downloads b))
          ~foreground:dim [] ])

let downloading_view m _send (d : S.download) =
  let frac =
    if d.S.total > 0 then Float.of_int d.S.bytes_done
                         /. Float.of_int d.S.total
    else 0.
  in
  let progress_line =
    fmt m T.Progress
      [| T.megabytes m.S.text d.S.bytes_done;
         T.megabytes m.S.text d.S.total |]
  in
  column ~gap:10 ~padding:16
    [ text ~value:(s m T.Downloading) ~foreground:fg ~font_size:"13" [];
      row ~gap:10 ~cross:`center
        [ progress ~value:frac ~width:300 ~height:8 [];
          text
            ~value:(Printf.sprintf "%.0f%%" (frac *. 100.))
            ~foreground:dim ~font_size:"12" ~width:44 [] ];
      row ~gap:10 ~cross:`center
        [ caption progress_line;
          spacer ~grow:1. [];
          (match d.S.eta with
           | Some secs ->
             caption (T.time_remaining m.S.text secs)
           | None -> spacer []) ] ]

let verifying_view m =
  status_body ~title:(s m T.Verifying) ~detail:"" []

let staged_view m =
  status_body ~title:(s m T.Installing) ~detail:"" []

let ready_view m _send (r : S.ready) =
  column ~gap:10 ~padding:16 ~grow:1.
    [ row ~gap:10 ~cross:`center
        [ icon ~name:`check_circle ~foreground:ok [];
          text ~value:(s m T.Ready) ~foreground:fg ~font_size:"13" [] ];
      caption (fmt m T.Ready_message [| m.S.app_name; r.S.version |]) ]

let error_view m _send (e : S.error) =
  column ~gap:10 ~padding:16 ~grow:1.
    [ row ~gap:10 ~cross:`center
        [ icon ~name:`alert ~foreground:bad [];
          text ~value:(s m T.Error) ~foreground:fg ~font_size:"13" [] ];
      caption
        (s m
           (match e.S.kind with
            | S.Check_failed -> T.Check_error
            | _ -> T.Install_error));
      (if e.S.message = "" then spacer []
       else
         text ~value:e.S.message ~foreground:faint ~font_size:"11" []) ]

(* ---- the tree ---------------------------------------------------------- *)

(* The scrollable body, one shape per phase. *)
let body_of (m : S.model) model_s send : t =
  match m.S.phase with
  | S.Idle -> column ~gap:10 ~padding:16 [ caption "—" ]
  | S.Checking -> checking_view m send
  | S.Up_to_date -> up_to_date_view m send
  | S.Available o -> available_view m model_s send o
  | S.Downloading d -> downloading_view m send d
  | S.Verifying _ -> verifying_view m
  | S.Staged _ -> staged_view m
  | S.Ready_to_restart r -> ready_view m send r
  | S.Error e -> error_view m send e
  | S.Closed -> spacer ~height:status_height []

(* The bottom button bar per phase — default action last, like the
   reference dialog. *)
let button_row_of (m : S.model) send : t =
  match m.S.phase with
  | S.Available _ ->
    btn_row
      [ ghost_btn send (s m T.Skip) S.Skip_version;
        spacer ~grow:1. [];
        ghost_btn send (s m T.Remind_later) S.Remind_later;
        primary_btn send (s m T.Install) S.Install_now ]
  | S.Downloading _ ->
    btn_row [ ghost_btn send (s m T.Cancel) S.Cancel_download ]
  | S.Ready_to_restart _ ->
    btn_row
      [ ghost_btn send (s m T.Later) S.Dismiss;
        primary_btn send (s m T.Relaunch) S.Relaunch ]
  | S.Error e ->
    btn_row
      ([ ghost_btn send (s m T.Later) S.Dismiss ]
      @ (if e.S.retryable then [ primary_btn send (s m T.Retry) S.Retry ]
         else [ primary_btn send (s m T.Ok) S.Dismiss ]))
  | _ -> spacer ~height:0 []

let header model_s =
  row ~padding_horizontal:16 ~padding_vertical:10 ~gap:12
    ~background:"#13141b" ~cross:`center
    [ icon ~name:`download ~foreground:accent [];
      heading
        ~value:(reactive (fun m -> s m T.Title) model_s)
        ~font_size:"15" ~foreground:fg [];
      spacer ~grow:1. [];
      text
        ~value:
          (reactive
             (fun m ->
                match m.S.phase with
                | S.Available o -> o.S.version
                | S.Downloading d -> d.S.offer.S.version
                | S.Verifying o | S.Staged { S.offer = o; _ } ->
                  o.S.version
                | S.Ready_to_restart r -> r.S.version
                | _ -> "")
             model_s)
        ~foreground:faint ~font_size:"12" [] ]

let view _ctx model_s send : t =
  column ~grow:1. ~gap:0 ~background:bg
    [ header model_s;
      divider ~background:"#262743" [];
      reactive
        ~equal:(fun a b -> a.S.phase = b.S.phase)
        (fun m ->
           column ~grow:1. ~gap:0
             [ scroll ~grow:1. ~orientation:`vertical
                 [ body_of m model_s send ];
               divider ~background:"#262743" [];
               button_row_of m send ])
        model_s ]

let create backend model =
  Lui_app.create backend model S.update view
