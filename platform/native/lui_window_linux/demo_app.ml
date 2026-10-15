(* Demo application for the window host: a todo list with a text
   field, an add button and a keyed list of items — enough to
   exercise TextChanged/Submit/Press/DoublePress/pointer events and
   focus handling end to end — plus a row of desktop-shell buttons
   (notification, clipboard, launcher badge) that hit the Linux shell
   layer. Modeled on the headless e2e app. *)

open Lui_elements

type model = { items : string list; draft : string }

type action =
  | Draft of string
  | Add
  | Remove of string
  | Promote of string

let initial =
  { items =
      [ "SDL events -> dispatch_event";
        "hit test by layout rect";
        "glyphs into the scene atlas";
        "present the rendered frame" ];
    draft = "" }

let update model action =
  match action with
  | Draft draft -> { model with draft }
  | Add ->
    let draft = String.trim model.draft in
    if draft = "" then model
    else { items = model.items @ [ draft ]; draft = "" }
  | Remove it ->
    { model with items = List.filter (fun s -> s <> it) model.items }
  | Promote it ->
    { model with items = it :: List.filter (fun s -> s <> it) model.items }

(* Shell side effects: the Linux shell layer reports (false, reason)
   or no-ops when the session has no bus/display — these calls are
   safe under the dummy video driver and with no D-Bus. *)
let shell_notify () =
  ignore
    (Lui_shell_linux.notify ~id:"lui-window-linux-demo"
       ~title:"lui_window_linux" ~body:"notification from the demo app"
       ())

let shell_copy text = ignore (Lui_shell_linux.clipboard_write text)

let shell_badge items =
  Lui_shell_linux.set_dock_badge
    (Some (string_of_int (List.length items)))

let item_row send item_s =
  let item = sample item_s in
  row ~gap:8 ~style_class:"item-row"
    [ list_item ~text:(reactive (fun v -> v) item_s)
        ~foreground:"#e4e6ee"
        ~padding_horizontal:8 ~corner_radius:6
        ~on_double_press:(press send (Promote item))
        ~on_pointer_down:(fun _event -> ())
        ~on_pointer_up:(fun _event -> ())
        ~on_pointer_enter:(fun _event -> ())
        ~on_pointer_leave:(fun _event -> ())
        ~on_context_menu:(fun _event -> ())
        [];
      button ~text:"x"
        ~background:"#2c2e3e" ~foreground:"#989eb2"
        ~corner_radius:6 ~padding_horizontal:8
        ~on_press:(press send (Remove item)) [] ]

let view _ctx model_s send : t =
  column ~gap:10 ~padding:16 ~background:"#161720"
    [ heading ~value:"lui_window_linux" ~font_size:"22"
        ~foreground:"#e4e6ee" [];
      text ~value:"SDL window + Lui_host, end to end on Linux"
        ~foreground:"#989eb2" ~font_size:"13" [];
      row ~gap:8
        [ text_field
            ~text:(reactive (fun m -> m.draft) model_s)
            ~placeholder:"new item" ~label:"New item" ~autofocus:true
            ~width:240
            ~background:"#282a3a" ~foreground:"#e4e6ee"
            ~border_color:"#383b4c" ~border_width:1 ~corner_radius:6
            ~padding_horizontal:8
            ~on_input:(on_input send (fun s -> Draft s))
            ~on_submit:(press send Add) [];
          button ~text:"add" ~background:"#4c74f6" ~foreground:"#ffffff"
            ~corner_radius:6 ~padding_horizontal:14
            ~on_press:(press send Add) [] ];
      row ~gap:8
        [ button ~text:"notify" ~background:"#2c2e3e"
            ~foreground:"#e4e6ee" ~corner_radius:6 ~padding_horizontal:10
            ~on_press:(fun _event -> shell_notify ()) [];
          button ~text:"copy" ~background:"#2c2e3e"
            ~foreground:"#e4e6ee" ~corner_radius:6 ~padding_horizontal:10
            ~on_press:(fun _event ->
              shell_copy (sample model_s).draft) [];
          button ~text:"badge" ~background:"#2c2e3e"
            ~foreground:"#e4e6ee" ~corner_radius:6 ~padding_horizontal:10
            ~on_press:(fun _event ->
              shell_badge (sample model_s).items) [] ];
      divider ~background:"#383b4c" [];
      keyed ~source:(map (fun m -> m.items) model_s) ~key:(fun s -> s)
        ~cmp:String.compare ~mount:(item_row send) ]

let create backend = Lui_app.create backend initial update view
