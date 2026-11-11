(* Real native focus and input events cross the existing OCaml C ABI. *)
open Lui_elements

type field = Primary | Optional | Outside | Paragraph

type value = { draft : string; saved : string; saves : int; node : int; previous_requests : int; next_requests : int }
type model = {
  primary : value; optional : value; outside : value; paragraph : value;
  optional_blur : bool; disabled : bool; disable_on_edit : bool; mounts : int;
}
type action =
  | Edit of field * string
  | Save of field
  | Navigate of field * bool
  | Mounted of field * int
  | Optional_blur of bool
  | Arm_disable
  | Enable

let value draft = { draft; saved = "none"; saves = 0; node = 0; previous_requests = 0; next_requests = 0 }
let initial = {
  primary = value "primary seed"; optional = value "optional seed";
  outside = value "outside seed"; paragraph = value "paragraph seed";
  optional_blur = false; disabled = false; disable_on_edit = false; mounts = 0;
}
let get field model = match field with
  | Primary -> model.primary | Optional -> model.optional
  | Outside -> model.outside | Paragraph -> model.paragraph
let change field f model = match field with
  | Primary -> { model with primary = f model.primary }
  | Optional -> { model with optional = f model.optional }
  | Outside -> { model with outside = f model.outside }
  | Paragraph -> { model with paragraph = f model.paragraph }
let update model = function
  | Edit (field, draft) ->
      let next = change field (fun value -> { value with draft }) model in
      if field = Primary && model.disable_on_edit
      then { next with disabled = true; disable_on_edit = false } else next
  | Save field ->
      change field (fun value -> { value with saved = value.draft; saves = value.saves + 1 }) model
  | Navigate (field, previous) ->
      change field (fun value ->
        if previous then { value with previous_requests = value.previous_requests + 1 }
        else { value with next_requests = value.next_requests + 1 }) model
  | Mounted (field, node) ->
      let next = change field (fun value -> { value with node }) model in
      { next with mounts = model.mounts + 1 }
  | Optional_blur optional_blur -> { model with optional_blur }
  | Arm_disable -> { model with disable_on_edit = true }
  | Enable -> { model with disabled = false; disable_on_edit = false }

let view context model_source send =
  let optional_node = ref None in
  let mounted field = function
    | Lui_protocol.Appear node ->
        if field = Optional then optional_node := Some node;
        ignore (send (Mounted (field, node)))
    | _ -> ()
  in
  (* Exercise the existing public property writer on an initially authored
     false option. No fixture-only production callback or signal API is added. *)
  let set_optional enabled _event =
    match !optional_node with
    | None -> invalid_arg "Optional Input has not appeared"
    | Some node ->
        Lui_ui.bool_property context node Lui_protocol.SubmitOnBlur enabled;
        ignore (send (Optional_blur enabled))
  in
  let navigate field = function
    | Lui_protocol.NavigatePrevious _ -> ignore (send (Navigate (field, true)))
    | Lui_protocol.NavigateNext _ -> ignore (send (Navigate (field, false)))
    | _ -> ()
  in
  let status identifier render =
    text ~accessibility_identifier:identifier ~value:(reactive render model_source) []
  in
  let summary title field model =
    let value = get field model in
    Printf.sprintf "%s saves %d text %s" title value.saves value.saved
  in
  column ~padding:16 ~gap:8
    [ text ~value:"Native Input blur qualification" []
    ; column ~gap:2
        [ text ~value:"Primary: Enter or leaving the field saves once" []
        ; input ~key:"primary" ~label:"Primary value" ~submit_on_blur:true
            ~accessibility_identifier:"input-primary"
            ~disabled:(reactive (fun model -> model.disabled) model_source)
            ~text:(reactive (fun model -> model.primary.draft) model_source)
            ~on_input:(on_input send (fun text -> Edit (Primary, text)))
            ~on_submit:(press send (Save Primary)) ~on_navigate:(navigate Primary) ~on_appear:(mounted Primary) []
        ; text ~value:"Optional: blur saving starts disabled" []
        ; text_field ~key:"optional" ~label:"Optional value" ~submit_on_blur:false
            ~accessibility_identifier:"input-optional"
            ~text:(reactive (fun model -> model.optional.draft) model_source)
            ~on_input:(on_input send (fun text -> Edit (Optional, text)))
            ~on_submit:(press send (Save Optional)) ~on_navigate:(navigate Optional) ~on_appear:(mounted Optional) []
        ; text ~value:"Outside: independent draft, ordinary native defaults" []
        ; text_field ~key:"outside" ~label:"Outside value"
            ~accessibility_identifier:"input-outside"
            ~text:(reactive (fun model -> model.outside.draft) model_source)
            ~on_input:(on_input send (fun text -> Edit (Outside, text)))
            ~on_appear:(mounted Outside) []
        ; text ~value:"Paragraph: Enter saves and keeps focus; leaving saves again" []
        ; textarea ~key:"paragraph" ~label:"Paragraph value" ~height:80
            ~accessibility_identifier:"input-paragraph" ~submit_on_blur:true ~submit_on_enter:true
            ~text:(reactive (fun model -> model.paragraph.draft) model_source)
            ~on_input:(on_input send (fun text -> Edit (Paragraph, text)))
            ~on_submit:(press send (Save Paragraph)) ~on_appear:(mounted Paragraph) []
        ]
    ; row ~gap:8
        [ button ~text:"Enable optional blur" ~on_press:(set_optional true) []
        ; button ~text:"Disable optional blur" ~on_press:(set_optional false) []
        ; button ~text:"Arm disable on edit" ~on_press:(press send Arm_disable) []
        ; button ~text:"Enable primary" ~on_press:(press send Enable) []
        ]
    ; status "input-primary-navigation" (fun model -> Printf.sprintf "Primary navigation previous=%d next=%d" model.primary.previous_requests model.primary.next_requests)
    ; status "input-optional-navigation" (fun model -> Printf.sprintf "Optional navigation previous=%d next=%d" model.optional.previous_requests model.optional.next_requests)
    ; status "input-policy" (fun model -> if model.optional_blur then "Optional policy on" else "Optional policy off")
    ; status "input-enabled" (fun model -> if model.disabled then "Primary disabled" else "Primary enabled")
    ; status "input-disable-arm" (fun model -> if model.disable_on_edit then "Disable on edit armed" else "Disable on edit idle")
    ; status "input-primary-model" (fun model -> "Primary draft " ^ model.primary.draft)
    ; status "input-primary-saves" (summary "Primary" Primary)
    ; status "input-optional-saves" (summary "Optional" Optional)
    ; status "input-paragraph-saves" (summary "Paragraph" Paragraph)
    ; status "input-optional-model" (fun model -> "Optional draft " ^ model.optional.draft)
    ; status "input-outside-model" (fun model -> "Outside draft " ^ model.outside.draft)
    ; status "input-paragraph-model" (fun model -> "Paragraph draft " ^ model.paragraph.draft)
    ; status "input-mounts" (fun model -> Printf.sprintf
        "Mounted primary=%d optional=%d outside=%d paragraph=%d count=%d"
        model.primary.node model.optional.node model.outside.node model.paragraph.node model.mounts)
    ]

let bridge = Lui_native_bridge.create "Native Input blur qualification"
let initialize platform_code host_code =
  let backend = Lui_native_bridge.backend bridge
    (Lui_native_bridge.profile platform_code host_code) in
  let app = Lui_app.create backend initial update view in
  Lui_native_bridge.boot bridge app

let () =
  Callback.register "lui_ocaml_init" initialize;
  Lui_native_bridge.register ~register_named:Callback.register "lui_ocaml" bridge
