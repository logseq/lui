(* Device emulation for the web backend: platform/form-factor/orientation
   attributes and CSS variables on the host and portal root, plus the soft
   keyboard visibility tracking driven by focusin/focusout on text entries. *)

open Lui_protocol
open Lui_web_types

module W = Webapi.Dom

let simulator_platform_name platform =
  match platform with
  | IOS -> "ios"
  | AndroidOS -> "android"
  | _ -> invalid_arg "web simulator platform must be iOS or Android"

let simulator_form_factor_name form_factor =
  match form_factor with
  | SimulatorPhone -> "phone"
  | SimulatorTablet -> "tablet"

let simulator_orientation_name orientation =
  match orientation with
  | SimulatorPortrait -> "portrait"
  | SimulatorLandscape -> "landscape"

let simulator_pointer_name pointer =
  match pointer with
  | SimulatorTouch -> "touch"
  | SimulatorHybrid -> "hybrid"

let simulator_device platform form_factor orientation =
  let ios = platform = IOS in
  let tablet = form_factor = SimulatorTablet in
  let portrait = orientation = SimulatorPortrait in
  let portrait_width = if tablet then (if ios then 1024 else 800) else if ios then 390 else 412 in
  let portrait_height = if tablet then (if ios then 1366 else 1280) else if ios then 844 else 915 in
  let landscape_phone = (not tablet) && not portrait in
  let android_landscape = (not ios) && not portrait in
  ignore (simulator_platform_name platform);
  ignore (simulator_form_factor_name form_factor);
  ignore (simulator_orientation_name orientation);
  { simulator_device_platform = platform;
    simulator_device_form_factor = form_factor;
    simulator_device_orientation = orientation;
    simulator_device_pointer =
      (if tablet then SimulatorHybrid else SimulatorTouch);
    simulator_device_width =
      (if portrait then portrait_width else portrait_height);
    simulator_device_height =
      (if portrait then portrait_height else portrait_width);
    simulator_device_scale =
      (if ios && not tablet then 3.0
       else if (not ios) && not tablet then 2.625
       else 2.0);
    simulator_device_safe_top =
      (if portrait then (if ios && not tablet then 47 else 24)
       else if tablet then 24
       else 0);
    simulator_device_safe_right =
      (if landscape_phone then (if ios then 47 else 24)
       else if android_landscape then 24
       else 0);
    simulator_device_safe_bottom =
      (if portrait then
         (if ios && not tablet then 34 else if ios then 20 else 24)
       else if ios then (if tablet then 20 else 21)
       else 0);
    simulator_device_safe_left =
      (if landscape_phone then (if ios then 47 else 24)
       else if android_landscape then 24
       else 0);
    simulator_device_keyboard_height =
      (if portrait then (if tablet then 350 else if ios then 291 else 300)
       else if tablet then 280
       else if ios then 162
       else 220) }

let set_style scope property value =
  W.CssStyleDeclaration.setProperty property value ""
    (W.HtmlElement.style (W.Element.unsafeAsHtmlElement scope))

let apply_simulator_device_to_scope scope device keyboard_visible =
  W.Element.setAttribute "data-lui-form-factor"
    (simulator_form_factor_name device.simulator_device_form_factor) scope;
  W.Element.setAttribute "data-lui-orientation"
    (simulator_orientation_name device.simulator_device_orientation) scope;
  W.Element.setAttribute "data-lui-pointer"
    (simulator_pointer_name device.simulator_device_pointer) scope;
  W.Element.setAttribute "data-lui-keyboard"
    (if keyboard_visible then "visible" else "hidden") scope;
  set_style scope "--lui-viewport-width"
    (string_of_int device.simulator_device_width ^ "px");
  set_style scope "--lui-viewport-height"
    (string_of_int device.simulator_device_height ^ "px");
  set_style scope "--lui-device-scale"
    (string_of_float device.simulator_device_scale);
  set_style scope "--lui-safe-area-top"
    (string_of_int device.simulator_device_safe_top ^ "px");
  set_style scope "--lui-safe-area-right"
    (string_of_int device.simulator_device_safe_right ^ "px");
  set_style scope "--lui-safe-area-bottom"
    (string_of_int device.simulator_device_safe_bottom ^ "px");
  set_style scope "--lui-safe-area-left"
    (string_of_int device.simulator_device_safe_left ^ "px");
  set_style scope "--lui-keyboard-height"
    (string_of_int
       (if keyboard_visible then device.simulator_device_keyboard_height else 0)
     ^ "px")

let apply_simulator_device_to_scope_bang = apply_simulator_device_to_scope

let set_simulator_device renderer device =
  let keyboard_visible = !(renderer.web_simulator_keyboard_visible) in
  apply_simulator_device_to_scope renderer.web_host device keyboard_visible;
  apply_simulator_device_to_scope renderer.web_portal_root device
    keyboard_visible;
  renderer.web_simulator_device := Some device;
  true

let set_simulator_device_bang = set_simulator_device

let set_simulator_keyboard_visible renderer visible =
  match !(renderer.web_simulator_device) with
  | Some device ->
      renderer.web_simulator_keyboard_visible := visible;
      set_simulator_device renderer device
  | None -> invalid_arg "web simulator device is unavailable"

let set_simulator_keyboard_visible_bang = set_simulator_keyboard_visible

let set_simulator_form_factor renderer form_factor =
  match !(renderer.web_simulator_device) with
  | Some device ->
      set_simulator_device renderer
        (simulator_device device.simulator_device_platform form_factor
           device.simulator_device_orientation)
  | None -> invalid_arg "web simulator device is unavailable"

let set_simulator_form_factor_bang = set_simulator_form_factor

let rotate_simulator renderer =
  match !(renderer.web_simulator_device) with
  | Some device ->
      set_simulator_device renderer
        (simulator_device device.simulator_device_platform
           device.simulator_device_form_factor
           (match device.simulator_device_orientation with
            | SimulatorPortrait -> SimulatorLandscape
            | SimulatorLandscape -> SimulatorPortrait))
  | None -> invalid_arg "web simulator device is unavailable"

let rotate_simulator_bang = rotate_simulator

let set_simulator_platform renderer platform =
  let name = simulator_platform_name platform in
  W.Element.setAttribute "data-lui-platform" name renderer.web_host;
  W.Element.setAttribute "data-lui-platform" name renderer.web_portal_root;
  renderer.web_simulator_platform := Some platform;
  (match !(renderer.web_simulator_device) with
   | Some device ->
       ignore
         (set_simulator_device renderer
            (simulator_device platform device.simulator_device_form_factor
               device.simulator_device_orientation))
   | None -> ());
  true

let set_simulator_platform_bang = set_simulator_platform

let simulator_text_entry element =
  let class_name = W.Element.className element in
  class_name = "lui-text-field" || class_name = "lui-input"
  || class_name = "lui-search-field" || class_name = "lui-textarea"
  || class_name = "lui-combobox-control"

let simulator_text_entry_ = simulator_text_entry

let compact_sheet renderer =
  match !(renderer.web_simulator_device) with
  | Some device -> device.simulator_device_form_factor = SimulatorPhone
  | None ->
      let root = W.Document.documentElement renderer.web_document in
      W.Element.clientWidth root <= 640

let compact_sheet_ = compact_sheet

let attach_simulator_keyboard_events renderer =
  List.iter
    (fun scope ->
       W.Element.addEventListener "focusin"
         (fun event ->
            let target =
              W.EventTarget.unsafeAsElement (W.Event.target event)
            in
            if simulator_text_entry target then
              ignore (set_simulator_keyboard_visible renderer true))
         scope;
       W.Element.addEventListener "focusout"
         (fun event ->
            let target =
              W.EventTarget.unsafeAsElement (W.Event.target event)
            in
            if simulator_text_entry target then
              ignore (set_simulator_keyboard_visible renderer false))
         scope)
    [ renderer.web_host; renderer.web_portal_root ];
  true

let attach_simulator_keyboard_events_bang = attach_simulator_keyboard_events
