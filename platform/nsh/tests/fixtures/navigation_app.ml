(* Real desktop navigation and controlled Split qualification through the C ABI.
   Existing LUI controls own hover, focus and color transitions. Split changes
   deliberately snap (no resize duration): accepted model values must be visible
   immediately, including with reduced motion. Status text also updates without
   motion. This bounded fixture adds no overlay, timer or animation controller. *)
open Lui_elements

type model = {
  breadcrumb_requests : int;
  breadcrumb_last : string;
  page_requests : int;
  page : int;
  step_order : int list;
  active : int;
  timeline_revision : int;
  timeline_updated : bool;
  timeline_selected : int;
  accepts : bool;
  ratio : float;
  pixels : float;
  ratio_requests : int;
  pixel_requests : int;
  last_ratio : float;
  last_pixels : float;
  pane_order : int list;
  reorder_on_edit : bool;
  first_draft : string;
  second_draft : string;
  first_appears : int;
  second_appears : int;
}

type action =
  | Breadcrumb of string
  | Page of int
  | Advance_step
  | Reorder_steps
  | Update_timeline
  | Select_activity of int
  | Set_accepts of bool
  | Ratio_request of float
  | Pixel_request of float
  | Set_ratio
  | Set_pixels
  | Arm_reorder
  | Edit of int * string
  | Appeared of int

let initial = {
  breadcrumb_requests = 0; breadcrumb_last = "none";
  page_requests = 0; page = 1;
  step_order = [1; 2; 3]; active = 0;
  timeline_revision = 0; timeline_updated = false; timeline_selected = 1;
  accepts = false; ratio = 0.5; pixels = 240.;
  ratio_requests = 0; pixel_requests = 0; last_ratio = 0.; last_pixels = 0.;
  pane_order = [1; 2]; reorder_on_edit = false;
  first_draft = "first seed"; second_draft = "second seed";
  first_appears = 0; second_appears = 0;
}

let reverse_panes model =
  { model with pane_order = if model.pane_order = [1; 2] then [2; 1] else [1; 2] }

let finish_edit model =
  if model.reorder_on_edit then reverse_panes { model with reorder_on_edit = false }
  else model

let update model = function
  | Breadcrumb breadcrumb_last ->
      { model with breadcrumb_requests = model.breadcrumb_requests + 1; breadcrumb_last }
  | Page page -> { model with page_requests = model.page_requests + 1; page }
  | Advance_step -> { model with active = (model.active + 1) mod 3 }
  | Reorder_steps ->
      { model with step_order = if model.step_order = [1; 2; 3] then [3; 2; 1] else [1; 2; 3] }
  | Update_timeline ->
      { model with timeline_revision = model.timeline_revision + 1;
                   timeline_updated = not model.timeline_updated }
  | Select_activity timeline_selected ->
      { model with timeline_revision = model.timeline_revision + 1; timeline_selected }
  | Set_accepts accepts -> { model with accepts }
  | Ratio_request value ->
      { model with ratio_requests = model.ratio_requests + 1; last_ratio = value;
                   ratio = if model.accepts then value else model.ratio }
  | Pixel_request value ->
      { model with pixel_requests = model.pixel_requests + 1; last_pixels = value;
                   pixels = if model.accepts then value else model.pixels }
  | Set_ratio -> { model with ratio = 0.25 }
  | Set_pixels -> { model with pixels = 180. }
  | Arm_reorder -> { model with reorder_on_edit = true }
  | Edit (1, first_draft) -> finish_edit { model with first_draft }
  | Edit (2, second_draft) -> finish_edit { model with second_draft }
  | Appeared 1 -> { model with first_appears = model.first_appears + 1 }
  | Appeared 2 -> { model with second_appears = model.second_appears + 1 }
  | Edit _ | Appeared _ -> model

let value_changed send make = function
  | Lui_protocol.ValueChanged (_, value) -> ignore (send (make value))
  | _ -> ()

let pane_name = function 1 -> "First" | _ -> "Second"
let draft id model = if id = 1 then model.first_draft else model.second_draft
let stage_name = function 1 -> "Plan" | 2 -> "Build" | _ -> "Ship"

let pane model_source send item_source =
  (* The logical id is immutable within this keyed pane's mounted scope. *)
  let id = sample item_source in
  let name = pane_name id in
  column ~min_width:100 ~padding:8 ~gap:8
    ~accessibility_identifier:("navigation-pane-" ^ string_of_int id)
    ~on_appear:(fun _ -> ignore (send (Appeared id)))
    [ text ~value:(name ^ " pane") []
    ; text_field ~width:120 ~label:(name ^ " draft")
        ~accessibility_identifier:("navigation-editor-" ^ string_of_int id)
        ~text:(reactive (draft id) model_source)
        ~on_input:(on_input send (fun value -> Edit (id, value))) []
    ]

let activity model send =
  timeline ~label:"Build activity" ~accessibility_identifier:"navigation-timeline"
    [ timeline_item
        ~title:(if model.timeline_updated then "Recompiled" else "Compiled")
        ~description:(if model.timeline_updated then "Native compile verified" else "Native compile finished")
        ~meta:(if model.timeline_updated then "09:01" else "09:00")
        ~icon:(if model.timeline_updated then `check_circle else `clock)
        ~indicator:"legacy" ~variant:`primary
        ~selected:(model.timeline_selected = 1)
        ~on_press:(press send (Select_activity 1)) []
    ; timeline_item ~title:"Review" ~description:"Inspect the native result"
        ~meta:"09:02" ~indicator:"R" ~connector:false
        ~selected:(model.timeline_selected = 2)
        ~on_press:(press send (Select_activity 2)) []
    ]

let view _context model_source send =
  let control identifier label action =
    button ~accessibility_identifier:identifier ~text:label
      ~on_press:(press send action) []
  in
  let status identifier render =
    text ~accessibility_identifier:identifier ~value:(reactive render model_source) []
  in
  column ~padding:16 ~gap:8
    [ text ~value:"Navigation and Split qualification" []
    ; status "navigation-split-mode"
        (fun model -> if model.accepts then "Split mode accepting" else "Split mode refusing")
    ; status "navigation-ratio-state"
        (fun model -> Printf.sprintf "Ratio source %.3f requests %d last %.3f"
          model.ratio model.ratio_requests model.last_ratio)
    ; status "navigation-pixel-state"
        (fun model -> Printf.sprintf "Pixel source %.1f requests %d last %.1f"
          model.pixels model.pixel_requests model.last_pixels)
    ; status "navigation-pane-state"
        (fun model -> Printf.sprintf "Pane order %s appears First=%d Second=%d"
          (String.concat "," (List.map pane_name model.pane_order))
          model.first_appears model.second_appears)
    ; scroll ~height:500 ~width:680 ~accessibility_identifier:"navigation-scroll"
        [ column ~gap:16 ~padding:8
            [ text ~value:"Authored navigation" []
            ; breadcrumb ~label:"Workspace path"
                [ button ~text:"Workspace" ~autofocus:true
                    ~on_press:(press send (Breadcrumb "Workspace")) []
                ; button ~text:"Archived" ~disabled:true
                    ~on_press:(press send (Breadcrumb "Archived")) []
                ; button ~text:"Current" ~on_press:(press send (Breadcrumb "Current")) []
                ]
            ; status "navigation-breadcrumb-state"
                (fun model -> Printf.sprintf "Breadcrumb requests %d last %s"
                  model.breadcrumb_requests model.breadcrumb_last)
            ; pagination ~label:"Result pages"
                [ button ~text:"Page one" ~selected:(reactive (fun model -> model.page = 1) model_source)
                    ~on_press:(press send (Page 1)) []
                ; button ~text:"Unavailable page" ~disabled:true
                    ~on_press:(press send (Page 2)) []
                ; button ~text:"Page three" ~selected:(reactive (fun model -> model.page = 3) model_source)
                    ~on_press:(press send (Page 3)) []
                ]
            ; status "navigation-page-state"
                (fun model -> Printf.sprintf "Page source %d requests %d" model.page model.page_requests)
            ; row ~gap:8
                [ control "navigation-next-step" "Advance step" Advance_step
                ; control "navigation-reorder-steps" "Reorder stages" Reorder_steps
                ]
            ; stepper ~label:"Delivery stages" ~active:(reactive (fun model -> model.active) model_source)
                [ keyed_step ~source:(reactive (fun model -> model.step_order) model_source)
                    ~key:Fun.id ~cmp:Int.compare
                    ~mount:(fun item_source -> step ~text:(stage_name (sample item_source)) [])
                ]
            ; status "navigation-stage-state"
                (fun model -> Printf.sprintf "Stages %s active %d"
                  (String.concat "," (List.map stage_name model.step_order)) model.active)
            ; control "navigation-update-activity" "Update activity" Update_timeline
            ; status "navigation-activity-state"
                (fun model -> "Activity selected " ^ (if model.timeline_selected = 1 then "Compile" else "Review"))
            (* These public TimelineItem properties have no signal-taking twins.
               Reconcile only on activity edits, keeping unrelated editor events
               outside this bounded branch's equality boundary. *)
            ; reactive
                ~equal:(fun before after -> before.timeline_revision = after.timeline_revision)
                (fun model -> activity model send) model_source
            ; text ~value:"Controlled panes" []
            ; row ~gap:8
                [ control "navigation-accept" "Accept resize" (Set_accepts true)
                ; control "navigation-refuse" "Refuse resize" (Set_accepts false)
                ; control "navigation-ratio-quarter" "Set ratio quarter" Set_ratio
                ]
            ; button ~accessibility_identifier:"navigation-arm-reorder"
                ~text:(reactive (fun model -> if model.reorder_on_edit then "Reorder armed" else "Reorder on next edit") model_source)
                ~on_press:(press send Arm_reorder) []
            ; text ~value:"Arm reorder, then edit either draft without leaving that editor." []
            ; split ~label:"Ratio layout" ~width:609 ~height:112 ~gap:9
                ~resize_handle_width:9 ~resize_handle_offset:0.
                ~accessibility_identifier:"navigation-ratio-split"
                ~value:(reactive (fun model -> model.ratio) model_source)
                ~on_resize:(value_changed send (fun value -> Ratio_request value))
                (keyed ~source:(reactive (fun model -> model.pane_order) model_source)
                   ~key:Fun.id ~cmp:Int.compare ~mount:(pane model_source send))
                (* One keyed source owns both direct panes. The second static
                   constructor slot mounts no node, so a reorder is one move. *)
                (dynamic (fun _context _parent -> ()))
            ; status "navigation-first-model" (fun model -> "First model " ^ model.first_draft)
            ; status "navigation-second-model" (fun model -> "Second model " ^ model.second_draft)
            ; control "navigation-pixel-180" "Set first pane 180" Set_pixels
            ; split ~label:"Pixel layout" ~width:609 ~height:80 ~gap:9
                ~resize_handle_width:9 ~resize_handle_offset:0.
                ~accessibility_identifier:"navigation-pixel-split"
                ~first_width:(reactive (fun model -> model.pixels) model_source)
                ~on_resize:(value_changed send (fun value -> Pixel_request value))
                (column ~min_width:100 ~padding:8 [text ~value:"Pixel first pane" []])
                (column ~min_width:100 ~padding:8 [text ~value:"Pixel second pane" []])
            ]
        ]
    ]

let bridge = Lui_native_bridge.create "Navigation and Split qualification"
let initialize platform_code host_code =
  let backend = Lui_native_bridge.backend bridge
    (Lui_native_bridge.profile platform_code host_code) in
  let app = Lui_app.create backend initial update view in
  Lui_native_bridge.boot bridge app

let () =
  Callback.register "lui_ocaml_init" initialize;
  Lui_native_bridge.register ~register_named:Callback.register "lui_ocaml" bridge
