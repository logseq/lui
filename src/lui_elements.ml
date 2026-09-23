(* Element DSL: typed constructors returning mount closures, e.g.
     row ~gap:4 [ child ] *)

open Lui_protocol

type t = Lui_ui.ui_context -> int option -> int

let mount context ?parent element = element context parent

(* Signal conveniences for view code: `map f src`, `sample src`,
   `src >|= f`, `const` — short spellings for the reactive props. *)

let reactive = Signal.map

let map = Signal.map

let sample = Signal.sample

let ( >|= ) source f = Signal.map f source

let get = Signal.get

let attach context parent node =
  match parent with
  | Some parent -> Lui_ui.append context parent node
  | None -> ()

let enable context node property =
  if Lui_protocol.property_supported (Lui_ui.node_kind context node) property
  then Lui_ui.bool_property context node property true

let mount_children context node children =
  List.iter (fun child -> ignore (child context (Some node))) children

(* Element adapters for dynamic structure: these mount reactive content
   under their parent node and return the parent as their (unused) node. *)

let dynamic mount : t =
 fun context parent ->
  match parent with
  | Some node ->
    ignore (mount context node);
    node
  | None -> invalid_arg "dynamic element requires a parent node"

let dyn ?(equal = fun _ _ -> false) f (source : 'a Signal.signal) : t =
 fun context parent ->
  dynamic
    (fun context node ->
       Lui_dynamic.switch context node source equal
         (fun branch_context value -> f value branch_context None))
    context parent

let if_ ~test (children : t) : t =
 fun context parent ->
  dynamic
    (fun context node ->
       Lui_dynamic.conditional context node test (fun branch_context ->
           children branch_context None))
    context parent

let keyed ~source ~key ~compare ~mount : t =
 fun context parent ->
  dynamic
    (fun context node ->
       Lui_dynamic.keyed context node source key compare
         (fun item_context item_source ->
            mount item_source item_context None))
    context parent

let press send action _event = ignore (send action)

let on_input send wrap event =
  match event with
  | TextChanged (_node, text) -> ignore (send (wrap text))
  | _ -> ()

let on_event context node predicate handler =
  Lui_ui.on_event context node (fun event ->
      if predicate event then handler event)

let is_press = function Press _ -> true | _ -> false
let is_long_press = function LongPress _ -> true | _ -> false
let is_double_press = function DoublePress _ -> true | _ -> false
let is_change = function Change _ -> true | _ -> false
let is_input = function TextChanged _ -> true | _ -> false
let is_submit = function Submit _ -> true | _ -> false
let is_toggle = function ToggleChanged _ -> true | _ -> false
let is_dismiss = function Dismiss _ -> true | _ -> false
let is_appear = function Appear _ -> true | _ -> false
let is_resize = function ValueChanged _ -> true | _ -> false

let register_press context node handler =
  ignore (on_event context node is_press handler)

let register_long_press context node handler =
  ignore (on_event context node is_long_press handler)

let register_double_press context node handler =
  ignore (on_event context node is_double_press handler)

let register_change context node handler =
  ignore (on_event context node is_change handler)

let register_input context node handler =
  ignore (on_event context node is_input handler)

let register_submit context node handler =
  ignore (on_event context node is_submit handler)

let register_toggle context node handler =
  ignore (on_event context node is_toggle handler)

let register_dismiss context node handler =
  ignore (on_event context node is_dismiss handler)

let appear_handler context node handler =
  enable context node AppearEnabled;
  ignore (on_event context node is_appear handler)

let register_resize context node handler =
  ignore (on_event context node is_resize handler)
let apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear =
  Option.iter (Lui_ui.key context node) key;
  Option.iter (Lui_ui.int_property context node Gap) gap;
  Option.iter (Lui_ui.string_property context node MainAlignment) main;
  Option.iter (Lui_ui.string_property context node CrossAlignment) cross;
  Option.iter (Lui_ui.float_property context node GrowValue) grow;
  Option.iter (Lui_ui.int_property context node GridColumns) columns;
  Option.iter (Lui_ui.int_property context node PaddingValue) padding;
  Option.iter (Lui_ui.int_property context node PaddingHorizontal) padding_horizontal;
  Option.iter (Lui_ui.int_property context node PaddingVertical) padding_vertical;
  Option.iter (Lui_ui.string_property context node BackgroundValue) background;
  Option.iter (Lui_ui.string_property context node ForegroundValue) foreground;
  Option.iter (Lui_ui.string_property context node BorderColorValue) border_color;
  Option.iter (Lui_ui.int_property context node BorderWidth) border_width;
  Option.iter (Lui_ui.int_property context node CornerRadius) corner_radius;
  Option.iter (Lui_ui.int_property context node WidthValue) width;
  Option.iter (Lui_ui.int_property context node HeightValue) height;
  Option.iter (Lui_ui.int_property context node MinWidth) min_width;
  Option.iter (Lui_ui.int_property context node MaxWidth) max_width;
  Option.iter (Lui_ui.int_property context node MinHeight) min_height;
  Option.iter (Lui_ui.int_property context node MaxHeight) max_height;
  Option.iter (Lui_ui.string_property context node ContainerRelativeFrameValue) container_relative_frame;
  Option.iter (Lui_ui.int_property context node ContainerRelativeFrameInset) container_relative_frame_inset;
  Option.iter (Lui_ui.string_property context node AccessibilityIdentifier) accessibility_identifier;
  Option.iter (Lui_ui.string_property_signal context node AccessibilityIdentifier) accessibility_identifier_signal;
  Option.iter (Lui_ui.string_property_signal context node ForegroundValue) foreground_signal;
  Option.iter (Lui_ui.string_property_signal context node BackgroundValue) background_signal;
  Option.iter (Lui_ui.string_property context node StyleClass) style_class;
  (match on_appear with
   | Some handler -> appear_handler context node handler
   | None -> ())

let row ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.row context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  attach context parent node;
  mount_children context node children;
  node

let column ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.column context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  attach context parent node;
  mount_children context node children;
  node

let grid ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.grid context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  attach context parent node;
  mount_children context node children;
  node

let stack ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.stack context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  attach context parent node;
  mount_children context node children;
  node

let panel ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.panel context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  attach context parent node;
  mount_children context node children;
  node

let card ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.card context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  attach context parent node;
  mount_children context node children;
  node

let alert ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?variant ?text_alignment ?label (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.alert context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node VariantValue) variant;
  Option.iter (Lui_ui.string_property context node TextAlignment) text_alignment;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let bubble ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?variant ?label (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.bubble context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node VariantValue) variant;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let box ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.box context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  attach context parent node;
  mount_children context node children;
  node

let scroll ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.scroll context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  attach context parent node;
  mount_children context node children;
  node

let list ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.list context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  attach context parent node;
  mount_children context node children;
  node

let virtual_list ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.virtual_list context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  attach context parent node;
  mount_children context node children;
  node

let tabs ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?label ?orientation (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.tabs context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.string_property context node OrientationValue) orientation;
  attach context parent node;
  mount_children context node children;
  node

let bottom_tabs ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?label (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.bottom_tabs context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let bottom_tab ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?title ?icon ?selected ?selected_signal ?enabled ?enabled_signal ?on_press (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.bottom_tab context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TitleValue) title;
  Option.iter (Lui_ui.string_property context node InlineIconName) icon;
  Option.iter (Lui_ui.bool_property context node Selected) selected;
  Option.iter (Lui_ui.bool_property_signal context node Selected) selected_signal;
  Option.iter (Lui_ui.bool_property context node Enabled) enabled;
  Option.iter (Lui_ui.bool_property_signal context node Enabled) enabled_signal;
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let button_group ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?label (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.button_group context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let toggle_group ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?label (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.toggle_group context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let breadcrumb ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?label (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.breadcrumb context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let pagination ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?label (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.pagination context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let table ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.table context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  attach context parent node;
  mount_children context node children;
  node

let table_row ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?selected ?selected_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.table_row context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.bool_property context node Selected) selected;
  Option.iter (Lui_ui.bool_property_signal context node Selected) selected_signal;
  attach context parent node;
  mount_children context node children;
  node

let table_cell ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?size ?text_alignment ?on_press (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.table_cell context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node SizeValue) size;
  Option.iter (Lui_ui.string_property context node TextAlignment) text_alignment;
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let tree ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?label ?role ?tree_level ?expanded ?expanded_signal ?on_press ?on_change ?on_toggle (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.tree context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.string_property context node RoleValue) role;
  Option.iter (Lui_ui.int_property context node TreeLevel) tree_level;
  Option.iter (Lui_ui.bool_property context node Expanded) expanded;
  Option.iter (Lui_ui.bool_property_signal context node Expanded) expanded_signal;
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  (match on_change with
   | Some handler ->
     enable context node ChangeEnabled;
     register_change context node handler
   | None -> ());
  (match on_toggle with
   | Some handler ->
     enable context node ToggleEnabled;
     register_toggle context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let resizable ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?label ?resizable_width (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.resizable context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.int_property context node WidthValue) resizable_width;
  attach context parent node;
  mount_children context node children;
  node

let split ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?value ?value_signal ?resize_duration ?resize_easing ?resize_origin ?label ?on_resize (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.create context Split in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.float_property context node ProgressValue) value;
  Option.iter (Lui_ui.float_property_signal context node ProgressValue) value_signal;
  Option.iter (Lui_ui.int_property context node ResizeDuration) resize_duration;
  Option.iter (Lui_ui.string_property context node ResizeEasing) resize_easing;
  Option.iter (Lui_ui.float_property context node ResizeOrigin) resize_origin;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  (match on_resize with
   | Some handler -> register_resize context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let drawer ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?selected ?selected_signal ?disabled ?disabled_signal ?label ?on_toggle (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.drawer context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.bool_property context node Selected) selected;
  Option.iter (Lui_ui.bool_property_signal context node Selected) selected_signal;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  Option.iter (Lui_ui.string_property context node TextValue) label;
  (match on_toggle with
   | Some handler ->
     enable context node ToggleEnabled;
     register_toggle context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let status_bar ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?value ?value_signal ?text_alignment (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.status_bar context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) value;
  Option.iter (Lui_ui.string_property_signal context node TextValue) value_signal;
  Option.iter (Lui_ui.string_property context node TextAlignment) text_alignment;
  attach context parent node;
  mount_children context node children;
  node

let spacer ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.spacer context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  attach context parent node;
  mount_children context node children;
  node

let spinner ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?size (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.spinner context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node SizeValue) size;
  attach context parent node;
  mount_children context node children;
  node

let icon ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?name ?name_signal ?size (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.create context Icon in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node IconName) name;
  Option.iter (Lui_ui.string_property_signal context node IconName) name_signal;
  Option.iter (Lui_ui.string_property context node SizeValue) size;
  attach context parent node;
  mount_children context node children;
  node

let text ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?value ?value_signal ?text_alignment ?on_press (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.create context Text in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) value;
  Option.iter (Lui_ui.string_property_signal context node TextValue) value_signal;
  Option.iter (Lui_ui.string_property context node TextAlignment) text_alignment;
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let heading ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?level ?value ?value_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.create context Heading in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.int_property context node HeadingLevel) level;
  Option.iter (Lui_ui.string_property context node TextValue) value;
  Option.iter (Lui_ui.string_property_signal context node TextValue) value_signal;
  attach context parent node;
  mount_children context node children;
  node

let paragraph ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?value ?value_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.create context Paragraph in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) value;
  Option.iter (Lui_ui.string_property_signal context node TextValue) value_signal;
  attach context parent node;
  mount_children context node children;
  node

let label ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?value ?value_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.create context Label in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) value;
  Option.iter (Lui_ui.string_property_signal context node TextValue) value_signal;
  attach context parent node;
  mount_children context node children;
  node

let button ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?variant ?size ?icon ?icon_placement ?label ?text_alignment ?selected ?autofocus ?disabled ?disabled_signal ?on_press ?on_long_press (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.button context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node VariantValue) variant;
  Option.iter (Lui_ui.string_property context node SizeValue) size;
  Option.iter (Lui_ui.string_property context node InlineIconName) icon;
  Option.iter (Lui_ui.string_property context node IconPlacementValue) icon_placement;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.string_property context node TextAlignment) text_alignment;
  Option.iter (Lui_ui.bool_property context node Selected) selected;
  Option.iter (Lui_ui.bool_property context node Autofocus) autofocus;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  (match on_long_press with
   | Some handler ->
     enable context node LongPressEnabled;
     register_long_press context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let toggle_button ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?variant ?size ?icon ?icon_placement ?label ?text_alignment ?selected ?autofocus ?disabled ?disabled_signal ?on_press ?on_toggle ?on_long_press (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.toggle_button context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node VariantValue) variant;
  Option.iter (Lui_ui.string_property context node SizeValue) size;
  Option.iter (Lui_ui.string_property context node InlineIconName) icon;
  Option.iter (Lui_ui.string_property context node IconPlacementValue) icon_placement;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.string_property context node TextAlignment) text_alignment;
  Option.iter (Lui_ui.bool_property context node Selected) selected;
  Option.iter (Lui_ui.bool_property context node Autofocus) autofocus;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  (match on_toggle with
   | Some handler ->
     enable context node ToggleEnabled;
     register_toggle context node handler
   | None -> ());
  (match on_long_press with
   | Some handler ->
     enable context node LongPressEnabled;
     register_long_press context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let checkbox ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?checked ?checked_signal ?label ?disabled ?disabled_signal ?on_toggle (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.checkbox context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.bool_property context node Checked) checked;
  Option.iter (Lui_ui.bool_property_signal context node Checked) checked_signal;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  (match on_toggle with
   | Some handler ->
     enable context node ToggleEnabled;
     register_toggle context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let switch_ ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?checked ?checked_signal ?label ?disabled ?disabled_signal ?on_toggle (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.switch_control context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.bool_property context node Checked) checked;
  Option.iter (Lui_ui.bool_property_signal context node Checked) checked_signal;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  (match on_toggle with
   | Some handler ->
     enable context node ToggleEnabled;
     register_toggle context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let toggle ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?checked ?checked_signal ?label ?disabled ?disabled_signal ?on_toggle (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.toggle context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.bool_property context node Checked) checked;
  Option.iter (Lui_ui.bool_property_signal context node Checked) checked_signal;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  (match on_toggle with
   | Some handler ->
     enable context node ToggleEnabled;
     register_toggle context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let radio_group ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?label (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.radio_group context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let radio ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?checked ?checked_signal ?selected ?label ?disabled ?disabled_signal ?on_change ?on_toggle ?on_press (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.radio context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.bool_property context node Checked) checked;
  Option.iter (Lui_ui.bool_property_signal context node Checked) checked_signal;
  Option.iter (Lui_ui.bool_property context node Checked) selected;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  (match on_change with
   | Some handler ->
     enable context node ChangeEnabled;
     register_change context node handler
   | None -> ());
  (match on_toggle with
   | Some handler ->
     enable context node ToggleEnabled;
     register_toggle context node handler
   | None -> ());
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let slider ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?value ?value_signal ?label ?disabled ?disabled_signal ?on_change (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.create context Slider in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.float_property context node ProgressValue) value;
  Option.iter (Lui_ui.float_property_signal context node ProgressValue) value_signal;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  (match on_change with
   | Some handler -> register_resize context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let progress ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?value ?value_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.create context Progress in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.float_property context node ProgressValue) value;
  Option.iter (Lui_ui.float_property_signal context node ProgressValue) value_signal;
  attach context parent node;
  mount_children context node children;
  node

let divider ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?orientation (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.create context Divider in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node OrientationValue) orientation;
  attach context parent node;
  mount_children context node children;
  node

let separator ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?orientation (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.create context Divider in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node OrientationValue) orientation;
  attach context parent node;
  mount_children context node children;
  node

let text_field ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?placeholder ?label ?autofocus ?submit_on_enter ?disabled ?disabled_signal ?on_input ?on_submit (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.text_field context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node PlaceholderValue) placeholder;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.bool_property context node Autofocus) autofocus;
  Option.iter (Lui_ui.bool_property context node SubmitOnEnter) submit_on_enter;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  (match on_input with
   | Some handler ->
     enable context node ChangeEnabled;
     register_input context node handler
   | None -> ());
  (match on_submit with
   | Some handler ->
     enable context node SubmitEnabled;
     register_submit context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let secure_field ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?placeholder ?label ?autofocus ?submit_on_enter ?disabled ?disabled_signal ?on_input ?on_submit (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.secure_field context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node PlaceholderValue) placeholder;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.bool_property context node Autofocus) autofocus;
  Option.iter (Lui_ui.bool_property context node SubmitOnEnter) submit_on_enter;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  (match on_input with
   | Some handler ->
     enable context node ChangeEnabled;
     register_input context node handler
   | None -> ());
  (match on_submit with
   | Some handler ->
     enable context node SubmitEnabled;
     register_submit context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let input ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?placeholder ?label ?autofocus ?submit_on_enter ?disabled ?disabled_signal ?on_input ?on_submit (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.input context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node PlaceholderValue) placeholder;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.bool_property context node Autofocus) autofocus;
  Option.iter (Lui_ui.bool_property context node SubmitOnEnter) submit_on_enter;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  (match on_input with
   | Some handler ->
     enable context node ChangeEnabled;
     register_input context node handler
   | None -> ());
  (match on_submit with
   | Some handler ->
     enable context node SubmitEnabled;
     register_submit context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let search_field ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?placeholder ?label ?autofocus ?submit_on_enter ?disabled ?disabled_signal ?on_input ?on_submit (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.search_field context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node PlaceholderValue) placeholder;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.bool_property context node Autofocus) autofocus;
  Option.iter (Lui_ui.bool_property context node SubmitOnEnter) submit_on_enter;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  (match on_input with
   | Some handler ->
     enable context node ChangeEnabled;
     register_input context node handler
   | None -> ());
  (match on_submit with
   | Some handler ->
     enable context node SubmitEnabled;
     register_submit context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let textarea ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?placeholder ?label ?autofocus ?submit_on_enter ?disabled ?disabled_signal ?on_input ?on_submit (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.textarea context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node PlaceholderValue) placeholder;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.bool_property context node Autofocus) autofocus;
  Option.iter (Lui_ui.bool_property context node SubmitOnEnter) submit_on_enter;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  (match on_input with
   | Some handler ->
     enable context node ChangeEnabled;
     register_input context node handler
   | None -> ());
  (match on_submit with
   | Some handler ->
     enable context node SubmitEnabled;
     register_submit context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let input_group ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?label (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.input_group context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let input_group_actions ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.input_group_actions context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  attach context parent node;
  mount_children context node children;
  node

let select ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?label ?text ?text_signal ?placeholder ?disabled ?disabled_signal ?on_press ?on_input ?on_submit ?on_dismiss (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.select context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node PlaceholderValue) placeholder;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  (match on_input with
   | Some handler ->
     enable context node ChangeEnabled;
     register_input context node handler
   | None -> ());
  (match on_submit with
   | Some handler ->
     enable context node SubmitEnabled;
     register_submit context node handler
   | None -> ());
  (match on_dismiss with
   | Some handler -> register_dismiss context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let combobox ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?placeholder ?disabled ?disabled_signal ?on_press ?on_input ?on_submit ?on_dismiss (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.combobox context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node PlaceholderValue) placeholder;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  (match on_input with
   | Some handler ->
     enable context node ChangeEnabled;
     register_input context node handler
   | None -> ());
  (match on_submit with
   | Some handler ->
     enable context node SubmitEnabled;
     register_submit context node handler
   | None -> ());
  (match on_dismiss with
   | Some handler -> register_dismiss context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let dropdown_menu ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?anchor ?anchor_alignment ?anchor_offset ?on_press ?on_input ?on_submit ?on_dismiss (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.dropdown_menu context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node AnchorValue) anchor;
  Option.iter (Lui_ui.string_property context node AnchorAlignmentValue) anchor_alignment;
  Option.iter (Lui_ui.float_property context node AnchorOffset) anchor_offset;
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  (match on_input with
   | Some handler ->
     enable context node ChangeEnabled;
     register_input context node handler
   | None -> ());
  (match on_submit with
   | Some handler ->
     enable context node SubmitEnabled;
     register_submit context node handler
   | None -> ());
  (match on_dismiss with
   | Some handler -> register_dismiss context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let context_menu ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?disabled ?disabled_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.context_menu context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  attach context parent node;
  mount_children context node children;
  node

let dialog ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?on_dismiss (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.dialog context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  (match on_dismiss with
   | Some handler -> register_dismiss context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let sheet ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?on_dismiss (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.sheet context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  (match on_dismiss with
   | Some handler -> register_dismiss context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let tooltip ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?anchor ?anchor_alignment ?anchor_offset ?tooltip_delay (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.tooltip context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node AnchorValue) anchor;
  Option.iter (Lui_ui.string_property context node AnchorAlignmentValue) anchor_alignment;
  Option.iter (Lui_ui.float_property context node AnchorOffset) anchor_offset;
  Option.iter (Lui_ui.int_property context node TooltipDelay) tooltip_delay;
  attach context parent node;
  mount_children context node children;
  node

let toast ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?duration ?label ?toast_class ?on_dismiss (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.toast context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.int_property context node DurationValue) duration;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.string_property context node StyleClass) toast_class;
  (match on_dismiss with
   | Some handler -> register_dismiss context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let toolbar ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?orientation ?label ?toolbar_gap ?toolbar_class (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.toolbar context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node OrientationValue) orientation;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.int_property context node Gap) toolbar_gap;
  Option.iter (Lui_ui.string_property context node StyleClass) toolbar_class;
  attach context parent node;
  mount_children context node children;
  node

let accordion ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?selected ?accordion_height ?on_toggle (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.accordion context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.bool_property context node Selected) selected;
  Option.iter (Lui_ui.int_property context node HeightValue) accordion_height;
  (match on_toggle with
   | Some handler ->
     enable context node ToggleEnabled;
     register_toggle context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let menu_item ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?icon ?role ?tree_level ?expanded ?disabled ?disabled_signal ?on_press ?on_input ?on_submit ?on_dismiss (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.menu_item context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node InlineIconName) icon;
  Option.iter (Lui_ui.string_property context node RoleValue) role;
  Option.iter (Lui_ui.int_property context node TreeLevel) tree_level;
  Option.iter (Lui_ui.bool_property context node Expanded) expanded;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  (match on_input with
   | Some handler ->
     enable context node ChangeEnabled;
     register_input context node handler
   | None -> ());
  (match on_submit with
   | Some handler ->
     enable context node SubmitEnabled;
     register_submit context node handler
   | None -> ());
  (match on_dismiss with
   | Some handler -> register_dismiss context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let list_item ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?icon ?icon_placement ?role ?tree_level ?expanded ?selected ?selected_signal ?disabled ?disabled_signal ?on_press ?on_long_press ?on_double_press ?on_submit ?on_input ?on_toggle (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.list_item context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node InlineIconName) icon;
  Option.iter (Lui_ui.string_property context node IconPlacementValue) icon_placement;
  Option.iter (Lui_ui.string_property context node RoleValue) role;
  Option.iter (Lui_ui.int_property context node TreeLevel) tree_level;
  Option.iter (Lui_ui.bool_property context node Expanded) expanded;
  Option.iter (Lui_ui.bool_property context node Selected) selected;
  Option.iter (Lui_ui.bool_property_signal context node Selected) selected_signal;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  (match on_long_press with
   | Some handler ->
     enable context node LongPressEnabled;
     register_long_press context node handler
   | None -> ());
  (match on_double_press with
   | Some handler ->
     enable context node DoublePressEnabled;
     register_double_press context node handler
   | None -> ());
  (match on_submit with
   | Some handler ->
     enable context node SubmitEnabled;
     register_submit context node handler
   | None -> ());
  (match on_input with
   | Some handler ->
     enable context node ChangeEnabled;
     register_input context node handler
   | None -> ());
  (match on_toggle with
   | Some handler ->
     enable context node ToggleEnabled;
     register_toggle context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let avatar ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?image ?image_signal ?source_x ?source_y ?source_width ?source_height ?label (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.create context Avatar in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.int_property context node ImageIdValue) image;
  Option.iter (Lui_ui.int_property_signal context node ImageIdValue) image_signal;
  Option.iter (Lui_ui.float_property context node SourceX) source_x;
  Option.iter (Lui_ui.float_property context node SourceY) source_y;
  Option.iter (Lui_ui.float_property context node SourceWidth) source_width;
  Option.iter (Lui_ui.float_property context node SourceHeight) source_height;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let image ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?image ?image_signal ?source_x ?source_y ?source_width ?source_height ?label (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.create context Image in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.int_property context node ImageIdValue) image;
  Option.iter (Lui_ui.int_property_signal context node ImageIdValue) image_signal;
  Option.iter (Lui_ui.float_property context node SourceX) source_x;
  Option.iter (Lui_ui.float_property context node SourceY) source_y;
  Option.iter (Lui_ui.float_property context node SourceWidth) source_width;
  Option.iter (Lui_ui.float_property context node SourceHeight) source_height;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let media_surface ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?surface ?surface_signal ?label (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.create context MediaSurface in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.int_property context node SurfaceIdValue) surface;
  Option.iter (Lui_ui.int_property_signal context node SurfaceIdValue) surface_signal;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let stepper ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?active ?active_signal ?label (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.create context Stepper in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.int_property context node ActiveIndex) active;
  Option.iter (Lui_ui.int_property_signal context node ActiveIndex) active_signal;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let step ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.step context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  attach context parent node;
  mount_children context node children;
  node

let timeline ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?label (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.timeline context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let timeline_item ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?title ?title_signal ?description ?meta ?indicator ?icon ?variant ?connector ?selected ?on_press (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.timeline_item context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TitleValue) title;
  Option.iter (Lui_ui.string_property_signal context node TitleValue) title_signal;
  Option.iter (Lui_ui.string_property context node DescriptionValue) description;
  Option.iter (Lui_ui.string_property context node MetaValue) meta;
  Option.iter (Lui_ui.string_property context node IndicatorValue) indicator;
  Option.iter (Lui_ui.string_property context node InlineIconName) icon;
  Option.iter (Lui_ui.string_property context node VariantValue) variant;
  Option.iter (Lui_ui.bool_property context node Connector) connector;
  Option.iter (Lui_ui.bool_property context node Selected) selected;
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node
