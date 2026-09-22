(* Component gallery view. Mirrors the original LG gallery:
   a column of sections exercising layout, text, controls, lists,
   pickers, overlays, and navigation — with signal-driven props. *)

open Lui_protocol
open Lui_elements

let section title children : t =
  column ~gap:16 ~padding:32
    (heading ~level:2 ~value:title [] :: children)

let layout_section : t =
  section "Layout"
    [ row ~gap:12 [panel ~padding:12 [text ~value:"First" []] ; panel ~padding:12 [text ~value:"Second" []]]
    ; column ~gap:8 [text ~value:"Column" [] ; text ~value:"Nested column" []]
    ; grid ~columns:2 ~gap:12 [card ~padding:12 [text ~value:"One" []] ; card ~padding:12 [text ~value:"Two" []] ; card ~padding:12 [text ~value:"Three" []] ; card ~padding:12 [text ~value:"Four" []]]
    ; stack ~width:320 ~height:96 [panel ~padding:16 [text ~value:"Stack base layer" []] ; text ~padding:16 ~value:"Overlay layer" []]
    ; list ~gap:8 ~cross:"stretch" ~max_width:480 [card ~padding:16 [text ~value:"List item one" []] ; card ~padding:16 [text ~value:"List item two" []]]
    ; scroll ~width:320 ~height:160 [list ~gap:8 ~cross:"stretch" [card ~padding:16 [text ~value:"Scrollable item one" []] ; card ~padding:16 [text ~value:"Scrollable item two" []] ; card ~padding:16 [text ~value:"Scrollable item three" []] ; card ~padding:16 [text ~value:"Scrollable item four" []]]]
    ]

let text_section : t =
  section "Text"
    [ text ~value:"A lightweight text label rendered by the backend." []
    ; row ~gap:8 ~max_width:320 [text ~value:"Leading" [] ; spacer ~grow:1.0 [] ; text ~value:"Trailing" []]
    ; status_bar ~text_alignment:"end" ~value:"lui gallery" []
    ]

let button_section model_source send : t =
  let disabled = model_source >|= Model.disabled in
  section "Button"
    [ button ~variant:"outline" ~text:"Toggle disabled" ~on_press:(press send Model.ToggleDisabled) []
    ; (if_ ~test:disabled
         (paragraph ~value:"Controls are disabled." []))
    ; grid ~columns:2 ~gap:12 [button ~text:"Default" ~disabled:(reactive disabled) ~on_press:(fun _event -> ()) [] ; button ~variant:"primary" ~icon:"download" ~text:"Primary" ~disabled:(reactive disabled) ~on_press:(fun _event -> ()) ~on_long_press:(fun _event -> ignore (send Model.ToggleDisabled)) [] ; button ~variant:"secondary" ~text:"Secondary" ~disabled:(reactive disabled) ~on_press:(fun _event -> ()) [] ; button ~variant:"outline" ~text:"Outline" ~disabled:(reactive disabled) ~on_press:(fun _event -> ()) []]
    ; paragraph ~value:"Press Primary normally; long-press it to toggle disabled state." []
    ]

let toggle_section model_source send : t =
  let checked = model_source >|= Model.checked in
  let on_toggle _event =
    ignore (send (Model.SetChecked (not (sample checked))))
  in
  section "Toggle"
    [ toggle ~checked:(reactive checked) ~label:"Enable notifications" ~on_toggle:on_toggle []
    ; checkbox ~checked:(reactive checked) ~label:"Remember choice" ~on_toggle:on_toggle []
    ; switch_ ~checked:(reactive checked) ~label:"Airplane mode" ~on_toggle:on_toggle []
    ; radio ~checked:(reactive Model.density_comfortable model_source) ~label:"Comfortable" ~on_toggle:(fun _event -> ignore (send (Model.SetDensity "comfortable"))) []
    ; radio ~checked:(reactive Model.density_compact model_source) ~label:"Compact" ~on_toggle:(fun _event -> ignore (send (Model.SetDensity "compact"))) []
    ]

let field_section model_source send : t =
  let field_value =
    model_source >|= Model.field_value
  in
  section "Field"
    [ text_field ~text:(reactive field_value) ~placeholder:"Type here" ~label:"Field value" ~on_input:(fun event ->
          match event with
          | TextChanged (_node, text) -> ignore (send (Model.SetFieldValue text))
          | _ -> ()) []
    ; paragraph ~value:(reactive (fun (m : Model.t) ->
          if m.field_value = "" then "Field is empty"
          else "Field: " ^ m.field_value) model_source) []
    ; search_field ~placeholder:"Search" ~label:"Search" ~on_input:(fun _event -> ()) []
    ]

let slider_section model_source send : t =
  let volume = model_source >|= Model.volume in
  section "Slider"
    [ slider ~value:(reactive volume) ~label:"Volume" ~on_change:(fun event ->
          match event with
          | ValueChanged (_node, value) -> ignore (send (Model.SetVolume value))
          | _ -> ()) []
    ; paragraph ~value:(reactive Model.volume_label model_source) []
    ]

let progress_section model_source send : t =
  let progress_value = model_source >|= Model.progress in
  section "Progress"
    [ progress ~value:(reactive progress_value) []
    ; paragraph ~value:(reactive Model.progress_label model_source) []
    ; button ~variant:"outline" ~text:"Advance" ~on_press:(press send Model.AdvanceProgress) []
    ]

let picker_section model_source send : t =
  let open_select = map Model.select_open model_source in
  let open_combobox = map Model.combobox_open model_source in
  section "Picker"
    [ select ~placeholder:"Environment" ~label:"Environment" ~on_press:(press send (Model.OpenPicker "select")) ~on_dismiss:(fun _event -> ignore (send Model.ClosePicker)) []
    ; (if_ ~test:open_select
         (column ~gap:4
              [ list_item ~on_press:(press send (Model.SelectEnvironment "Production"))
                    [ text ~value:"Production" [] ]
                ; list_item ~on_press:(press send (Model.SelectEnvironment "Staging"))
                    [ text ~value:"Staging" [] ]
                ]))
    ; combobox ~placeholder:"Pick environment" ~on_input:(fun event ->
          match event with
          | TextChanged (_node, query) ->
            ignore (send (Model.SetPickerQuery query))
          | _ -> ()) ~on_submit:(fun _event -> ignore (send Model.CommitPickerQuery)) ~on_dismiss:(fun _event -> ignore (send Model.ClosePicker)) []
    ; (if_ ~test:open_combobox
         (column ~gap:4
              [ (if_ ~test:(map Model.production_visible model_source)
                     (list_item
                          ~on_press:(press send (Model.SelectEnvironment "Production"))
                          [ text ~value:"Production" [] ]))
                ; (if_ ~test:(map Model.staging_visible model_source)
                     (list_item
                          ~on_press:(press send (Model.SelectEnvironment "Staging"))
                          [ text ~value:"Staging" [] ]))
                ]))
    ; paragraph ~value:(reactive (fun (m : Model.t) ->
          "Environment: " ^ m.environment) model_source) []
    ]

let document_section model_source send : t =
  let action = model_source >|= Model.document_action in
  section "Documents"
    [ list ~gap:2 ~cross:"stretch" ~max_width:480 [list_item ~icon:"file-text" ~selected:(reactive Model.report_selected model_source) ~on_press:(press send (Model.SelectDocument "Quarterly report.md")) ~on_double_press:(fun _event ->
            ignore (send (Model.OpenDocument "Quarterly report.md"))) [text ~value:"Quarterly report.md" []] ; list_item ~selected:(reactive Model.checklist_selected model_source) ~on_press:(press send (Model.SelectDocument "Launch checklist.md")) ~on_double_press:(fun _event ->
            ignore (send (Model.OpenDocument "Launch checklist.md"))) [row ~gap:8 ~cross:"center" [icon ~name:"check-circle" ~size:"sm" [] ; text ~value:"Launch checklist.md" [] ; spacer []]] ; list_item ~icon:"music" ~disabled:true [text ~value:"demo-track.wav" []]]
    ; paragraph ~value:(reactive action) []
    ; text ~value:"Right-click target" [context_menu [menu_item ~text:"Rename" ~on_press:(press send (Model.PerformContextAction "Rename")) [] ; menu_item ~text:"Archive" ~on_press:(press send (Model.PerformContextAction "Archive")) []]]
    ]

let overlay_section model_source send : t =
  let dialog_open = model_source >|= Model.dialog_open in
  let sheet_open = model_source >|= Model.sheet_open in
  let toast_open = model_source >|= Model.toast_open in
  section "Overlays"
    [ button ~variant:"outline" ~text:"Open dialog" ~on_press:(press send Model.OpenDialog) []
    ; (if_ ~test:dialog_open
         (dialog ~text:"Rename note" ~width:380 ~height:240 ~padding:24
              ~on_dismiss:(fun _event -> ignore (send Model.CloseDialog))
              [ column ~gap:16
                    [ input ~placeholder:"Note name" ~autofocus:true
                          []
                      ; row ~gap:8 ~main:"end"
                          [ button ~variant:"ghost" ~text:"Cancel"
                                ~on_press:(press send Model.CloseDialog)
                                []
                            ; button ~variant:"primary" ~text:"Save"
                                ~on_press:(press send Model.CloseDialog)
                                []
                            ]
                      ]
                ]))
    ; button ~variant:"outline" ~text:"Open sheet" ~on_press:(press send Model.OpenSheet) []
    ; (if_ ~test:sheet_open
         (sheet ~text:"Share" ~height:320 ~padding:24
              ~on_dismiss:(fun _event -> ignore (send Model.CloseSheet))
              [ column ~gap:12
                    [ paragraph
                          ~value:"Anyone with the link can view this showcase."
                          []
                      ; input ~placeholder:"Share link" []
                      ]
                ]))
    ; button ~variant:"outline" ~text:"Show toast" ~on_press:(press send Model.ShowToasts) []
    ; (if_ ~test:toast_open
         (toast ~label:"Saved"
              ~on_dismiss:(fun _event -> ignore (send Model.CloseToasts))
              [ paragraph ~value:(reactive Model.toast_description model_source)
                    [] ]))
    ]

let navigation_section model_source send : t =
  let overview = map Model.overview_tab_selected model_source in
  let activity = map Model.activity_tab_selected model_source in
  section "Navigation"
    [ tabs ~label:"Sections" []
    ; list ~gap:4 ~cross:"stretch" ~max_width:480 [list_item ~selected:(reactive overview) ~on_press:(press send (Model.SelectTab "overview")) [text ~value:"Overview" []] ; list_item ~selected:(reactive activity) ~on_press:(press send (Model.SelectTab "activity")) [text ~value:"Activity" []]]
    ; dyn
        (fun (m : Model.t) ->
           if Model.activity_tab_selected m
           then paragraph ~value:"Recent retained updates" []
           else paragraph ~value:"Signal updates remain local" [])
        model_source
    ; bottom_tabs ~accessibility_identifier:"primary-destinations" [bottom_tab ~icon:"folder" ~title:"Home" ~selected:(reactive Model.home_bottom_tab_selected model_source) ~on_press:(press send (Model.SelectBottomTab "home")) [column ~gap:12 ~padding:20 [heading ~level:2 ~value:"Home" [] ; input ~label:"Draft" ~placeholder:"Retained home draft" [] ; paragraph ~value:"This input stays mounted while another destination is active." []]] ; bottom_tab ~icon:"search" ~title:"Search" ~selected:(reactive Model.search_bottom_tab_selected model_source) ~on_press:(press send (Model.SelectBottomTab "search")) [column ~gap:12 ~padding:20 [heading ~level:2 ~value:"Search" [] ; paragraph ~value:"Search uses the same retained destination model." []]] ; bottom_tab ~icon:"settings" ~title:"Settings" ~selected:(reactive Model.settings_bottom_tab_selected model_source) ~on_press:(press send (Model.SelectBottomTab "settings")) [column ~gap:12 ~padding:20 [heading ~level:2 ~value:"Settings" [] ; paragraph ~value:"Platform chrome changes without rebuilding this page." []]]]
    ; paragraph ~value:"Apple maps this component to TabView; Android maps it to Material NavigationBar." []
    ]

let view context model_source send =
  let _platform = Lui_ui.platform context in
  (scroll [column ~gap:32 ~padding:24 [(layout_section) ; (text_section) ; (button_section model_source send) ; (toggle_section model_source send) ; (field_section model_source send) ; (slider_section model_source send) ; (progress_section model_source send) ; (picker_section model_source send) ; (document_section model_source send) ; (overlay_section model_source send) ; (navigation_section model_source send)]])
