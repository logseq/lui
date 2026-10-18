open Lui_elements
open Model

type viewport =
  | Anchored
  | Anchored_list
  | Host_driven of host_viewport

and host_viewport = {
  container : [ `list | `virtual_list ];
  at_bottom : bool Signal.signal;
  scroll_to : key:string -> animated:bool -> unit;
}

type config = {
  render_item : item Signal.signal -> t option;
  render_attachment : attachment -> t;
  item_class : item -> string;
  item_data_attrs : item -> (string * string) list;
  item_actions : (item Signal.signal -> t) option;
  on_retry : (id -> unit) option;
  retry_label : string;
  on_load_full : (id -> unit) option;
  load_full_label : item -> string;
  content_width : int;
}

(* Per-mount states are created under the mount's ui_state_scope so they
   die with the row/transcript instead of leaking across remounts. *)
let pinned_slot = Signal.state_slot "lui-ai-pinned"
let request_slot = Signal.state_slot "lui-ai-scroll-request"
let at_top_slot = Signal.state_slot "lui-ai-at-top"
let think_open_slot = Signal.state_slot "lui-ai-think-open"
let tool_open_slot = Signal.state_slot "lui-ai-tool-open"
let group_open_slot = Signal.state_slot "lui-ai-group-open"

let scoped_state context slot init =
  Signal.state_at context.Lui_ui.ui_scheduler context.ui_state_scope slot
    init

let own context signal = Signal.own_signal context.Lui_ui.ui_scope signal

let own_sub context sub = ignore (Signal.own context.Lui_ui.ui_scope sub)

let tool_headline (call : tool_call) =
  call.title ^ " · " ^ tool_status_label call.status

let empty_node : t = row ~gap:0 []

(* {1 Item pieces} *)

let attachments_block cfg (item_s : item Signal.signal) : t =
  if_ ~test:(reactive (fun (i : item) -> i.attachments <> []) item_s)
    (reactive
       (fun (i : item) ->
          row ~gap:8 ~flex_wrap:`wrap
            (List.map cfg.render_attachment i.attachments))
       item_s)

let delivery_bits cfg (item_s : item Signal.signal) : t =
  reactive
    (fun (i : item) ->
       match i.delivery with
       | `sent -> empty_node
       | `pending ->
           row ~gap:6 ~cross:`center
             ~accessibility_identifier:"lui-ai-pending"
             [ icon ~name:`clock ~width:12 ~height:12
                 ~foreground:"muted-foreground" []
             ; text ~value:"Sending…" ~foreground:"muted-foreground"
                 ~style_class:"caption" [] ]
       | `uncertain ->
           row ~gap:6 ~cross:`center
             ~accessibility_identifier:"lui-ai-uncertain"
             (text ~value:"Delivery uncertain"
                ~foreground:"warning-foreground" ~style_class:"caption" []
              :: (match cfg.on_retry with
                  | Some on_retry ->
                      [ button ~text:cfg.retry_label ~variant:`outline
                          ~size:`sm ~label:cfg.retry_label
                          ~accessibility_identifier:"lui-ai-retry"
                          ~on_press:(fun _ -> on_retry i.id) [] ]
                  | None -> [])))
    item_s

let load_full_control cfg (item_s : item Signal.signal) : t =
  match cfg.on_load_full with
  | None -> empty_node
  | Some on_load_full ->
      if_
        ~test:(reactive (fun (i : item) -> i.truncated) item_s)
        (button ~variant:`ghost ~size:`sm
           ~text:(cfg.load_full_label (sample item_s))
           ~label:(cfg.load_full_label (sample item_s))
           ~accessibility_identifier:"lui-ai-load-full"
           ~on_press:(fun _ -> on_load_full (get item_s).id)
           [])

let meta_row cfg (item_s : item Signal.signal) ~main : t =
  row ~gap:8 ~cross:`center ~main
    ~accessibility_identifier:"lui-ai-meta"
    ([ if_ ~test:(reactive (fun (i : item) -> i.streaming) item_s)
         (icon ~name:`circle_dot ~width:10 ~height:10
            ~foreground:"muted-foreground"
            ~data_attrs:[ ("aria-label", "Streaming"); ("role", "img") ] [])
     ; delivery_bits cfg item_s
     ; load_full_control cfg item_s ]
     @ (match cfg.item_actions with
        | Some actions -> [ actions item_s ]
        | None -> []))

let text_body (item_s : item Signal.signal) : t =
  text ~value:(reactive (fun (i : item) -> i.text) item_s)
    ~white_space:"pre-wrap" ~style_class:"lui-ai-text" []

let user_body cfg (item_s : item Signal.signal) : t =
  column ~cross:`end_ ~gap:4
    [ column ~cross:`stretch ~gap:6 ~max_width:(cfg.content_width * 4 / 5)
        ~background:"secondary" ~corner_radius:18 ~padding_horizontal:14
        ~padding_vertical:10 ~style_class:"lui-ai-user-bubble"
        [ text_body item_s; attachments_block cfg item_s ]
    ; meta_row cfg item_s ~main:`end_ ]

let assistant_body cfg (item_s : item Signal.signal) : t =
  column ~cross:`stretch ~gap:4 ~style_class:"lui-ai-assistant"
    [ text_body item_s
    ; attachments_block cfg item_s
    ; meta_row cfg item_s ~main:`start ]

let think_body cfg (item_s : item Signal.signal) : t =
  ignore cfg;
  scoped (fun context ->
    let item = sample item_s in
    let context =
      Lui_ui.child_context context ("lui-ai-think:" ^ item.id)
    in
    let open_ = scoped_state context think_open_slot item.streaming in
    accordion ~text:"Thought process"
      ~selected_signal:(Signal.value open_)
      ~on_toggle:(fun _ -> Signal.set open_ (not (Signal.get_state open_)))
      [ text ~value:(reactive (fun (i : item) -> i.text) item_s)
          ~white_space:"pre-wrap" ~foreground:"muted-foreground" [] ])

let host_fallback (item_s : item Signal.signal) : t =
  column ~cross:`stretch ~gap:4
    [ text_body item_s
    ; text
        ~value:(reactive
                  (fun (i : item) -> Option.value i.payload ~default:"")
                  item_s)
        ~foreground:"muted-foreground" ~white_space:"pre-wrap"
        ~style_class:"caption" [] ]

(* Tool card body: input/output rendered as escaped text plus the lazy
   "load full" control. Everything is a text element — tool payloads can
   never inject markup. *)
let tool_detail cfg (item_s : item Signal.signal) : t =
  column ~cross:`stretch ~gap:6 ~padding:8
    [ reactive
        (fun (i : item) ->
           match i.tool with
           | None -> empty_node
           | Some call ->
               column ~cross:`stretch ~gap:6
                 ((match call.input with
                   | Some input when input <> "" ->
                       [ text ~value:input ~white_space:"pre-wrap"
                           ~foreground:"muted-foreground"
                           ~style_class:"lui-ai-tool-io" [] ]
                   | _ -> [])
                  @ (match call.output with
                     | Some output when output <> "" ->
                         [ text ~value:output ~white_space:"pre-wrap"
                             ~style_class:"lui-ai-tool-io" [] ]
                     | _ -> [])
                  @ (match call.output_truncated, cfg.on_load_full with
                     | true, Some on_load_full ->
                         [ button ~variant:`ghost ~size:`sm
                             ~text:(cfg.load_full_label i)
                             ~label:(cfg.load_full_label i)
                             ~accessibility_identifier:"lui-ai-load-full"
                             ~on_press:(fun _ -> on_load_full i.id) [] ]
                     | _ -> [])
                  @ [ text ~value:(tool_status_label call.status)
                        ~foreground:"muted-foreground" ~style_class:"caption"
                        [] ]))
        item_s ]

(* One tool card: a collapsible accordion whose expansion defaults to the
   call's active state until the user toggles (kept in row scope). *)
let tool_card cfg (item_s : item Signal.signal) : t =
  scoped (fun context ->
    let item = sample item_s in
    let context =
      Lui_ui.child_context context ("lui-ai-tool:" ^ item.id)
    in
    let open_ = scoped_state context tool_open_slot None in
    let tool_s = own context (Signal.map (fun (i : item) -> i.tool) item_s) in
    let expanded_s =
      own context
        (Signal.map2
           (fun (tool : tool_call option) (chosen : bool option) ->
              match chosen with
              | Some value -> value
              | None -> (
                  match tool with
                  | Some call -> tool_active call
                  | None -> false))
           tool_s (Signal.value open_))
    in
    let toggle _ =
      let current =
        match Signal.get_state open_ with
        | Some value -> value
        | None -> (
            match (get item_s).tool with
            | Some call -> tool_active call
            | None -> false)
      in
      Signal.set open_ (Some (not current))
    in
    accordion
      ~text:(reactive
               (fun (i : item) ->
                  match i.tool with
                  | Some call -> tool_headline call
                  | None -> "Tool call")
               item_s)
      ~selected_signal:expanded_s ~on_toggle:toggle
      ~accessibility_identifier:"lui-ai-tool"
      [ tool_detail cfg item_s ])

(* Collapsible section around a run of Tool_call items. Auto-expands
   while any member is active; user toggles persist in row scope. *)
let tool_group cfg (row_s : row Signal.signal) : t =
  scoped (fun context ->
    let items_s =
      own context
        (Signal.map
           (fun (r : row) ->
              match r with Tool_group l -> l | Single i -> [ i ])
           row_s)
    in
    let first_id =
      match sample row_s with
      | Tool_group (i :: _) -> i.id
      | Tool_group [] -> "empty"
      | Single i -> i.id
    in
    let context =
      Lui_ui.child_context context ("lui-ai-group:" ^ first_id)
    in
    let open_ = scoped_state context group_open_slot None in
    let active_s = own context (Signal.map group_active items_s) in
    let expanded_s =
      own context
        (Signal.map2
           (fun (active : bool) (chosen : bool option) ->
              Option.value chosen ~default:active)
           active_s (Signal.value open_))
    in
    let toggle _ =
      let current =
        Option.value (Signal.get_state open_) ~default:(Signal.get active_s)
      in
      Signal.set open_ (Some (not current))
    in
    accordion
      ~text:(reactive
               (fun (items : item list) (active : bool) ->
                  let n = List.length items in
                  let plural = if n = 1 then "" else "s" in
                  if active then
                    Printf.sprintf "Working on %d step%s" n plural
                  else Printf.sprintf "Worked through %d step%s" n plural)
               items_s active_s)
      ~selected_signal:expanded_s ~on_toggle:toggle
      ~accessibility_identifier:"lui-ai-tool-group"
      [ column ~cross:`stretch ~gap:6
          [ keyed ~source:items_s ~key:(fun (i : item) -> i.id)
              ~cmp:String.compare ~mount:(tool_card cfg) ] ])

let builtin_body cfg context (item_s : item Signal.signal) : t =
  ignore context;
  match (sample item_s).kind with
  | User -> user_body cfg item_s
  | Assistant -> assistant_body cfg item_s
  | Thinking -> think_body cfg item_s
  | Tool_call -> tool_card cfg item_s
  | Notice ->
      text ~value:(reactive (fun (i : item) -> i.text) item_s)
        ~foreground:"muted-foreground" ~text_alignment:`center
        ~style_class:"caption lui-ai-notice" []
  | Host _ -> host_fallback item_s

let item_row_of cfg context (item_s : item Signal.signal) : t =
  let item = sample item_s in
  let body =
    match cfg.render_item item_s with
    | Some view -> view
    | None -> builtin_body cfg context item_s
  in
  list_item ~key:item.id ~separator:`hidden
    ~accessibility_identifier:("lui-ai-item:" ^ item.id)
    ?style_class:
      (match cfg.item_class item with "" -> None | s -> Some s)
    ?data_attrs:
      (match cfg.item_data_attrs item with [] -> None | l -> Some l)
    [ column ~cross:`stretch ~gap:6 ~padding_horizontal:8 ~padding_vertical:4
        [ body ] ]

let row_of cfg (row_s : row Signal.signal) : t =
  scoped (fun context ->
    match sample row_s with
    | Tool_group _ -> tool_group cfg row_s
    | Single _ ->
        let item_s =
          own context
            (Signal.map
               (fun (r : row) ->
                  match r with
                  | Single i -> i
                  | Tool_group (i :: _) -> i
                  | Tool_group [] -> item "tools:empty" Tool_call)
               row_s)
        in
        item_row_of cfg context item_s)

(* {1 Follow/jump wiring} *)

let last_key (items : item list) =
  match List.rev items with i :: _ -> Some i.id | [] -> None

(* While pinned, content changes re-issue a scroll to the tail row; the
   (key, fingerprint) pair is cutoff-deduped so unchanged lists do not
   re-scroll. *)
let follow_requests messages (pinned : bool Signal.state) =
  Signal.map2
    (fun (items : item list) (pinned : bool) ->
       if pinned && items <> [] then
         Option.map (fun key -> (key, Hashtbl.hash items)) (last_key items)
       else None)
    messages (Signal.value pinned)

let transcript ?key ?(viewport = Anchored) ?overscan ?item_extent
    ?(content_width = 768) ?(group_tools = true) ?render_item
    ?render_attachment ?item_class ?item_data_attrs ?container_class
    ?container_data_attrs ?item_actions ?on_retry
    ?(retry_label = "Retry same message") ?on_load_full
    ?(load_full_label = fun _ -> "Load full item") ?on_reach_top
    ?(scroll_animated = false) ~messages () : t =
  scoped (fun context ->
    let context =
      Lui_ui.child_context context (Lui_ui.owner_name context "lui-ai")
    in
    let pinned = scoped_state context pinned_slot true in
    let request = scoped_state context request_slot ("", 0) in
    let at_top = scoped_state context at_top_slot false in
    let cfg =
      {
        render_item = Option.value render_item ~default:(fun _ -> None);
        render_attachment =
          Option.value render_attachment ~default:Attachment.view;
        item_class = Option.value item_class ~default:(fun _ -> "");
        item_data_attrs =
          Option.value item_data_attrs ~default:(fun _ -> []);
        item_actions;
        on_retry;
        retry_label;
        on_load_full;
        load_full_label;
        content_width;
      }
    in
    let seq = ref 0 in
    let scroll_to ~key ~animated =
      match viewport with
      | Anchored | Anchored_list ->
          incr seq;
          Signal.set request (key, !seq)
      | Host_driven h -> h.scroll_to ~key ~animated
    in
    let container_kind =
      match viewport with
      | Anchored -> `virtual_list
      | Anchored_list -> `list
      | Host_driven h -> h.container
    in
    let follow =
      own context
        (Signal.cutoff (fun a b -> a = b)
           (follow_requests messages pinned))
    in
    own_sub context
      (Signal.subscribe follow (fun req ->
           match req with
           | Some (key, _) -> scroll_to ~key ~animated:false
           | None -> ()));
    (match viewport with
     | Host_driven h ->
         own_sub context
           (Signal.subscribe h.at_bottom (fun b -> Signal.set pinned b))
     | Anchored | Anchored_list -> ());
    let on_visible_range (ev : Lui_protocol.event) =
      match ev with
      | Lui_protocol.VisibleRange (_, first, last) ->
          let count = List.length (get messages) in
          Signal.set pinned (count = 0 || last >= count - 1);
          if first <= 0 && not (Signal.get_state at_top) then begin
            Signal.set at_top true;
            Option.iter (fun f -> f ()) on_reach_top
          end
          else if first > 0 then Signal.set at_top false
      | _ -> ()
    in
    let jump_now _ =
      Signal.set pinned true;
      match last_key (get messages) with
      | Some key -> scroll_to ~key ~animated:scroll_animated
      | None -> ()
    in
    let rows_s =
      own context (Signal.map (group_rows ~group:group_tools) messages)
    in
    let rows =
      keyed ~source:rows_s ~key:row_key ~cmp:String.compare
        ~mount:(row_of cfg)
    in
    let anchored =
      match viewport with Anchored | Anchored_list -> true | Host_driven _ -> false in
    let list_el =
      match container_kind, anchored with
      | `list, true ->
          list ?key ~grow:1.0 ~gap:12 ~cross:`stretch ~style:`plain
            ~track_visible_range:true ~on_visible_range
            ~scroll_anchor:`bottom
            ~scroll_target:
              (reactive (fun (k, _) -> k) (Signal.value request))
            ~scroll_token:
              (reactive (fun (_, t) -> t) (Signal.value request))
            ~scroll_animated
            ?style_class:container_class ?data_attrs:container_data_attrs
            [ rows ]
      | `virtual_list, true ->
          virtual_list ?key ~grow:1.0 ~gap:12 ~cross:`stretch ?overscan
            ?item_extent ~track_visible_range:true ~on_visible_range
            ~scroll_anchor:`bottom
            ~scroll_target:
              (reactive (fun (k, _) -> k) (Signal.value request))
            ~scroll_token:
              (reactive (fun (_, t) -> t) (Signal.value request))
            ~scroll_animated
            ?style_class:container_class ?data_attrs:container_data_attrs
            [ rows ]
      | `list, false ->
          list ?key ~grow:1.0 ~gap:12 ~cross:`stretch ~style:`plain
            ?style_class:container_class ?data_attrs:container_data_attrs
            [ rows ]
      | `virtual_list, false ->
          virtual_list ?key ~grow:1.0 ~gap:12 ~cross:`stretch ?overscan
            ?item_extent ?style_class:container_class
            ?data_attrs:container_data_attrs [ rows ]
    in
    stack ~grow:1.0
      [ list_el
      ; align `bottom
          (if_
             ~test:(reactive (fun p -> not p) (Signal.value pinned))
             (button ~icon:`arrow_down ~variant:`secondary ~size:`icon
                ~width:36 ~height:36 ~corner_radius:18 ~label:"Jump to latest"
                ~accessibility_identifier:"lui-ai-jump" ~on_press:jump_now
                [])) ])

let item_row (item : item) : t =
  scoped (fun context ->
    let item_s =
      own context (Signal.constant context.Lui_ui.ui_scheduler item)
    in
    item_row_of
      {
        render_item = (fun _ -> None);
        render_attachment = Attachment.view;
        item_class = (fun _ -> "");
        item_data_attrs = (fun _ -> []);
        item_actions = None;
        on_retry = None;
        retry_label = "Retry same message";
        on_load_full = None;
        load_full_label = (fun _ -> "Load full item");
        content_width = 768;
      }
      context item_s)
