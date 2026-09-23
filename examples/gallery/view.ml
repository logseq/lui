(* Component gallery view. Mirrors the original LG gallery:
   each component gets its own page — a direct child of the root
   column, titled by a level-2 heading — so the iOS host renders
   one master-detail row per component. *)

open Lui_protocol
open Lui_elements

let section title children : t =
  column ~gap:16 ~padding:32
    (heading ~level:2 ~value:title [] :: children)

let noop _event = ()

let on_toggle send make event =
  match event with
  | ToggleChanged (_node, value) -> ignore (send (make value))
  | _ -> ()

let value_changed send make event =
  match event with
  | ValueChanged (_node, value) -> ignore (send (make value))
  | _ -> ()

(* Layout primitives *)

let row_section : t =
  section "Row"
    [ row ~gap:12
        [ panel ~padding:12 [ text ~value:"First" [] ]
        ; panel ~padding:12 [ text ~value:"Second" [] ]
        ]
    ]

let column_section : t =
  section "Column"
    [ column ~gap:8
        [ text ~value:"First" []
        ; text ~value:"Second" []
        ]
    ]

let grid_section : t =
  section "Grid"
    [ grid ~columns:2 ~gap:12
        [ card ~padding:12 [ text ~value:"One" [] ]
        ; card ~padding:12 [ text ~value:"Two" [] ]
        ; card ~padding:12 [ text ~value:"Three" [] ]
        ; card ~padding:12 [ text ~value:"Four" [] ]
        ]
    ]

let text_section : t =
  section "Text"
    [ text ~value:"A lightweight text label rendered by the native backend." []
    ]

let spacer_section : t =
  section "Spacer"
    [ row ~gap:8 ~max_width:320
        [ text ~value:"Leading" []
        ; spacer ~grow:1.0 []
        ; text ~value:"Trailing" []
        ]
    ]

(* Buttons and groups *)

let button_section model_source send : t =
  let disabled = model_source >|= Model.disabled in
  section "Button"
    [ button ~variant:"outline" ~text:"Toggle disabled"
        ~on_press:(press send Model.ToggleDisabled) []
    ; if_ ~test:disabled (paragraph ~value:"Controls are disabled." [])
    ; grid ~columns:2 ~gap:12
        [ button ~text:"Default" ~disabled:(reactive disabled)
            ~on_press:noop []
        ; button ~variant:"primary" ~icon:"download" ~text:"Primary"
            ~disabled:(reactive disabled) ~on_press:noop
            ~on_long_press:(press send Model.ToggleDisabled) []
        ; button ~variant:"secondary" ~text:"Secondary"
            ~disabled:(reactive disabled) ~on_press:noop []
        ; button ~variant:"outline" ~text:"Outline"
            ~disabled:(reactive disabled) ~on_press:noop []
        ; button ~variant:"ghost" ~text:"Selected" ~selected:true
            ~disabled:(reactive disabled) ~on_press:noop []
        ; button ~variant:"destructive" ~text:"Destructive"
            ~disabled:(reactive disabled) ~on_press:noop []
        ]
    ; row ~gap:12
        [ button ~size:"sm" ~text:"Small" ~disabled:(reactive disabled)
            ~on_press:noop []
        ; button ~text:"Default" ~disabled:(reactive disabled)
            ~on_press:noop []
        ; button ~size:"lg" ~icon:"chevron-right"
            ~icon_placement:"trailing" ~text:"Large"
            ~disabled:(reactive disabled) ~on_press:noop []
        ; button ~size:"icon" ~icon:"plus" ~label:"New note"
            ~disabled:(reactive disabled) ~on_press:noop []
        ]
    ; paragraph
        ~value:"Press Primary normally; long-press it for 350 ms to toggle disabled state."
        []
    ]

let toggle_button_section model_source send : t =
  let disabled = model_source >|= Model.disabled in
  section "ToggleButton"
    [ row ~gap:12
        [ dyn
            ~equal:(fun (a : Model.t) (b : Model.t) ->
              a.Model.checked = b.Model.checked)
            (fun (m : Model.t) ->
              toggle_button ~variant:"outline" ~size:"sm" ~icon:"edit"
                ~text:"Controlled" ~selected:m.Model.checked
                ~disabled:(reactive disabled)
                ~on_toggle:(on_toggle send (fun v -> Model.SetChecked v))
                ~on_long_press:(press send Model.ToggleDisabled) [])
            model_source
        ; toggle_button ~variant:"ghost" ~text:"Backend-owned"
            ~disabled:(reactive disabled) ~on_toggle:noop []
        ; toggle_button ~size:"icon" ~icon:"check"
            ~label:"Toggle approval" ~disabled:(reactive disabled)
            ~on_toggle:noop []
        ]
    ; paragraph
        ~value:"Controlled selection follows one Signal; backend-owned selection survives unrelated patches."
        []
    ]

let button_group_section model_source send : t =
  let disabled = model_source >|= Model.disabled in
  section "ButtonGroup"
    [ button_group ~accessibility_identifier:"Document actions"
        [ button ~icon:"save" ~text:"Save" ~disabled:(reactive disabled)
            ~on_press:(press send Model.ToggleDisabled) []
        ; dyn
            ~equal:(fun (a : Model.t) (b : Model.t) ->
              a.Model.checked = b.Model.checked)
            (fun (m : Model.t) ->
              toggle_button ~icon:"check" ~text:"Pin"
                ~selected:m.Model.checked ~disabled:(reactive disabled)
                ~on_toggle:(on_toggle send (fun v -> Model.SetChecked v)) [])
            model_source
        ]
    ]

let toggle_group_section model_source send : t =
  let disabled = model_source >|= Model.disabled in
  section "ToggleGroup"
    [ toggle_group ~accessibility_identifier:"View options"
        [ dyn
            ~equal:(fun (a : Model.t) (b : Model.t) ->
              a.Model.checked = b.Model.checked)
            (fun (m : Model.t) ->
              toggle_button ~text:"Controlled" ~selected:m.Model.checked
                ~disabled:(reactive disabled)
                ~on_toggle:(on_toggle send (fun v -> Model.SetChecked v)) [])
            model_source
        ; toggle_button ~text:"Multi-select" ~disabled:(reactive disabled)
            ~on_toggle:noop []
        ; dyn
            ~equal:(fun (a : Model.t) (b : Model.t) ->
              a.Model.checked = b.Model.checked)
            (fun (m : Model.t) ->
              button ~variant:"outline" ~text:"Action chip"
                ~selected:m.Model.checked ~disabled:(reactive disabled)
                ~on_press:(press send Model.ToggleDisabled) [])
            model_source
        ]
    ; paragraph
        ~value:"Groups own native layout and focus navigation; each child owns its event and selection state."
        []
    ]

(* Navigation *)

let breadcrumb_section send : t =
  section "Breadcrumb"
    [ breadcrumb ~accessibility_identifier:"Component path"
        [ text ~value:"Gallery" ~foreground:"muted-foreground"
            ~on_press:(press send (Model.SelectTab "overview")) []
        ; icon ~name:"chevron-right" ~size:"sm"
            ~foreground:"muted-foreground" []
        ; text ~value:"Navigation" []
        ]
    ]

let pagination_section model_source send : t =
  let disabled = model_source >|= Model.disabled in
  let tab_button ~text tab =
    dyn
      ~equal:(fun (a : Model.t) (b : Model.t) ->
        a.Model.tab = b.Model.tab && a.Model.disabled = b.Model.disabled)
      (fun (m : Model.t) ->
        button ~variant:"outline" ~text ~selected:(m.Model.tab = tab)
          ~disabled:m.Model.disabled
          ~on_press:(press send (Model.SelectTab tab)) [])
      model_source
  in
  section "Pagination"
    [ pagination ~accessibility_identifier:"Gallery pages"
        [ button ~variant:"ghost" ~icon:"chevron-left" ~text:"Previous"
            ~disabled:(reactive disabled)
            ~on_press:(press send (Model.SelectTab "overview")) []
        ; tab_button ~text:"1" "overview"
        ; icon ~name:"ellipsis" ~foreground:"muted-foreground" []
        ; tab_button ~text:"2" "activity"
        ; button ~variant:"ghost" ~icon:"chevron-right"
            ~icon_placement:"trailing" ~text:"Next"
            ~disabled:(reactive disabled)
            ~on_press:(press send (Model.SelectTab "activity")) []
        ]
    ; paragraph
        ~value:"Pagination composes native buttons around shared model-owned selection."
        []
    ]

let tabs_buttons model_source send =
  let disabled = model_source >|= Model.disabled in
  let tab_button ~text tab =
    dyn
      ~equal:(fun (a : Model.t) (b : Model.t) -> a.Model.tab = b.Model.tab)
      (fun (m : Model.t) ->
        button ~text ~selected:(m.Model.tab = tab)
          ~disabled:(reactive disabled)
          ~on_press:(press send (Model.SelectTab tab)) [])
      model_source
  in
  [ tab_button ~text:"Overview" "overview"
  ; tab_button ~text:"Activity" "activity"
  ]

let tabs_section model_source send : t =
  section "Tabs"
    [ tabs ~label:"Workspace sections" (tabs_buttons model_source send)
    ; card ~padding:16
        [ paragraph
            ~value:(reactive Model.tab_content model_source) []
        ]
    ; tabs ~label:"Workspace sections vertical" ~orientation:"vertical"
        (tabs_buttons model_source send)
    ; paragraph
        ~value:"Tabs owns layout and platform presentation; Signals own selection and content."
        []
    ]

let bottom_tabs_section model_source send : t =
  let home = model_source >|= Model.home_bottom_tab_selected in
  let search = model_source >|= Model.search_bottom_tab_selected in
  let settings = model_source >|= Model.settings_bottom_tab_selected in
  section "BottomTabs"
    [ bottom_tabs ~label:"Primary destinations"
        [ bottom_tab ~title:"Home" ~icon:"folder"
            ~selected:(reactive home)
            ~on_press:(press send (Model.SelectBottomTab "home"))
            [ column ~gap:12 ~padding:20
                [ heading ~level:3 ~value:"Home" []
                ; input ~label:"Draft" ~placeholder:"Retained home draft" []
                ; paragraph
                    ~value:"This input stays mounted while another destination is active."
                    []
                ]
            ]
        ; bottom_tab ~title:"Search" ~icon:"search"
            ~selected:(reactive search)
            ~on_press:(press send (Model.SelectBottomTab "search"))
            [ column ~gap:12 ~padding:20
                [ heading ~level:3 ~value:"Search" []
                ; paragraph
                    ~value:"Search uses the same retained destination model." []
                ]
            ]
        ; bottom_tab ~title:"Settings" ~icon:"settings"
            ~selected:(reactive settings)
            ~on_press:(press send (Model.SelectBottomTab "settings"))
            [ column ~gap:12 ~padding:20
                [ heading ~level:3 ~value:"Settings" []
                ; paragraph
                    ~value:"Platform chrome changes without rebuilding this page." []
                ]
            ]
        ]
    ; paragraph
        ~value:"Apple maps this component to TabView; Android maps it to Material NavigationBar."
        []
    ]

(* Status and indicators *)

let separator_section : t =
  section "Separator"
    [ paragraph ~value:"Horizontal" []
    ; separator []
    ; row ~gap:12
        [ text ~value:"Left" []
        ; separator ~orientation:"vertical" []
        ; text ~value:"Right" []
        ]
    ]

let spinner_section : t =
  section "Spinner"
    [ row ~gap:16 ~cross:"center"
        [ spinner ~size:"sm" []
        ; spinner []
        ; spinner ~size:"lg" []
        ; spinner ~size:"icon" []
        ]
    ]

let icon_section : t =
  section "Icon"
    [ paragraph
        ~value:"Common actions, navigation, status, files, and media" []
    ; row ~gap:16 ~cross:"center"
        [ icon ~name:"search" ~size:"sm" []
        ; icon ~name:"check-circle" []
        ; icon ~name:"git-pull-request" []
        ; icon ~name:"folder-open" []
        ; icon ~name:"play" []
        ; icon ~name:"settings" []
        ; icon ~name:"trash" ~size:"lg" ~foreground:"destructive" []
        ]
    ]

let progress_section model_source send : t =
  let progress_value = model_source >|= Model.progress in
  section "Progress"
    [ paragraph ~value:"Uploading files" []
    ; progress ~value:(reactive progress_value) ~width:280 []
    ; text ~value:(reactive Model.progress_label model_source) []
    ; button ~variant:"outline" ~text:"Advance progress"
        ~on_press:(press send Model.AdvanceProgress) []
    ]

let stepper_steps =
  [ step ~text:"Draft" []
  ; step ~text:"Review" []
  ; step ~text:"Ship" []
  ]

let stepper_section model_source send : t =
  let active = model_source >|= Model.active_step in
  section "Stepper"
    [ stepper ~active:(reactive active) ~label:"Release progress"
        stepper_steps
    ; button ~variant:"outline" ~text:"Advance stage"
        ~on_press:(press send Model.AdvanceStep) []
    ]

let step_section model_source : t =
  let active = model_source >|= Model.active_step in
  section "Step"
    [ stepper ~active:(reactive active) ~label:"Step states" stepper_steps
    ]

let timeline_section send : t =
  section "Timeline"
    [ timeline ~gap:4 ~label:"Release activity"
        [ timeline_item ~title:"Validated"
            ~description:"All platform checks passed" ~meta:"CI · 2m"
            ~icon:"check" ~variant:"primary"
            ~on_press:(press send Model.AdvanceStep) []
        ; timeline_item ~title:"Published"
            ~description:"Waiting for the next model action"
            ~connector:false []
        ]
    ]

let timeline_item_section send : t =
  section "TimelineItem"
    [ timeline ~gap:4 ~label:"Activity item"
        [ timeline_item ~title:"Validated"
            ~description:"One retained timeline row" ~meta:"CI · now"
            ~icon:"check" ~variant:"primary" ~connector:false
            ~on_press:(press send Model.AdvanceStep) []
        ]
    ; paragraph
        ~value:"TimelineItem owns its content and interaction inside Timeline." []
    ]

(* Surfaces *)

let stack_section : t =
  section "Stack"
    [ stack ~width:320 ~height:96
        [ panel ~padding:16 [ text ~value:"Stack base layer" [] ]
        ; text ~padding:16 ~value:"Overlay layer" []
        ]
    ]

let panel_section : t =
  section "Panel"
    [ panel ~padding:16
        [ column ~gap:8
            [ text ~value:"Panel" []
            ; paragraph
                ~value:"A raised overlay surface with explicit content padding." []
            ]
        ]
    ]

let card_section model_source : t =
  section "Card"
    [ card
        [ column ~gap:12
            [ text ~value:"Card" []
            ; paragraph
                ~value:(reactive Model.document_action model_source) []
            ; button ~text:"Save changes" ~on_press:noop []
            ]
        ]
    ]

let alert_section : t =
  section "Alert"
    [ alert ~text:"Sync paused" ~variant:"secondary"
        [ paragraph ~value:"Reconnect to resume model-owned updates." [] ]
    ]

let bubble_section model_source : t =
  section "Bubble"
    [ row ~main:"end"
        [ bubble ~variant:"primary"
            [ paragraph
                ~value:(reactive Model.document_action model_source) []
            ]
        ]
    ]

let status_bar_section model_source : t =
  section "StatusBar"
    [ status_bar ~value:(reactive Model.document_action model_source)
        ~text_alignment:"end" []
    ]

let resizable_section : t =
  section "Resizable"
    [ row ~height:180
        [ resizable ~resizable_width:260 ~min_width:180 ~max_width:480
            ~padding:12 ~label:"Resizable sidebar"
            [ column
                [ text ~value:"Sidebar" ~foreground:"muted-foreground" []
                ; paragraph
                    ~value:"Drag the right edge; unrelated Signal patches keep its native width."
                    []
                ]
            ]
        ]
    ; paragraph
        ~value:"Width seeds backend-owned geometry; a changed width source explicitly resets it."
        []
    ]

let split_section model_source send : t =
  let fraction = model_source >|= Model.split_fraction in
  section "Split"
    [ split ~value:(reactive fraction) ~gap:8 ~height:220
        ~resize_duration:180 ~resize_easing:"standard"
        ~label:"Gallery workspace"
        ~on_resize:(value_changed send (fun v -> Model.SetSplitFraction v))
        [ panel ~min_width:96 ~padding:16
            [ column ~gap:8
                [ text ~value:"Sidebar" []
                ; paragraph
                    ~value:"Drag, use arrow keys, or adjust with assistive controls." []
                ]
            ]
        ; panel ~min_width:140 ~padding:16
            [ column ~gap:8
                [ text ~value:"Content" []
                ; paragraph
                    ~value:"The shared model echoes the effective pane fraction." []
                ]
            ]
        ]
    ; paragraph
        ~value:"Exactly two retained panes share one model-owned divider fraction." []
    ]

(* Overlays *)

let dialog_section model_source send : t =
  let open_ = model_source >|= Model.dialog_open in
  section "Dialog"
    [ button ~variant:"outline" ~text:"Open dialog"
        ~on_press:(press send Model.OpenDialog) []
    ; paragraph
        ~value:"The same model-owned conditional drives the native modal on every host."
        []
    ; if_ ~test:open_
        (dialog ~text:"Rename note" ~width:380 ~height:240 ~padding:24
           ~on_dismiss:(press send Model.CloseDialog)
           [ column ~gap:16
               [ box ~height:24 []
               ; input ~placeholder:"Note name" ~autofocus:true []
               ; row ~gap:8 ~main:"end"
                   [ button ~variant:"ghost" ~text:"Cancel"
                       ~on_press:(press send Model.CloseDialog) []
                   ; button ~variant:"primary" ~text:"Save"
                       ~on_press:(press send Model.CloseDialog) []
                   ]
               ]
           ])
    ]

let sheet_section model_source send : t =
  let open_ = model_source >|= Model.sheet_open in
  section "Sheet"
    [ button ~variant:"outline" ~text:"Open sheet"
        ~on_press:(press send Model.OpenSheet) []
    ; paragraph
        ~value:"Sheet uses the host platform's native modal presentation." []
    ; if_ ~test:open_
        (sheet ~text:"Share" ~height:320 ~padding:24
           ~on_dismiss:(press send Model.CloseSheet)
           [ column ~gap:12
               [ box ~height:24 []
               ; paragraph
                   ~value:"Anyone with the link can view this showcase." []
               ; input ~placeholder:"Share link" []
               ; row ~gap:8 ~main:"end"
                   [ button ~variant:"ghost" ~text:"Cancel"
                       ~on_press:(press send Model.CloseSheet) []
                   ; button ~variant:"primary" ~text:"Done"
                       ~on_press:(press send Model.CloseSheet) []
                   ]
               ]
           ])
    ]

(* Lists *)

let list_section : t =
  section "List"
    [ list ~gap:8 ~cross:"stretch" ~max_width:480
        [ card ~padding:16 [ text ~value:"List item one" [] ]
        ; card ~padding:16 [ text ~value:"List item two" [] ]
        ; card ~padding:16 [ text ~value:"List item three" [] ]
        ]
    ]

let scroll_section : t =
  section "Scroll"
    [ scroll ~width:320 ~height:160
        [ list ~gap:8 ~cross:"stretch"
            [ card ~padding:16 [ text ~value:"Scrollable item one" [] ]
            ; card ~padding:16 [ text ~value:"Scrollable item two" [] ]
            ; card ~padding:16 [ text ~value:"Scrollable item three" [] ]
            ; card ~padding:16 [ text ~value:"Scrollable item four" [] ]
            ]
        ]
    ]

let list_item_section model_source send : t =
  let report = model_source >|= Model.report_selected in
  let checklist = model_source >|= Model.checklist_selected in
  let disabled = model_source >|= Model.disabled in
  section "ListItem"
    [ list ~gap:2 ~cross:"stretch" ~max_width:480
        [ list_item ~icon:"file-text" ~text:"Quarterly report.md"
            ~selected:(reactive report) ~disabled:(reactive disabled)
            ~on_press:(press send (Model.SelectDocument "Quarterly report.md"))
            ~on_double_press:(press send (Model.OpenDocument "Quarterly report.md"))
            ~on_submit:(press send (Model.OpenDocument "Quarterly report.md"))
            []
        ; list_item ~selected:(reactive checklist)
            ~disabled:(reactive disabled)
            ~on_press:(press send (Model.SelectDocument "Launch checklist.md"))
            ~on_double_press:(press send (Model.OpenDocument "Launch checklist.md"))
            ~on_submit:(press send (Model.OpenDocument "Launch checklist.md"))
            [ row ~gap:8 ~cross:"center"
                [ icon ~name:"check-circle" ~size:"sm" []
                ; text ~value:"Launch checklist.md" []
                ; spacer []
                ; text ~value:"Ready" ~foreground:"success" []
                ]
            ]
        ; list_item ~icon:"music" ~text:"demo-track.wav" ~disabled:true []
        ]
    ; paragraph ~value:(reactive Model.document_action model_source) []
    ; paragraph
        ~value:"Click selects immediately; double click and Enter run the primary action without replacing a row."
        []
    ]

let context_menu_section model_source send : t =
  let disabled = model_source >|= Model.disabled in
  section "ContextMenu"
    [ list ~gap:2 ~cross:"stretch" ~max_width:480
        [ list_item ~text:"Quarterly report.md"
            [ context_menu
                [ menu_item ~text:"Rename"
                    ~on_press:(press send (Model.PerformContextAction "Rename")) []
                ; separator []
                ; menu_item ~text:"Archive" ~disabled:(reactive disabled)
                    ~on_press:(press send (Model.PerformContextAction "Archive")) []
                ]
            ]
        ]
    ; paragraph ~value:(reactive Model.document_action model_source) []
    ; paragraph
        ~value:"Right click on desktop or long press on touch platforms; the deepest retained host owns the native menu."
        []
    ]

let menu_item_section model_source send : t =
  let disabled = model_source >|= Model.disabled in
  section "MenuItem"
    [ dropdown_menu ~min_width:200
        [ menu_item ~text:"Rename" ~icon:"edit"
            ~on_press:(press send (Model.PerformContextAction "Rename")) []
        ; menu_item ~text:"Share"
            [ dropdown_menu ~anchor:"right" ~anchor_offset:6.0
                [ menu_item ~text:"Copy link"
                    ~on_press:(press send (Model.PerformContextAction "Rename")) []
                ; menu_item ~text:"Export"
                    ~on_press:(press send (Model.PerformContextAction "Archive")) []
                ]
            ]
        ; menu_item ~text:"Archive" ~disabled:(reactive disabled)
            ~on_press:(press send (Model.PerformContextAction "Archive")) []
        ]
    ]

let table_section model_source send : t =
  let overview = model_source >|= Model.overview_tab_selected in
  let activity = model_source >|= Model.activity_tab_selected in
  let header_cell text_ =
    table_cell ~grow:1.0 ~size:"sm" ~foreground:"muted-foreground"
      ~text:text_ []
  in
  section "Table"
    [ table ~grow:1.0 ~max_width:520
        [ table_row ~gap:8
            [ header_cell "Invoice"
            ; header_cell "Status"
            ; table_cell ~grow:1.0 ~size:"sm"
                ~foreground:"muted-foreground" ~text_alignment:"end"
                ~text:"Amount" []
            ]
        ; table_row ~gap:8 ~selected:(reactive overview)
            [ table_cell ~grow:1.0 ~text:"INV-002"
                ~on_press:(press send (Model.SelectTab "overview")) []
            ; table_cell ~grow:1.0 ~text:"Pending" []
            ; table_cell ~grow:1.0 ~text_alignment:"end" ~text:"$150.00" []
            ]
        ; table_row ~gap:8 ~selected:(reactive activity)
            [ table_cell ~grow:1.0 ~text:"INV-003"
                ~on_press:(press send (Model.SelectTab "activity")) []
            ; table_cell ~grow:1.0 ~text:"Paid" []
            ; table_cell ~grow:1.0 ~text_alignment:"end" ~text:"$275.00" []
            ]
        ]
    ; paragraph
        ~value:"Press an invoice cell to patch only the selected retained rows." []
    ]

let table_row_section : t =
  section "TableRow"
    [ table ~grow:1.0 ~max_width:520
        [ table_row ~gap:8
            [ table_cell ~grow:1.0 ~text:"A retained row" []
            ; table_cell ~grow:1.0 ~text:"Two cells" []
            ]
        ]
    ]

let table_cell_section send : t =
  section "TableCell"
    [ table ~grow:1.0 ~max_width:520
        [ table_row ~gap:8
            [ table_cell ~grow:1.0 ~text:"Pressable cell"
                ~on_press:(press send (Model.SelectTab "overview")) []
            ]
        ]
    ]

let tree_section model_source send : t =
  let open_ = model_source >|= Model.accordion_open in
  let report = model_source >|= Model.report_selected in
  let checklist = model_source >|= Model.checklist_selected in
  section "Tree"
    [ tree ~gap:2 ~label:"Project files" ~max_width:480
        [ dyn
            ~equal:(fun (a : Model.t) (b : Model.t) ->
              a.Model.accordion_open = b.Model.accordion_open)
            (fun (m : Model.t) ->
              list_item ~role:"treeitem" ~tree_level:1 ~icon:"folder-open"
                ~text:"Documents" ~expanded:m.Model.accordion_open
                ~on_toggle:(on_toggle send (fun v -> Model.SetAccordionOpen v))
                ~on_press:(press send (Model.SelectDocument "Quarterly report.md"))
                [])
            model_source
        ; if_ ~test:open_
            (column ~padding_horizontal:20
               [ list_item ~role:"treeitem" ~tree_level:2 ~icon:"file-text"
                   ~text:"Quarterly report.md" ~selected:(reactive report)
                   ~on_press:(press send (Model.SelectDocument "Quarterly report.md"))
                   []
               ; list_item ~role:"treeitem" ~tree_level:2
                   ~text:"Launch checklist.md" ~selected:(reactive checklist)
                   ~on_press:(press send (Model.SelectDocument "Launch checklist.md"))
                   []
               ])
        ]
    ; paragraph
        ~value:"Arrow keys move one native focus set; Signals own disclosure and selection."
        []
    ]

(* Media *)

let avatar_section model_source send : t =
  let image = model_source >|= Model.avatar_image in
  section "Avatar"
    [ row ~gap:12 ~cross:"center"
        [ avatar ~text:"ZN" ~image:(reactive image)
            ~label:"Registered profile image" []
        ; avatar ~text:"CT" []
        ]
    ; button ~variant:"outline" ~text:"Toggle registered image"
        ~on_press:(press send Model.ToggleAvatarImage) []
    ; paragraph
        ~value:"The host owns image resources; changing the ImageId Signal retains the Avatar node."
        []
    ]

let image_section model_source : t =
  let resource = model_source >|= Model.media_surface in
  section "Image"
    [ image ~image:(reactive resource) ~width:160 ~height:96
        ~corner_radius:12 ~label:"Registered application icon" []
    ; paragraph ~value:"Image shares the host image registry." []
    ]

let media_surface_section model_source : t =
  let resource = model_source >|= Model.media_surface in
  section "MediaSurface"
    [ media_surface ~surface:(reactive resource) ~width:160 ~height:96
        ~corner_radius:12 ~label:"Producer-owned preview frame" []
    ; paragraph
        ~value:"MediaSurface keeps one SurfaceId while its producer replaces frames."
        []
    ]

(* Text inputs *)

let text_field_section model_source send : t =
  let value = model_source >|= Model.field_value in
  let disabled = model_source >|= Model.disabled in
  section "TextField"
    [ text_field ~text:(reactive value) ~label:"Project name"
        ~placeholder:"Project name" ~disabled:(reactive disabled)
        ~on_input:(on_input send (fun v -> Model.SetFieldValue v)) []
    ]

let input_section model_source send : t =
  let value = model_source >|= Model.field_value in
  let disabled = model_source >|= Model.disabled in
  section "Input"
    [ input ~text:(reactive value) ~label:"Email"
        ~placeholder:"you@example.com" ~disabled:(reactive disabled)
        ~on_input:(on_input send (fun v -> Model.SetFieldValue v)) []
    ]

let search_field_section model_source send : t =
  let value = model_source >|= Model.field_value in
  let disabled = model_source >|= Model.disabled in
  section "SearchField"
    [ search_field ~text:(reactive value) ~label:"Search components"
        ~placeholder:"Search components" ~disabled:(reactive disabled)
        ~on_input:(on_input send (fun v -> Model.SetFieldValue v)) []
    ]

let textarea_section model_source send : t =
  let value = model_source >|= Model.field_value in
  let disabled = model_source >|= Model.disabled in
  section "Textarea"
    [ textarea ~text:(reactive value) ~label:"Notes"
        ~placeholder:"Add notes" ~disabled:(reactive disabled)
        ~on_input:(on_input send (fun v -> Model.SetFieldValue v)) []
    ; paragraph
        ~value:"The native editor owns composition while the shared Signal retains its value."
        []
    ]

let input_group_section model_source send : t =
  let value = model_source >|= Model.field_value in
  let disabled = model_source >|= Model.disabled in
  section "InputGroup"
    [ input_group ~label:"Message composer" ~height:120 ~min_width:240
        [ textarea ~text:(reactive value) ~placeholder:"Message the team"
            ~disabled:(reactive disabled)
            ~on_input:(on_input send (fun v -> Model.SetFieldValue v)) []
        ; input_group_actions ~gap:8
            [ button ~variant:"ghost" ~icon:"plus" ~text:"Attach"
                ~disabled:(reactive disabled) ~on_press:noop []
            ; spacer ~grow:1.0 []
            ; button ~variant:"primary" ~icon:"send" ~text:"Send"
                ~disabled:(reactive disabled) ~on_press:noop []
            ]
        ]
    ; paragraph
        ~value:"The textarea and actions share one native focus surface while retaining their own nodes."
        []
    ]

let input_group_actions_section model_source send : t =
  let value = model_source >|= Model.field_value in
  let disabled = model_source >|= Model.disabled in
  section "InputGroupActions"
    [ input_group ~label:"Compact composer" ~min_width:240
        [ textarea ~text:(reactive value) ~placeholder:"Write a reply"
            ~disabled:(reactive disabled)
            ~on_input:(on_input send (fun v -> Model.SetFieldValue v)) []
        ; input_group_actions ~gap:8
            [ button ~variant:"ghost" ~icon:"plus" ~text:"Attach"
                ~disabled:(reactive disabled) ~on_press:noop []
            ; spacer ~grow:1.0 []
            ; button ~variant:"primary" ~icon:"send" ~text:"Send"
                ~disabled:(reactive disabled) ~on_press:noop []
            ]
        ]
    ]

(* Anchored overlays *)

let tooltip_section : t =
  section "Tooltip"
    [ row ~gap:16 ~cross:"center"
        [ stack
            [ button ~size:"icon" ~icon:"edit" ~label:"Edit document"
                ~variant:"outline" ~on_press:noop []
            ; tooltip ~text:"Edit this document" ~anchor:"above"
                ~anchor_alignment:"end" ~anchor_offset:8.0
                ~tooltip_delay:250 []
            ]
        ; tooltip ~text:"Saved" []
        ]
    ; paragraph
        ~value:"Hover, focus, or long-press the icon to reveal the native anchored Tooltip; the second Tooltip is a static status label."
        []
    ]

let toast_section model_source send : t =
  let open_ = model_source >|= Model.toast_open in
  section "Toast"
    [ button ~variant:"outline" ~text:"Show notifications"
        ~on_press:(press send Model.ShowToasts) []
    ; if_ ~test:open_
        (column
           [ toast ~duration:2000 ~label:"Draft saved"
               ~on_dismiss:(press send Model.CloseToasts)
               [ column ~gap:2
                   [ text ~value:(reactive Model.toast_message model_source) []
                   ; paragraph
                       ~value:(reactive Model.toast_description model_source) []
                   ]
               ; button ~variant:"outline" ~text:"Update notification"
                   ~on_press:(press send Model.UpdateToast) []
               ; button ~variant:"ghost" ~text:"Close"
                   ~on_press:(press send Model.CloseToasts) []
               ]
           ; toast ~duration:0 ~label:"Changes synced"
               ~on_dismiss:(press send Model.CloseToasts)
               [ column ~gap:2
                   [ text ~value:"Synced" []
                   ; paragraph
                       ~value:"Changes are available on every device" []
                   ]
               ; button ~variant:"ghost" ~text:"Close"
                   ~on_press:(press send Model.CloseToasts) []
               ]
           ])
    ; paragraph
        ~value:"Toasts share one application viewport, pause on interaction, and dismiss by timer or swipe."
        []
    ]

let toolbar_section model_source send : t =
  let value = model_source >|= Model.field_value in
  let checked = model_source >|= Model.checked in
  let disabled = model_source >|= Model.disabled in
  section "Toolbar"
    [ toolbar ~orientation:"horizontal" ~label:"Formatting" ~gap:4
        [ button ~variant:"ghost" ~text:"Bold" ~on_press:noop []
        ; button_group ~accessibility_identifier:"Text style"
            [ button ~variant:"ghost" ~text:"Italic" ~on_press:noop []
            ; button ~variant:"ghost" ~text:"Underline" ~on_press:noop []
            ]
        ; button ~variant:"ghost" ~text:"Redo" ~disabled:true ~on_press:noop []
        ; button ~variant:"ghost" ~text:"More" ~on_press:noop []
        ; input ~text:(reactive value) ~placeholder:"Format value"
            ~label:"Format value"
            ~on_input:(on_input send (fun v -> Model.SetFieldValue v)) []
        ]
    ; toolbar ~orientation:"vertical" ~label:"Insert" ~gap:4
        [ button ~variant:"ghost" ~text:"Link" ~on_press:noop []
        ; button ~variant:"ghost" ~text:"Image" ~on_press:noop []
        ; checkbox ~text:"Locked option" ~checked:(reactive checked)
            ~disabled:(reactive disabled) []
        ; select ~text:(reactive value) ~placeholder:"Locked picker"
            ~disabled:(reactive disabled) []
        ; input ~text:(reactive value) ~label:"Locked input"
            ~disabled:(reactive disabled) []
        ]
    ; paragraph
        ~value:"Toolbar composes ordinary controls and owns only orientation-aware roving focus."
        []
    ]

let accordion_section model_source send : t =
  let open_ = model_source >|= Model.accordion_open in
  section "Accordion"
    [ accordion ~text:"Do collapsed children stay retained?"
        ~selected:(sample open_)
        ~on_toggle:(on_toggle send (fun v -> Model.SetAccordionOpen v))
        [ paragraph
            ~value:"Yes. The native disclosure hides this content while LUI preserves its node identity."
            []
        ]
    ; paragraph
        ~value:"The shared Signal owns expansion while each backend uses its native disclosure widget."
        []
    ]

(* Pickers and menus *)

let environment_menu model_source send : t =
  let disabled = model_source >|= Model.disabled in
  let dismiss = press send Model.ClosePicker in
  dropdown_menu ~anchor:"below" ~anchor_alignment:"stretch"
    ~anchor_offset:6.0 ~min_width:200 ~on_dismiss:dismiss
    [ menu_item ~text:"Production" ~icon:"check"
        ~disabled:(reactive disabled)
        ~on_press:(press send (Model.SelectEnvironment "Production")) []
    ; menu_item ~text:"Staging" ~disabled:(reactive disabled)
        ~on_press:(press send (Model.SelectEnvironment "Staging")) []
    ; menu_item ~text:"More environments" ~disabled:(reactive disabled)
        [ dropdown_menu ~anchor:"right" ~anchor_alignment:"start"
            ~anchor_offset:4.0 ~min_width:180 ~on_dismiss:dismiss
            [ menu_item ~text:"Production region"
                ~on_press:(press send (Model.SelectEnvironment "Production")) []
            ; menu_item ~text:"Staging region"
                ~on_press:(press send (Model.SelectEnvironment "Staging")) []
            ]
        ]
    ; menu_item ~text:"Development" ~disabled:true []
    ]

let select_section model_source send : t =
  let environment = model_source >|= Model.environment in
  let open_ = model_source >|= Model.select_open in
  let disabled = model_source >|= Model.disabled in
  section "Select"
    [ stack
        [ select ~text:(reactive environment)
            ~disabled:(reactive disabled)
            ~on_press:(press send (Model.OpenPicker "select"))
            ~on_dismiss:(press send Model.ClosePicker) []
        ; if_ ~test:open_ (environment_menu model_source send)
        ]
    ; paragraph ~value:"Select opens a model-owned retained menu segment." []
    ]

let combobox_section model_source send : t =
  let query = model_source >|= Model.picker_query in
  let open_ = model_source >|= Model.combobox_open in
  let production_visible = model_source >|= Model.production_visible in
  let staging_visible = model_source >|= Model.staging_visible in
  let disabled = model_source >|= Model.disabled in
  let dismiss = press send Model.ClosePicker in
  section "Combobox"
    [ stack
        [ combobox ~text:(reactive query) ~placeholder:"Search environments"
            ~disabled:(reactive disabled)
            ~on_input:(on_input send (fun v -> Model.SetPickerQuery v))
            ~on_submit:(press send Model.CommitPickerQuery)
            ~on_press:(press send (Model.OpenPicker "combobox"))
            ~on_dismiss:dismiss []
        ; if_ ~test:open_
            (dropdown_menu ~anchor:"below" ~anchor_alignment:"stretch"
               ~anchor_offset:6.0 ~min_width:200 ~on_dismiss:dismiss
               [ if_ ~test:production_visible
                   (menu_item ~text:"Production" ~icon:"check"
                      ~disabled:(reactive disabled)
                      ~on_press:(press send (Model.SelectEnvironment "Production")) [])
               ; if_ ~test:staging_visible
                   (menu_item ~text:"Staging" ~disabled:(reactive disabled)
                      ~on_press:(press send (Model.SelectEnvironment "Staging")) [])
               ])
        ]
    ; row ~gap:8 ~cross:"center"
        [ text ~value:"Shared query:" []
        ; text ~value:(reactive query) []
        ]
    ; paragraph
        ~value:"Signals filter the retained options while the native input keeps focus and identity."
        []
    ]

let dropdown_menu_section model_source send : t =
  let _prod = model_source >|= Model.production_selected in
  let _stag = model_source >|= Model.staging_selected in
  section "DropdownMenu"
    [ environment_menu model_source send
    ; paragraph
        ~value:"DropdownMenu retains its MenuItem children while the host owns presentation."
        []
    ]

(* Toggles *)

let checkbox_section model_source send : t =
  let checked = model_source >|= Model.checked in
  let disabled = model_source >|= Model.disabled in
  section "Checkbox"
    [ checkbox ~text:"Enable notifications" ~checked:(reactive checked)
        ~disabled:(reactive disabled)
        ~on_toggle:(on_toggle send (fun v -> Model.SetChecked v)) []
    ; paragraph ~value:"Checkbox patches its retained native state in place." []
    ]

let switch_section model_source send : t =
  let checked = model_source >|= Model.checked in
  let disabled = model_source >|= Model.disabled in
  section "Switch"
    [ switch_ ~text:"Background sync" ~checked:(reactive checked)
        ~disabled:(reactive disabled)
        ~on_toggle:(on_toggle send (fun v -> Model.SetChecked v)) []
    ; paragraph ~value:"Switch shares the same model-owned Signal." []
    ]

let toggle_section model_source send : t =
  let checked = model_source >|= Model.checked in
  let disabled = model_source >|= Model.disabled in
  section "Toggle"
    [ toggle ~text:"Bold formatting" ~checked:(reactive checked)
        ~disabled:(reactive disabled)
        ~on_toggle:(on_toggle send (fun v -> Model.SetChecked v)) []
    ]

let radio_group_section model_source send : t =
  let comfortable = model_source >|= Model.density_comfortable in
  let compact = model_source >|= Model.density_compact in
  let disabled = model_source >|= Model.disabled in
  section "RadioGroup"
    [ radio_group ~label:"Content density"
        [ radio ~text:"Comfortable" ~checked:(reactive comfortable)
            ~disabled:(reactive disabled)
            ~on_change:(press send (Model.SetDensity "comfortable")) []
        ; radio ~text:"Compact" ~checked:(reactive compact)
            ~disabled:(reactive disabled)
            ~on_change:(press send (Model.SetDensity "compact")) []
        ]
    ]

let radio_section model_source send : t =
  let comfortable = model_source >|= Model.density_comfortable in
  let compact = model_source >|= Model.density_compact in
  let disabled = model_source >|= Model.disabled in
  section "Radio"
    [ radio_group ~label:"Individual radio choices"
        [ radio ~text:"Comfortable" ~checked:(reactive comfortable)
            ~disabled:(reactive disabled)
            ~on_change:(press send (Model.SetDensity "comfortable")) []
        ; radio ~text:"Compact" ~checked:(reactive compact)
            ~disabled:(reactive disabled)
            ~on_change:(press send (Model.SetDensity "compact")) []
        ]
    ]

let slider_section model_source send : t =
  let volume = model_source >|= Model.volume in
  let disabled = model_source >|= Model.disabled in
  section "Slider"
    [ paragraph ~value:(reactive Model.volume_label model_source) []
    ; slider ~value:(reactive volume) ~label:"Volume"
        ~disabled:(reactive disabled)
        ~on_change:(value_changed send (fun v -> Model.SetVolume v)) []
    ; paragraph
        ~value:"The model-owned Signal patches the retained native slider." []
    ]

(* Native extensions: mounted through the raw Lui_ui bridge so the
   section stays a plain gallery page on every other platform. *)

let native_extension_section : t =
 fun context parent ->
  let page =
    column ~gap:16 ~padding:32
      [ heading ~level:2 ~value:"Native Extensions" []
      ; paragraph
          ~value:"apple-map renders a real MapKit map; its marker children stay retained."
          []
      ]
  in
  let page_id = page context parent in
  let map = Lui_ui.extension context "apple-map" in
  Lui_ui.extension_property context map "latitude" (FloatValue 37.3349);
  Lui_ui.extension_property context map "longitude" (FloatValue (-122.0090));
  Lui_ui.extension_property context map "latitude-delta" (FloatValue 0.02);
  Lui_ui.extension_property context map "longitude-delta" (FloatValue 0.02);
  Lui_elements.attach context (Some page_id) map;
  let marker = Lui_ui.extension context "apple-map-marker" in
  Lui_ui.extension_property context marker "title" (StringValue "Apple Park");
  Lui_ui.extension_property context marker "latitude" (FloatValue 37.3349);
  Lui_ui.extension_property context marker "longitude" (FloatValue (-122.0090));
  Lui_elements.attach context (Some map) marker;
  page_id

let tweak_paragraph : t =
 fun context parent ->
  let node = Lui_ui.platform_tweak context "gallery-accent" in
  ignore
    (paragraph
       ~value:"A registered platform tweak wraps exactly one retained child."
       [] context (Some node));
  Lui_elements.attach context parent node;
  node

let view context model_source send : t =
  let sections =
    [ (* Maestro-tested components first, in .maestro/ios-components-interactions.yaml order *)
      button_section model_source send
    ; tabs_section model_source send
    ; dialog_section model_source send
    ; sheet_section model_source send
    ; tree_section model_source send
    ; tooltip_section
    ; text_field_section model_source send
    ; select_section model_source send
    ; combobox_section model_source send
    ; dropdown_menu_section model_source send
    ; checkbox_section model_source send
    ; switch_section model_source send
    ; toggle_section model_source send
    ; radio_group_section model_source send
    ; slider_section model_source send
    ; row_section
    ; column_section
    ; grid_section
    ; text_section
    ; spacer_section
    ; toggle_button_section model_source send
    ; button_group_section model_source send
    ; toggle_group_section model_source send
    ; breadcrumb_section send
    ; pagination_section model_source send
    ; bottom_tabs_section model_source send
    ; separator_section
    ; spinner_section
    ; icon_section
    ; progress_section model_source send
    ; stepper_section model_source send
    ; step_section model_source
    ; timeline_section send
    ; timeline_item_section send
    ; stack_section
    ; panel_section
    ; card_section model_source
    ; alert_section
    ; bubble_section model_source
    ; status_bar_section model_source
    ; resizable_section
    ; split_section model_source send
    ; list_section
    ; scroll_section
    ; list_item_section model_source send
    ; context_menu_section model_source send
    ; menu_item_section model_source send
    ; table_section model_source send
    ; table_row_section
    ; table_cell_section send
    ; avatar_section model_source send
    ; image_section model_source
    ; media_surface_section model_source
    ; input_section model_source send
    ; search_field_section model_source send
    ; textarea_section model_source send
    ; input_group_section model_source send
    ; input_group_actions_section model_source send
    ; toast_section model_source send
    ; toolbar_section model_source send
    ; accordion_section model_source send
    ; radio_section model_source send
    ]
  in
  let sections =
    match Lui_ui.platform context with
    | IOS | MacOS -> sections @ [ native_extension_section; tweak_paragraph ]
    | _ -> sections
  in
  column sections
