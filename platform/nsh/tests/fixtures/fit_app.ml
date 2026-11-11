(* Real native layout selects these retained OCaml alternatives through the C ABI. *)
open Lui_elements

type model = {
  visible : bool;
  short_vertical : bool;
  main_draft : string;
  wide_draft : string;
  compact_draft : string;
  wide_appears : int;
  compact_appears : int;
  vertical_appears : int;
  vertical_fallback_appears : int;
  after_actions : int;
}

type action =
  | Visibility of bool
  | Short_vertical
  | Edit_main of string
  | Edit_wide of string
  | Edit_compact of string
  | Appeared of int
  | After_action

let initial = {
  visible = true; short_vertical = false;
  main_draft = "main seed"; wide_draft = "wide seed"; compact_draft = "compact seed";
  wide_appears = 0; compact_appears = 0;
  vertical_appears = 0; vertical_fallback_appears = 0;
  after_actions = 0;
}

let update model = function
  | Visibility visible -> { model with visible }
  | Short_vertical -> { model with short_vertical = true }
  | Edit_main main_draft -> { model with main_draft }
  | Edit_wide wide_draft -> { model with wide_draft }
  | Edit_compact compact_draft -> { model with compact_draft }
  | Appeared 1 -> { model with wide_appears = model.wide_appears + 1 }
  | Appeared 2 -> { model with compact_appears = model.compact_appears + 1 }
  | Appeared 3 -> { model with vertical_appears = model.vertical_appears + 1 }
  | Appeared 4 -> { model with vertical_fallback_appears = model.vertical_fallback_appears + 1 }
  | Appeared _ -> model
  | After_action -> { model with after_actions = model.after_actions + 1 }

let view _context model_source send =
  let control label action =
    button ~text:label ~on_press:(press send action) []
  in
  let status identifier render =
    text ~accessibility_identifier:identifier ~value:(reactive render model_source) []
  in
  let candidate ~key ~width ~label ~draft ~edit ~appeared =
    column ~key ~width ~height:96 ~padding:8 ~gap:4
      ~on_appear:(fun _ -> ignore (send (Appeared appeared)))
      [ text ~value:label []
      ; text_field ~label:(label ^ " draft")
          ~accessibility_identifier:("fit-editor-" ^ key)
          ~text:(reactive draft model_source)
          ~on_input:(on_input send edit) []
      ]
  in
  column ~padding:16 ~gap:8
    [ text ~value:"ViewThatFits native qualification" []
    ; row ~gap:8
        [ control "Hide feedback" (Visibility false)
        ; control "Show feedback" (Visibility true)
        ; control "Short vertical" Short_vertical
        ]
    ; status "fit-visible" (fun model -> if model.visible then "Feedback shown" else "Feedback hidden")
    ; status "fit-appears" (fun model -> Printf.sprintf "Fit appears wide=%d compact=%d" model.wide_appears model.compact_appears)
    ; status "fit-vertical-appears" (fun model -> Printf.sprintf "Vertical appears preferred=%d fallback=%d" model.vertical_appears model.vertical_fallback_appears)
    ; status "fit-main-model" (fun model -> "Main model " ^ model.main_draft)
    ; status "fit-wide-model" (fun model -> "Wide model " ^ model.wide_draft)
    ; status "fit-compact-model" (fun model -> "Compact model " ^ model.compact_draft)
    ; status "fit-after-actions" (fun model -> Printf.sprintf "After actions %d" model.after_actions)
    ; edge_inset ~key:"journal-feedback" ~edge:`top ~height:430 ~gap:0
        ~background:"bar" ~visible:(reactive (fun model -> model.visible) model_source)
        [ column ~padding:8 ~gap:8
            [ text ~value:"Main body stays visible" []
            ; text_field ~label:"Main draft" ~accessibility_identifier:"fit-main-editor"
                ~text:(reactive (fun model -> model.main_draft) model_source)
                ~on_input:(on_input send (fun value -> Edit_main value)) []
            ; view_that_fits ~key:"vertical-fit" ~orientation:`vertical ~width:280 ~height:110
                [ column ~key:"vertical-preferred" ~width:280
                    ~on_appear:(fun _ -> ignore (send (Appeared 3)))
                    [ text ~value:(reactive (fun model ->
                        if model.short_vertical then "Short vertical candidate"
                        else String.concat "\n" (List.init 12 (fun index -> Printf.sprintf "Tall vertical line %d" index))) model_source) [] ]
                ; column ~key:"vertical-fallback" ~width:280 ~height:48
                    ~on_appear:(fun _ -> ignore (send (Appeared 4)))
                    [ text ~value:"Vertical fallback" [] ]
                ]
            ]
        ; view_that_fits ~key:"horizontal-fit" ~orientation:`horizontal
            [ candidate ~key:"wide" ~width:640 ~label:"Wide feedback"
                ~draft:(fun model -> model.wide_draft) ~edit:(fun value -> Edit_wide value) ~appeared:1
            ; candidate ~key:"compact" ~width:280 ~label:"Compact feedback"
                ~draft:(fun model -> model.compact_draft) ~edit:(fun value -> Edit_compact value) ~appeared:2
            ]
        ]
    ; control "After feedback" After_action
    ]

let bridge = Lui_native_bridge.create "ViewThatFits native qualification"
let initialize platform_code host_code =
  let backend = Lui_native_bridge.backend bridge
    (Lui_native_bridge.profile platform_code host_code) in
  let app = Lui_app.create backend initial update view in
  Lui_native_bridge.boot bridge app

let () =
  Callback.register "lui_ocaml_init" initialize;
  Lui_native_bridge.register ~register_named:Callback.register "lui_ocaml" bridge
