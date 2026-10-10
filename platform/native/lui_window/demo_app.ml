(* Demo application for the window host, extended into a tabbed
   showcase exercising most LUI kinds end to end: text fields with IME,
   buttons in every interaction state, scrollable lists, tabs, popups /
   dialogs / menus / toasts, form controls and decoration showcases.
   Side effects only the driver can perform (shell notify, clipboard,
   a11y dump, FPS badge) travel through the model: [req_*] counters the
   driver polls each frame, plus the [Badge] action it sends. *)

open Lui_elements

type tab = Inputs | Controls | Lists | Overlays | Deco
type popup = P_dialog | P_popover | P_menu | P_ctx | P_sheet | P_toast

type model = {
  tab : tab;
  badge : string;         (* "renderer — N fps" line, set by the driver *)
  last_event : string;    (* status line: the last interesting action *)
  last_drop : string;     (* payload of the last completed drop, set by the driver *)
  (* Inputs *)
  name : string;
  secret : string;
  search : string;
  notes : string;
  combo : string;
  (* Controls *)
  bold : bool;
  italic : bool;
  subscribed : bool;
  wifi : bool;
  choice : string;
  volume : float;
  count : float;
  (* Lists *)
  items : string list;
  draft : string;
  (* Overlays *)
  dialog_open : bool;
  popover_open : bool;
  menu_open : bool;
  ctx_open : bool;
  sheet_open : bool;
  toast_open : bool;
  drawer_open : bool;
  (* Deco *)
  split_ratio : float;
  (* Driver side-effect requests (counters, polled per frame). *)
  req_notify : int;
  req_clipboard : int;
  req_a11y : int;
}

type action =
  | Tab of tab
  | Badge of string
  | Last_event of string
  | Dropped of string
  | Name of string
  | Secret of string
  | Search of string
  | Notes of string
  | Combo of string
  | Bold
  | Italic
  | Subscribed of bool
  | Wifi of bool
  | Choice of string
  | Volume of float
  | Count of float
  | Draft of string
  | Add
  | Remove of string
  | Promote of string
  | Open of popup
  | Close of popup
  | Drawer_flip of bool
  | Split of float
  | Req_notify
  | Req_clipboard
  | Req_a11y

let tab_name = function
  | Inputs -> "inputs" | Controls -> "controls" | Lists -> "lists"
  | Overlays -> "overlays" | Deco -> "deco"

let initial =
  { tab = Inputs;
    badge = "";
    last_event = "ready — click a tab";
    last_drop = "";
    name = ""; secret = ""; search = ""; notes = ""; combo = "";
    bold = false; italic = false; subscribed = true; wifi = true;
    choice = "alpha"; volume = 0.35; count = 2.;
    items =
      [ "SDL events -> dispatch_event";
        "hit test by layout rect";
        "scroll offsets shift children";
        "glyphs into the scene atlas";
        "push_clip around scroll views";
        "swap the framebuffer" ];
    draft = "";
    dialog_open = false; popover_open = false; menu_open = false;
    ctx_open = false; sheet_open = false; toast_open = false;
    drawer_open = false;
    split_ratio = 0.4;
    req_notify = 0; req_clipboard = 0; req_a11y = 0 }

let open_ p m =
  match p with
  | P_dialog -> { m with dialog_open = true }
  | P_popover -> { m with popover_open = true }
  | P_menu -> { m with menu_open = true }
  | P_ctx -> { m with ctx_open = true }
  | P_sheet -> { m with sheet_open = true }
  | P_toast -> { m with toast_open = true }

let close p m =
  match p with
  | P_dialog -> { m with dialog_open = false }
  | P_popover -> { m with popover_open = false }
  | P_menu -> { m with menu_open = false }
  | P_ctx -> { m with ctx_open = false }
  | P_sheet -> { m with sheet_open = false }
  | P_toast -> { m with toast_open = false }

let update model action =
  match action with
  | Tab t -> { model with tab = t; last_event = "tab: " ^ tab_name t }
  | Badge s -> { model with badge = s }
  | Last_event s -> { model with last_event = s }
  | Dropped s ->
    { model with last_drop = s; last_event = "drop: " ^ s }
  | Name s -> { model with name = s; last_event = "name changed" }
  | Secret s -> { model with secret = s; last_event = "secret changed" }
  | Search s -> { model with search = s; last_event = "search changed" }
  | Notes s -> { model with notes = s; last_event = "notes changed" }
  | Combo s -> { model with combo = s; last_event = "combo changed" }
  | Bold -> { model with bold = not model.bold;
              last_event = "bold toggled" }
  | Italic -> { model with italic = not model.italic;
                last_event = "italic toggled" }
  | Subscribed b -> { model with subscribed = b;
                      last_event = "checkbox toggled" }
  | Wifi b -> { model with wifi = b; last_event = "switch toggled" }
  | Choice s -> { model with choice = s; last_event = "radio: " ^ s }
  | Volume v ->
    { model with volume = v;
      last_event = Printf.sprintf "volume %.0f%%" (v *. 100.) }
  | Count v ->
    { model with count = v;
      last_event = Printf.sprintf "count %.1f" v }
  | Draft draft -> { model with draft }
  | Add ->
    let draft = String.trim model.draft in
    if draft = "" then model
    else { model with items = model.items @ [ draft ]; draft = "";
           last_event = "added: " ^ draft }
  | Remove it ->
    { model with items = List.filter (fun s -> s <> it) model.items;
      last_event = "removed: " ^ it }
  | Promote it ->
    { model with items = it :: List.filter (fun s -> s <> it) model.items;
      last_event = "promoted: " ^ it }
  | Open p -> open_ p model
  | Close p -> close p model
  | Drawer_flip b -> { model with drawer_open = b;
                       last_event = "drawer toggled" }
  | Split v -> { model with split_ratio = v }
  | Req_notify ->
    { model with req_notify = model.req_notify + 1;
      last_event = "notify requested" }
  | Req_clipboard ->
    { model with req_clipboard = model.req_clipboard + 1;
      last_event = "clipboard copy requested" }
  | Req_a11y ->
    { model with req_a11y = model.req_a11y + 1;
      last_event = "a11y dump requested" }

(* ---- event decoders ---------------------------------------------- *)

(* [ValueChanged] carries the float for sliders/steppers/split views. *)
let on_value send wrap (event : Lui_protocol.event) =
  match event with
  | Lui_protocol.ValueChanged (_, v) -> ignore (send (wrap v))
  | _ -> ()

(* [ToggleChanged] carries the new bool for checkbox/switch/toggle. *)
let on_toggle send wrap (event : Lui_protocol.event) =
  match event with
  | Lui_protocol.ToggleChanged (_, b) -> ignore (send (wrap b))
  | _ -> ()

(* Fire-and-forget handler for events whose payload the action does
   not need (press, submit, dismiss). *)
let press send act (_ : Lui_protocol.event) = ignore (send act)

(* ---- small view helpers ------------------------------------------ *)

let caption v = text ~value:v ~foreground:"#5f6478" ~font_size:"12" []

(* A [dynamic] element runs its mount hook on the parent node — here it
   injects props the element vocabulary does not expose (shadow spec,
   dashed border style) without forking the elements. *)
let set_shadow spec : t =
  dynamic (fun ctx parent -> Lui_ui.shadow ctx parent spec)

(* data-user-select is the legal data-* channel for opting a text
   node into the host's selection model when the vocabulary lacks a
   user-select param — drag-select/double-click/click-outside and
   Cmd+C all work on it. *)
let sel_text_attrs = [ ("data-user-select", "text") ]

let ghost_btn send label act =
  button ~text:label ~background:"#2c2e3e" ~foreground:"#e4e6ee"
    ~border_color:"#383b4c" ~border_width:1 ~corner_radius:6
    ~padding_horizontal:12 ~on_press:(press send act) []

(* ---- sections ----------------------------------------------------- *)

let field_bg = "#1f2030" and field_fg = "#e4e6ee"
and field_border = "#383b4c"

let section_inputs model_s send =
  column ~gap:14 ~padding:16
    [ caption
        "text fields — click or Tab to focus, type to input, Enter \
         submits; IME composition is live in every field";
      row ~gap:14
        [ column ~grow:1. ~gap:10
            [ text_field
                ~text:(reactive (fun m -> m.name) model_s)
                ~placeholder:"your name" ~label:"Name" ~autofocus:true
                ~background:field_bg
                ~foreground:field_fg ~border_color:field_border
                ~border_width:1 ~corner_radius:6
                ~on_input:(on_input send (fun s -> Name s))
                ~on_submit:(press send (Last_event "name submitted"))
                [];
              secure_field
                ~text:(reactive (fun m -> m.secret) model_s)
                ~placeholder:"password" ~label:"Secret"
                ~background:field_bg
                ~foreground:field_fg ~border_color:field_border
                ~border_width:1 ~corner_radius:6
                ~on_input:(on_input send (fun s -> Secret s))
                ~on_submit:(press send (Last_event "secret submitted"))
                [];
              search_field
                ~text:(reactive (fun m -> m.search) model_s)
                ~placeholder:"search…" ~label:"Search"
                ~background:field_bg
                ~foreground:field_fg ~border_color:field_border
                ~border_width:1 ~corner_radius:6
                ~on_input:(on_input send (fun s -> Search s))
                ~on_submit:(press send (Last_event "search submitted"))
                [];
              row ~gap:10
                [ combobox
                    ~text:(reactive (fun m -> m.combo) model_s)
                    ~placeholder:"combobox" ~width:170
                    ~background:field_bg ~foreground:field_fg
                    ~border_color:field_border ~border_width:1
                    ~corner_radius:6
                    ~on_input:(on_input send (fun s -> Combo s))
                    ~on_submit:(press send (Last_event "combo submitted"))
                    [];
                  select ~text:"pick an option" ~width:170
                    ~background:field_bg ~foreground:field_fg
                    ~border_color:field_border ~border_width:1
                    ~corner_radius:6
                    ~on_press:(press send (Open P_menu)) [] ] ] ];
      textarea ~text:(reactive (fun m -> m.notes) model_s)
        ~placeholder:"multi-line notes — IME composition works here too"
        ~label:"Notes" ~height:96 ~background:field_bg
        ~foreground:field_fg ~border_color:field_border ~border_width:1
        ~corner_radius:6
        ~on_input:(on_input send (fun s -> Notes s)) [];
      text
        ~value:
          "the IME candidate window tracks the caret — the host reports \
           its rect to SDL every frame"
        ~foreground:"#5f6478" ~font_size:"11" [];
      column ~gap:6
        [ text
            ~value:
              "this line is selectable — drag-select, \
               double-click a word, Cmd+C copies"
            ~foreground:"#8ab4ff" ~font_size:"12"
            ~data_attrs:sel_text_attrs [];
          text
            ~value:
              "fields: Cmd/Ctrl+A select-all, X/C/V cut-copy-paste, \
               Cmd+Z undo, shift+arrows extend, triple-click selects \
               a line"
            ~foreground:"#5f6478" ~font_size:"11" [] ];
      caption
        "OS drops — drag a file or text snippet onto the well; drags \
         of list rows land here too";
      row ~gap:8 ~cross:`center
        [ text
            ~value:
              (reactive
                 (fun m ->
                    if m.last_drop = "" then
                      "drop well — drop a file or text onto me"
                    else "dropped " ^ m.last_drop)
                 model_s)
            ~foreground:"#8ab4ff" ~font_size:"12" ~padding:8
            ~corner_radius:6
            ~data_attrs:
              [ ("data-drop-target", "true");
                ("data-drop-accept", "file:,text:,row-") ] [] ] ]

let section_controls model_s send =
  column ~gap:14 ~padding:16
    [ caption "buttons — hover, press, long-press";
      row ~gap:8
        [ button ~text:"primary" ~background:"#4c74f6"
            ~foreground:"#ffffff" ~corner_radius:6 ~padding_horizontal:12
            ~on_press:(press send (Last_event "primary pressed")) [];
          button ~text:"secondary" ~background:"#2c2e3e"
            ~foreground:"#e4e6ee" ~border_color:field_border
            ~border_width:1 ~corner_radius:6 ~padding_horizontal:12
            ~on_press:(press send (Last_event "secondary pressed")) [];
          button ~text:"danger" ~background:"#8f2d3d"
            ~foreground:"#ffffff" ~corner_radius:6 ~padding_horizontal:12
            ~on_press:(press send (Last_event "danger pressed")) [];
          button ~text:"disabled" ~disabled:true ~background:"#24252f"
            ~foreground:"#565b70" ~corner_radius:6 ~padding_horizontal:12
            ~on_press:(press send (Last_event "unreachable")) [] ];
      caption "toggles";
      row ~gap:12 ~cross:`center
        [ toggle_button ~text:"bold"
            ~checked:(reactive (fun m -> m.bold) model_s)
            ~on_toggle:(press send Bold) ~background:"#2c2e3e"
            ~foreground:"#e4e6ee" ~corner_radius:6 ~padding_horizontal:12
            [];
          toggle_button ~text:"italic"
            ~checked:(reactive (fun m -> m.italic) model_s)
            ~on_toggle:(press send Italic) ~background:"#2c2e3e"
            ~foreground:"#e4e6ee" ~corner_radius:6 ~padding_horizontal:12
            [];
          checkbox ~text:"notify me"
            ~checked:(reactive (fun m -> m.subscribed) model_s)
            ~on_toggle:(on_toggle send (fun b -> Subscribed b))
            ~foreground:"#e4e6ee" [];
          switch_ ~text:"wifi"
            ~checked:(reactive (fun m -> m.wifi) model_s)
            ~on_toggle:(on_toggle send (fun b -> Wifi b)) [] ];
      caption "radio group";
      (* [radio] yields the typed [radio_el], so signal props cannot be
         wired on it — the group itself is remounted on [choice] change
         via a children-position [reactive] instead. *)
      reactive
        ~equal:(fun a b -> a.choice = b.choice)
        (fun m ->
          radio_group ~label:"pick one"
            [ radio ~text:"alpha" ~checked:(m.choice = "alpha")
                ~on_change:(press send (Choice "alpha"))
                ~foreground:"#e4e6ee" [];
              radio ~text:"beta" ~checked:(m.choice = "beta")
                ~on_change:(press send (Choice "beta")) ~foreground:"#e4e6ee"
                [];
              radio ~text:"gamma" ~checked:(m.choice = "gamma")
                ~on_change:(press send (Choice "gamma"))
                ~foreground:"#e4e6ee" [] ])
        model_s;
      caption "values — slider, progress, stepper";
      row ~gap:12 ~cross:`center
        [ slider ~value:(reactive (fun m -> m.volume) model_s) ~width:200
            ~on_change:(on_value send (fun v -> Volume v)) [];
          progress ~value:(reactive (fun m -> m.volume) model_s)
            ~width:120 [];
          text
            ~value:
              (reactive
                 (fun m -> Printf.sprintf "%.0f%%" (m.volume *. 100.))
                 model_s)
            ~foreground:"#989eb2" ~font_size:"12" [];
          number_stepper ~value:(reactive (fun m -> m.count) model_s)
            ~min:0. ~max:10. ~step:0.5 ~label:"stepper"
            ~on_value_changed:(on_value send (fun v -> Count v)) [] ];
      row ~gap:10 ~cross:`center
        [ spinner ~size:`sm [];
          icon ~name:`check ~foreground:"#3ecf8e" [];
          icon ~name:`volume ~foreground:"#989eb2" [];
          icon ~name:`settings ~foreground:"#989eb2" [];
          kbd ~value:"⌘Q" [];
          caption "spinner · icons · kbd chip" ] ]

let item_row send item_s =
  let item = sample item_s in
  row ~gap:8 ~style_class:"item-row"
    [ list_item ~text:(reactive (fun v -> v) item_s) ~foreground:"#e4e6ee"
        ~padding_horizontal:8 ~corner_radius:6
        ~on_double_press:(press send (Promote item))
        ~on_context_menu:(press send (Open P_ctx)) [];
      button ~text:"x" ~background:"#2c2e3e" ~foreground:"#989eb2"
        ~corner_radius:6 ~padding_horizontal:8
        ~on_press:(press send (Remove item)) [] ]

let section_lists model_s send =
  row ~grow:1. ~gap:16 ~padding:16
    [ column ~grow:1. ~gap:10
        [ caption
            "keyed todo — Enter/add appends, double-click promotes, \
             right-click opens a menu, wheel scrolls";
          row ~gap:8
            [ text_field
                ~text:(reactive (fun m -> m.draft) model_s)
                ~placeholder:"new item" ~label:"New item" ~width:200
                ~background:field_bg ~foreground:field_fg
                ~border_color:field_border ~border_width:1
                ~corner_radius:6
                ~on_input:(on_input send (fun s -> Draft s))
                ~on_submit:(press send Add) [];
              button ~text:"add" ~background:"#4c74f6"
                ~foreground:"#ffffff" ~corner_radius:6
                ~padding_horizontal:14 ~on_press:(press send Add) [] ];
          list ~height:200 ~background:"#1b1c28" ~corner_radius:8
            ~padding:6 ~gap:6
            [ keyed ~source:(map (fun m -> m.items) model_s)
                ~key:(fun s -> s) ~cmp:String.compare
                ~mount:(item_row send) ] ];
      column ~grow:1. ~gap:10
        [ caption
            "fixed-height list — opens scrolled to row 08 \
             (scroll-target), wheel/typeahead/arrows move, \
             row 12 drags into the drop well";
          list ~height:130 ~background:"#1b1c28" ~corner_radius:8
            ~padding:6 ~gap:4 ~track_visible_range:true
            ~scroll_target:"row-08" ~scroll_token:1
            ~scroll_anchor:`center
            (List.init 16 (fun i ->
               let n = i + 1 in
               list_item
                 ~text:(Printf.sprintf "row %02d — hover me" n)
                 ~key:(Printf.sprintf "row-%02d" n)
                 ~foreground:"#e4e6ee" ~padding_horizontal:8
                 ~corner_radius:4
                 ~data_attrs:
                   (if n = 12 then
                      [ ("draggable", "true");
                        ("data-drag-payload", "row-12") ]
                    else [])
                 ~on_press:
                   (press send
                      (Last_event
                         (Printf.sprintf "row %d pressed" n)))
                 []));
          row ~gap:8 ~cross:`center
            ~on_appear:
              (press send (Last_event "lists section appeared"))
            [ text
                ~value:"drop well (data-drop-target)"
                ~foreground:"#8ab4ff" ~font_size:"12"
                ~padding:8 ~corner_radius:6
                ~data_attrs:
                  [ ("data-drop-target", "true");
                    ("data-drop-accept", "row-") ] [] ];
          caption
            "horizontal strip — wheel-x or shift+wheel scrolls it";
          scroll ~height:64 ~background:"#1b1c28" ~corner_radius:8
            ~padding:6
            [ row ~gap:8
                (List.init 10 (fun i ->
                   box ~width:96 ~height:44 ~background:"#262743"
                     ~corner_radius:6 ~padding:8
                     [ text
                         ~value:
                           (Printf.sprintf "cell %02d" (i + 1))
                         ~foreground:"#e4e6ee" ~font_size:"12" [] ])) ];
          caption
            "multi-line selection — drag selects across these \
             sibling lines, Cmd+C copies in document order";
          column ~gap:2
            [ text ~value:"alpha line — drag down through the siblings"
                ~foreground:"#8ab4ff" ~font_size:"12"
                ~data_attrs:sel_text_attrs [];
              text
                ~value:"beta line — contiguous siblings join the selection"
                ~foreground:"#8ab4ff" ~font_size:"12"
                ~data_attrs:sel_text_attrs [];
              text
                ~value:"gamma line — the copy lands in document order"
                ~foreground:"#8ab4ff" ~font_size:"12"
                ~data_attrs:sel_text_attrs [] ];
          caption "table";
          table ~background:"#1b1c28" ~corner_radius:8
            [ table_row
                [ table_cell ~text:"event" ~size:`sm [];
                  table_cell ~text:"kind gate" ~size:`sm [];
                  table_cell ~text:"result" ~size:`sm [] ];
              table_row
                [ table_cell ~text:"Press" [];
                  table_cell ~text:"PressEnabled" [];
                  table_cell ~text:"dispatch" [] ];
              table_row
                [ table_cell ~text:"TextChanged" [];
                  table_cell ~text:"input-capable" [];
                  table_cell ~text:"dispatch" [] ];
              table_row
                [ table_cell ~text:"ToggleChanged" [];
                  table_cell ~text:"ToggleEnabled" [];
                  table_cell ~text:"dispatch" [] ] ];
          breadcrumb ~label:"trail"
            [ text ~value:"sections" ~foreground:"#989eb2"
                ~font_size:"12" [];
              text ~value:"lists" ~foreground:"#e4e6ee" ~font_size:"12"
                [] ];
          timeline ~label:"pipeline"
            [ timeline_item ~title:"patch applied"
                ~description:"store mirrors it" ~meta:"t0" ~connector:true
                [];
              timeline_item ~title:"layout synced"
                ~description:"flex positions" ~meta:"t1" ~connector:true
                [];
              timeline_item ~title:"frame painted"
                ~description:"scene ops out" ~meta:"t2" [] ] ] ]

let section_overlays model_s send =
  column ~gap:14 ~padding:16
    [ caption
        "popups and overlays — the dismiss affordance or Esc closes \
         them";
      row ~gap:8
        [ ghost_btn send "dialog" (Open P_dialog);
          ghost_btn send "popover" (Open P_popover);
          ghost_btn send "dropdown" (Open P_menu);
          ghost_btn send "sheet" (Open P_sheet);
          ghost_btn send "toast" (Open P_toast) ];
      box ~padding:4 ~background:"#1b1c28" ~corner_radius:8
        ~border_color:field_border ~border_width:1
        [ list_item ~text:"right-click me — context menu"
            ~foreground:"#989eb2" ~padding_horizontal:10 ~corner_radius:6
            ~on_context_menu:(press send (Open P_ctx)) [] ];
      caption "drawer";
      drawer ~selected:(reactive (fun m -> m.drawer_open) model_s)
        ~label:"drawer" ~on_toggle:(on_toggle send (fun b -> Drawer_flip b))
        (box ~padding:10 ~background:"#22233a" ~corner_radius:8
           [ text ~value:"drawer pane" ~foreground:"#989eb2"
               ~font_size:"12" [] ])
        (box ~padding:10 ~background:"#1b1c28" ~corner_radius:8
           [ text ~value:"content pane — toggle the drawer"
               ~foreground:"#989eb2" ~font_size:"12" [] ]);
      caption "shell integration — the tray icon sits in the menu bar";
      row ~gap:8
        [ ghost_btn send "notify" Req_notify;
          ghost_btn send "copy stats" Req_clipboard;
          ghost_btn send "dump a11y" Req_a11y ];
      caption "toolbar with a menu";
      toolbar ~label:"demo" ~toolbar_gap:8
        [ text ~value:"app bar" ~foreground:"#4c74f6" ~font_size:"11" [];
          menu ~text:"File" ~label:"file menu" ~foreground:"#e4e6ee"
            [ menu_item ~text:"new item" ~foreground:"#e4e6ee"
                ~on_press:(press send Add) [];
              menu_item ~text:"notify" ~foreground:"#e4e6ee"
                ~on_press:(press send Req_notify) [];
              menu_item ~text:"tooltip item" ~foreground:"#e4e6ee"
                ~tooltip:"menu items can carry tooltips"
                ~on_press:(press send (Last_event "tooltip item")) [] ] ] ]

let deco_tile children = stack children

let section_deco model_s send =
  column ~gap:14 ~padding:16
    [ caption "gradients, shadows, translucency, borders — scene ops";
      row ~gap:12
        [ deco_tile
            [ box ~width:110 ~height:56 ~corner_radius:8
                ~background:"linear-gradient(135deg,#4c74f6,#22d3ee)"
                ~padding:8
                [ text ~value:"gradient" ~foreground:"#ffffff"
                    ~font_size:"11" [] ] ];
          deco_tile
            [ box ~width:110 ~height:56 ~corner_radius:8
                ~background:"linear-gradient(180deg,#0f766e,#34d399)"
                ~padding:8
                [ text ~value:"gradient b" ~foreground:"#ffffff"
                    ~font_size:"11" [] ] ];
          deco_tile
            [ box ~width:110 ~height:56 ~corner_radius:8
                ~background:"#262743" ~padding:8
                [ set_shadow "0 14px 30px rgba(0,0,0,0.55)";
                  text ~value:"shadow" ~foreground:"#e4e6ee"
                    ~font_size:"11" [] ] ];
          deco_tile
            [ stack
                [ box ~width:110 ~height:56 ~corner_radius:8
                    ~background:"#1b1c28" ~border_color:"#4c74f6"
                    ~border_width:2 ~padding:8 [];
                  box ~width:100 ~height:46 ~corner_radius:6
                    ~border_color:"#4c74f680" ~border_width:1
                    ~padding:8
                    [ text ~value:"ring" ~foreground:"#989eb2"
                        ~font_size:"11" [] ] ] ];
          deco_tile
            [ box ~width:110 ~height:56 ~corner_radius:8
                ~background:"#1b1c28"
                ~border_color:"#ef4444 #22c55e #3b82f6 #eab308"
                ~border_width:3 ~padding:8
                [ text ~value:"per-edge" ~foreground:"#989eb2"
                    ~font_size:"11" [] ] ] ];
      caption "glass (translucent pane over a gradient) · opacity · stack";
      row ~gap:12
        [ stack
            [ box ~width:150 ~height:64 ~corner_radius:10
                ~background:"linear-gradient(135deg,#8b5cf6,#f43f5e)" [];
              box ~width:110 ~height:44 ~corner_radius:10
                ~background:"#ffffff29" ~border_color:"#ffffff40"
                ~border_width:1 ~padding:8
                [ text ~value:"glass" ~foreground:"#ffffff"
                    ~font_size:"11" [] ] ];
          box ~width:110 ~height:56 ~corner_radius:8 ~opacity:0.45
            ~background:"#4c74f6" ~padding:8
            [ text ~value:"opacity .45" ~foreground:"#ffffff"
                ~font_size:"11" [] ];
          stack
            [ box ~width:110 ~height:56 ~corner_radius:8
                ~background:"#4c74f6" [];
              box ~width:64 ~height:30 ~corner_radius:6
                ~background:"#00000066" ~padding:6
                [ text ~value:"stack" ~foreground:"#ffffff"
                    ~font_size:"11" [] ] ] ];
      caption "drag-resize — the resizable frame and the split divider";
      resizable ~resizable_width:240 ~label:"resize me"
        [ split ~value:(reactive (fun m -> m.split_ratio) model_s)
            ~label:"split" ~on_resize:(on_value send (fun v -> Split v))
            (box ~padding:10 ~background:"#262743" ~corner_radius:6
               [ text ~value:"left" ~foreground:"#989eb2" ~font_size:"12"
                   [] ])
            (box ~padding:10 ~background:"#1b1c28" ~corner_radius:6
               [ text ~value:"right" ~foreground:"#989eb2" ~font_size:"12"
                   [] ]) ];
      caption "view that fits";
      view_that_fits ~orientation:`horizontal
        [ box ~padding:8 ~background:"#262743" ~corner_radius:6
            [ text ~value:"either pane fits" ~foreground:"#989eb2"
                ~font_size:"12" [] ] ] ]

let section_of tab model_s send =
  match tab with
  | Inputs -> section_inputs model_s send
  | Controls -> section_controls model_s send
  | Lists -> section_lists model_s send
  | Overlays -> section_overlays model_s send
  | Deco -> section_deco model_s send

(* ---- header / tabs / footer / popups ------------------------------ *)

let header model_s =
  row ~padding_horizontal:16 ~padding_vertical:10 ~gap:12
    ~background:"#13141b" ~cross:`center
    [ heading ~value:"lui_window" ~font_size:"18" ~foreground:"#e4e6ee"
        [];
      text ~value:"native backend demo" ~foreground:"#5f6478"
        ~font_size:"12" [];
      spacer ~grow:1. [];
      text ~value:(reactive (fun m -> m.badge) model_s)
        ~foreground:"#3ecf8e" ~font_size:"12" [] ]

let tabstrip model_s send =
  let tab_el m t title ic =
    bottom_tab ~title ~icon:ic ~selected:(m.tab = t)
      ~on_press:(press send (Tab t)) []
  in
  (* [bottom_tab] yields the typed [bottom_tab_el]; remount the strip on
     [tab] change rather than wiring signals on the children. *)
  reactive
    ~equal:(fun a b -> a.tab = b.tab)
    (fun m ->
      bottom_tabs ~label:"sections"
        [ tab_el m Inputs "inputs" `edit;
          tab_el m Controls "controls" `settings;
          tab_el m Lists "lists" `folder;
          tab_el m Overlays "overlays" `external_link;
          tab_el m Deco "deco" `sun ])
    model_s

let footer model_s =
  row ~padding_horizontal:16 ~padding_vertical:8 ~gap:16
    ~background:"#13141b" ~cross:`center
    [ text ~value:(reactive (fun m -> m.last_event) model_s)
        ~foreground:"#3ecf8e" ~font_size:"12" [];
      spacer ~grow:1. [];
      text
        ~value:
          "Tab focus · Enter submit · Esc blur/quit · dbl-click promotes \
           · wheel scrolls · drag edge resizes"
        ~foreground:"#5f6478" ~font_size:"11" [] ]

let popups model_s send =
  let open_ ~test child = if_ ~test:(reactive test model_s) child in
  [ open_ ~test:(fun m -> m.dialog_open)
      (* modal surfaces (dialog/drawer/sheet) own their chrome —
         background/border/radius props are rejected by the schema *)
      (dialog ~text:"native dialog"
         ~description:"a retained-mode dialog painted by the scene"
         ~padding:16 ~width:320
         ~on_dismiss:(press send (Close P_dialog))
         [ text
             ~value:"every op in this frame went through Lui_paint"
             ~foreground:"#989eb2" ~font_size:"12" [];
           row ~gap:8 ~main:`end_
             [ button ~text:"cancel" ~background:"#2c2e3e"
                 ~foreground:"#e4e6ee" ~corner_radius:6
                 ~on_press:(press send (Close P_dialog)) [];
               button ~text:"ok" ~background:"#4c74f6"
                 ~foreground:"#ffffff" ~corner_radius:6
                 ~on_press:(press send (Close P_dialog)) [] ] ]);
    open_ ~test:(fun m -> m.popover_open)
      (popover ~at:(160., 260.) ~anchor:`below ~background:"#262743"
         ~foreground:"#e4e6ee" ~border_color:"#4c74f6" ~border_width:1
         ~corner_radius:10 ~padding:12
         ~on_dismiss:(press send (Close P_popover))
         [ text ~value:"popover — anchored by the layout insets"
             ~foreground:"#e4e6ee" ~font_size:"12" [];
           ghost_btn send "close" (Close P_popover) ]);
    open_ ~test:(fun m -> m.menu_open)
      (dropdown_menu ~on_dismiss:(press send (Close P_menu))
         ~background:"#262743" ~border_color:"#383b4c" ~border_width:1
         ~corner_radius:8 ~padding:4
         [ menu_item ~text:"profile" ~icon:`settings
             ~foreground:"#e4e6ee"
             ~on_press:(press send (Close P_menu)) [];
           menu_item ~text:"notify" ~icon:`copy ~foreground:"#e4e6ee"
             ~on_press:(press send Req_notify) [];
           menu_item ~text:"close" ~foreground:"#989eb2"
             ~on_press:(press send (Close P_menu)) [] ]);
    open_ ~test:(fun m -> m.ctx_open)
      (context_menu ~background:"#262743" ~border_color:"#383b4c"
         ~border_width:1 ~corner_radius:8 ~padding:4
         [ menu_item ~text:"context: first" ~foreground:"#e4e6ee"
             ~on_press:(press send (Close P_ctx)) [];
           menu_item ~text:"context: second" ~foreground:"#e4e6ee"
             ~on_press:(press send (Close P_ctx)) [];
           menu_item ~text:"dismiss" ~foreground:"#989eb2"
             ~on_press:(press send (Close P_ctx)) [] ]);
    open_ ~test:(fun m -> m.sheet_open)
      (sheet ~detents:"medium" ~padding:16
         ~on_dismiss:(press send (Close P_sheet))
         [ text ~value:"sheet — drag detents live on the platform host"
             ~foreground:"#e4e6ee" ~font_size:"12" [];
           ghost_btn send "close" (Close P_sheet) ]);
    open_ ~test:(fun m -> m.toast_open)
      (toast ~duration:2500 ~label:"saved"
         ~on_dismiss:(press send (Close P_toast))
         [ text ~value:"toast — auto-dismisses" ~foreground:"#e4e6ee"
             ~font_size:"12" [] ]) ]

let view _ctx model_s send : t =
  column ~grow:1. ~gap:0 ~background:"#161720"
    ([ header model_s;
       tabstrip model_s send;
       divider ~background:"#262743" [];
       scroll ~grow:1. ~orientation:`vertical
         [ reactive ~equal:(fun a b -> a.tab = b.tab)
             (fun m -> section_of m.tab model_s send) model_s ];
       divider ~background:"#262743" [];
       footer model_s ]
    @ popups model_s send)

let create backend = Lui_app.create backend initial update view
