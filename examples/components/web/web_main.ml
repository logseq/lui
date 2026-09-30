(* Web entry for the component gallery, ported from web_main.cljc: builds
   the Lui app over the simulator web backend, installs the demo extension
   adapters, mounts the gallery shell + simulator toolbar, and wires backend
   events into the reducer loop. *)

open Lui_protocol
open Lui_web_types

module W = Webapi.Dom

external element_value : W.Element.t -> string = "value" [@@mel.get]
external set_muted : W.Element.t -> bool -> unit = "muted" [@@mel.set]

(* Extension adapters *)

let native_card_adapter : web_extension_adapter =
  { web_extension_create =
      (fun _node document _emit ->
        let button = W.Document.createElement "button" document in
        let pressed = ref false in
        W.Element.setAttribute "type" "button" button;
        W.Element.setClassName button "lui-native-card";
        W.Element.addEventListener "click"
          (fun _event ->
            pressed := not !pressed;
            W.Element.setAttribute "data-active"
              (if !pressed then "true" else "false")
              button)
          button;
        button);
    web_extension_set_property =
      (fun node property value ->
        if property = "title" then
          match value with
          | StringValue text -> W.Element.setTextContent node text
          | _ -> invalid_arg "native-card title must be a string");
    web_extension_remove_property =
      (fun node property ->
        if property = "title" then W.Element.setTextContent node "");
    web_extension_cleanup = (fun _node -> ());
  }

let gallery_accent_adapter : web_extension_adapter =
  { web_extension_create =
      (fun _node document _emit ->
        let element = W.Document.createElement "div" document in
        W.Element.setClassName element "lui-gallery-accent";
        element);
    web_extension_set_property = (fun _node _property _value -> ());
    web_extension_remove_property = (fun _node _property -> ());
    web_extension_cleanup = (fun _node -> ());
  }

let append parent child = W.Element.appendChild (W.Element.asNode child) parent

let set_hidden element hidden =
  if hidden then W.Element.setAttribute "hidden" "" element
  else W.Element.removeAttribute "hidden" element

let attribute_float element name fallback =
  match W.Element.getAttribute name element with
  | Some value -> float_of_string value
  | None -> fallback

let set_float_attribute element name value =
  W.Element.setAttribute name (Js.Float.toString value) element

let refresh_map_markers map =
  let center_latitude = attribute_float map "data-center-latitude" 0.0 in
  let center_longitude = attribute_float map "data-center-longitude" 0.0 in
  let latitude_delta = attribute_float map "data-latitude-delta" 1.0 in
  let longitude_delta = attribute_float map "data-longitude-delta" 1.0 in
  let markers =
    W.Element.querySelectorAll ".lui-simulator-map-marker" map
  in
  for index = 0 to W.NodeList.length markers - 1 do
    match W.NodeList.item index markers with
    | Some node -> (
        match W.Element.ofNode node with
        | Some marker ->
            let latitude = attribute_float marker "data-latitude" 0.0 in
            let longitude = attribute_float marker "data-longitude" 0.0 in
            let x =
              50.0
              +. ((longitude -. center_longitude) /. longitude_delta *. 100.0)
            in
            let y =
              50.0
              -. ((latitude -. center_latitude) /. latitude_delta *. 100.0)
            in
            let style =
              W.HtmlElement.style (W.Element.unsafeAsHtmlElement marker)
            in
            W.CssStyleDeclaration.setProperty "left"
              (Js.Float.toString x ^ "%") "" style;
            W.CssStyleDeclaration.setProperty "top"
              (Js.Float.toString y ^ "%") "" style
        | None -> ())
    | None -> ()
  done

let emit_map_region map emit =
  emit "region-change"
    (String_map.empty
     |> String_map.add "latitude"
          (FloatValue (attribute_float map "data-center-latitude" 0.0))
     |> String_map.add "longitude"
          (FloatValue (attribute_float map "data-center-longitude" 0.0))
     |> String_map.add "latitude-delta"
          (FloatValue (attribute_float map "data-latitude-delta" 1.0))
     |> String_map.add "longitude-delta"
          (FloatValue (attribute_float map "data-longitude-delta" 1.0)))

let map_control document label text on_press =
  let button = W.Document.createElement "button" document in
  W.Element.setAttribute "type" "button" button;
  W.Element.setAttribute "aria-label" label button;
  W.Element.setTextContent button text;
  W.Element.addEventListener "click" (fun _event -> on_press ()) button;
  button

let recenter_map map emit =
  List.iter
    (fun (current, home) ->
      match W.Element.getAttribute home map with
      | Some value -> W.Element.setAttribute current value map
      | None -> ())
    [ ("data-center-latitude", "data-home-latitude")
    ; ("data-center-longitude", "data-home-longitude")
    ; ("data-latitude-delta", "data-home-latitude-delta")
    ; ("data-longitude-delta", "data-home-longitude-delta")
    ];
  refresh_map_markers map;
  emit_map_region map emit

let update_zoom map emit factor =
  set_float_attribute map "data-latitude-delta"
    (attribute_float map "data-latitude-delta" 1.0 *. factor);
  set_float_attribute map "data-longitude-delta"
    (attribute_float map "data-longitude-delta" 1.0 *. factor);
  refresh_map_markers map;
  emit_map_region map emit

let map_pointer_down map drag dragging event =
  let target =
    W.EventTarget.unsafeAsElement (W.Event.target event)
  in
  if W.Element.tagName target <> "BUTTON" then (
    let pointer = Lui_web_util.pointer_mouse_event event in
    drag :=
      ( float_of_int (W.MouseEvent.clientX pointer)
      , float_of_int (W.MouseEvent.clientY pointer)
      , attribute_float map "data-center-latitude" 0.0
      , attribute_float map "data-center-longitude" 0.0 );
    dragging := true;
    W.Element.setAttribute "aria-grabbed" "true" map)

let map_pointer_move map drag dragging event =
  if !dragging then (
    let start_x, start_y, start_latitude, start_longitude = !drag in
    let bounds = W.Element.getBoundingClientRect map in
    let width = Float.max 1.0 (W.DomRect.width bounds) in
    let height = Float.max 1.0 (W.DomRect.height bounds) in
    let pointer = Lui_web_util.pointer_mouse_event event in
    let x = float_of_int (W.MouseEvent.clientX pointer) in
    let y = float_of_int (W.MouseEvent.clientY pointer) in
    let longitude_delta =
      attribute_float map "data-longitude-delta" 1.0
    in
    let latitude_delta = attribute_float map "data-latitude-delta" 1.0 in
    set_float_attribute map "data-center-longitude"
      (start_longitude -. ((x -. start_x) /. width *. longitude_delta));
    set_float_attribute map "data-center-latitude"
      (start_latitude +. ((y -. start_y) /. height *. latitude_delta));
    refresh_map_markers map)

let simulator_map_create _node document emit =
  let map = W.Document.createElement "section" document in
  let texture = W.Document.createElement "div" document in
  let controls = W.Document.createElement "div" document in
  let drag = ref (0.0, 0.0, 0.0, 0.0) in
  let dragging = ref false in
  W.Element.setClassName map "lui-simulator-map";
  W.Element.setAttribute "role" "region" map;
  W.Element.setAttribute "aria-grabbed" "false" map;
  W.Element.setClassName texture "lui-simulator-map-texture";
  W.Element.setAttribute "aria-hidden" "true" texture;
  W.Element.setClassName controls "lui-simulator-map-controls";
  append controls (map_control document "Zoom in" "+" (fun () ->
       update_zoom map emit 0.5));
  append controls
    (map_control document "Zoom out" {js|−|js} (fun () ->
         update_zoom map emit 2.0));
  append controls
    (map_control document "Recenter map" {js|◎|js} (fun () ->
         recenter_map map emit));
  append map texture;
  append map controls;
  W.Element.addEventListener "pointerdown"
    (map_pointer_down map drag dragging)
    map;
  W.Element.addEventListener "pointermove"
    (map_pointer_move map drag dragging)
    map;
  let map_pointer_up _event =
    if !dragging then (
      dragging := false;
      W.Element.setAttribute "aria-grabbed" "false" map;
      emit_map_region map emit)
  in
  W.Element.addEventListener "pointerup" map_pointer_up map;
  W.Element.addEventListener "pointercancel" map_pointer_up map;
  map

let simulator_map_adapter : web_extension_adapter =
  { web_extension_create = simulator_map_create;
    web_extension_set_property =
      (fun map property value ->
        (match (property, value) with
         | "label", StringValue label ->
             W.Element.setAttribute "aria-label" label map
         | "latitude", FloatValue latitude ->
             set_float_attribute map "data-center-latitude" latitude;
             set_float_attribute map "data-home-latitude" latitude
         | "longitude", FloatValue longitude ->
             set_float_attribute map "data-center-longitude" longitude;
             set_float_attribute map "data-home-longitude" longitude
         | "latitude-delta", FloatValue delta ->
             set_float_attribute map "data-latitude-delta" delta;
             set_float_attribute map "data-home-latitude-delta" delta
         | "longitude-delta", FloatValue delta ->
             set_float_attribute map "data-longitude-delta" delta;
             set_float_attribute map "data-home-longitude-delta" delta
         | _ -> invalid_arg "invalid simulator-map property");
        Webapi.requestAnimationFrame (fun _time -> refresh_map_markers map));
    web_extension_remove_property =
      (fun map property ->
        match property with
        | "label" -> W.Element.removeAttribute "aria-label" map
        | "latitude" ->
            W.Element.removeAttribute "data-center-latitude" map
        | "longitude" ->
            W.Element.removeAttribute "data-center-longitude" map
        | "latitude-delta" ->
            W.Element.removeAttribute "data-latitude-delta" map
        | "longitude-delta" ->
            W.Element.removeAttribute "data-longitude-delta" map
        | _ -> ());
    web_extension_cleanup = (fun _map -> ());
  }

let simulator_map_marker_adapter : web_extension_adapter =
  { web_extension_create =
      (fun _node document _emit ->
        let marker = W.Document.createElement "button" document in
        W.Element.setAttribute "type" "button" marker;
        W.Element.setClassName marker "lui-simulator-map-marker";
        marker);
    web_extension_set_property =
      (fun marker property value ->
        (match (property, value) with
         | "title", StringValue title ->
             W.Element.setTextContent marker title;
             W.Element.setAttribute "aria-label" title marker
         | "latitude", FloatValue latitude ->
             set_float_attribute marker "data-latitude" latitude
         | "longitude", FloatValue longitude ->
             set_float_attribute marker "data-longitude" longitude
         | _ -> invalid_arg "invalid simulator-map-marker property");
        Webapi.requestAnimationFrame (fun _time ->
          match W.Element.parentElement marker with
          | Some parent -> refresh_map_markers parent
          | None -> ()));
    web_extension_remove_property =
      (fun marker property ->
        match property with
        | "title" ->
            W.Element.setTextContent marker "";
            W.Element.removeAttribute "aria-label" marker
        | "latitude" -> W.Element.removeAttribute "data-latitude" marker
        | "longitude" -> W.Element.removeAttribute "data-longitude" marker
        | _ -> ());
    web_extension_cleanup = (fun _marker -> ());
  }

type camera_dom =
  { camera : Dom.element;
    video : Dom.element;
    mock : Dom.element;
    status : Dom.element;
    alert : Dom.element;
    action : Dom.element }

let simulator_camera_dom document =
  let camera = W.Document.createElement "section" document in
  let frame = W.Document.createElement "div" document in
  let video = W.Document.createElement "video" document in
  let mock = W.Document.createElement "div" document in
  let status = W.Document.createElement "span" document in
  let alert = W.Document.createElement "p" document in
  let action = W.Document.createElement "button" document in
  W.Element.setClassName camera "lui-simulator-camera";
  W.Element.setAttribute "role" "group" camera;
  W.Element.setAttribute "data-camera-state" "mock" camera;
  W.Element.setClassName frame "lui-simulator-camera-frame";
  W.Element.setAttribute "autoplay" "" video;
  W.Element.setAttribute "muted" "" video;
  W.Element.setAttribute "playsinline" "" video;
  set_muted video true;
  W.Element.setAttribute "aria-label" "Live camera preview" video;
  set_hidden video true;
  W.Element.setClassName mock "lui-simulator-camera-mock";
  W.Element.setAttribute "aria-hidden" "true" mock;
  W.Element.setTextContent mock "SIMULATOR CAMERA";
  W.Element.setAttribute "role" "status" status;
  W.Element.setTextContent status "Using deterministic simulator camera";
  W.Element.setAttribute "role" "alert" alert;
  set_hidden alert true;
  W.Element.setAttribute "type" "button" action;
  W.Element.setTextContent action "Use browser camera";
  append frame video;
  append frame mock;
  append camera frame;
  append camera status;
  append camera alert;
  append camera action;
  { camera; video; mock; status; alert; action }

let simulator_camera_adapter : web_extension_adapter =
  let create _node document emit =
    let { camera; video; mock; status; alert; action } =
      simulator_camera_dom document
    in
    let show_state state status_text action_text ~video_hidden ~mock_hidden
        ~alert_hidden =
      W.Element.setAttribute "data-camera-state" state camera;
      set_hidden video video_hidden;
      set_hidden mock mock_hidden;
      set_hidden alert alert_hidden;
      W.Element.setTextContent status status_text;
      W.Element.setTextContent action action_text;
      emit "state-change" (String_map.singleton "state" (StringValue state))
    in
    let show_mock () =
      Lui_web_media.stop_camera video;
      show_state "mock" "Using deterministic simulator camera"
        "Use browser camera" ~video_hidden:true ~mock_hidden:false
        ~alert_hidden:true
    in
    let show_live () =
      show_state "live" "Using browser camera" "Use simulator camera"
        ~video_hidden:false ~mock_hidden:true ~alert_hidden:true
    in
    let show_denied () =
      W.Element.setAttribute "data-camera-state" "denied" camera;
      set_hidden video true;
      set_hidden mock false;
      set_hidden alert false;
      W.Element.setTextContent alert
        "Camera permission denied. The simulator camera remains available.";
      W.Element.setTextContent status "Using deterministic simulator camera";
      W.Element.setTextContent action "Use browser camera";
      emit "state-change" (String_map.singleton "state" (StringValue "denied"))
    in
    W.Element.addEventListener "click"
      (fun _event ->
        match W.Element.getAttribute "data-camera-state" camera with
        | Some "live" -> show_mock ()
        | _ ->
            W.Element.setAttribute "data-camera-state" "requesting" camera;
            W.Element.setTextContent status "Requesting browser camera";
            Lui_web_media.request_camera document video
              (match W.Element.getAttribute "data-facing" camera with
               | Some facing -> facing
               | None -> "environment")
              show_live show_denied)
      action;
    camera
  in
  { web_extension_create = create;
    web_extension_set_property =
      (fun camera property value ->
        match (property, value) with
        | "label", StringValue label ->
            W.Element.setAttribute "aria-label" label camera
        | "facing", StringValue facing ->
            W.Element.setAttribute "data-facing" facing camera
        | _ -> invalid_arg "invalid simulator-camera property");
    web_extension_remove_property =
      (fun camera property ->
        match property with
        | "label" -> W.Element.removeAttribute "aria-label" camera
        | "facing" -> W.Element.removeAttribute "data-facing" camera
        | _ -> ());
    web_extension_cleanup =
      (fun camera ->
        match W.Element.querySelector "video" camera with
        | Some video -> Lui_web_media.stop_camera video
        | None -> ());
  }

(* Simulator toolbar (outside #app) *)

let select_value event =
  element_value (W.EventTarget.unsafeAsElement (W.Event.target event))

let simulator_option document value label =
  let option = W.Document.createElement "option" document in
  W.Element.setAttribute "value" value option;
  W.Element.setTextContent option label;
  option

let mount_simulator_toolbar renderer refresh_layout =
  let document = renderer.web_document in
  let html_document = W.Document.unsafeAsHtmlDocument document in
  let toolbar = W.Document.createElement "div" document in
  let label = W.Document.createElement "label" document in
  let label_text = W.Document.createElement "span" document in
  let select = W.Document.createElement "select" document in
  let device_label = W.Document.createElement "label" document in
  let device_label_text = W.Document.createElement "span" document in
  let device_select = W.Document.createElement "select" document in
  let rotate = W.Document.createElement "button" document in
  W.Element.setClassName toolbar "lui-simulator-toolbar";
  W.Element.setClassName label "lui-simulator-platform-field";
  W.Element.setTextContent label_text "Platform";
  W.Element.setAttribute "aria-label" "Simulator platform" select;
  append select (simulator_option document "ios" "iOS");
  append select (simulator_option document "android" "Android");
  W.Element.setClassName device_label "lui-simulator-platform-field";
  W.Element.setTextContent device_label_text "Device";
  W.Element.setAttribute "aria-label" "Simulator form factor" device_select;
  append device_select (simulator_option document "phone" "Phone");
  append device_select (simulator_option document "tablet" "Tablet");
  W.Element.setAttribute "type" "button" rotate;
  W.Element.setAttribute "aria-label" "Rotate simulator" rotate;
  W.Element.setTextContent rotate "Rotate";
  W.Element.addEventListener "change"
    (fun event ->
      (match select_value event with
       | "ios" -> ignore (Lui_web_simulator.set_simulator_platform renderer IOS)
       | "android" ->
           ignore (Lui_web_simulator.set_simulator_platform renderer AndroidOS)
       | _ -> ());
      refresh_layout ())
    select;
  W.Element.addEventListener "change"
    (fun event ->
      (match select_value event with
       | "phone" ->
           ignore
             (Lui_web_simulator.set_simulator_form_factor renderer
                SimulatorPhone)
       | "tablet" ->
           ignore
             (Lui_web_simulator.set_simulator_form_factor renderer
                SimulatorTablet)
       | _ -> ());
      refresh_layout ())
    device_select;
  W.Element.addEventListener "click"
    (fun _event ->
      ignore (Lui_web_simulator.rotate_simulator renderer);
      refresh_layout ())
    rotate;
  append label label_text;
  append label select;
  append device_label device_label_text;
  append device_label device_select;
  append toolbar label;
  append toolbar device_label;
  append toolbar rotate;
  match W.HtmlDocument.body html_document with
  | Some body ->
      ignore
        (W.Element.insertBefore (W.Element.asNode toolbar)
           (W.Element.asNode renderer.web_host) body)
  | None -> invalid_arg "document body is unavailable"

(* Gallery shell *)

let set_accessibility_hidden element hidden =
  W.Element.setAttribute "aria-hidden"
    (if hidden then "true" else "false")
    element;
  if hidden then W.Element.setAttribute "inert" "" element
  else W.Element.removeAttribute "inert" element

let focus element =
  W.HtmlElement.focus (W.Element.unsafeAsHtmlElement element)

let select_section renderer content buttons sections selected_index =
  let section = sections.(selected_index) in
  W.Element.setTextContent content "";
  Lui_web.mount renderer section.root_section_node content;
  Array.iteri
    (fun index button ->
      let selected = index = selected_index in
      W.Element.setAttribute "aria-current"
        (if selected then "page" else "false")
        button;
      W.Element.setAttribute "data-selected"
        (if selected then "true" else "false")
        button)
    buttons

let mount_gallery_shell renderer root host =
  let document = renderer.web_document in
  let shell = W.Document.createElement "div" document in
  let navigation_bar = W.Document.createElement "header" document in
  let back = W.Document.createElement "button" document in
  let navigation_title = W.Document.createElement "span" document in
  let sidebar = W.Document.createElement "nav" document in
  let content = W.Document.createElement "div" document in
  let sections = Array.of_list (Lui_web.root_sections renderer root) in
  let selected_index = ref 0 in
  let buttons =
    Array.map
      (fun section ->
        let button = W.Document.createElement "button" document in
        W.Element.setAttribute "type" "button" button;
        W.Element.setClassName button "lui-gallery-nav-item";
        W.Element.setTextContent button section.root_section_title;
        append sidebar button;
        button)
      sections
  in
  let refresh_layout () =
    let tablet =
      W.Element.getAttribute "data-lui-form-factor" host = Some "tablet"
    in
    let detail =
      W.Element.getAttribute "data-lui-navigation" shell = Some "detail"
    in
    let show_detail = tablet || detail in
    set_accessibility_hidden sidebar ((not tablet) && detail);
    set_accessibility_hidden content (not show_detail);
    set_hidden back (tablet || not detail);
    W.Element.setTextContent navigation_title
      (if detail then sections.(!selected_index).root_section_title
       else "Components")
  in
  W.Element.setClassName shell "lui-gallery-shell";
  W.Element.setAttribute "data-lui-navigation" "list" shell;
  W.Element.setClassName navigation_bar "lui-gallery-navigation-bar";
  W.Element.setClassName back "lui-gallery-navigation-back";
  W.Element.setAttribute "type" "button" back;
  W.Element.setAttribute "aria-label" "Back to Components" back;
  W.Element.setTextContent back "Components";
  W.Element.setClassName navigation_title "lui-gallery-navigation-title";
  W.Element.setTextContent navigation_title "Components";
  W.Element.setClassName sidebar "lui-gallery-sidebar";
  W.Element.setAttribute "aria-label" "Components" sidebar;
  W.Element.setClassName content "lui-gallery-content";
  append navigation_bar back;
  append navigation_bar navigation_title;
  append shell navigation_bar;
  append shell sidebar;
  append shell content;
  append host shell;
  W.Element.addEventListener "click"
    (fun _event ->
      W.Element.setAttribute "data-lui-navigation" "list" shell;
      refresh_layout ();
      focus buttons.(!selected_index))
    back;
  Array.iteri
    (fun index button ->
      W.Element.addEventListener "click"
        (fun _event ->
          select_section renderer content buttons sections index;
          selected_index := index;
          W.Element.setAttribute "data-lui-navigation" "detail" shell;
          refresh_layout ();
          if W.Element.getAttribute "data-lui-form-factor" host = Some "phone"
          then focus back)
        button)
    buttons;
  if Array.length sections > 0 then
    select_section renderer content buttons sections 0;
  refresh_layout ();
  refresh_layout

(* Entry *)

let app_icon_url =
  "/examples/components/flutter/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png"

let main host =
  let registry = Extension_schemas.registry () in
  let adapters =
    String_map.empty
    |> String_map.add "simulator-map" simulator_map_adapter
    |> String_map.add "simulator-map-marker" simulator_map_marker_adapter
    |> String_map.add "simulator-camera" simulator_camera_adapter
    |> String_map.add "native-card" native_card_adapter
    |> String_map.add "gallery-accent" gallery_accent_adapter
  in
  let renderer =
    Lui_web.create_simulator_with_extensions host IOS String_map.empty
      registry adapters
  in
  let app =
    Lui_app.create_with_extensions (Lui_web.backend renderer) registry
      Model.initial Model.update View.view
  in
  Hashtbl.replace renderer.web_images 1
    { web_image_url = app_icon_url
    ; web_image_width = 128.0
    ; web_image_height = 128.0
    };
  Hashtbl.replace renderer.web_media_surfaces 1
    { web_image_url = app_icon_url
    ; web_image_width = 128.0
    ; web_image_height = 128.0
    };
  ignore
    (Lui_web.set_event_handler renderer (fun event ->
       ignore (Lui_app.dispatch_event app event);
       Lui_app.flush app));
  ignore (Lui_app.start app);
  ignore (Lui_app.flush app);
  let refresh_gallery_layout =
    mount_gallery_shell renderer (Lui_app.root_node app) host
  in
  mount_simulator_toolbar renderer refresh_gallery_layout;
  true
