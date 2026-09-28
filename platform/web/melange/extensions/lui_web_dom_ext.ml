(* Generic raw-DOM extension family for the web backend: "lui-dom-<tag>"
   elements for attributes and DOM events the LUI schema does not cover
   (blockid, data-*, pointer/keyboard edge cases).

   The element tag is encoded in the identifier ("lui-dom-a" -> <a>)
   because adapter create runs before any SetExtensionProp op.

   Extension props:
     attrs  — JSON object {name: value} applied via setAttribute
     events — space-separated DOM event names to listen for
     text   — textContent (or .value for input/textarea/select)
     style-class / accessibility-identifier — same as standard props

   Emits one event kind:
     dom-event {name: string, payload: JSON string of event fields}
   The payload serializes key/code/data/inputType, modifier flags,
   pointer coordinates, target.value/checked/id/className, and for text
   controls target.selectionStart/selectionEnd/selectionDirection so apps
   can implement caret-edge behaviors without extra DOM round-trips. *)

open Lui_protocol
open Lui_web_types
module W = Webapi.Dom

type emit_fn = string -> wire_value String_map.t -> unit
type handler_tbl = (string, Js.Json.t -> unit) Hashtbl.t

external parse_json : string -> Js.Json.t = "parse" [@@mel.scope "JSON"]

external obj_keys : Js.Json.t -> string array = "keys" [@@mel.scope "Object"]

external json_get : Js.Json.t -> string -> Js.Json.t Js.Undefined.t = ""
  [@@mel.get_index]

external prop_undef : Js.Json.t -> string -> 'a Js.Undefined.t = ""
  [@@mel.get_index]

external managed_get : W.Element.t -> string Js.Undefined.t = "__luiDomAttrs"
  [@@mel.get]

external managed_set : W.Element.t -> string -> unit = "__luiDomAttrs"
  [@@mel.set]

external emit_get : W.Element.t -> emit_fn Js.Undefined.t = "__luiDomEmit"
  [@@mel.get]

external emit_set : W.Element.t -> emit_fn -> unit = "__luiDomEmit"
  [@@mel.set]

external handlers_get : W.Element.t -> handler_tbl Js.Undefined.t =
  "__luiDomHandlers"
[@@mel.get]

external handlers_set : W.Element.t -> handler_tbl -> unit =
  "__luiDomHandlers"
[@@mel.set]

external set_value : W.Element.t -> string -> unit = "value" [@@mel.set]

external get_value : W.Element.t -> string = "value" [@@mel.get]

external add_listener :
  W.Element.t -> string -> (Js.Json.t -> unit) -> unit = "addEventListener"
  [@@mel.send]

external remove_listener :
  W.Element.t -> string -> (Js.Json.t -> unit) -> unit =
  "removeEventListener"
  [@@mel.send]

external prevent_default : Js.Json.t -> unit = "preventDefault" [@@mel.send]

let is_control_tag el =
  match String.lowercase_ascii (W.Element.tagName el) with
  | "input" | "textarea" | "select" -> true
  | _ -> false

(* -- attrs prop -- *)

let json_string v = Option.value (Js.Json.decodeString v) ~default:""

let apply_attrs el json =
  let prev =
    managed_get el
    |> Js.Undefined.toOption
    |> Option.value ~default:""
    |> String.split_on_char ','
    |> List.filter (fun s -> s <> "")
  in
  let obj = parse_json json in
  let keys = Array.to_list (obj_keys obj) in
  List.iter
    (fun k ->
      match Js.Undefined.toOption (json_get obj k) with
      | Some v -> W.Element.setAttribute k (json_string v) el
      | None -> ())
    keys;
  List.iter
    (fun k ->
      if not (List.mem k keys) then W.Element.removeAttribute k el)
    prev;
  managed_set el (String.concat "," keys)

(* -- events prop -- *)

let is_undefined_json v =
  match Js.Json.classify v with Js.Json.JSONFalse -> true | _ -> false

let put_target_fields d (t : Js.Json.t) =
  let put name v = if not (is_undefined_json v) then Js.Dict.set d name v in
  (match Js.Undefined.toOption (prop_undef t "value") with
   | Some v -> put "value" (Js.Json.string v)
   | None -> ());
  (match Js.Undefined.toOption (prop_undef t "checked") with
   | Some v -> put "checked" (Js.Json.boolean v)
   | None -> ());
  (match Js.Undefined.toOption (prop_undef t "id") with
   | Some v -> put "targetId" (Js.Json.string v)
   | None -> ());
  (match Js.Undefined.toOption (prop_undef t "className") with
   | Some v -> put "targetClass" (Js.Json.string v)
   | None -> ());
  (* caret/selection for text controls — lets apps implement caret-edge
     behaviors (e.g. arrow at boundary exits editing) from the payload *)
  List.iter
    (fun k ->
      match Js.Undefined.toOption (prop_undef t k) with
      | Some v -> put k (Js.Json.number v)
      | None -> ())
    [ "selectionStart"; "selectionEnd" ];
  match Js.Undefined.toOption (prop_undef t "selectionDirection") with
  | Some v -> put "selectionDirection" (Js.Json.string v)
  | None -> ()

let json_of_event name (ev : Js.Json.t) : string =
  let d = Js.Dict.empty () in
  let put name v = if not (is_undefined_json v) then Js.Dict.set d name v in
  put "type" (Js.Json.string name);
  let s k = Option.iter (fun v -> put k (Js.Json.string v)) in
  let b k = Option.iter (fun v -> put k (Js.Json.boolean v)) in
  let n k = Option.iter (fun v -> put k (Js.Json.number v)) in
  s "key" (Js.Undefined.toOption (prop_undef ev "key"));
  s "code" (Js.Undefined.toOption (prop_undef ev "code"));
  s "data" (Js.Undefined.toOption (prop_undef ev "data"));
  s "inputType" (Js.Undefined.toOption (prop_undef ev "inputType"));
  b "shiftKey" (Js.Undefined.toOption (prop_undef ev "shiftKey"));
  b "ctrlKey" (Js.Undefined.toOption (prop_undef ev "ctrlKey"));
  b "metaKey" (Js.Undefined.toOption (prop_undef ev "metaKey"));
  b "altKey" (Js.Undefined.toOption (prop_undef ev "altKey"));
  b "repeat" (Js.Undefined.toOption (prop_undef ev "repeat"));
  b "isComposing" (Js.Undefined.toOption (prop_undef ev "isComposing"));
  n "button" (Js.Undefined.toOption (prop_undef ev "button"));
  n "buttons" (Js.Undefined.toOption (prop_undef ev "buttons"));
  n "clientX" (Js.Undefined.toOption (prop_undef ev "clientX"));
  n "clientY" (Js.Undefined.toOption (prop_undef ev "clientY"));
  n "which" (Js.Undefined.toOption (prop_undef ev "which"));
  (match Js.Undefined.toOption (prop_undef ev "target") with
   | Some t -> put_target_fields d t
   | None -> ());
  Js.Json.stringify (Js.Json.object_ d)

let handlers_of el =
  match Js.Undefined.toOption (handlers_get el) with
  | Some h -> h
  | None ->
      let h = Hashtbl.create 8 in
      handlers_set el h;
      h

let apply_events el names =
  (* The emit closure is bound to the node's runtime id at create time; read
     it lazily so a reused element always emits for its current node. *)
  let current_emit () =
    match Js.Undefined.toOption (emit_get el) with
    | Some e -> e
    | None -> fun _ _ -> ()
  in
  let tbl = handlers_of el in
  let wanted =
    names
    |> String.split_on_char ' '
    |> List.filter (fun s -> s <> "")
  in
  Hashtbl.iter
    (fun name f ->
      if not (List.mem name wanted) then (
        remove_listener el name f;
        Hashtbl.remove tbl name))
    (Hashtbl.copy tbl);
  List.iter
    (fun name ->
      if not (Hashtbl.mem tbl name) then (
        let f (ev : Js.Json.t) =
          if name = "contextmenu" then prevent_default ev;
          (* keep textarea textContent matching its value so innerText and
             text selectors see what was typed *)
          if name = "input" && W.Element.tagName el = "TEXTAREA" then
            W.Element.setTextContent el (get_value el);
          let payload = json_of_event name ev in
          current_emit () "dom-event"
            (String_map.empty
            |> String_map.add "name" (StringValue name)
            |> String_map.add "payload" (StringValue payload))
        in
        add_listener el name f;
        Hashtbl.replace tbl name f))
    wanted

(* -- adapter -- *)

let set_property el prop value =
  match (prop, value) with
  | "attrs", StringValue s -> apply_attrs el s
  | "events", StringValue s -> apply_events el s
  | "text", StringValue s ->
      if is_control_tag el then (
        (* skip redundant .value writes — assigning resets the caret *)
        if get_value el <> s then set_value el s;
        if W.Element.tagName el = "TEXTAREA" then
          W.Element.setTextContent el s)
      else W.Element.setTextContent el s
  | "style-class", StringValue s -> W.Element.setClassName el s
  | "accessibility-identifier", StringValue s ->
      W.Element.setAttribute "id" s el
  | _ -> ()

let remove_property el prop =
  match prop with
  | "attrs" -> apply_attrs el "{}"
  | "events" -> apply_events el ""
  | "text" ->
      if is_control_tag el then set_value el ""
      else W.Element.setTextContent el ""
  | "style-class" -> W.Element.setClassName el ""
  | "accessibility-identifier" -> W.Element.removeAttribute "id" el
  | _ -> ()

let cleanup el =
  let tbl = handlers_of el in
  Hashtbl.iter (fun name f -> remove_listener el name f) tbl;
  Hashtbl.reset tbl

(* -- tag registry -- *)

let prefix = "lui-dom-"

let tags =
  [ "div"; "span"; "a"; "button"; "textarea"; "input"; "img"; "main"
  ; "header"; "h1"; "h2"; "h3"; "p"; "ul"; "li"; "nav"; "section"
  ; "strong"; "em"; "code"; "pre"; "label"; "form"; "select"; "option"
  ; "video"; "audio"; "iframe"; "small"; "kbd"; "table"; "thead"; "tbody"
  ; "tr"; "td"; "th"; "br"; "hr"; "canvas"; "svg"; "path"; "article"
  ; "aside"; "footer"; "details"; "summary"; "u"; "mark"; "b"; "i" ]

let identifier tag = prefix ^ tag

let child_identifiers = List.map identifier tags

let web_profile =
  { Lui_protocol.profile_os = WebOS; Lui_protocol.profile_host = WebHost }

let schema_of tag =
  Lui_extension.component (identifier tag) [ web_profile ]
    true (* standard_children *)
    child_identifiers
    [ Lui_extension.property "attrs" Lui_extension.StringScalar false None
    ; Lui_extension.property "events" Lui_extension.StringScalar false None
    ; Lui_extension.property "text" Lui_extension.StringScalar false None
    ; Lui_extension.property "style-class" Lui_extension.StringScalar false
        None
    ; Lui_extension.property "accessibility-identifier"
        Lui_extension.StringScalar false None
    ]
    [ Lui_extension.event "dom-event"
        [ Lui_extension.event_field "name" Lui_extension.StringScalar true
        ; Lui_extension.event_field "payload" Lui_extension.StringScalar
            false
        ]
    ]

let register registry =
  List.iter
    (fun tag -> Lui_extension.register_component registry (schema_of tag))
    tags

let adapter_of_tag tag : web_extension_adapter =
  { web_extension_create =
      (fun _node document emit ->
        let el = W.Document.createElement tag document in
        emit_set el emit;
        el)
  ; web_extension_set_property = set_property
  ; web_extension_remove_property = remove_property
  ; web_extension_cleanup = cleanup
  }

let adapters : web_extension_adapter String_map.t =
  List.fold_left
    (fun acc tag ->
      String_map.add (identifier tag) (adapter_of_tag tag) acc)
    String_map.empty tags
