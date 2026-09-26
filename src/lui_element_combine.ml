(** Generic composite elements assembled purely from {!Lui_elements}
    primitives: composer, confirm dialog, form sheet, settings sections,
    feedback banner, loading, empty state, section heading, action toolbar,
    suggestion list, breadcrumbs and sidebar navigation.

    Composites take content and behaviour parameters (labels, icons,
    callbacks, signals) but no fine-grained style knobs — their layout,
    padding, colour and typography are fixed so every host renders them
    with the platform-native idiom. *)

open Lui_elements

type t = Lui_elements.t

(* ------------------------------------------------------------------ *)
(* Glass buttons                                                      *)
(* ------------------------------------------------------------------ *)

type action =
  { label : string
  ; icon : icon
  ; text : string option
  ; on_press : Lui_protocol.event -> unit
  }

let glass_action_button ?background ?corner_radius action =
  let visible_text =
    match action.text with
    | Some text when text <> "" -> Some text
    | _ -> None
  in
  let icon_only = Option.is_none visible_text in
  button
    ~variant:`ghost
    ~size:(if icon_only then `icon else `default)
    ~icon:action.icon
    ?text:visible_text
    ~label:action.label
    ~foreground:"foreground"
    ?background
    ?corner_radius
    ?padding_horizontal:(if icon_only then None else Some 12)
    ?width:(if icon_only then Some 44 else None)
    ~height:44
    ~on_press:action.on_press
    []
;;

let buttons ~actions =
  match actions with
  | [ action ] ->
    glass_action_button ~background:"glass" ~corner_radius:999 action
  | _ :: _ :: _ ->
    button_group
      ~gap:0
      ~height:44
      ~background:"glass"
      ~corner_radius:999
      (List.map glass_action_button actions)
  | [] -> invalid_arg "buttons requires at least one action"
;;

let rec intersperse separator_ = function
  | [] -> []
  | [ x ] -> [ x ]
  | x :: rest -> x :: separator_ :: intersperse separator_ rest
;;

(* ------------------------------------------------------------------ *)
(* Composer                                                            *)
(* ------------------------------------------------------------------ *)

let with_press handler (elem : t) : t =
 fun context parent ->
   let node = elem context parent in
   enable context node Lui_protocol.PressEnabled;
   register_press context node handler;
   node
;;

let with_bool_prop_signal prop signal_ (elem : t) : t =
 fun context parent ->
   let node = elem context parent in
   Lui_ui.bool_property_signal context node prop signal_;
   node
;;

let composer_send_button context ?send_icon send_disabled on_send : t =
  let android_icon = Option.value send_icon ~default:(`send : icon) in
  let apple_icon = Option.value send_icon ~default:(`arrow_up : icon) in
  if Lui_ui.platform context = Lui_protocol.AndroidOS
  then
    if Lui_ui.host context = Lui_protocol.FlutterHost
    then
      button
        ~icon:android_icon ~variant:`primary ~size:`icon ~width:48 ~height:48
        ~label:"Send" ~accessibility_identifier:"button.send"
        ?disabled_signal:send_disabled ~on_press:on_send []
    else
      button
        ~icon:android_icon ~variant:`primary ~label:"Send"
        ~accessibility_identifier:"button.send" ?disabled_signal:send_disabled
        ~on_press:on_send ~text:"Send" []
  else
    button
      ~icon:apple_icon ~variant:`ghost ~width:36 ~height:36
      ~background:"black" ~foreground:"white" ~corner_radius:18 ~label:"Send"
      ~accessibility_identifier:"button.send" ?disabled_signal:send_disabled
      ~on_press:on_send []
;;

let composer
      ?key
      ?accessibility_identifier
      ?attachments
      ?attachments_visible_signal
      ?(actions = [])
      ~placeholder
      ?label
      ?text
      ?text_signal
      ?(autofocus = false)
      ?autofocus_signal
      ?submit_on_enter
      ?send_icon
      ?send_disabled_signal
      ?on_input
      ?on_submit
      ?on_send
      ?on_press
      ()
  : t
  =
 fun context parent ->
   let flutter = Lui_ui.host context = Lui_protocol.FlutterHost in
   let attachment_strip =
     match attachments with
     | None -> []
     | Some content ->
       let strip =
         scroll ~orientation:`horizontal ~height:140 [ row ~gap:8 [ content ] ]
       in
       [ (match attachments_visible_signal with
          | None -> strip
          | Some test -> if_ ~test strip)
       ]
   in
   let field =
     textarea
       ~min_height:36 ~style_class:"composer-input" ~placeholder
       ~label:(match label with Some value -> value | None -> placeholder)
       ?text ?text_signal ~autofocus ?submit_on_enter
       ~accessibility_identifier:"field.composer" ?on_input ?on_submit []
   in
   let field =
     match autofocus_signal with
     | None -> field
     | Some signal_ ->
       with_bool_prop_signal Lui_protocol.Autofocus signal_ field
   in
   let send_button =
     match on_send with
     | None -> []
     | Some on_send ->
      [ composer_send_button context ?send_icon send_disabled_signal on_send ]
   in
   let capsule =
     column
       ?key ?accessibility_identifier
       ~grow:1.0 ~min_height:58 ~main:`end_ ~gap:0
       ~padding_horizontal:(if flutter then 12 else 16)
       ~padding_vertical:(if flutter then 12 else 8)
       ~background:(if flutter then "surface-container-high" else "glass")
       ~corner_radius:24
       ([ box ~height:6 ~accessibility_identifier:"spacer.composer.top" [] ]
        @ attachment_strip
        @ [ field
          ; box ~height:8
              ~accessibility_identifier:"spacer.composer.field-controls" []
          ; row
              ~gap:8 ~height:44 ~cross:`center
              ~accessibility_identifier:"row.composer.controls"
              (actions
               @ [ spacer
                     ~grow:1.0
                     ~accessibility_identifier:"spacer.composer.controls" []
                 ]
               @ send_button)
          ])
   in
   (match on_press with
    | None -> capsule
    | Some handler -> with_press handler capsule)
     context parent
;;

let composer_collapsed
      ?key
      ?accessibility_identifier
      ~label
      ?icon
      ~on_press
      ()
  : t
  =
 fun context parent ->
   if Lui_ui.host context = Lui_protocol.FlutterHost
   then
     (button
        ?key ?accessibility_identifier ~variant:`secondary ?icon ~grow:1.0
        ~height:58 ~padding_horizontal:20 ~label ~text:label ~on_press [])
       context parent
   else
     (button
        ?key ?accessibility_identifier ~variant:`ghost ~grow:1.0 ~height:58
        ~padding_horizontal:30 ~background:"glass"
        ~foreground:"muted-foreground" ~corner_radius:999 ?icon ~text:label
        ~on_press [])
       context parent
;;

(* ------------------------------------------------------------------ *)
(* Dialogs and sheets                                                  *)
(* ------------------------------------------------------------------ *)

let confirm_dialog
      ?key
      ?accessibility_identifier
      ~title
      ?message
      ?(cancel_label = "Cancel")
      ?(confirm_label = "Confirm")
      ?(destructive = false)
      ?on_dismiss
      ?on_cancel
      ~on_confirm
      ()
  =
  dialog
    ?key
    ?accessibility_identifier
    ~text:title
    ?description:message
    ?on_dismiss
    [ button
        ~variant:`ghost
        ~text:cancel_label
        ~on_press:
          (match on_cancel, on_dismiss with
           | Some handler, _ -> handler
           | None, Some handler -> handler
           | None, None -> fun _ -> ())
        []
    ; button
        ~variant:(if destructive then `destructive else `primary)
        ~text:confirm_label
        ~on_press:on_confirm
        []
    ]
;;

let form_sheet
      ?key
      ?accessibility_identifier
      ~title
      ?on_dismiss
      ~content
      ?cancel
      ?confirm
      ?confirm_disabled
      ()
  =
  let action_buttons =
    (match cancel with
     | None -> []
     | Some (cancel_label, on_cancel) ->
       [ button
           ~style_class:"cancellation-action"
           ~text:cancel_label
           ~on_press:on_cancel
           []
       ])
    @ (match confirm with
       | None -> []
       | Some (confirm_label, on_confirm) ->
         [ button
             ~style_class:"confirmation-action"
             ~text:confirm_label
             ?disabled_signal:confirm_disabled
             ~on_press:on_confirm
             []
         ])
  in
  let actions =
    match action_buttons with
    | [] -> []
    | buttons ->
      [ toolbar
          ~orientation:`horizontal
          ~label:"Form actions"
          ~style_class:"navigation-actions"
          buttons
      ]
  in
  sheet
    ?key
    ?accessibility_identifier
    ~text:title
    ~style_class:"navigation-form"
    ?on_dismiss
    ([ column ~style_class:"form" content ] @ actions)
;;

(* ------------------------------------------------------------------ *)
(* Settings                                                            *)
(* ------------------------------------------------------------------ *)

let settings_row ?key ?accessibility_identifier ~label ?icon ?on_press () =
  list_item ?key ?accessibility_identifier ~text:label ?icon ?on_press []
;;

let labeled_row
      ?key
      ?accessibility_identifier
      ~label
      ?value
      ?value_signal
      ()
  =
  list_item
    ?key
    ?accessibility_identifier
    [ row
        ~grow:1.0
        ~cross:`center
        ~main:`space_between
        [ text ~value:label []
        ; text ?value ?value_signal ~foreground:"secondary" ~text_alignment:`end_ []
        ]
    ]
;;

let toggle_row
      ?key
      ?accessibility_identifier
      ~label
      ?checked
      ?checked_signal
      ?disabled
      ?disabled_signal
      ~on_toggle
      ()
  =
  toggle
    ?key
    ?accessibility_identifier
    ~text:label
    ?checked
    ?checked_signal
    ?disabled
    ?disabled_signal
    ~on_toggle
    []
;;

let settings_section ?key ?accessibility_identifier ?title ~rows () =
  let heading_row =
    match title with
    | None -> []
    | Some value ->
      [ text
          ~style_class:"headline"
          ~foreground:"muted-foreground"
          ~value
          []
      ]
  in
  column
    ?key
    ?accessibility_identifier
    ~gap:8
    (heading_row
     @ [ column
           ~gap:0
           ~padding:16
           ~background:"surface"
           ~corner_radius:14
           (intersperse (separator []) rows)
       ])
;;

(* ------------------------------------------------------------------ *)
(* Feedback                                                            *)
(* ------------------------------------------------------------------ *)

let feedback_banner
      ?key
      ?accessibility_identifier
      ?(kind = `error)
      ?message
      ?message_signal
      ()
  =
  let variant, icon_name, icon_color =
    match kind with
    | `error -> `destructive, `alert, "destructive"
    | `info -> `default, `info, "secondary"
  in
  alert
    ?key
    ?accessibility_identifier
    ~variant
    ~padding:14
    ~corner_radius:16
    ~border_width:0
    [ row
        ~gap:10
        ~cross:`center
        [ icon ~name:icon_name ~width:22 ~height:22 ~foreground:icon_color []
        ; text ?value:message ?value_signal:message_signal ~grow:1.0 []
        ]
    ]
;;

let loading ?key ?accessibility_identifier ~message ?(centered = false) () =
  if centered
  then
    column
      ?key
      ?accessibility_identifier
      ~grow:1.0
      ~main:`center
      ~cross:`center
      ~gap:12
      [ spinner []; text ~value:message ~foreground:"muted-foreground" [] ]
  else
    row
      ?key
      ?accessibility_identifier
      ~gap:10
      ~cross:`center
      [ spinner ~size:`sm []; text ~value:message ~foreground:"muted-foreground" [] ]
;;

let empty_state
      ?key
      ?accessibility_identifier
      ?icon
      ~title
      ?description
      ?(actions = [])
      ()
  =
  column
    ?key
    ?accessibility_identifier
    ~grow:1.0
    ~main:`center
    ~cross:`center
    ~gap:12
    ~padding:24
    ((match icon with
      | None -> []
      | Some name ->
        [ Lui_elements.icon ~name ~size:`lg ~foreground:"muted-foreground" [] ])
     @ [ heading ~level:4 ~value:title [] ]
     @ (match description with
        | None -> []
        | Some value ->
          [ text
              ~value
              ~foreground:"muted-foreground"
              ~text_alignment:`center
              []
          ])
     @
     if actions = [] then [] else [ row ~gap:12 ~cross:`center actions ])
;;

(* ------------------------------------------------------------------ *)
(* Section heading                                                     *)
(* ------------------------------------------------------------------ *)

let section_heading ?key ?accessibility_identifier ?icon ~title () =
  row
    ?key
    ?accessibility_identifier
    ~gap:8
    ~cross:`center
    ~padding_vertical:8
    ((match icon with
      | None -> []
      | Some name ->
        [ Lui_elements.icon ~name ~size:`sm ~foreground:"muted-foreground" [] ])
     @ [ text
           ~style_class:"caption semibold"
           ~foreground:"muted-foreground"
           ~value:title
           []
       ])
;;

(* ------------------------------------------------------------------ *)
(* Action toolbar                                                      *)
(* ------------------------------------------------------------------ *)

type toolbar_item =
  { toolbar_item_label : string
  ; toolbar_item_icon : icon option
  ; toolbar_item_disabled : bool Signal.signal option
  ; toolbar_item_selected : bool option
  ; toolbar_item_on_press : Lui_protocol.event -> unit
  }

let toolbar_item ~label ?icon ?disabled ?selected ~on_press () =
  { toolbar_item_label = label
  ; toolbar_item_icon = icon
  ; toolbar_item_disabled = disabled
  ; toolbar_item_selected = selected
  ; toolbar_item_on_press = on_press
  }
;;

let action_toolbar ?key ?accessibility_identifier ~items () =
  let button_of item =
    button
      ~variant:`ghost
      ~text:item.toolbar_item_label
      ?icon:item.toolbar_item_icon
      ~icon_placement:`top
      ?disabled_signal:item.toolbar_item_disabled
      ?selected:item.toolbar_item_selected
      ~on_press:item.toolbar_item_on_press
      []
  in
  column
    ?key
    ?accessibility_identifier
    ~padding:8
    ~background:"surface"
    ~corner_radius:20
    ~cross:`stretch
    [ row ~gap:8 ~main:`space_between (List.map button_of items) ]
;;

(* ------------------------------------------------------------------ *)
(* Suggestion list (autocomplete)                                      *)
(* ------------------------------------------------------------------ *)

let suggestion_list
      ?key
      ?accessibility_identifier
      ~source
      ~item_key
      ~label
      ?icon
      ~on_select
      ()
  =
  scroll
    ?key
    ?accessibility_identifier
    ~orientation:`vertical
    ~max_height:240
    [ column
        ~gap:4
        ~padding:4
        ~background:"surface"
        ~corner_radius:12
        [ keyed
            ~source
            ~key:item_key
            ~cmp:String.compare
            ~mount:(fun item_signal ->
              button
                ~variant:`ghost
                ~text_alignment:`start
                ~corner_radius:8
                ~text_signal:(map label item_signal)
                ?icon_signal:(Option.map (fun f -> map f item_signal) icon)
                ~on_press:(fun event -> on_select (get item_signal) event)
                [])
        ]
    ]
;;

(* ------------------------------------------------------------------ *)
(* Breadcrumbs                                                         *)
(* ------------------------------------------------------------------ *)

let breadcrumb_trail
      ?key
      ?accessibility_identifier
      ~items
      ()
  =
  breadcrumb
    ?key
    ?accessibility_identifier
    ~gap:5
    ~main:`start
    (List.map
       (fun (item_label, on_press) ->
          button
            ~variant:`ghost
            ~style_class:"caption"
            ~foreground:"muted-foreground"
            ~text:item_label
            ~on_press
            [])
       items)
;;

(* ------------------------------------------------------------------ *)
(* Sidebar navigation                                                  *)
(* ------------------------------------------------------------------ *)

let nav_item
      ?key
      ?accessibility_identifier
      ?accessibility_identifier_signal
      ~label
      ?label_signal
      ?icon
      ?selected
      ?selected_signal
      ~on_press
      ()
  =
  list_item
    ?key
    ?accessibility_identifier
    ?accessibility_identifier_signal
    ~role:`navigation
    ~text:label
    ?text_signal:label_signal
    ?icon
    ?selected
    ?selected_signal
    ~on_press
    []
;;

let check_menu_item
      ?key
      ?accessibility_identifier
      ~label
      ?icon
      ?checked
      ?checked_signal
      ?disabled
      ?disabled_signal
      ~on_press
      ()
  =
  menu_item
    ?key
    ?accessibility_identifier
    ~text:label
    ?icon
    ?checked
    ?checked_signal
    ?disabled
    ?disabled_signal
    ~on_press
    []
;;

let menu_button
      ?key
      ?accessibility_identifier
      ~label
      ?icon
      ?(anchor = `below)
      ~open_
      ~menu
      ?on_dismiss
      ?on_press
      ()
  =
  let trigger =
    button
      ~variant:`ghost
      ~text:label
      ~icon:`chevron_down
      ~icon_placement:`trailing
      ?on_press
      []
  in
  let trigger =
    match icon with
    | None -> trigger
    | Some leading ->
      row ~gap:4 ~cross:`center [ Lui_elements.icon ~name:leading []; trigger ]
  in
  stack
    ?key
    ?accessibility_identifier
    [ trigger
    ; if_ ~test:open_
        (dropdown_menu ~anchor ~anchor_alignment:`start ?on_dismiss menu)
    ]
;;

type sidebar_section =
  { sidebar_section_title : string
  ; sidebar_section_items : t list
  }

let sidebar_section ~title ~items () =
  { sidebar_section_title = title; sidebar_section_items = items }
;;

let sidebar
      ?key
      ?accessibility_identifier
      ?header
      ?(items = [])
      ?(sections = [])
      ()
  =
  let section_views =
    List.concat_map
      (fun section ->
         section_heading ~title:section.sidebar_section_title ()
         :: section.sidebar_section_items)
      sections
  in
  column
    ?key
    ?accessibility_identifier
    ~grow:1.0
    ~gap:8
    ~padding:12
    ((match header with
      | None -> []
      | Some view -> [ view ])
     @ items
     @ [ scroll
           ~grow:1.0
           ~orientation:`vertical
           [ column ~gap:4 ~cross:`stretch section_views ]
       ])
;;
