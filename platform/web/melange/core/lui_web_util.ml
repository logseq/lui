(* Low-level DOM helpers shared by every web-backend feature module.
   Nothing here reads the retained store. *)

open Lui_web_types

module W = Webapi.Dom

(* The DOM is untyped: a "pointerdown" listener receives a Dom.event whose
   runtime representation is a PointerEvent. melange-webapi performs the same
   narrowing with its own %identity externals (EventTarget.asEventTarget,
   Element.unsafeAsHtmlElement); these are the webapi-shaped equivalents for
   the subtypes it does not export. *)
external as_pointer_event : Dom.event -> Dom.pointerEvent = "%identity"
external as_mouse_event : Dom.event -> Dom.mouseEvent = "%identity"
external event_target_to_element : Dom.eventTarget -> Dom.element = "%identity"
external element_to_event_target : Dom.element -> Dom.eventTarget = "%identity"
external node_to_element : Dom.node -> Dom.element = "%identity"
external element_to_html_element : Dom.element -> Dom.htmlElement = "%identity"

external pointer_type_raw : Dom.pointerEvent -> string = "pointerType" [@@mel.get]
external pointer_id_raw : Dom.pointerEvent -> int = "pointerId" [@@mel.get]

let pointer_mouse_event (event : Dom.event) : Dom.mouseEvent = as_mouse_event event
let pointer_type (event : Dom.event) : string = pointer_type_raw (as_pointer_event event)
let pointer_id (event : Dom.event) : int = pointer_id_raw (as_pointer_event event)

(* Element construction. [attributes] is (name, value) pairs applied before
   children are appended, matching the original element/5 helper. *)
let element document tag class_name attributes children =
  let node = W.Document.createElement tag document in
  List.iter
    (fun (name, value) -> W.Element.setAttribute name value node)
    attributes;
  W.Element.setClassName node class_name;
  List.iter (fun child -> W.Element.appendChild (W.Element.asNode child) node) children;
  node

let child_element dom_node index =
  match W.HtmlCollection.item index (W.Element.children dom_node) with
  | Some child -> child
  | None ->
      invalid_arg
        ("DOM node child is missing: " ^ W.Element.tagName dom_node ^ "."
        ^ W.Element.className dom_node ^ "[" ^ string_of_int index ^ "] of "
        ^ string_of_int
            (W.HtmlCollection.length (W.Element.children dom_node)))

let text_control_node dom_node =
  let tag_name = W.Element.tagName dom_node in
  let candidate =
    if tag_name = "INPUT" || tag_name = "TEXTAREA" then dom_node
    else child_element dom_node 0
  in
  let candidate_tag_name = W.Element.tagName candidate in
  if candidate_tag_name <> "INPUT" && candidate_tag_name <> "TEXTAREA" then
    invalid_arg "DOM node is not a text control";
  match W.HtmlInputElement.ofNode (W.Element.asNode candidate) with
  | Some control -> control
  | None -> invalid_arg "DOM node is not a text control"

let toggle_label_node dom_node = child_element dom_node 1
let button_icon_node dom_node = child_element dom_node 0
let button_label_node dom_node = child_element dom_node 1

let node_dom_id node = "lui-node-" ^ string_of_int node

let accordion_trigger_node dom_node = child_element dom_node 0
let accordion_panel_node dom_node = child_element dom_node 1
let accordion_label_node dom_node = child_element (accordion_trigger_node dom_node) 0

let initialize_accordion_semantics node dom_node =
  let trigger = accordion_trigger_node dom_node in
  let panel = accordion_panel_node dom_node in
  let trigger_id = node_dom_id node ^ "-trigger" in
  let panel_id = node_dom_id node ^ "-panel" in
  W.Element.setAttribute "id" trigger_id trigger;
  W.Element.setAttribute "id" panel_id panel;
  W.Element.setAttribute "aria-controls" panel_id trigger;
  W.Element.setAttribute "aria-labelledby" trigger_id panel

let insert_dom_child parent child index =
  (* index into childNodes, not Element.children: text-node children (e.g.
     raw-text placeholders) occupy DOM positions that element-only indexing
     skips, while visible_child_index counts them *)
  let children = W.Node.childNodes (W.Element.asNode parent) in
  let length = W.NodeList.length children in
  if index = length then
    W.Element.appendChild (W.Element.asNode child) parent
  else
    match W.NodeList.item index children with
    | Some reference ->
        ignore
          (W.Element.insertBefore
             (W.Element.asNode child) reference parent)
    | None -> invalid_arg "DOM child index is out of bounds"

let document_body renderer =
  let document = W.Document.unsafeAsHtmlDocument renderer.web_document in
  match W.HtmlDocument.body document with
  | Some body -> body
  | None -> invalid_arg "document body is unavailable"

let modal_layer_node surface =
  match W.Element.parentElement surface with
  | Some layer -> layer
  | None -> invalid_arg "modal surface requires a portal layer"

let bottom_tab_trigger_id node = "lui-bottom-tab-" ^ string_of_int node
let bottom_tabs_pages_node dom_node = child_element dom_node 0
let bottom_tabs_bar_node dom_node = child_element dom_node 1

let focus_element element =
  let html_element = W.Element.unsafeAsHtmlElement element in
  W.HtmlElement.focus html_element

let set_style scope name value =
  W.CssStyleDeclaration.setProperty name value "" scope

let set_state_attribute dom_node attribute enabled =
  if enabled then W.Element.setAttribute attribute "" dom_node
  else W.Element.removeAttribute attribute dom_node

let css_url url =
  let buffer = Buffer.create (String.length url + 8) in
  Buffer.add_string buffer "url(\"";
  String.iter
    (fun c ->
       if c = '\\' || c = '"' then Buffer.add_char buffer '\\';
       Buffer.add_char buffer c)
    url;
  Buffer.add_string buffer "\")";
  Buffer.contents buffer

let semantic_color_names =
  [ "background"; "foreground"; "card"; "card-foreground"; "primary";
    "primary-foreground"; "secondary"; "secondary-foreground"; "accent";
    "accent-foreground"; "muted-foreground"; "destructive";
    "destructive-foreground"; "success"; "success-foreground"; "warning";
    "warning-foreground"; "error"; "error-foreground"; "input"; "ring";
    "border" ]

let web_color_value color =
  if color = "transparent" then "transparent"
  else if List.mem color semantic_color_names then "var(--color-" ^ color ^ ")"
  else color

(* Which element actually receives children for a given node kind. Several
   components keep their content in a wrapper child (dropdown menu surface,
   split panes, modal layers, accordion panels). *)
let content_container kind dom_node =
  match kind with
  | Lui_protocol.DropdownMenu | Lui_protocol.Split -> child_element dom_node 0
  | Lui_protocol.Alert -> child_element dom_node 1
  | Lui_protocol.Bubble -> child_element dom_node 0
  | Lui_protocol.Accordion -> accordion_panel_node dom_node
  | kind when Lui_protocol.modal_surface kind -> child_element dom_node 1
  | _ -> dom_node

let set_optional_text element value =
  W.Element.setTextContent element value;
  if value = "" then W.Element.setAttribute "hidden" "" element
  else W.Element.removeAttribute "hidden" element

let some_node value = Some value
