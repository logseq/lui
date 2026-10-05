(* Widgets: icons, avatar/image/media-surface registries, stepper,
   bottom tabs, timeline, progress, and select display text. Ported from
   web.cljc (update-icon-name! … select-display-text). *)

open Lui_protocol
open Lui_web_types

module W = Webapi.Dom
module Store = Lui_web_store
module Util = Lui_web_util

let float_string value = Js.Float.toString value

let set_style element property value =
  Util.set_style
    (W.HtmlElement.style (W.Element.unsafeAsHtmlElement element))
    property value

let update_icon_name renderer dom_node name =
  let element_style =
    W.HtmlElement.style (W.Element.unsafeAsHtmlElement dom_node)
  in
  if String.starts_with ~prefix:"app:" name then begin
    let bare_name = String.sub name 4 (String.length name - 4) in
    let image =
      match String_map.find_opt bare_name renderer.web_app_icons with
      | Some url -> Util.css_url url
      | None -> "url(\"./icons/missing.svg\")"
    in
    W.CssStyleDeclaration.setProperty "--lui-icon-image" image ""
      element_style
  end
  else
    W.CssStyleDeclaration.setProperty "--lui-icon-image"
      (Util.css_url ("./icons/" ^ name ^ ".svg"))
      "" element_style

let update_icon_name_bang = update_icon_name

let avatar_float renderer node property fallback =
  match Store.property renderer.web_store node property with
  | Some (FloatValue value) -> value
  | _ -> fallback

let media_size renderer node property fallback =
  match Store.property renderer.web_store node property with
  | Some (IntValue value) -> Float.of_int value
  | _ -> fallback

let registered_image renderer node =
  match Store.property renderer.web_store node ImageIdValue with
  | Some (IntValue image_id) ->
      if image_id = 0 then None
      else Hashtbl.find_opt renderer.web_images image_id
  | _ -> None

let registered_avatar_image renderer node = registered_image renderer node

(* Shared crop math: positions [target] so the source rect covers it at the
   given scale. *)
let apply_crop element resource source_x source_y scale_x scale_y =
  set_style element "width"
    (float_string (resource.web_image_width *. scale_x) ^ "px");
  set_style element "height"
    (float_string (resource.web_image_height *. scale_y) ^ "px");
  set_style element "left"
    (float_string (Float.neg source_x *. scale_x) ^ "px");
  set_style element "top"
    (float_string (Float.neg source_y *. scale_y) ^ "px")

let fill_image element object_fit =
  set_style element "width" "100%";
  set_style element "height" "100%";
  set_style element "left" "0";
  set_style element "top" "0";
  set_style element "object-fit" object_fit

let image_source renderer node =
  let source_x = avatar_float renderer node SourceX 0.0 in
  let source_y = avatar_float renderer node SourceY 0.0 in
  let source_width = avatar_float renderer node SourceWidth 0.0 in
  let source_height = avatar_float renderer node SourceHeight 0.0 in
  (source_x, source_y, source_width, source_height)

let update_avatar renderer node dom_node =
  let image_node = Util.child_element dom_node 0 in
  let initials_node = Util.child_element dom_node 1 in
  match registered_avatar_image renderer node with
  | Some resource ->
      let source_x, source_y, source_width, source_height =
        image_source renderer node
      in
      let cropped = source_width > 0.0 in
      W.Element.setAttribute "src" resource.web_image_url image_node;
      Util.set_state_attribute image_node "hidden" false;
      Util.set_state_attribute initials_node "hidden" true;
      if cropped then begin
        let size = 40.0 in
        let scale =
          Float.max (size /. source_width) (size /. source_height)
        in
        let crop_width = source_width *. scale in
        let crop_height = source_height *. scale in
        set_style image_node "width"
          (float_string (resource.web_image_width *. scale) ^ "px");
        set_style image_node "height"
          (float_string (resource.web_image_height *. scale) ^ "px");
        set_style image_node "left"
          (float_string
             (Float.neg source_x *. scale +. ((size -. crop_width) /. 2.0))
           ^ "px");
        set_style image_node "top"
          (float_string
             (Float.neg source_y *. scale +. ((size -. crop_height) /. 2.0))
           ^ "px");
        set_style image_node "object-fit" "fill"
      end
      else fill_image image_node "cover"
  | None ->
      W.Element.removeAttribute "src" image_node;
      Util.set_state_attribute image_node "hidden" true;
      Util.set_state_attribute initials_node "hidden" false

let update_avatar_bang = update_avatar

let update_image renderer node dom_node =
  let pixels = Util.child_element dom_node 0 in
  match registered_image renderer node with
  | Some resource ->
      let source_x, source_y, source_width, source_height =
        image_source renderer node
      in
      let cropped = source_width > 0.0 in
      W.Element.setAttribute "src" resource.web_image_url pixels;
      Util.set_state_attribute pixels "hidden" false;
      if cropped then begin
        let target_width =
          media_size renderer node WidthValue source_width
        in
        let target_height =
          media_size renderer node HeightValue source_height
        in
        let scale_x = target_width /. source_width in
        let scale_y = target_height /. source_height in
        apply_crop pixels resource source_x source_y scale_x scale_y;
        set_style pixels "object-fit" "fill"
      end
      else fill_image pixels "fill"
  | None ->
      (match Store.property renderer.web_store node UrlValue with
       | Some (StringValue url) when url <> "" ->
           W.Element.setAttribute "src" url pixels;
           Util.set_state_attribute pixels "hidden" false;
           fill_image pixels "fill"
       | _ ->
           W.Element.removeAttribute "src" pixels;
           Util.set_state_attribute pixels "hidden" true)

let update_image_bang = update_image

let surface_placeholder_color surface_id =
  "rgb("
  ^ string_of_int (64 + (surface_id * 37 mod 64))
  ^ ", "
  ^ string_of_int (64 + (surface_id * 57 mod 64))
  ^ ", "
  ^ string_of_int (64 + (surface_id * 83 mod 64))
  ^ ")"

let update_media_surface renderer node dom_node =
  let frame = Util.child_element dom_node 0 in
  match Store.property renderer.web_store node SurfaceIdValue with
  | Some (IntValue surface_id) ->
      (match
         if surface_id = 0 then None
         else Hashtbl.find_opt renderer.web_media_surfaces surface_id
       with
       | Some resource ->
           set_style dom_node "background-color" "transparent";
           W.Element.setAttribute "src" resource.web_image_url frame;
           Util.set_state_attribute frame "hidden" false
       | None ->
           set_style dom_node "background-color"
             (if surface_id = 0 then "transparent"
              else surface_placeholder_color surface_id);
           W.Element.removeAttribute "src" frame;
           Util.set_state_attribute frame "hidden" true)
  | _ ->
      set_style dom_node "background-color" "transparent";
      W.Element.removeAttribute "src" frame;
      Util.set_state_attribute frame "hidden" true

let update_media_surface_bang = update_media_surface

let refresh_image_id renderer image_id =
  Hashtbl.iter
    (fun node current ->
       if
         (Store.standard_kind_is current Avatar
          || Store.standard_kind_is current Image)
         && Property_map.find_opt ImageIdValue current.retained_properties
            = Some (IntValue image_id)
       then
         if Store.standard_kind_is current Avatar then
           update_avatar renderer node current.platform_node
         else update_image renderer node current.platform_node)
    (Store.nodes renderer.web_store);
  true

let refresh_image_id_bang = refresh_image_id

let validate_positive id dims what =
  if id <= 0 then invalid_arg (what ^ " id must be positive");
  let width, height = dims in
  if
    (not (Float.is_finite width))
    || (not (Float.is_finite height))
    || width <= 0.0 || height <= 0.0
  then invalid_arg (what ^ " dimensions must be positive")

let register_image renderer image_id url width height =
  validate_positive image_id (width, height) "registered image";
  Hashtbl.replace renderer.web_images image_id
    { web_image_url = url;
      web_image_width = width;
      web_image_height = height };
  refresh_image_id renderer image_id

let register_image_bang = register_image

let unregister_image renderer image_id =
  if image_id <= 0 then
    invalid_arg "registered image id must be positive";
  if Hashtbl.mem renderer.web_images image_id then begin
    Hashtbl.remove renderer.web_images image_id;
    ignore (refresh_image_id renderer image_id)
  end;
  true

let unregister_image_bang = unregister_image

let refresh_media_surface_id renderer surface_id =
  Hashtbl.iter
    (fun node current ->
       if
         Store.standard_kind_is current MediaSurface
         && Property_map.find_opt SurfaceIdValue current.retained_properties
            = Some (IntValue surface_id)
       then update_media_surface renderer node current.platform_node)
    (Store.nodes renderer.web_store);
  true

let refresh_media_surface_id_bang = refresh_media_surface_id

let present_media_surface_frame renderer surface_id url width height =
  validate_positive surface_id (width, height) "media surface";
  Hashtbl.replace renderer.web_media_surfaces surface_id
    { web_image_url = url;
      web_image_width = width;
      web_image_height = height };
  refresh_media_surface_id renderer surface_id

let present_media_surface_frame_bang = present_media_surface_frame

let unregister_media_surface renderer surface_id =
  if surface_id <= 0 then invalid_arg "media surface id must be positive";
  if Hashtbl.mem renderer.web_media_surfaces surface_id then begin
    Hashtbl.remove renderer.web_media_surfaces surface_id;
    ignore (refresh_media_surface_id renderer surface_id)
  end;
  true

let unregister_media_surface_bang = unregister_media_surface

let main_alignment_value alignment =
  match alignment with
  | "start" -> "flex-start"
  | "center" -> "center"
  | "end" -> "flex-end"
  | "space_between" -> "space-between"
  | _ -> invalid_arg "invalid main alignment"

let cross_alignment_value alignment =
  match alignment with
  | "stretch" -> "stretch"
  | "start" -> "flex-start"
  | "center" -> "center"
  | "end" -> "flex-end"
  | _ -> invalid_arg "invalid cross alignment"

let string_property renderer node property =
  match Store.property renderer.web_store node property with
  | Some (StringValue value) -> value
  | _ -> ""

let update_stepper renderer node =
  let children = Store.children renderer.web_store node in
  let current =
    match Store.node renderer.web_store node with
    | Some current -> current
    | None -> invalid_arg "unknown Stepper"
  in
  let active = int_property current.retained_properties ActiveIndex 0 in
  let count = List.length children in
  List.iteri
    (fun index child ->
       let step = Lui_web_nodes.dom_node renderer child in
       let indicator = Util.child_element step 0 in
       let label = string_property renderer child TextValue in
       let state =
         if index < active then "completed"
         else if index = active then "active"
         else "pending"
       in
       W.Element.setAttribute "data-state" state step;
       W.Element.setAttribute "aria-label"
         (label ^ " (" ^ state ^ ")") step;
       W.Element.setAttribute "aria-posinset"
         (string_of_int (index + 1)) step;
       W.Element.setAttribute "aria-setsize" (string_of_int count) step;
       (if state = "active" then
          W.Element.setAttribute "aria-current" "step" step
        else W.Element.removeAttribute "aria-current" step);
       (if state = "completed" then begin
          W.Element.setTextContent indicator "";
          W.Element.setAttribute "data-name" "check" indicator;
          update_icon_name renderer indicator "check"
        end
        else begin
          W.Element.removeAttribute "data-name" indicator;
          set_style indicator "--lui-icon-image" "none";
          W.Element.setTextContent indicator (string_of_int (index + 1))
        end);
       let connector = Util.child_element step 2 in
       if index = count - 1 then W.Element.setAttribute "hidden" "" connector
       else W.Element.removeAttribute "hidden" connector)
    children

let update_stepper_bang = update_stepper

let bottom_tab_trigger renderer node =
  match Store.node renderer.web_store node with
  | Some current ->
      (match current.retained_parent with
       | Some parent ->
           W.Element.querySelector
             ("#" ^ Util.bottom_tab_trigger_id node)
             (Lui_web_nodes.dom_node renderer parent)
       | None -> None)
  | None -> None

let bottom_tab_string_property renderer node property =
  match Store.property renderer.web_store node property with
  | Some (StringValue value) -> value
  | _ -> ""

let refresh_bottom_tabs renderer tabs =
  let children = Store.children renderer.web_store tabs in
  let selected =
    match
      List.find_opt
        (fun child ->
           Store.property renderer.web_store child Selected
           = Some (BoolValue true))
        children
    with
    | Some child -> Some child
    | None -> (match children with [] -> None | first :: _ -> Some first)
  in
  List.iter
    (fun child ->
       match Store.node renderer.web_store child with
       | Some current ->
           let active = selected = Some child in
           let panel = current.platform_node in
           Util.set_state_attribute panel "hidden" (not active);
           Util.set_state_attribute panel "inert" (not active);
           (match bottom_tab_trigger renderer child with
            | Some trigger ->
                W.Element.setAttribute "aria-selected"
                  (if active then "true" else "false") trigger;
                W.Element.setAttribute "tabindex"
                  (if active then "0" else "-1") trigger
            | None -> ())
       | None -> ())
    children

let refresh_bottom_tabs_bang = refresh_bottom_tabs

let create_bottom_tab_trigger renderer tabs node index =
  let document = renderer.web_document in
  let panel = Lui_web_nodes.dom_node renderer node in
  let panel_id = Util.node_dom_id node in
  let trigger_id = Util.bottom_tab_trigger_id node in
  let icon_name = bottom_tab_string_property renderer node InlineIconName in
  let title = bottom_tab_string_property renderer node TitleValue in
  let icon =
    Util.element document "span" "lui-icon" [ ("aria-hidden", "true") ] []
  in
  let label = Util.element document "span" "lui-bottom-tabs-label" [] [] in
  let trigger =
    Util.element document "button" "lui-bottom-tabs-tab"
      [ ("type", "button"); ("role", "tab"); ("id", trigger_id);
        ("aria-controls", panel_id); ("aria-selected", "false");
        ("tabindex", "-1") ]
      [ icon; label ]
  in
  let enabled = Store.enabled_node renderer node in
  let press _event =
    if
      Store.enabled_node renderer node
      && Store.event_capability renderer node PressEnabled
    then begin
      W.HtmlElement.focus (W.Element.unsafeAsHtmlElement trigger);
      ignore (!(renderer.web_event_handler) (Press node))
    end
  in
  W.Element.setAttribute "aria-labelledby" trigger_id panel;
  W.Element.setTextContent label title;
  W.Element.setAttribute "data-name" icon_name icon;
  update_icon_name renderer icon icon_name;
  (if enabled then begin
     W.Element.removeAttribute "disabled" trigger;
     W.Element.setAttribute "aria-disabled" "false" trigger
   end
   else begin
     W.Element.setAttribute "disabled" "disabled" trigger;
     W.Element.setAttribute "aria-disabled" "true" trigger
   end);
  W.Element.addEventListener "click" press trigger;
  Util.insert_dom_child
    (Util.bottom_tabs_bar_node (Lui_web_nodes.dom_node renderer tabs))
    trigger index;
  trigger

let create_bottom_tab_trigger_bang = create_bottom_tab_trigger

let update_stepper_parent renderer node =
  match Store.node renderer.web_store node with
  | Some current ->
      (match current.retained_parent with
       | Some parent ->
           (match Store.node renderer.web_store parent with
            | Some parent_node ->
                if Store.standard_kind_is parent_node Stepper then
                  update_stepper renderer parent
            | None -> ())
       | None -> ())
  | None -> ()

let update_stepper_parent_bang = update_stepper_parent

let update_timeline renderer node =
  let children = Store.children renderer.web_store node in
  let count = List.length children in
  List.iteri
    (fun index child ->
       let item = Lui_web_nodes.dom_node renderer child in
       W.Element.setAttribute "aria-posinset"
         (string_of_int (index + 1)) item;
       W.Element.setAttribute "aria-setsize" (string_of_int count) item)
    children

let update_timeline_bang = update_timeline

let update_timeline_indicator renderer node dom_node =
  let indicator = Util.child_element (Util.child_element dom_node 0) 0 in
  let icon = string_property renderer node InlineIconName in
  let text = string_property renderer node IndicatorValue in
  if icon <> "" then begin
    W.Element.setTextContent indicator "";
    W.Element.setAttribute "data-name" icon indicator;
    update_icon_name renderer indicator icon
  end
  else begin
    W.Element.removeAttribute "data-name" indicator;
    set_style indicator "--lui-icon-image" "none";
    W.Element.setTextContent indicator text;
    if text = "" then W.Element.setAttribute "data-dot" "" indicator
    else W.Element.removeAttribute "data-dot" indicator
  end

let update_timeline_indicator_bang = update_timeline_indicator

let progress_float renderer node =
  match Store.property renderer.web_store node ProgressValue with
  | Some (FloatValue value) -> value
  | _ -> 0.0

let update_progress renderer node dom_node =
  let value = progress_float renderer node in
  let clamped = Float.max 0.0 (Float.min value 1.0) in
  let position = clamped *. 100.0 in
  W.Element.setAttribute "aria-valuenow" (float_string clamped) dom_node;
  set_style dom_node "--lui-progress-position"
    (float_string position ^ "%")

let update_progress_bang = update_progress

let select_display_text renderer node =
  match Store.property renderer.web_store node TextValue with
  | Some (StringValue text) ->
      if text <> "" then text
      else
        (match Store.property renderer.web_store node PlaceholderValue with
         | Some (StringValue placeholder) -> placeholder
         | _ -> "")
  | _ ->
      (match Store.property renderer.web_store node PlaceholderValue with
       | Some (StringValue placeholder) -> placeholder
       | _ -> "")
