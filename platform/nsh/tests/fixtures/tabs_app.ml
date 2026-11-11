(* Real native tab controllers drive this OCaml model through the desktop C ABI. *)
open Lui_elements

type model = {
  order : int list;
  selected : int option;
  accepts : bool;
  requests : int;
  last_request : int;
  home_draft : string;
  search_draft : string;
  home_actions : int;
  search_actions : int;
  home_appears : int;
  search_appears : int;
}

type action =
  | Set_accepts of bool
  | Select of int
  | Reorder
  | Edit of int * string
  | Page_action of int
  | Appeared of int

let initial = {
  order = [1; 2; 3]; selected = None; accepts = false;
  requests = 0; last_request = 0;
  home_draft = "home seed"; search_draft = "search seed";
  home_actions = 0; search_actions = 0;
  home_appears = 0; search_appears = 0;
}

let title = function 1 -> "Home" | 2 -> "Disabled" | 3 -> "Search" | _ -> "Unknown"
let slug = function 1 -> "home" | 2 -> "disabled" | 3 -> "search" | _ -> "unknown"
let draft id model = if id = 1 then model.home_draft else model.search_draft

let update model = function
  | Set_accepts accepts -> { model with accepts }
  | Select id ->
      let requested = { model with requests = model.requests + 1; last_request = id } in
      if model.accepts && id <> 2 then { requested with selected = Some id }
      else requested
  | Reorder ->
      { model with order = if model.order = [1; 2; 3] then [3; 2; 1] else [1; 2; 3] }
  | Edit (1, home_draft) -> { model with home_draft }
  | Edit (3, search_draft) -> { model with search_draft }
  | Page_action 1 -> { model with home_actions = model.home_actions + 1 }
  | Page_action 3 -> { model with search_actions = model.search_actions + 1 }
  | Appeared 1 -> { model with home_appears = model.home_appears + 1 }
  | Appeared 3 -> { model with search_appears = model.search_appears + 1 }
  | Edit _ | Page_action _ | Appeared _ -> model

let destination model_source send item_source =
  (* The keyed source's logical id is immutable for this mounted destination. *)
  let id = sample item_source in
  let name = title id in
  let body =
    if id = 2 then
      column ~padding:8
        [ text ~value:"Disabled destination content" [] ]
    else
      column ~padding:8 ~gap:8
        ~accessibility_identifier:("tabs-body-" ^ slug id)
        ~on_appear:(fun _ -> ignore (send (Appeared id)))
        [ text ~value:(name ^ " content") []
        ; text_field ~label:(name ^ " draft")
            ~accessibility_identifier:("tabs-editor-" ^ slug id)
            ~text:(reactive (draft id) model_source)
            ~on_input:(on_input send (fun value -> Edit (id, value))) []
        ; button ~text:(name ^ " action")
            ~accessibility_identifier:("tabs-action-" ^ slug id)
            ~on_press:(press send (Page_action id)) []
        ]
  in
  bottom_tab ~title:name ~enabled:(id <> 2)
    ~accessibility_identifier:("tabs-page-" ^ slug id)
    ~icon:(if id = 1 then `folder else if id = 2 then `settings else `search)
    ~selected:(reactive (fun model -> model.selected = Some id) model_source)
    ~on_press:(press send (Select id)) [body]

let view _context model_source send =
  let control identifier label action =
    button ~accessibility_identifier:identifier ~text:label
      ~on_press:(press send action) []
  in
  column ~padding:16 ~gap:8
    [ text ~value:"BottomTabs qualification" []
    ; row ~gap:8
        [ control "tabs-accept" "Accept" (Set_accepts true)
        ; control "tabs-refuse" "Refuse" (Set_accepts false)
        ; control "tabs-reorder" "Reorder" Reorder
        ]
    ; column ~gap:2
        [ text ~accessibility_identifier:"tabs-mode"
            ~value:(reactive (fun model -> if model.accepts then "Mode accepting" else "Mode refusing") model_source) []
        ; text ~accessibility_identifier:"tabs-requests"
            ~value:(reactive (fun model -> Printf.sprintf "Requests %d last=%d" model.requests model.last_request) model_source) []
        ; text ~accessibility_identifier:"tabs-order"
            ~value:(reactive (fun model -> "Order " ^ String.concat "," (List.map title model.order)) model_source) []
        ; text ~accessibility_identifier:"tabs-home-model"
            ~value:(reactive (fun model -> "Home model " ^ model.home_draft) model_source) []
        ; text ~accessibility_identifier:"tabs-search-model"
            ~value:(reactive (fun model -> "Search model " ^ model.search_draft) model_source) []
        ; text ~accessibility_identifier:"tabs-page-actions"
            ~value:(reactive (fun model -> Printf.sprintf "Page actions Home=%d Search=%d" model.home_actions model.search_actions) model_source) []
        ; text ~accessibility_identifier:"tabs-appears"
            ~value:(reactive (fun model -> Printf.sprintf "Page appears Home=%d Search=%d" model.home_appears model.search_appears) model_source) []
        ]
    ; bottom_tabs ~label:"Qualification destinations" ~height:280
        [ keyed_bottom_tab
            ~source:(reactive (fun model -> model.order) model_source)
            ~key:Fun.id ~cmp:Int.compare ~mount:(destination model_source send)
        ]
    ]

let bridge = Lui_native_bridge.create "BottomTabs qualification"
let initialize platform_code host_code =
  let backend = Lui_native_bridge.backend bridge
    (Lui_native_bridge.profile platform_code host_code) in
  let app = Lui_app.create backend initial update view in
  Lui_native_bridge.boot bridge app

let () =
  Callback.register "lui_ocaml_init" initialize;
  Lui_native_bridge.register ~register_named:Callback.register "lui_ocaml" bridge
