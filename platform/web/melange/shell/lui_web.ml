(* Public surface of the LUI web DOM backend: renderer construction, the
   Lui_protocol backend, mount, and the query API. *)

open Lui_protocol
open Lui_web_types

module W = Webapi.Dom
module Store = Lui_web_store

let create_with_extensions host app_icons registry adapters =
  let document =
    match W.Element.ownerDocument host with
    | document -> document
  in
  let portal_root = W.Document.createElement "div" document in
  let toast_viewport = W.Document.createElement "div" document in
  let html_document = W.Document.unsafeAsHtmlDocument document in
  W.Element.setClassName portal_root "lui-popup-portal";
  W.Element.setClassName toast_viewport "lui-toast-viewport";
  W.Element.setAttribute "role" "region" toast_viewport;
  W.Element.setAttribute "aria-label" "Notifications" toast_viewport;
  W.Element.setAttribute "tabindex" "-1" toast_viewport;
  W.Element.appendChild (W.Element.asNode toast_viewport) portal_root;
  W.Element.setAttribute "data-lui-root" "" host;
  (match W.HtmlDocument.body html_document with
   | Some body -> W.Element.appendChild (W.Element.asNode portal_root) body
   | None -> invalid_arg "document body is unavailable");
  let web_extension_adapters = Hashtbl.create 8 in
  String_map.iter
    (fun name adapter -> Hashtbl.replace web_extension_adapters name adapter)
    adapters;
  let renderer =
    { web_store = Store.create_store ();
    web_document = document;
    web_host = host;
    web_portal_root = portal_root;
    web_simulator_platform = ref None;
    web_simulator_device = ref None;
    web_simulator_keyboard_visible = ref false;
    web_toast_viewport = toast_viewport;
    web_event_handler = ref (fun _event -> true);
    web_app_icons = app_icons;
    web_images = Hashtbl.create 8;
    web_media_surfaces = Hashtbl.create 4;
    web_cleanups = Hashtbl.create 8;
    web_layers = Lui_web_layers.create ();
    web_modal_return_focus = ref None;
    web_modal_focus_returns = Hashtbl.create 4;
    web_open_tooltip = ref None;
    web_tooltip_warm = ref false;
    web_open_context_menu = ref None;
    web_splits = Hashtbl.create 4;
    web_extension_registry = registry;
    web_extension_adapters }
  in
  Lui_web_layers.install renderer.web_layers renderer.web_document
    (fun root target ->
      Lui_web_store.descendant renderer.web_store.retained_nodes root target)
    Lui_web_util.event_target_to_element;
  renderer

let create_simulator_with_extensions host platform app_icons registry adapters =
  let renderer = create_with_extensions host app_icons registry adapters in
  ignore (Lui_web_simulator.set_simulator_platform renderer platform);
  ignore
    (Lui_web_simulator.set_simulator_device renderer
       (Lui_web_simulator.simulator_device platform SimulatorPhone
          SimulatorPortrait));
  ignore (Lui_web_simulator.attach_simulator_keyboard_events renderer);
  renderer

let create_simulator ?(app_icons = String_map.empty) host platform =
  create_simulator_with_extensions host platform app_icons
    (Lui_extension.registry ()) String_map.empty

let create ?(app_icons = String_map.empty) host =
  create_with_extensions host app_icons (Lui_extension.registry ())
    String_map.empty

let extension_adapter = Lui_web_extensions.extension_adapter
let extension_platform_node = Lui_web_extensions.extension_platform_node

let apply_extension_property =
  Lui_web_extensions.apply_extension_property

let remove_extension_property =
  Lui_web_extensions.remove_extension_property

let cleanup_extension_node = Lui_web_extensions.cleanup_extension_node

let set_event_handler renderer handler =
  renderer.web_event_handler := handler;
  true

let backend renderer =
  { backend_profile = profile WebOS WebHost;
    apply_batch =
      (fun batch ->
        try
          let previous_nodes =
            Hashtbl.copy renderer.web_store.retained_nodes
          in
          let applied =
            try
              Store.apply_batch_with_extensions renderer.web_store
                (fun kind -> Lui_web_nodes.platform_node renderer kind)
                (fun node identifier ->
                  Lui_web_extensions.extension_platform_node renderer node
                    identifier)
                renderer.web_extension_registry (fun _batch -> true) batch
            with Invalid_argument msg ->
              invalid_arg ("store batch: " ^ msg)
          in
          (* The store returns false only for a stale batch it dropped without
             applying — replaying its ops against the DOM would resurrect ops
             that were already consumed. *)
          (if applied then
             try Lui_web_apply.apply_dom_batch renderer previous_nodes batch
             with Invalid_argument msg ->
               invalid_arg ("dom batch: " ^ msg));
          true
        with Js.Exn.Error error ->
          (* DOM calls and platform node creation throw JS exceptions, not
             Invalid_argument; the runtime only consumes a failed batch's
             generation for Invalid_argument, so translate — a resend under
             the same generation would be dropped as stale and lose the
             queued ops silently. *)
          let detail =
            match Js.Exn.message error with
            | Some message -> message
            | None -> "unknown JS exception"
          in
          invalid_arg ("batch apply: " ^ detail)) }

let mount renderer root host =
  W.Element.appendChild
    (W.Element.asNode (Lui_web_nodes.dom_node renderer root))
    host;
  Lui_web_split.update_splits_under renderer root

let rec first_section_title renderer node =
  match Store.node renderer.web_store node with
  | Some current ->
      let kind = Store.standard_kind current in
      let title = Store.property renderer.web_store node TextValue in
      let title_text =
        match title with
        | Some (StringValue value) when value <> "" -> Some value
        | _ -> None
      in
      if (kind = Some Heading || kind = Some Text) && title_text <> None then
        title_text
      else
        let rec search = function
          | [] -> None
          | child :: rest ->
              (match first_section_title renderer child with
               | Some _ as found -> found
               | None -> search rest)
        in
        search current.retained_children
  | None -> None

let root_sections renderer root =
  let store = renderer.web_store in
  let root_children = Store.children store root in
  let children =
    match Store.node store root with
    | Some current ->
        if
          Store.standard_kind current = Some Root
          && List.length root_children = 1
        then Store.children store (List.hd root_children)
        else root_children
    | None -> root_children
  in
  List.map
    (fun page ->
       let title =
         match first_section_title renderer page with
         | Some found -> found
         | None -> "Component " ^ string_of_int page
       in
       { root_section_node = page; root_section_title = title })
    children

let some_node value = Some value

let node renderer node_id =
  match Store.node renderer.web_store node_id with
  | Some current -> Some current.platform_node
  | None -> None

let property renderer node_id property =
  Store.property renderer.web_store node_id property

let children renderer node_id = Store.children renderer.web_store node_id
let node_count renderer = Store.node_count renderer.web_store
let batches renderer = Store.batches renderer.web_store
