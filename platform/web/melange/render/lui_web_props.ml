(* Property application for the LUI web (DOM) backend: apply_property! and
   remove_property! plus the DOM refresh helpers they share. Ported from
   web.cljc — see PORTING.md. *)

open Lui_protocol
open Lui_web_types

module W = Webapi.Dom
module Store = Lui_web_store
module Util = Lui_web_util
module Widgets = Lui_web_widgets
module Focus = Lui_web_focus
module Nodes = Lui_web_nodes

let set_style dom_node name value =
  let scope = W.HtmlElement.style (W.Element.unsafeAsHtmlElement dom_node) in
  Util.set_style scope name value

(* webapi declares mediaQueryList but exposes no `matches` accessor; the LG
   source read it through a dict lookup on the same value. *)
external media_query_matches : W.Window.mediaQueryList -> bool = "matches"
  [@@mel.get]

let prefers_reduced_motion document =
  let html_document = W.Document.unsafeAsHtmlDocument document in
  match W.HtmlDocument.defaultView html_document with
  | Some window ->
      media_query_matches
        (W.Window.matchMedia "(prefers-reduced-motion: reduce)" window)
  | None -> false

let transition_event_from target event =
  W.Element.isSameNode
    (W.Element.asNode
       (W.EventTarget.unsafeAsElement (W.Event.target event)))
    target

let after_transition document target fallback_duration finish_on_cancel
    complete =
  if prefers_reduced_motion document then complete ()
  else begin
    let finished = ref false in
    let timer = ref None in
    let finish_ref = ref (fun () -> ()) in
    let transition_handler event =
      if transition_event_from target event then !finish_ref ()
    in
    let finish () =
      if not !finished then begin
        finished := true;
        (match !timer with
         | Some timer_id -> Js.Global.clearTimeout timer_id
         | None -> ());
        W.Element.removeEventListener "transitionend" transition_handler
          target;
        if finish_on_cancel then
          W.Element.removeEventListener "transitioncancel" transition_handler
            target;
        complete ()
      end
    in
    finish_ref := finish;
    W.Element.addEventListener "transitionend" transition_handler target;
    if finish_on_cancel then
      W.Element.addEventListener "transitioncancel" transition_handler target;
    timer := Some (Js.Global.setTimeout ~f:finish fallback_duration)
  end

let finish_accordion_close panel =
  if W.Element.hasAttribute "data-ending-style" panel then begin
    W.Element.removeAttribute "data-ending-style" panel;
    W.Element.setAttribute "hidden" "" panel
  end

let open_accordion renderer dom_node panel =
  W.Element.removeAttribute "data-closed" dom_node;
  W.Element.setAttribute "data-open" "" dom_node;
  W.Element.removeAttribute "hidden" panel;
  W.Element.removeAttribute "data-closed" panel;
  W.Element.removeAttribute "data-ending-style" panel;
  W.Element.setAttribute "data-open" "" panel;
  set_style panel "--lui-accordion-panel-height"
    (string_of_int (W.Element.scrollHeight panel) ^ "px");
  W.Element.setAttribute "data-starting-style" "" panel;
  Webapi.requestAnimationFrame (fun _time ->
      if W.Element.hasAttribute "data-open" panel then
        W.Element.removeAttribute "data-starting-style" panel);
  if prefers_reduced_motion renderer.web_document then
    set_style panel "--lui-accordion-panel-height" "auto"
  else
    ignore
      (Js.Global.setTimeout
         ~f:(fun () ->
           if W.Element.hasAttribute "data-open" panel then
             set_style panel "--lui-accordion-panel-height" "auto")
         190)

let close_accordion renderer dom_node panel =
  W.Element.removeAttribute "data-open" dom_node;
  W.Element.setAttribute "data-closed" "" dom_node;
  if not (W.Element.hasAttribute "hidden" panel) then begin
    set_style panel "--lui-accordion-panel-height"
      (string_of_int (W.Element.scrollHeight panel) ^ "px");
    ignore
      (W.HtmlElement.offsetHeight (W.Element.unsafeAsHtmlElement panel));
    W.Element.removeAttribute "data-open" panel;
    W.Element.removeAttribute "data-starting-style" panel;
    W.Element.setAttribute "data-closed" "" panel;
    if prefers_reduced_motion renderer.web_document then begin
      W.Element.setAttribute "data-ending-style" "" panel;
      finish_accordion_close panel
    end
    else begin
      after_transition renderer.web_document panel 190 false
        (fun () -> finish_accordion_close panel);
      W.Element.setAttribute "data-ending-style" "" panel
    end
  end

let set_accordion_open renderer _node dom_node opened =
  let trigger = Util.accordion_trigger_node dom_node in
  let panel = Util.accordion_panel_node dom_node in
  W.Element.setAttribute "aria-expanded"
    (if opened then "true" else "false") trigger;
  if opened then open_accordion renderer dom_node panel
  else close_accordion renderer dom_node panel

let set_accordion_open_bang = set_accordion_open

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

let refresh_node_class renderer node kind dom_node =
  let style_class =
    match Store.property renderer.web_store node StyleClass with
    | Some (StringValue value) -> value
    | _ -> ""
  in
  let tree_class =
    if Store.treeitem renderer node then "lui-tree-item" else ""
  in
  W.Element.setClassName
    (if kind = DropdownMenu then Util.child_element dom_node 0 else dom_node)
    (String.trim
       (Nodes.base_class_name kind ^ " " ^ tree_class ^ " " ^ style_class))

let refresh_node_class_bang = refresh_node_class

let set_text_control_value dom_node text =
  let control = Util.text_control_node dom_node in
  if text <> W.HtmlInputElement.value control then (
    W.HtmlInputElement.setValue control text;
    (* keep textarea textContent matching its value so innerText and text
       selectors observe the buffer *)
    if W.Element.tagName dom_node = "TEXTAREA" then
      W.Element.setTextContent dom_node text)

let set_visible_text kind dom_node text =
  let target =
    if Store.direct_toggle kind then Util.toggle_label_node dom_node
    else if
      Store.button_like kind || kind = MenuItem || kind = MenuTrigger
    then Util.button_label_node dom_node
    else dom_node
  in
  if text <> W.Element.textContent target then
    W.Element.setTextContent target text

let apply_text_value renderer node kind dom_node text =
  match kind with
  | Alert -> W.Element.setTextContent (Util.child_element dom_node 0) text
  | Bubble -> W.Element.setTextContent (Util.child_element dom_node 1) text
  | Accordion ->
      W.Element.setTextContent (Util.accordion_label_node dom_node) text
  | Step ->
      W.Element.setTextContent (Util.child_element dom_node 1) text;
      Widgets.update_stepper_parent renderer node
  | Dialog | Sheet ->
      W.Element.setTextContent
        (Util.child_element (Util.child_element dom_node 0) 0) text
  | NumberStepper ->
      W.Element.setTextContent (Util.toggle_label_node dom_node) text
  | Avatar ->
      W.Element.setTextContent (Util.child_element dom_node 1) text;
      Widgets.update_avatar renderer node dom_node
  | Select ->
      W.Element.setTextContent
        (Util.child_element dom_node 0)
        (select_display_text renderer node)
  | Link ->
      W.Element.setTextContent (Util.child_element dom_node 1) text
  | TextField | SecureField | Input | SearchField | Textarea | Combobox ->
      set_text_control_value dom_node text
  | _ -> set_visible_text kind dom_node text

let apply_text_value_bang = apply_text_value

let apply_enabled renderer node kind dom_node enabled =
  if kind = BottomTab then begin
    (match Widgets.bottom_tab_trigger renderer node with
     | Some trigger ->
         if enabled then begin
           W.Element.removeAttribute "disabled" trigger;
           W.Element.setAttribute "aria-disabled" "false" trigger
         end
         else begin
           W.Element.setAttribute "disabled" "disabled" trigger;
           W.Element.setAttribute "aria-disabled" "true" trigger
         end
     | None -> ());
    match Store.node renderer.web_store node with
    | Some current ->
        (match current.retained_parent with
         | Some parent -> Widgets.refresh_bottom_tabs renderer parent
         | None -> ())
    | None -> ()
  end
  else begin
    let control_node =
      if Store.direct_toggle kind || kind = NumberStepper then
        Util.child_element dom_node 0
      else if kind = Combobox then Util.child_element dom_node 0
      else dom_node
    in
    if enabled then W.Element.removeAttribute "disabled" control_node
    else W.Element.setAttribute "disabled" "disabled" control_node;
    if kind = Combobox then begin
      let trigger = Util.child_element dom_node 1 in
      if enabled then W.Element.removeAttribute "disabled" trigger
      else W.Element.setAttribute "disabled" "disabled" trigger;
      Util.set_state_attribute dom_node "data-disabled" (not enabled)
    end;
    if Store.direct_toggle kind then
      Util.set_state_attribute dom_node "data-disabled" (not enabled);
    if Store.treeitem renderer node then
      W.Element.setAttribute "aria-disabled"
        (if enabled then "false" else "true") dom_node;
    if Store.node_has_ancestor_kind renderer.web_store node Toolbar then
      ignore
        (Focus.apply_toolbar_disabled_semantics renderer node)
  end

let apply_grid_columns dom_node columns =
  if columns = 0 then begin
    set_style dom_node "grid-auto-flow" "column";
    set_style dom_node "grid-auto-columns" "minmax(0, 1fr)";
    set_style dom_node "grid-template-columns" "none"
  end
  else begin
    set_style dom_node "grid-auto-flow" "row";
    set_style dom_node "grid-auto-columns" "auto";
    set_style dom_node "grid-template-columns"
      ("repeat(" ^ string_of_int columns ^ ", minmax(0, 1fr))")
  end

let apply_gap renderer node kind dom_node gap =
  if kind = Split then Lui_web_split.update_split renderer node
  else set_style dom_node "gap" (string_of_int gap ^ "px");
  if kind = TableRow then
    set_style dom_node "--lui-table-gap" (string_of_int gap ^ "px")

let apply_placeholder renderer node kind dom_node placeholder =
  if kind = Select then
    W.Element.setTextContent
      (Util.child_element dom_node 0)
      (select_display_text renderer node)
  else
    W.HtmlInputElement.setPlaceholder (Util.text_control_node dom_node)
      placeholder

let apply_accessibility_label kind dom_node label =
  if kind = BottomTabs then
    W.Element.setAttribute "aria-label" label
      (Util.bottom_tabs_bar_node dom_node)
  else if kind = Split then
    W.Element.setAttribute "aria-label" (label ^ " divider")
      (Util.child_element dom_node 1)
  else
    W.Element.setAttribute "aria-label" label
      (if Store.direct_toggle kind || kind = NumberStepper then
         Util.child_element dom_node 0
       else dom_node)

let apply_checked kind dom_node checked =
  if kind = Toggle then begin
    Util.set_state_attribute dom_node "data-checked" checked;
    W.Element.setAttribute "aria-pressed"
      (if checked then "true" else "false") dom_node
  end
  else begin
    W.HtmlInputElement.setChecked (Util.text_control_node dom_node) checked;
    Util.set_state_attribute dom_node "data-checked" checked;
    W.Element.setAttribute "aria-checked"
      (if checked then "true" else "false") (Util.child_element dom_node 0)
  end

let apply_progress_value renderer node kind dom_node value =
  if kind = Split then Lui_web_split.reconcile_split renderer node dom_node value
  else if kind = Progress then Widgets.update_progress renderer node dom_node
  else
    W.HtmlInputElement.setValue (Util.text_control_node dom_node)
      (Js.Float.toString value)

let apply_inline_icon_name renderer node kind dom_node name =
  if kind = BottomTab then
    (match Widgets.bottom_tab_trigger renderer node with
     | Some trigger ->
         let icon = Util.child_element trigger 0 in
         W.Element.setAttribute "data-name" name icon;
         Widgets.update_icon_name renderer icon name
     | None -> ())
  else if kind = TimelineItem then
    Widgets.update_timeline_indicator renderer node dom_node
  else begin
    let icon =
      if kind = ListItem then dom_node else Util.button_icon_node dom_node
    in
    W.Element.setAttribute "data-name" name icon;
    Widgets.update_icon_name renderer icon name
  end

let apply_selected renderer node kind dom_node selected =
  if kind = BottomTab then
    (match Store.node renderer.web_store node with
     | Some current ->
         (match current.retained_parent with
          | Some parent -> Widgets.refresh_bottom_tabs renderer parent
          | None -> ())
     | None -> ())
  else if kind = Accordion then
    set_accordion_open renderer node dom_node selected
  else if
    kind = TableRow || kind = TimelineItem || Store.treeitem renderer node
  then begin
    Util.set_state_attribute dom_node "data-selected" selected;
    W.Element.setAttribute "aria-selected"
      (if selected then "true" else "false") dom_node
  end
  else begin
    Util.set_state_attribute dom_node "data-selected" selected;
    W.Element.setAttribute
      (if kind = MenuItem || Focus.direct_tab_trigger renderer node then
         "aria-selected"
       else "aria-pressed")
      (if selected then "true" else "false") dom_node
  end

let apply_autofocus dom_node autofocus =
  if autofocus then begin
    W.Element.setAttribute "autofocus" "autofocus" dom_node;
    ignore
      (Js.Global.setTimeout
         ~f:(fun () ->
           W.HtmlElement.focus (W.Element.unsafeAsHtmlElement dom_node))
         0)
  end
  else W.Element.removeAttribute "autofocus" dom_node

let apply_pressable_target kind dom_node enabled =
  if kind = Text then begin
    Util.set_state_attribute dom_node "data-pressable" enabled;
    if enabled then begin
      W.Element.setAttribute "role" "button" dom_node;
      W.Element.setAttribute "tabindex" "0" dom_node
    end
    else begin
      W.Element.removeAttribute "role" dom_node;
      W.Element.removeAttribute "tabindex" dom_node
    end
  end

let apply_pressable_cell kind dom_node enabled =
  if kind = TableCell then begin
    Util.set_state_attribute dom_node "data-pressable" enabled;
    if enabled then W.Element.setAttribute "tabindex" "0" dom_node
    else W.Element.removeAttribute "tabindex" dom_node
  end

let apply_pressable_timeline_item kind dom_node enabled =
  if kind = TimelineItem then begin
    Util.set_state_attribute dom_node "data-pressable" enabled;
    if enabled then begin
      W.Element.setAttribute "tabindex" "0" dom_node;
      W.Element.removeAttribute "hidden" (Util.child_element dom_node 2)
    end
    else begin
      W.Element.removeAttribute "tabindex" dom_node;
      W.Element.setAttribute "hidden" "" (Util.child_element dom_node 2)
    end
  end

let apply_press_enabled kind dom_node enabled =
  Util.set_state_attribute dom_node "data-press-enabled" enabled;
  apply_pressable_target kind dom_node enabled;
  apply_pressable_cell kind dom_node enabled;
  apply_pressable_timeline_item kind dom_node enabled;
  if kind = BottomTab then
    Util.set_state_attribute dom_node "data-press-enabled" enabled

let apply_title renderer node kind dom_node title =
  if kind = BottomTab then
    (match Widgets.bottom_tab_trigger renderer node with
     | Some trigger ->
         W.Element.setTextContent (Util.child_element trigger 1) title
     | None -> ())
  else begin
    W.Element.setTextContent
      (Util.child_element (Util.child_element dom_node 1) 0)
      title;
    W.Element.setAttribute "aria-label" title dom_node
  end

let apply_media_source renderer node kind dom_node =
  if kind = Avatar then Widgets.update_avatar renderer node dom_node
  else Widgets.update_image renderer node dom_node

(* container-relative-frame: fills (or min-sizes against) the nearest
   container. Axes and inset arrive as separate properties, so each is cached
   on the element and the styles recomputed on either update. *)
let apply_container_frame dom_node axes inset =
  let inset_px = "calc(100% - " ^ string_of_int inset ^ "px)" in
  match axes with
  | "horizontal" -> set_style dom_node "width" "100%"
  | "vertical" -> set_style dom_node "height" "100%"
  | "both" ->
      set_style dom_node "width" "100%";
      set_style dom_node "height" "100%"
  | "min-horizontal" -> set_style dom_node "min-width" inset_px
  | "min-vertical" -> set_style dom_node "min-height" inset_px
  | "min-both" ->
      set_style dom_node "min-width" inset_px;
      set_style dom_node "min-height" inset_px
  | _ -> ()

let apply_frame_axes dom_node axes =
  W.Element.setAttribute "data-lui-frame-axes" axes dom_node;
  let inset =
    match W.Element.getAttribute "data-lui-frame-inset" dom_node with
    | Some value -> int_of_string_opt value |> Option.value ~default:0
    | None -> 0
  in
  apply_container_frame dom_node axes inset

let apply_frame_inset dom_node inset =
  W.Element.setAttribute "data-lui-frame-inset" (string_of_int inset) dom_node;
  match W.Element.getAttribute "data-lui-frame-axes" dom_node with
  | Some axes -> apply_container_frame dom_node axes inset
  | None -> ()

let apply_anchor_offset kind dom_node offset =
  set_style dom_node "--lui-anchor-offset" (Js.Float.toString offset ^ "px");
  if kind = Tooltip then
    W.Element.setAttribute "data-anchor-offset"
      (Js.Float.toString offset) dom_node

let rec apply_property renderer node kind dom_node property value =
  match (property, value) with
  | TextValue, StringValue text ->
      apply_text_value renderer node kind dom_node text
  | Enabled, BoolValue enabled ->
      apply_enabled renderer node kind dom_node enabled
  | Gap, IntValue gap -> apply_gap renderer node kind dom_node gap
  | MainAlignment, StringValue alignment ->
      set_style dom_node "justify-content" (main_alignment_value alignment)
  | CrossAlignment, StringValue alignment ->
      set_style dom_node "align-items" (cross_alignment_value alignment)
  | GrowValue, FloatValue grow ->
      set_style dom_node "flex-grow" (Js.Float.toString grow)
  | GridColumns, IntValue columns -> apply_grid_columns dom_node columns
  | PaddingValue, IntValue padding ->
      set_style dom_node "padding" (string_of_int padding ^ "px");
      set_style dom_node "--lui-content-padding"
        (string_of_int padding ^ "px")
  | PaddingHorizontal, IntValue padding ->
      set_style dom_node "padding-inline" (string_of_int padding ^ "px")
  | PaddingVertical, IntValue padding ->
      set_style dom_node "padding-block" (string_of_int padding ^ "px")
  | BackgroundValue, StringValue background ->
      set_style dom_node "background" (Util.web_color_value background)
  | ForegroundValue, StringValue foreground ->
      set_style dom_node "color" (Util.web_color_value foreground)
  | BorderColorValue, StringValue border ->
      set_style dom_node "border-color" (Util.web_color_value border)
  | BorderWidth, IntValue width ->
      set_style dom_node "border-style" "solid";
      set_style dom_node "border-width" (string_of_int width ^ "px")
  | CornerRadius, IntValue radius ->
      set_style dom_node "border-radius" (string_of_int radius ^ "px")
  | WidthValue, IntValue width ->
      set_style dom_node "width" (string_of_int width ^ "px");
      if kind = Image then Widgets.update_image renderer node dom_node;
      if kind = Bubble then
        W.Element.setAttribute "data-width" "explicit" dom_node
  | HeightValue, IntValue height ->
      set_style dom_node "height" (string_of_int height ^ "px");
      if kind = Image then Widgets.update_image renderer node dom_node
  | MinWidth, IntValue width ->
      set_style dom_node "min-width" (string_of_int width ^ "px")
  | MaxWidth, IntValue width ->
      set_style dom_node "max-width" (string_of_int width ^ "px")
  | MinHeight, IntValue height ->
      set_style dom_node "min-height" (string_of_int height ^ "px")
  | MaxHeight, IntValue height ->
      set_style dom_node "max-height" (string_of_int height ^ "px")
  | PlaceholderValue, StringValue placeholder ->
      apply_placeholder renderer node kind dom_node placeholder
  | AccessibilityLabel, StringValue label ->
      apply_accessibility_label kind dom_node label
  | AccessibilityIdentifier, StringValue identifier ->
      W.Element.setAttribute "id" identifier dom_node
  | StyleClass, StringValue _class_name ->
      refresh_node_class renderer node kind dom_node
  | HeadingLevel, IntValue level ->
      W.Element.setAttribute "aria-level" (string_of_int level) dom_node
  | _ -> apply_secondary_property renderer node kind dom_node property value

(* Sheets honour `detents` (medium|large|fraction list — the largest caps
   the surface height as a viewport fraction) and `sizing` (form|fitted
   narrow the surface to a centered column; page stretches full width). *)
and sheet_detent_max value =
  String.split_on_char ',' value
  |> List.fold_left
       (fun cap token ->
         match String.trim token with
         | "medium" -> max cap 0.5
         | "large" -> max cap 1.0
         | trimmed ->
             (match float_of_string_opt trimmed with
              | Some fraction when fraction > 0.0 && fraction <= 1.0 ->
                  max cap fraction
              | _ -> cap))
       0.0

and apply_sheet_detents dom_node value =
  let cap = sheet_detent_max value in
  if cap > 0.0 then
    set_style dom_node "max-height"
      (Printf.sprintf "%gdvh" (cap *. 100.0))
  else
    set_style dom_node "max-height" ""

and apply_sheet_sizing dom_node value =
  match value with
  | "form" | "fitted" ->
      set_style dom_node "max-width" "560px";
      set_style dom_node "margin-inline" "auto"
  | _ ->
      set_style dom_node "max-width" "";
      set_style dom_node "margin-inline" ""

and apply_secondary_property renderer node kind dom_node property value =
  match (property, value) with
  | Checked, BoolValue checked -> apply_checked kind dom_node checked
  | ProgressValue, FloatValue value ->
      apply_progress_value renderer node kind dom_node value
  | MinValue, FloatValue value ->
      W.Element.setAttribute "min" (Js.Float.toString value)
        (Util.child_element dom_node 0)
  | MaxValue, FloatValue value ->
      W.Element.setAttribute "max" (Js.Float.toString value)
        (Util.child_element dom_node 0)
  | StepValue, FloatValue value ->
      W.Element.setAttribute "step" (Js.Float.toString value)
        (Util.child_element dom_node 0)
  | Detents, StringValue value ->
      W.Element.setAttribute "data-detents" value dom_node;
      if kind = Sheet then apply_sheet_detents dom_node value
  | Sizing, StringValue value ->
      W.Element.setAttribute "data-sizing" value dom_node;
      if kind = Sheet then apply_sheet_sizing dom_node value
  | ResizeDuration, IntValue _duration ->
      Lui_web_split.update_split renderer node
  | ResizeEasing, StringValue _easing ->
      Lui_web_split.update_split renderer node
  | ResizeOrigin, FloatValue _origin ->
      Lui_web_split.update_split renderer node
  | OrientationValue, StringValue orientation ->
      W.Element.setAttribute "data-orientation" orientation dom_node;
      W.Element.setAttribute "aria-orientation" orientation dom_node
  | SizeValue, StringValue size ->
      W.Element.setAttribute "data-size" size dom_node
  | IconName, StringValue name ->
      W.Element.setAttribute "data-name" name dom_node;
      Widgets.update_icon_name renderer dom_node name
  | VariantValue, StringValue variant ->
      W.Element.setAttribute "data-variant" variant dom_node
  | InlineIconName, StringValue name ->
      apply_inline_icon_name renderer node kind dom_node name
  | IconPlacementValue, StringValue placement ->
      W.Element.setAttribute "data-icon-placement" placement dom_node
  | Selected, BoolValue selected ->
      apply_selected renderer node kind dom_node selected
  | Autofocus, BoolValue autofocus -> apply_autofocus dom_node autofocus
  | SubmitOnEnter, BoolValue enabled ->
      Util.set_state_attribute dom_node "data-submit-on-enter" enabled
  | LongPressEnabled, BoolValue enabled ->
      Util.set_state_attribute dom_node "data-long-press-enabled" enabled
  | ChangeEnabled, BoolValue enabled ->
      Util.set_state_attribute dom_node "data-change-enabled" enabled
  | ToggleEnabled, BoolValue enabled ->
      Util.set_state_attribute dom_node "data-toggle-enabled" enabled
  | PressEnabled, BoolValue enabled ->
      apply_press_enabled kind dom_node enabled
  | RoleValue, StringValue role ->
      W.Element.setAttribute "role" role dom_node;
      W.Element.removeAttribute "aria-pressed" dom_node;
      refresh_node_class renderer node kind dom_node
  | TreeLevel, IntValue level ->
      W.Element.setAttribute "aria-level" (string_of_int level) dom_node
  | Expanded, BoolValue expanded ->
      Util.set_state_attribute dom_node "data-expanded" expanded;
      W.Element.setAttribute "aria-expanded"
        (if expanded then "true" else "false") dom_node
  | SubmitEnabled, BoolValue enabled ->
      Util.set_state_attribute dom_node "data-submit-enabled" enabled
  | DoublePressEnabled, BoolValue enabled ->
      Util.set_state_attribute dom_node "data-double-press-enabled" enabled
  | ImageIdValue, IntValue _image_id ->
      apply_media_source renderer node kind dom_node
  | SurfaceIdValue, IntValue _surface_id ->
      Widgets.update_media_surface renderer node dom_node
  | ActiveIndex, IntValue _active ->
      Widgets.update_stepper renderer node
  | TitleValue, StringValue title ->
      apply_title renderer node kind dom_node title
  | DescriptionValue, StringValue description ->
      Util.set_optional_text
        (if modal_surface kind then
           Util.child_element (Util.child_element dom_node 0) 1
         else Util.child_element (Util.child_element dom_node 1) 1)
        description
  | MetaValue, StringValue meta ->
      Util.set_optional_text
        (Util.child_element (Util.child_element dom_node 1) 2)
        meta
  | IndicatorValue, StringValue _indicator ->
      Widgets.update_timeline_indicator renderer node dom_node
  | Connector, BoolValue connector ->
      Util.set_state_attribute
        (Util.child_element (Util.child_element dom_node 0) 1)
        "hidden" (not connector)
  | SourceX, FloatValue _value | SourceY, FloatValue _value
  | SourceWidth, FloatValue _value | SourceHeight, FloatValue _value ->
      apply_media_source renderer node kind dom_node
  | AnchorValue, StringValue anchor ->
      W.Element.setAttribute "data-anchor" anchor dom_node;
      if kind = Tooltip then
        W.Element.setAttribute "data-anchor-alignment" "start" dom_node
  | AnchorAlignmentValue, StringValue alignment ->
      W.Element.setAttribute "data-anchor-alignment" alignment dom_node
  | AnchorOffset, FloatValue offset ->
      apply_anchor_offset kind dom_node offset
  | UrlValue, StringValue url ->
      W.Element.setAttribute "href" url dom_node;
      W.Element.setAttribute "target" "_blank" dom_node
  | PathValue, StringValue path ->
      W.Element.setAttribute "data-path" path dom_node
  | MaxPixelSize, IntValue size ->
      W.Element.setAttribute "data-max-pixel-size" (string_of_int size)
        dom_node
  | TooltipDelay, IntValue delay ->
      W.Element.setAttribute "data-tooltip-delay"
        (string_of_int delay) dom_node
  | DurationValue, IntValue duration ->
      W.Element.setAttribute "data-duration" (string_of_int duration)
        dom_node
  | TextAlignment, StringValue alignment ->
      if kind = Bubble then
        W.Element.setAttribute "data-reactions-alignment" alignment dom_node
      else set_style dom_node "text-align" alignment
  | ContainerRelativeFrameValue, StringValue axes ->
      apply_frame_axes dom_node axes
  | ContainerRelativeFrameInset, IntValue inset ->
      apply_frame_inset dom_node inset
  | EdgeValue, StringValue edge ->
      W.Element.setAttribute "data-edge" edge dom_node
  | Visible, BoolValue visible ->
      Util.set_state_attribute dom_node "data-pinned-hidden" (not visible)
  | AlignmentValue, StringValue alignment ->
      W.Element.setAttribute "data-alignment" alignment dom_node
  | _ ->
      invalid_arg
        ("invalid DOM property value: " ^ Lui_wire_schema.property_name property)

let apply_property_bang = apply_property

let remove_property renderer node kind dom_node property =
  match Store.node renderer.web_store node with
  | Some _current ->
      (match property with
       | TextValue -> apply_text_value renderer node kind dom_node ""
       | Enabled ->
           apply_property renderer node kind dom_node Enabled
             (BoolValue true)
       | Gap -> set_style dom_node "gap" ""
       | MainAlignment -> set_style dom_node "justify-content" ""
       | CrossAlignment -> set_style dom_node "align-items" ""
       | GrowValue -> set_style dom_node "flex-grow" ""
       | GridColumns ->
           set_style dom_node "grid-auto-flow" "";
           set_style dom_node "grid-auto-columns" "";
           set_style dom_node "grid-template-columns" ""
       | PaddingValue ->
           set_style dom_node "padding" "";
           set_style dom_node "--lui-content-padding" ""
       | PaddingHorizontal -> set_style dom_node "padding-inline" ""
       | PaddingVertical -> set_style dom_node "padding-block" ""
       | BackgroundValue -> set_style dom_node "background" ""
       | ForegroundValue -> set_style dom_node "color" ""
       | BorderColorValue -> set_style dom_node "border-color" ""
       | BorderWidth ->
           set_style dom_node "border-style" "";
           set_style dom_node "border-width" ""
       | CornerRadius -> set_style dom_node "border-radius" ""
       | WidthValue -> set_style dom_node "width" ""
       | HeightValue -> set_style dom_node "height" ""
       | MinWidth -> set_style dom_node "min-width" ""
       | MaxWidth -> set_style dom_node "max-width" ""
       | MinHeight -> set_style dom_node "min-height" ""
       | MaxHeight -> set_style dom_node "max-height" ""
       | ContainerRelativeFrameValue ->
           W.Element.removeAttribute "data-lui-frame-axes" dom_node;
           set_style dom_node "width" "";
           set_style dom_node "height" "";
           set_style dom_node "min-width" "";
           set_style dom_node "min-height" ""
       | ContainerRelativeFrameInset ->
           W.Element.removeAttribute "data-lui-frame-inset" dom_node
       | EdgeValue -> W.Element.removeAttribute "data-edge" dom_node
       | Visible -> W.Element.removeAttribute "data-pinned-hidden" dom_node
       | AlignmentValue ->
           W.Element.removeAttribute "data-alignment" dom_node
       | PlaceholderValue ->
           W.HtmlInputElement.setPlaceholder (Util.text_control_node dom_node)
             ""
       | AccessibilityLabel ->
           W.Element.removeAttribute "aria-label"
             (if Store.direct_toggle kind || kind = NumberStepper then
                Util.child_element dom_node 0
              else dom_node)
       | MinValue ->
           W.Element.removeAttribute "min" (Util.child_element dom_node 0)
       | MaxValue ->
           W.Element.removeAttribute "max" (Util.child_element dom_node 0)
       | StepValue ->
           W.Element.removeAttribute "step" (Util.child_element dom_node 0)
       | Detents ->
           W.Element.removeAttribute "data-detents" dom_node;
           if kind = Sheet then set_style dom_node "max-height" ""
       | Sizing ->
           W.Element.removeAttribute "data-sizing" dom_node;
           if kind = Sheet then begin
             set_style dom_node "max-width" "";
             set_style dom_node "margin-inline" ""
           end
       | UrlValue ->
           W.Element.removeAttribute "href" dom_node;
           W.Element.removeAttribute "target" dom_node
       | PathValue -> W.Element.removeAttribute "data-path" dom_node
       | MaxPixelSize ->
           W.Element.removeAttribute "data-max-pixel-size" dom_node
       | AccessibilityIdentifier -> W.Element.removeAttribute "id" dom_node
       | OrientationValue ->
           if kind = Tabs then begin
             W.Element.setAttribute "data-orientation" "horizontal" dom_node;
             W.Element.setAttribute "aria-orientation" "horizontal" dom_node
           end
       | StyleClass -> refresh_node_class renderer node kind dom_node
       | _ -> ())
  | None -> invalid_arg "unknown DOM node"

let remove_property_bang = remove_property
