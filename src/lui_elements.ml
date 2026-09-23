(* Element DSL: typed constructors returning mount closures, e.g.
     row ~gap:4 [ child ] *)

open Lui_protocol

type t = Lui_ui.ui_context -> int option -> int

(* Closed vocabularies from the wire schema: fixed-value props are typed as
   polymorphic variants so invalid values fail [dune build] instead of
   erroring inside [emit_patch] at emit time. [icon] also accepts
   [`app of string] for application-registered SF Symbol names. *)

type variant =
  [ `default | `primary | `secondary | `outline | `ghost | `destructive ]

type control_size = [ `default | `sm | `lg | `icon ]
type text_size = [ `heading | `display ]
type cell_size = [ control_size | text_size ]
type main_alignment = [ `start | `center | `end_ | `space_between ]
type cross_alignment = [ `stretch | `start | `center | `end_ ]
type text_alignment = [ `start | `center | `end_ ]
type orientation = [ `horizontal | `vertical ]
type icon_placement = [ `leading | `trailing | `top ]
type anchor = [ `above | `below | `left | `right ]
type anchor_alignment = [ `start | `end_ | `stretch ]

type frame_axes =
  [ `horizontal | `vertical | `both
  | `min_horizontal | `min_vertical | `min_both ]

type resize_easing = [ `linear | `standard | `emphasized | `spring ]
type role = [ `treeitem | `navigation | `navigation_heading ]

type icon =
  [ `alert | `archive | `arrow_down | `arrow_right | `arrow_up | `check | `check_circle | `chevron_down | `chevron_left | `chevron_right | `chevron_up | `circle_dot | `clock | `copy | `download | `edit | `ellipsis | `external_link | `eye | `file_text | `folder | `folder_open | `git_branch | `git_merge | `git_pull_request | `info | `menu | `mic | `moon | `music | `panel_left | `panel_right | `pause | `play | `plus | `refresh_cw | `repeat | `save | `search | `send | `settings | `shuffle | `skip_back | `skip_forward | `sun | `terminal | `trash | `volume | `wrench | `x | `x_circle
  | `app of string ]

(* Element kinds the schema restricts to specific parents: these types are
   abstract in the .mli so [stepper], [timeline], [bottom_tabs], [table],
   [table_row], [radio_group] and [input_group] can require them and illegal
   nesting fails at compile time. *)

type step_el = t
type timeline_item_el = t
type bottom_tab_el = t
type table_row_el = t
type table_cell_el = t
type radio_el = t
type input_group_actions_el = t

(* Children slot of leaf elements: the only inhabitant is [[]], so any real
   child fails [dune build] instead of being rejected by the schema at emit. *)
type nothing = |

let variant_value : variant -> string = function
  | `default -> "default"
  | `primary -> "primary"
  | `secondary -> "secondary"
  | `outline -> "outline"
  | `ghost -> "ghost"
  | `destructive -> "destructive"

let control_size_value : control_size -> string = function
  | `default -> "default"
  | `sm -> "sm"
  | `lg -> "lg"
  | `icon -> "icon"

let text_size_value : text_size -> string = function
  | `heading -> "heading"
  | `display -> "display"

let cell_size_value : cell_size -> string = function
  | #control_size as size -> control_size_value size
  | #text_size as size -> text_size_value size

let main_alignment_value : main_alignment -> string = function
  | `start -> "start"
  | `center -> "center"
  | `end_ -> "end"
  | `space_between -> "space_between"

let cross_alignment_value : cross_alignment -> string = function
  | `stretch -> "stretch"
  | `start -> "start"
  | `center -> "center"
  | `end_ -> "end"

let text_alignment_value : text_alignment -> string = function
  | `start -> "start"
  | `center -> "center"
  | `end_ -> "end"

let orientation_value : orientation -> string = function
  | `horizontal -> "horizontal"
  | `vertical -> "vertical"

let icon_placement_value : icon_placement -> string = function
  | `leading -> "leading"
  | `trailing -> "trailing"
  | `top -> "top"

let anchor_value : anchor -> string = function
  | `above -> "above"
  | `below -> "below"
  | `left -> "left"
  | `right -> "right"

let anchor_alignment_value : anchor_alignment -> string = function
  | `start -> "start"
  | `end_ -> "end"
  | `stretch -> "stretch"

let frame_axes_value : frame_axes -> string = function
  | `horizontal -> "horizontal"
  | `vertical -> "vertical"
  | `both -> "both"
  | `min_horizontal -> "min-horizontal"
  | `min_vertical -> "min-vertical"
  | `min_both -> "min-both"

let resize_easing_value : resize_easing -> string = function
  | `linear -> "linear"
  | `standard -> "standard"
  | `emphasized -> "emphasized"
  | `spring -> "spring"

let role_value : role -> string = function
  | `treeitem -> "treeitem"
  | `navigation -> "navigation"
  | `navigation_heading -> "navigation-heading"

let icon_value : icon -> string = function
  | `app name -> "app:" ^ name
  | `alert -> "alert"
  | `archive -> "archive"
  | `arrow_down -> "arrow-down"
  | `arrow_right -> "arrow-right"
  | `arrow_up -> "arrow-up"
  | `check -> "check"
  | `check_circle -> "check-circle"
  | `chevron_down -> "chevron-down"
  | `chevron_left -> "chevron-left"
  | `chevron_right -> "chevron-right"
  | `chevron_up -> "chevron-up"
  | `circle_dot -> "circle-dot"
  | `clock -> "clock"
  | `copy -> "copy"
  | `download -> "download"
  | `edit -> "edit"
  | `ellipsis -> "ellipsis"
  | `external_link -> "external-link"
  | `eye -> "eye"
  | `file_text -> "file-text"
  | `folder -> "folder"
  | `folder_open -> "folder-open"
  | `git_branch -> "git-branch"
  | `git_merge -> "git-merge"
  | `git_pull_request -> "git-pull-request"
  | `info -> "info"
  | `menu -> "menu"
  | `mic -> "mic"
  | `moon -> "moon"
  | `music -> "music"
  | `panel_left -> "panel-left"
  | `panel_right -> "panel-right"
  | `pause -> "pause"
  | `play -> "play"
  | `plus -> "plus"
  | `refresh_cw -> "refresh-cw"
  | `repeat -> "repeat"
  | `save -> "save"
  | `search -> "search"
  | `send -> "send"
  | `settings -> "settings"
  | `shuffle -> "shuffle"
  | `skip_back -> "skip-back"
  | `skip_forward -> "skip-forward"
  | `sun -> "sun"
  | `terminal -> "terminal"
  | `trash -> "trash"
  | `volume -> "volume"
  | `wrench -> "wrench"
  | `x -> "x"
  | `x_circle -> "x-circle"

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
  enable context node ChangeEnabled;
  ignore (on_event context node is_resize handler)
let apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear =
  Option.iter (Lui_ui.key context node) key;
  Option.iter (Lui_ui.int_property context node Gap) gap;
  Option.iter (Lui_ui.string_property context node MainAlignment) (Option.map main_alignment_value main);
  Option.iter (Lui_ui.string_property context node CrossAlignment) (Option.map cross_alignment_value cross);
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
  Option.iter (Lui_ui.string_property context node ContainerRelativeFrameValue) (Option.map frame_axes_value container_relative_frame);
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
  Option.iter (Lui_ui.string_property context node VariantValue) (Option.map variant_value variant);
  Option.iter (Lui_ui.string_property context node TextAlignment) (Option.map text_alignment_value text_alignment);
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
  Option.iter (Lui_ui.string_property context node VariantValue) (Option.map variant_value variant);
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

let scroll ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?orientation (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.scroll context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node OrientationValue) (Option.map orientation_value orientation);
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
  Option.iter (Lui_ui.string_property context node OrientationValue) (Option.map orientation_value orientation);
  attach context parent node;
  mount_children context node children;
  node

let bottom_tabs ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?label (children : bottom_tab_el list) : t =
 fun context parent ->
  let node = Lui_ui.bottom_tabs context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let bottom_tab ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?title ?icon ?selected ?selected_signal ?enabled ?enabled_signal ?on_press (children : t list) : bottom_tab_el =
 fun context parent ->
  let node = Lui_ui.bottom_tab context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TitleValue) title;
  Option.iter (Lui_ui.string_property context node InlineIconName) (Option.map icon_value icon);
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

let table ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear (children : table_row_el list) : t =
 fun context parent ->
  let node = Lui_ui.table context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  attach context parent node;
  mount_children context node children;
  node

let table_row ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?selected ?selected_signal (children : table_cell_el list) : table_row_el =
 fun context parent ->
  let node = Lui_ui.table_row context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.bool_property context node Selected) selected;
  Option.iter (Lui_ui.bool_property_signal context node Selected) selected_signal;
  attach context parent node;
  mount_children context node children;
  node

let table_cell ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?size ?text_alignment ?on_press (children : t list) : table_cell_el =
 fun context parent ->
  let node = Lui_ui.table_cell context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node SizeValue) (Option.map cell_size_value size);
  Option.iter (Lui_ui.string_property context node TextAlignment) (Option.map text_alignment_value text_alignment);
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
  Option.iter (Lui_ui.string_property context node RoleValue) (Option.map role_value role);
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

let split ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?value ?value_signal ?resize_duration ?resize_easing ?resize_origin ?label ?on_resize (first : t) (second : t) : t =
 fun context parent ->
  let node = Lui_ui.create context Split in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.float_property context node ProgressValue) value;
  Option.iter (Lui_ui.float_property_signal context node ProgressValue) value_signal;
  Option.iter (Lui_ui.int_property context node ResizeDuration) resize_duration;
  Option.iter (Lui_ui.string_property context node ResizeEasing) (Option.map resize_easing_value resize_easing);
  Option.iter (Lui_ui.float_property context node ResizeOrigin) resize_origin;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  (match on_resize with
   | Some handler -> register_resize context node handler
   | None -> ());
  attach context parent node;
  ignore (first context (Some node));
  ignore (second context (Some node));
  node

let drawer ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?selected ?selected_signal ?disabled ?disabled_signal ?label ?on_toggle (first : t) (second : t) : t =
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
  ignore (first context (Some node));
  ignore (second context (Some node));
  node

let status_bar ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?value ?value_signal ?text_alignment (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.status_bar context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) value;
  Option.iter (Lui_ui.string_property_signal context node TextValue) value_signal;
  Option.iter (Lui_ui.string_property context node TextAlignment) (Option.map text_alignment_value text_alignment);
  attach context parent node;
  
  node

let spacer ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.spacer context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  attach context parent node;
  
  node

let spinner ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?size (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.spinner context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node SizeValue) (Option.map control_size_value size);
  attach context parent node;
  
  node

let icon ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?name ?name_signal ?size ?point_size (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context Icon in
  let width = match width with Some _ -> width | None -> point_size in
  let height = match height with Some _ -> height | None -> point_size in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node IconName) (Option.map icon_value name);
  Option.iter (fun signal -> Lui_ui.string_property_signal context node IconName (Signal.map icon_value signal)) name_signal;
  Option.iter (Lui_ui.string_property context node SizeValue) (Option.map control_size_value size);
  attach context parent node;
  
  node

let text ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?value ?value_signal ?text_alignment ?on_press (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.create context Text in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) value;
  Option.iter (Lui_ui.string_property_signal context node TextValue) value_signal;
  Option.iter (Lui_ui.string_property context node TextAlignment) (Option.map text_alignment_value text_alignment);
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let heading ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?level ?value ?value_signal (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context Heading in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.int_property context node HeadingLevel) level;
  Option.iter (Lui_ui.string_property context node TextValue) value;
  Option.iter (Lui_ui.string_property_signal context node TextValue) value_signal;
  attach context parent node;
  
  node

let paragraph ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?value ?value_signal (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context Paragraph in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) value;
  Option.iter (Lui_ui.string_property_signal context node TextValue) value_signal;
  attach context parent node;
  
  node

let label ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?value ?value_signal (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context Label in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) value;
  Option.iter (Lui_ui.string_property_signal context node TextValue) value_signal;
  attach context parent node;
  
  node

let button ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?variant ?size ?icon ?icon_placement ?label ?text_alignment ?selected ?autofocus ?disabled ?disabled_signal ?on_press ?on_long_press (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.button context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node VariantValue) (Option.map variant_value variant);
  Option.iter (Lui_ui.string_property context node SizeValue) (Option.map control_size_value size);
  Option.iter (Lui_ui.string_property context node InlineIconName) (Option.map icon_value icon);
  Option.iter (Lui_ui.string_property context node IconPlacementValue) (Option.map icon_placement_value icon_placement);
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.string_property context node TextAlignment) (Option.map text_alignment_value text_alignment);
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

let toggle_button ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?variant ?size ?icon ?icon_placement ?label ?text_alignment ?selected ?checked ?checked_signal ?autofocus ?disabled ?disabled_signal ?on_press ?on_toggle ?on_long_press (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.toggle_button context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node VariantValue) (Option.map variant_value variant);
  Option.iter (Lui_ui.string_property context node SizeValue) (Option.map control_size_value size);
  Option.iter (Lui_ui.string_property context node InlineIconName) (Option.map icon_value icon);
  Option.iter (Lui_ui.string_property context node IconPlacementValue) (Option.map icon_placement_value icon_placement);
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.string_property context node TextAlignment) (Option.map text_alignment_value text_alignment);
  let selected = match selected with Some _ -> selected | None -> checked in
  Option.iter (Lui_ui.bool_property context node Selected) selected;
  Option.iter (Lui_ui.bool_property_signal context node Selected) checked_signal;
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

let radio_group ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?label (children : radio_el list) : t =
 fun context parent ->
  let node = Lui_ui.radio_group context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let radio ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?checked ?checked_signal ?selected ?label ?disabled ?disabled_signal ?on_change ?on_toggle ?on_press (children : t list) : radio_el =
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
  let press_handler =
    match on_press with
    | Some _ -> on_press
    | None -> on_toggle
  in
  (match press_handler with
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

let progress ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?value ?value_signal (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context Progress in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.float_property context node ProgressValue) value;
  Option.iter (Lui_ui.float_property_signal context node ProgressValue) value_signal;
  attach context parent node;
  
  node

let divider ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?orientation (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context Divider in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node OrientationValue) (Option.map orientation_value orientation);
  attach context parent node;
  
  node

let separator ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?orientation (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context Divider in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node OrientationValue) (Option.map orientation_value orientation);
  attach context parent node;
  
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

let input_group ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?label ?actions (field : t) : t =
 fun context parent ->
  let node = Lui_ui.input_group context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  ignore (field context (Some node));
  Option.iter (fun actions -> ignore (actions context (Some node))) actions;
  node

let input_group_actions ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear (children : t list) : input_group_actions_el =
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
  Option.iter (Lui_ui.string_property context node AnchorValue) (Option.map anchor_value anchor);
  Option.iter (Lui_ui.string_property context node AnchorAlignmentValue) (Option.map anchor_alignment_value anchor_alignment);
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

let dialog ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?description ?description_signal ?on_dismiss (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.dialog context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node DescriptionValue) description;
  Option.iter (Lui_ui.string_property_signal context node DescriptionValue) description_signal;
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

let tooltip ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?anchor ?anchor_alignment ?anchor_offset ?tooltip_delay (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.tooltip context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node AnchorValue) (Option.map anchor_value anchor);
  Option.iter (Lui_ui.string_property context node AnchorAlignmentValue) (Option.map anchor_alignment_value anchor_alignment);
  Option.iter (Lui_ui.float_property context node AnchorOffset) anchor_offset;
  Option.iter (Lui_ui.int_property context node TooltipDelay) tooltip_delay;
  attach context parent node;
  
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
  Option.iter (Lui_ui.string_property context node OrientationValue) (Option.map orientation_value orientation);
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

let menu_item ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?icon ?role ?variant ?size ?tree_level ?expanded ?selected ?checked ?selected_signal ?checked_signal ?disabled ?disabled_signal ?on_press ?on_input ?on_submit ?on_dismiss (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.menu_item context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node InlineIconName) (Option.map icon_value icon);
  Option.iter (Lui_ui.string_property context node RoleValue) (Option.map role_value role);
  Option.iter (Lui_ui.string_property context node VariantValue) (Option.map variant_value variant);
  Option.iter (Lui_ui.string_property context node SizeValue) (Option.map control_size_value size);
  Option.iter (Lui_ui.int_property context node TreeLevel) tree_level;
  Option.iter (Lui_ui.bool_property context node Expanded) expanded;
  let selected = match selected with Some _ -> selected | None -> checked in
  Option.iter (Lui_ui.bool_property context node Selected) selected;
  let selected_signal =
    match selected_signal with
    | Some _ -> selected_signal
    | None -> checked_signal
  in
  Option.iter (Lui_ui.bool_property_signal context node Selected) selected_signal;
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

let submenu ?key ?text ?icon ?role ?variant ?selected ?checked ?disabled
    ?on_dismiss entries : t =
 fun context parent ->
  let host =
    menu_item ?key ?text ?icon ?role ?variant ?selected ?checked ?disabled
      ?on_dismiss [] context parent
  in
  ignore (dropdown_menu entries context (Some host));
  host

let list_item ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?icon ?icon_placement ?role ?tree_level ?expanded ?selected ?selected_signal ?disabled ?disabled_signal ?on_press ?on_long_press ?on_double_press ?on_submit ?on_input ?on_toggle (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.list_item context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node InlineIconName) (Option.map icon_value icon);
  Option.iter (Lui_ui.string_property context node IconPlacementValue) (Option.map icon_placement_value icon_placement);
  Option.iter (Lui_ui.string_property context node RoleValue) (Option.map role_value role);
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

let avatar ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal ?image ?image_signal ?source_x ?source_y ?source_width ?source_height ?label (_children : nothing list) : t =
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
  
  node

let image ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?image ?image_signal ?source_x ?source_y ?source_width ?source_height ?label (_children : nothing list) : t =
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
  
  node

let media_surface ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?surface ?surface_signal ?label (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context MediaSurface in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.int_property context node SurfaceIdValue) surface;
  Option.iter (Lui_ui.int_property_signal context node SurfaceIdValue) surface_signal;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  
  node

let stepper ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?active ?active_signal ?label (children : step_el list) : t =
 fun context parent ->
  let node = Lui_ui.create context Stepper in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.int_property context node ActiveIndex) active;
  Option.iter (Lui_ui.int_property_signal context node ActiveIndex) active_signal;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let step ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?text ?text_signal (_children : nothing list) : step_el =
 fun context parent ->
  let node = Lui_ui.step context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  attach context parent node;
  
  node

let timeline ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?label (children : timeline_item_el list) : t =
 fun context parent ->
  let node = Lui_ui.timeline context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let timeline_item ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?on_appear ?title ?title_signal ?description ?meta ?indicator ?icon ?variant ?connector ?selected ?on_press (_children : nothing list) : timeline_item_el =
 fun context parent ->
  let node = Lui_ui.timeline_item context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~on_appear;
  Option.iter (Lui_ui.string_property context node TitleValue) title;
  Option.iter (Lui_ui.string_property_signal context node TitleValue) title_signal;
  Option.iter (Lui_ui.string_property context node DescriptionValue) description;
  Option.iter (Lui_ui.string_property context node MetaValue) meta;
  Option.iter (Lui_ui.string_property context node IndicatorValue) indicator;
  Option.iter (Lui_ui.string_property context node InlineIconName) (Option.map icon_value icon);
  Option.iter (Lui_ui.string_property context node VariantValue) (Option.map variant_value variant);
  Option.iter (Lui_ui.bool_property context node Connector) connector;
  Option.iter (Lui_ui.bool_property context node Selected) selected;
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  attach context parent node;
  
  node
