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
type image_fit = [ `fit | `fill ]
type text_alignment = [ `start | `center | `end_ ]
type orientation = [ `horizontal | `vertical ]
type icon_placement = [ `leading | `trailing | `top ]
type anchor = [ `above | `below | `left | `right ]
type anchor_alignment = [ `start | `end_ | `stretch ]
type edge = [ `top | `bottom | `leading | `trailing ]

type alignment =
  [ `top_leading | `top | `top_trailing
  | `leading | `center | `trailing
  | `bottom_leading | `bottom | `bottom_trailing ]

type frame_axes =
  [ `horizontal | `vertical | `both
  | `min_horizontal | `min_vertical | `min_both ]

type resize_easing = [ `linear | `standard | `emphasized | `spring ]
type role = [ `treeitem | `navigation | `navigation_heading ]
type list_style = [ `plain | `inset | `inset_grouped ]
type scroll_anchor = [ `top | `center | `bottom ]
type separator_visibility = [ `visible | `hidden ]

type image_loading = [ `eager | `lazy_ ]

type referrer_policy =
  [ `no_referrer | `origin | `strict_origin_when_cross_origin | `unsafe_url ]

type link_target = [ `self_ | `blank ]
type display = [ `contents ]
type input_kind = [ `text | `color ]
type popover_role = [ `menu ]
type swipe_edge = [ `leading | `trailing ]

(* [~as_] element-tag overrides for the phrasing kinds ([text], [heading],
   [paragraph], [label]) on web. [Lui_protocol.element_tag_supported]
   restricts each kind to its phrasing-appropriate subset, so a block tag
   on [text] fails validation at emit instead of breaking inline layout. *)
type element_tag =
  [ `Span
  | `Em
  | `Strong
  | `B
  | `I
  | `U
  | `S
  | `Del
  | `Mark
  | `Small
  | `Code
  | `Kbd
  | `Sub
  | `Sup
  | `Pre
  | `H1
  | `H2
  | `H3
  | `H4
  | `H5
  | `H6
  | `P
  | `Div
  | `Label ]

(** [~source] of [file_picker]: [`files] presents a document importer,
    [`photos] the photo library, [`camera] live capture (iOS only —
    other platforms answer the request with a cancel event). *)
type file_picker_source = [ `files | `photos | `camera ]

(** [~request] / [~completion] of [file_picker]: an opaque token echoed back
    in [picked] payloads. String tokens cover UUID-style identifiers; int
    tokens cover counters. *)
type file_picker_token = [ `String of string | `Int of int ]

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
type swipe_action_el = t

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

let edge_value : edge -> string = function
  | `top -> "top"
  | `bottom -> "bottom"
  | `leading -> "leading"
  | `trailing -> "trailing"

let alignment_value : alignment -> string = function
  | `top_leading -> "top-leading"
  | `top -> "top"
  | `top_trailing -> "top-trailing"
  | `leading -> "leading"
  | `center -> "center"
  | `trailing -> "trailing"
  | `bottom_leading -> "bottom-leading"
  | `bottom -> "bottom"
  | `bottom_trailing -> "bottom-trailing"

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

let list_style_value : list_style -> string = function
  | `plain -> "plain"
  | `inset -> "inset"
  | `inset_grouped -> "inset-grouped"

let scroll_anchor_value : scroll_anchor -> string = function
  | `top -> "top"
  | `center -> "center"
  | `bottom -> "bottom"

let separator_value : separator_visibility -> string = function
  | `visible -> "visible"
  | `hidden -> "hidden"

let image_loading_value : image_loading -> string = function
  | `eager -> "eager"
  | `lazy_ -> "lazy"

let referrer_policy_value : referrer_policy -> string = function
  | `no_referrer -> "no-referrer"
  | `origin -> "origin"
  | `strict_origin_when_cross_origin -> "strict-origin-when-cross-origin"
  | `unsafe_url -> "unsafe-url"

let link_target_value : link_target -> string = function
  | `self_ -> "_self"
  | `blank -> "_blank"

let display_value : display -> string = function `contents -> "contents"

let input_kind_value : input_kind -> string = function
  | `text -> "text"
  | `color -> "color"

let popover_role_value : popover_role -> string = function `menu -> "menu"

let swipe_edge_value : swipe_edge -> string = function
  | `leading -> "leading"
  | `trailing -> "trailing"

let element_tag_value : element_tag -> string = function
  | `Span -> "span"
  | `Em -> "em"
  | `Strong -> "strong"
  | `B -> "b"
  | `I -> "i"
  | `U -> "u"
  | `S -> "s"
  | `Del -> "del"
  | `Mark -> "mark"
  | `Small -> "small"
  | `Code -> "code"
  | `Kbd -> "kbd"
  | `Sub -> "sub"
  | `Sup -> "sup"
  | `Pre -> "pre"
  | `H1 -> "h1"
  | `H2 -> "h2"
  | `H3 -> "h3"
  | `H4 -> "h4"
  | `H5 -> "h5"
  | `H6 -> "h6"
  | `P -> "p"
  | `Div -> "div"
  | `Label -> "label"

let file_picker_source_value : file_picker_source -> string = function
  | `files -> "files"
  | `photos -> "photos"
  | `camera -> "camera"

let file_picker_token_wire_value
    : file_picker_token -> Lui_protocol.wire_value
  = function
  | `String value -> Lui_protocol.StringValue value
  | `Int value -> Lui_protocol.IntValue value

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

let scoped build : t = fun context parent -> build context context parent

(* Signal conveniences for view code: `map f src`, `sample src`,
   `src >|= f`, `const` — short spellings for the reactive props. *)

let reactive = Signal.map

let map = Signal.map

let sample = Signal.sample

let ( >|= ) source f = Signal.map f source

let get = Signal.get

let get_state = Signal.get_state

let owned_map context project source =
  Signal.own_signal context.Lui_ui.ui_scope (Signal.map project source)

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
  | None ->
    (* A dynamic rendered as the branch of another dynamic has no anchor of
       its own: mount under a transparent stack so it still has a home. *)
    let anchor = Lui_ui.stack context in
    ignore (mount context anchor);
    anchor

let dyn ?(equal = ( = )) f (source : 'a Signal.signal) : t =
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
       Lui_dynamic.conditional context node test
         (fun branch_context ->
           children branch_context None))
    context parent

let keyed ~source ~key ~cmp ~mount : t =
 fun context parent ->
  dynamic
    (fun context node ->
       Lui_dynamic.keyed context node source key cmp
         (fun item_context item_source ->
            mount item_source item_context None))
    context parent

(* Every *_el is a t underneath, so the same keyed collection mounts
   children directly under the restricted parent; the .mli signatures
   are what pin each variant's item type. *)
let keyed_step = keyed
let keyed_timeline_item = keyed
let keyed_bottom_tab = keyed
let keyed_table_row = keyed
let keyed_table_cell = keyed
let keyed_radio = keyed
let keyed_swipe_action = keyed

let press send action _event = ignore (send action)

let on_input send wrap event =
  match event with
  | TextChanged (_node, text) -> ignore (send (wrap text))
  | _ -> ()

let on_event context node predicate handler =
  Lui_ui.on_event context node (fun event ->
      if predicate event then handler event)

let is_press = function
  | Press _ | PressModifiers _ -> true
  | _ -> false
let is_long_press = function LongPress _ -> true | _ -> false
let is_double_press = function DoublePress _ -> true | _ -> false
let is_change = function Change _ -> true | _ -> false
let is_input = function TextChanged _ -> true | _ -> false
let is_submit = function Submit _ -> true | _ -> false
let is_toggle = function ToggleChanged _ -> true | _ -> false
let is_dismiss = function Dismiss _ -> true | _ -> false
let is_picked = function Picked _ -> true | _ -> false
let is_load = function Load _ -> true | _ -> false
let is_appear = function Appear _ -> true | _ -> false
let is_resize = function ValueChanged _ -> true | _ -> false
let is_scroll_completed = function ScrollCompleted _ -> true | _ -> false
let is_visible_range = function VisibleRange _ -> true | _ -> false

(* Fail loudly when a handler is registered for an event the node kind can
   never emit. Dispatch rejects such events anyway, so a registration that
   cannot fire is a bug — without this check it fails silently (e.g. a
   Press handler on a kind the backend never wires up). Mirrors
   [Lui_runtime.dispatch]'s admission check, evaluated at mount time once
   the node's initial properties are in place. *)
let pointer_detail_probe =
  { x = 0.; y = 0.; modifiers = 0; button = 0; target_class = "" }

let require_event_supported context node event label =
  let kind = Lui_ui.node_kind context node in
  let properties =
    match
      Hashtbl.find_opt
        context.Lui_ui.ui_application.Lui_runtime.runtime_properties node
    with
    | Some current -> current
    | None -> Property_map.empty
  in
  if
    not (Lui_protocol.event_supported_for_properties kind properties event)
  then
    invalid_arg
      (Printf.sprintf "%s handler is unsupported by node kind %s" label
         (Lui_wire_schema.node_kind_name kind))

let register_press context node handler =
  require_event_supported context node (Press node) "press";
  ignore (on_event context node is_press handler)

let register_long_press context node handler =
  require_event_supported context node (LongPress node) "long-press";
  ignore (on_event context node is_long_press handler)

let register_double_press context node handler =
  require_event_supported context node (DoublePress node) "double-press";
  ignore (on_event context node is_double_press handler)

let register_change context node handler =
  require_event_supported context node (Change node) "change";
  ignore (on_event context node is_change handler)

let register_input context node handler =
  require_event_supported context node (TextChanged (node, "")) "input";
  ignore (on_event context node is_input handler)

let register_submit context node handler =
  require_event_supported context node (Submit node) "submit";
  ignore (on_event context node is_submit handler)

let register_toggle context node handler =
  require_event_supported context node (ToggleChanged (node, false)) "toggle";
  ignore (on_event context node is_toggle handler)

let register_dismiss context node handler =
  require_event_supported context node (Dismiss node) "dismiss";
  ignore (on_event context node is_dismiss handler)

let register_picked context node handler =
  require_event_supported context node (Picked (node, "")) "picked";
  ignore (on_event context node is_picked handler)

let register_load context node handler =
  require_event_supported context node (Load node) "load";
  ignore (on_event context node is_load handler)

let appear_handler context node handler =
  enable context node AppearEnabled;
  ignore (on_event context node is_appear handler)

let register_resize context node handler =
  enable context node ChangeEnabled;
  require_event_supported context node (ValueChanged (node, 0.)) "resize";
  ignore (on_event context node is_resize handler)

let register_scroll_completed context node handler =
  require_event_supported context node (ScrollCompleted (node, 0, ""))
    "scroll-completed";
  ignore (on_event context node is_scroll_completed handler)

let register_visible_range context node handler =
  require_event_supported context node (VisibleRange (node, 0, 0))
    "visible-range";
  ignore (on_event context node is_visible_range handler)

let is_press_detail = function PressDetail _ -> true | _ -> false
let is_pointer_down = function PointerDown _ -> true | _ -> false
let is_pointer_up = function PointerUp _ -> true | _ -> false
let is_pointer_enter = function PointerEnter _ -> true | _ -> false
let is_pointer_leave = function PointerLeave _ -> true | _ -> false
let is_context_menu_press = function
  | ContextMenuPress _ -> true
  | _ -> false

let register_press_detail context node handler =
  enable context node PointerEnabled;
  require_event_supported context node
    (PressDetail (node, pointer_detail_probe))
    "press-detail";
  ignore (on_event context node is_press_detail handler)

let register_pointer_down context node handler =
  enable context node PointerEnabled;
  require_event_supported context node
    (PointerDown (node, pointer_detail_probe))
    "pointer-down";
  ignore (on_event context node is_pointer_down handler)

let register_pointer_up context node handler =
  enable context node PointerEnabled;
  require_event_supported context node
    (PointerUp (node, pointer_detail_probe))
    "pointer-up";
  ignore (on_event context node is_pointer_up handler)

let register_pointer_enter context node handler =
  enable context node PointerEnabled;
  ignore (on_event context node is_pointer_enter handler)

let register_pointer_leave context node handler =
  enable context node PointerEnabled;
  ignore (on_event context node is_pointer_leave handler)

let register_context_menu_press context node handler =
  enable context node PointerEnabled;
  require_event_supported context node
    (ContextMenuPress (node, pointer_detail_probe))
    "context-menu-press";
  ignore (on_event context node is_context_menu_press handler)

let apply_pointer_events context node ?on_press_detail ?on_pointer_down
    ?on_pointer_up ?on_context_menu () =
  Option.iter (register_press_detail context node) on_press_detail;
  Option.iter (register_pointer_down context node) on_pointer_down;
  Option.iter (register_pointer_up context node) on_pointer_up;
  Option.iter (register_context_menu_press context node) on_context_menu
let apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave =
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
  Option.iter
    (fun pairs ->
       Lui_ui.string_property context node DataAttrs
         (data_attrs_encode pairs))
    data_attrs;
  Option.iter
    (fun source ->
       Lui_ui.string_property_signal context node DataAttrs
         (owned_map context data_attrs_encode source))
    data_attrs_signal;
  (match on_appear with
   | Some handler -> appear_handler context node handler
   | None -> ());
  Option.iter (register_pointer_enter context node) on_pointer_enter;
  Option.iter (register_pointer_leave context node) on_pointer_leave

let row ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?opacity ?opacity_signal ?display (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.row context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.float_property context node Opacity) opacity;
  Option.iter (Lui_ui.float_property_signal context node Opacity) opacity_signal;
  Option.iter (Lui_ui.string_property context node DisplayValue) (Option.map display_value display);
  attach context parent node;
  mount_children context node children;
  node

let column ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?on_press_detail ?on_pointer_down ?on_pointer_up ?opacity ?opacity_signal ?display (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.column context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.float_property context node Opacity) opacity;
  Option.iter (Lui_ui.float_property_signal context node Opacity) opacity_signal;
  Option.iter (Lui_ui.string_property context node DisplayValue) (Option.map display_value display);
  apply_pointer_events context node ?on_press_detail ?on_pointer_down ?on_pointer_up ();
  attach context parent node;
  mount_children context node children;
  node

let grid ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?opacity ?opacity_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.grid context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.float_property context node Opacity) opacity;
  Option.iter (Lui_ui.float_property_signal context node Opacity) opacity_signal;
  attach context parent node;
  mount_children context node children;
  node

let stack ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?opacity ?opacity_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.stack context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.float_property context node Opacity) opacity;
  Option.iter (Lui_ui.float_property_signal context node Opacity) opacity_signal;
  attach context parent node;
  mount_children context node children;
  node

let edge_inset ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ~edge ?visible ?visible_signal ?opacity ?opacity_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.edge_inset context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.float_property context node Opacity) opacity;
  Option.iter (Lui_ui.float_property_signal context node Opacity) opacity_signal;
  Lui_ui.string_property context node EdgeValue (edge_value edge);
  Option.iter (Lui_ui.bool_property context node Visible) visible;
  Option.iter (Lui_ui.bool_property_signal context node Visible) visible_signal;
  attach context parent node;
  mount_children context node children;
  node

let overlay ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?alignment ?opacity ?opacity_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.overlay context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.float_property context node Opacity) opacity;
  Option.iter (Lui_ui.float_property_signal context node Opacity) opacity_signal;
  Option.iter (Lui_ui.string_property context node AlignmentValue) (Option.map alignment_value alignment);
  attach context parent node;
  mount_children context node children;
  node

let view_that_fits ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?orientation ?opacity ?opacity_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.view_that_fits context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.float_property context node Opacity) opacity;
  Option.iter (Lui_ui.float_property_signal context node Opacity) opacity_signal;
  Option.iter (Lui_ui.string_property context node OrientationValue) (Option.map orientation_value orientation);
  attach context parent node;
  mount_children context node children;
  node

(* Sets an [alignment] hint on [child]'s node; honored when [child] is an
   [overlay] child (children past the first), inert elsewhere. *)
let align alignment (child : t) : t =
 fun context parent ->
  let node = child context parent in
  Lui_ui.string_property context node AlignmentValue (alignment_value alignment);
  node

let panel ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?opacity ?opacity_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.panel context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.float_property context node Opacity) opacity;
  Option.iter (Lui_ui.float_property_signal context node Opacity) opacity_signal;
  attach context parent node;
  mount_children context node children;
  node

let card ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?opacity ?opacity_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.card context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.float_property context node Opacity) opacity;
  Option.iter (Lui_ui.float_property_signal context node Opacity) opacity_signal;
  attach context parent node;
  mount_children context node children;
  node

let alert ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?variant ?text_alignment ?label ?opacity ?opacity_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.alert context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.float_property context node Opacity) opacity;
  Option.iter (Lui_ui.float_property_signal context node Opacity) opacity_signal;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node VariantValue) (Option.map variant_value variant);
  Option.iter (Lui_ui.string_property context node TextAlignment) (Option.map text_alignment_value text_alignment);
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let bubble ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?variant ?label ?opacity ?opacity_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.bubble context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.float_property context node Opacity) opacity;
  Option.iter (Lui_ui.float_property_signal context node Opacity) opacity_signal;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node VariantValue) (Option.map variant_value variant);
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let box ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?opacity ?opacity_signal ?display (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.box context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.float_property context node Opacity) opacity;
  Option.iter (Lui_ui.float_property_signal context node Opacity) opacity_signal;
  Option.iter (Lui_ui.string_property context node DisplayValue) (Option.map display_value display);
  attach context parent node;
  mount_children context node children;
  node

let scroll ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?orientation ?opacity ?opacity_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.scroll context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.float_property context node Opacity) opacity;
  Option.iter (Lui_ui.float_property_signal context node Opacity) opacity_signal;
  Option.iter (Lui_ui.string_property context node OrientationValue) (Option.map orientation_value orientation);
  attach context parent node;
  mount_children context node children;
  node

let list ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?style ?scroll_target ?scroll_anchor ?scroll_token ?scroll_target_signal ?scroll_token_signal ?scroll_animated ?track_visible_range ?on_scroll_completed ?on_visible_range ?opacity ?opacity_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.list context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.float_property context node Opacity) opacity;
  Option.iter (Lui_ui.float_property_signal context node Opacity) opacity_signal;
  Option.iter (Lui_ui.string_property context node StyleValue)
    (Option.map list_style_value style);
  Option.iter (Lui_ui.string_property context node ScrollTarget) scroll_target;
  Option.iter (Lui_ui.string_property context node ScrollAnchor)
    (Option.map scroll_anchor_value scroll_anchor);
  Option.iter (Lui_ui.int_property context node ScrollToken) scroll_token;
  Option.iter
    (Lui_ui.string_property_signal context node ScrollTarget)
    scroll_target_signal;
  Option.iter
    (Lui_ui.int_property_signal context node ScrollToken)
    scroll_token_signal;
  Option.iter (Lui_ui.bool_property context node ScrollAnimated)
    scroll_animated;
  Option.iter (Lui_ui.bool_property context node TrackVisibleRange)
    track_visible_range;
  Option.iter (register_scroll_completed context node) on_scroll_completed;
  Option.iter (register_visible_range context node) on_visible_range;
  attach context parent node;
  mount_children context node children;
  node

let virtual_list ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?opacity ?opacity_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.virtual_list context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.float_property context node Opacity) opacity;
  Option.iter (Lui_ui.float_property_signal context node Opacity) opacity_signal;
  attach context parent node;
  mount_children context node children;
  node

let tabs ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?label ?orientation (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.tabs context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.string_property context node OrientationValue) (Option.map orientation_value orientation);
  attach context parent node;
  mount_children context node children;
  node

let bottom_tabs ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?label (children : bottom_tab_el list) : t =
 fun context parent ->
  let node = Lui_ui.bottom_tabs context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let bottom_tab ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?title ?icon ?icon_signal ?selected ?selected_signal ?enabled ?enabled_signal ?on_press ?on_press_detail ?on_pointer_down ?on_pointer_up (children : t list) : bottom_tab_el =
 fun context parent ->
  let node = Lui_ui.bottom_tab context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node TitleValue) title;
  Option.iter (Lui_ui.string_property context node InlineIconName) (Option.map icon_value icon);
  Option.iter (fun signal_ -> Lui_ui.string_property_signal context node InlineIconName (owned_map context icon_value signal_)) icon_signal;
  Option.iter (Lui_ui.bool_property context node Selected) selected;
  Option.iter (Lui_ui.bool_property_signal context node Selected) selected_signal;
  Option.iter (Lui_ui.bool_property context node Enabled) enabled;
  Option.iter (Lui_ui.bool_property_signal context node Enabled) enabled_signal;
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  apply_pointer_events context node ?on_press_detail ?on_pointer_down ?on_pointer_up ();
  attach context parent node;
  mount_children context node children;
  node

let button_group ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?label (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.button_group context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let toggle_group ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?label (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.toggle_group context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let breadcrumb ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?label (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.breadcrumb context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let pagination ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?label (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.pagination context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let table ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave (children : table_row_el list) : t =
 fun context parent ->
  let node = Lui_ui.table context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  attach context parent node;
  mount_children context node children;
  node

let table_row ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?selected ?selected_signal (children : table_cell_el list) : table_row_el =
 fun context parent ->
  let node = Lui_ui.table_row context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.bool_property context node Selected) selected;
  Option.iter (Lui_ui.bool_property_signal context node Selected) selected_signal;
  attach context parent node;
  mount_children context node children;
  node

let table_cell ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?size ?text_alignment ?on_press ?on_press_detail ?on_pointer_down ?on_pointer_up ?on_context_menu (children : t list) : table_cell_el =
 fun context parent ->
  let node = Lui_ui.table_cell context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node SizeValue) (Option.map cell_size_value size);
  Option.iter (Lui_ui.string_property context node TextAlignment) (Option.map text_alignment_value text_alignment);
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  apply_pointer_events context node ?on_press_detail ?on_pointer_down ?on_pointer_up ?on_context_menu ();
  attach context parent node;
  mount_children context node children;
  node

let tree ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?label ?role ?tree_level ?expanded ?expanded_signal ?on_press ?on_change ?on_toggle ?on_press_detail ?on_pointer_down ?on_pointer_up ?on_context_menu (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.tree context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
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
  apply_pointer_events context node ?on_press_detail ?on_pointer_down ?on_pointer_up ?on_context_menu ();
  attach context parent node;
  mount_children context node children;
  node

let resizable ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?label ?resizable_width (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.resizable context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.int_property context node WidthValue) resizable_width;
  attach context parent node;
  mount_children context node children;
  node

let split ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?value ?value_signal ?resize_duration ?resize_easing ?resize_origin ?label ?on_resize (first : t) (second : t) : t =
 fun context parent ->
  let node = Lui_ui.create context Split in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
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

let drawer ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?selected ?selected_signal ?disabled ?disabled_signal ?label ?on_toggle (first : t) (second : t) : t =
 fun context parent ->
  let node = Lui_ui.drawer context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
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

let status_bar ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?value ?value_signal ?text_alignment (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.status_bar context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node TextValue) value;
  Option.iter (Lui_ui.string_property_signal context node TextValue) value_signal;
  Option.iter (Lui_ui.string_property context node TextAlignment) (Option.map text_alignment_value text_alignment);
  attach context parent node;
  
  node

let spacer ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.spacer context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  attach context parent node;
  
  node

let spinner ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?size (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.spinner context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node SizeValue) (Option.map control_size_value size);
  attach context parent node;
  
  node

let icon ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?name ?name_signal ?size ?point_size ?tooltip ?tooltip_signal ?shortcut_hint ?shortcut_hint_signal (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context Icon in
  let width = match width with Some _ -> width | None -> point_size in
  let height = match height with Some _ -> height | None -> point_size in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node IconName) (Option.map icon_value name);
  Option.iter (fun signal -> Lui_ui.string_property_signal context node IconName (owned_map context icon_value signal)) name_signal;
  Option.iter (Lui_ui.string_property context node SizeValue) (Option.map control_size_value size);
  Option.iter (Lui_ui.string_property context node TooltipText) tooltip;
  Option.iter (Lui_ui.string_property_signal context node TooltipText) tooltip_signal;
  Option.iter (Lui_ui.string_property context node TooltipKeys) shortcut_hint;
  Option.iter (Lui_ui.string_property_signal context node TooltipKeys) shortcut_hint_signal;
  attach context parent node;
  
  node

let text ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?as_ ?on_appear ?on_pointer_enter ?on_pointer_leave ?value ?value_signal ?text_alignment ?on_press ?on_press_detail ?on_pointer_down ?on_pointer_up ?on_context_menu (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.create context Text in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter
    (fun tag -> Lui_ui.string_property context node As (element_tag_value tag))
    as_;
  Option.iter (Lui_ui.string_property context node TextValue) value;
  Option.iter (Lui_ui.string_property_signal context node TextValue) value_signal;
  Option.iter (Lui_ui.string_property context node TextAlignment) (Option.map text_alignment_value text_alignment);
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  apply_pointer_events context node ?on_press_detail ?on_pointer_down ?on_pointer_up ?on_context_menu ();
  attach context parent node;
  mount_children context node children;
  node

let heading ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?as_ ?on_appear ?on_pointer_enter ?on_pointer_leave ?level ?value ?value_signal (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context Heading in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter
    (fun tag -> Lui_ui.string_property context node As (element_tag_value tag))
    as_;
  Option.iter (Lui_ui.int_property context node HeadingLevel) level;
  Option.iter (Lui_ui.string_property context node TextValue) value;
  Option.iter (Lui_ui.string_property_signal context node TextValue) value_signal;
  attach context parent node;
  
  node

let paragraph ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?as_ ?on_appear ?on_pointer_enter ?on_pointer_leave ?value ?value_signal (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context Paragraph in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter
    (fun tag -> Lui_ui.string_property context node As (element_tag_value tag))
    as_;
  Option.iter (Lui_ui.string_property context node TextValue) value;
  Option.iter (Lui_ui.string_property_signal context node TextValue) value_signal;
  attach context parent node;
  
  node

let label ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?as_ ?on_appear ?on_pointer_enter ?on_pointer_leave ?value ?value_signal (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context Label in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter
    (fun tag -> Lui_ui.string_property context node As (element_tag_value tag))
    as_;
  Option.iter (Lui_ui.string_property context node TextValue) value;
  Option.iter (Lui_ui.string_property_signal context node TextValue) value_signal;
  attach context parent node;
  
  node

let kbd ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?value ?value_signal (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context Kbd in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node TextValue) value;
  Option.iter (Lui_ui.string_property_signal context node TextValue) value_signal;
  attach context parent node;

  node

let button ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?variant ?size ?icon ?icon_signal ?icon_placement ?label ?text_alignment ?selected ?autofocus ?disabled ?disabled_signal ?on_press ?on_long_press ?on_press_detail ?on_pointer_down ?on_pointer_up ?on_context_menu ?tooltip ?tooltip_signal ?shortcut_hint ?shortcut_hint_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.button context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node VariantValue) (Option.map variant_value variant);
  Option.iter (Lui_ui.string_property context node SizeValue) (Option.map control_size_value size);
  Option.iter (Lui_ui.string_property context node InlineIconName) (Option.map icon_value icon);
  Option.iter (fun signal_ -> Lui_ui.string_property_signal context node InlineIconName (owned_map context icon_value signal_)) icon_signal;
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
  apply_pointer_events context node ?on_press_detail ?on_pointer_down ?on_pointer_up ?on_context_menu ();
  Option.iter (Lui_ui.string_property context node TooltipText) tooltip;
  Option.iter (Lui_ui.string_property_signal context node TooltipText) tooltip_signal;
  Option.iter (Lui_ui.string_property context node TooltipKeys) shortcut_hint;
  Option.iter (Lui_ui.string_property_signal context node TooltipKeys) shortcut_hint_signal;
  attach context parent node;
  mount_children context node children;
  node

let toggle_button ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?variant ?size ?icon ?icon_signal ?icon_placement ?label ?text_alignment ?selected ?checked ?checked_signal ?autofocus ?disabled ?disabled_signal ?on_press ?on_toggle ?on_long_press ?on_context_menu (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.toggle_button context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node VariantValue) (Option.map variant_value variant);
  Option.iter (Lui_ui.string_property context node SizeValue) (Option.map control_size_value size);
  Option.iter (Lui_ui.string_property context node InlineIconName) (Option.map icon_value icon);
  Option.iter (fun signal_ -> Lui_ui.string_property_signal context node InlineIconName (owned_map context icon_value signal_)) icon_signal;
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
  apply_pointer_events context node ?on_context_menu ();
  attach context parent node;
  mount_children context node children;
  node

let checkbox ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?checked ?checked_signal ?label ?disabled ?disabled_signal ?on_toggle ?on_context_menu (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.checkbox context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
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
  apply_pointer_events context node ?on_context_menu ();
  attach context parent node;
  mount_children context node children;
  node

let switch_ ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?checked ?checked_signal ?label ?disabled ?disabled_signal ?on_toggle ?on_context_menu (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.switch_control context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
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
  apply_pointer_events context node ?on_context_menu ();
  attach context parent node;
  mount_children context node children;
  node

let toggle ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?checked ?checked_signal ?label ?disabled ?disabled_signal ?on_toggle ?on_context_menu (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.toggle context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
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
  apply_pointer_events context node ?on_context_menu ();
  attach context parent node;
  mount_children context node children;
  node

let radio_group ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?label (children : radio_el list) : t =
 fun context parent ->
  let node = Lui_ui.radio_group context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let radio ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?checked ?checked_signal ?selected ?label ?disabled ?disabled_signal ?on_change ?on_toggle ?on_press ?on_press_detail ?on_pointer_down ?on_pointer_up ?on_context_menu (children : t list) : radio_el =
 fun context parent ->
  let node = Lui_ui.radio context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
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
  apply_pointer_events context node ?on_press_detail ?on_pointer_down ?on_pointer_up ?on_context_menu ();
  attach context parent node;
  mount_children context node children;
  node

let slider ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?value ?value_signal ?label ?disabled ?disabled_signal ?on_change ?on_context_menu (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.create context Slider in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.float_property context node ProgressValue) value;
  Option.iter (Lui_ui.float_property_signal context node ProgressValue) value_signal;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  (match on_change with
   | Some handler -> register_resize context node handler
   | None -> ());
  apply_pointer_events context node ?on_context_menu ();
  attach context parent node;
  mount_children context node children;
  node

let number_stepper ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?value ?value_signal ?min ?max ?step ?text ?text_signal ?label ?enabled ?enabled_signal ?on_value_changed ?on_context_menu (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.create context NumberStepper in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.float_property context node ProgressValue) value;
  Option.iter (Lui_ui.float_property_signal context node ProgressValue) value_signal;
  Option.iter (Lui_ui.float_property context node MinValue) min;
  Option.iter (Lui_ui.float_property context node MaxValue) max;
  Option.iter (Lui_ui.float_property context node StepValue) step;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.bool_property context node Enabled) enabled;
  Option.iter (Lui_ui.bool_property_signal context node Enabled) enabled_signal;
  (match on_value_changed with
   | Some handler -> register_resize context node handler
   | None -> ());
  apply_pointer_events context node ?on_context_menu ();
  attach context parent node;
  mount_children context node children;
  node

let progress ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?value ?value_signal (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context Progress in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.float_property context node ProgressValue) value;
  Option.iter (Lui_ui.float_property_signal context node ProgressValue) value_signal;
  attach context parent node;
  
  node

let divider ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?orientation (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context Divider in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node OrientationValue) (Option.map orientation_value orientation);
  attach context parent node;
  
  node

let separator ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?orientation (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context Divider in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node OrientationValue) (Option.map orientation_value orientation);
  attach context parent node;

  node

let br ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.br context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  attach context parent node;

  node

let text_field ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?placeholder ?label ?autofocus ?submit_on_enter ?disabled ?disabled_signal ?on_input ?on_submit ?on_context_menu (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.text_field context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
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
  apply_pointer_events context node ?on_context_menu ();
  attach context parent node;
  mount_children context node children;
  node

let secure_field ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?placeholder ?label ?autofocus ?submit_on_enter ?disabled ?disabled_signal ?on_input ?on_submit ?on_context_menu (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.secure_field context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
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
  apply_pointer_events context node ?on_context_menu ();
  attach context parent node;
  mount_children context node children;
  node

let input ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?placeholder ?label ?autofocus ?submit_on_enter ?disabled ?disabled_signal ?on_input ?on_submit ?on_context_menu ?kind (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.input context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node PlaceholderValue) placeholder;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.bool_property context node Autofocus) autofocus;
  Option.iter (Lui_ui.bool_property context node SubmitOnEnter) submit_on_enter;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  Option.iter (Lui_ui.string_property context node InputType) (Option.map input_kind_value kind);
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
  apply_pointer_events context node ?on_context_menu ();
  attach context parent node;
  mount_children context node children;
  node

let search_field ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?placeholder ?label ?autofocus ?submit_on_enter ?disabled ?disabled_signal ?on_input ?on_submit ?on_context_menu (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.search_field context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
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
  apply_pointer_events context node ?on_context_menu ();
  attach context parent node;
  mount_children context node children;
  node

let textarea ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?placeholder ?label ?autofocus ?submit_on_enter ?disabled ?disabled_signal ?on_input ?on_submit ?on_context_menu (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.textarea context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
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
  apply_pointer_events context node ?on_context_menu ();
  attach context parent node;
  mount_children context node children;
  node

let input_group ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?label ?actions (field : t) : t =
 fun context parent ->
  let node = Lui_ui.input_group context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  ignore (field context (Some node));
  Option.iter (fun actions -> ignore (actions context (Some node))) actions;
  node

let input_group_actions ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave (children : t list) : input_group_actions_el =
 fun context parent ->
  let node = Lui_ui.input_group_actions context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  attach context parent node;
  mount_children context node children;
  node

let select ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?label ?text ?text_signal ?placeholder ?disabled ?disabled_signal ?on_press ?on_input ?on_submit ?on_dismiss ?on_press_detail ?on_pointer_down ?on_pointer_up ?on_context_menu (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.select context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
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
  apply_pointer_events context node ?on_press_detail ?on_pointer_down ?on_pointer_up ?on_context_menu ();
  attach context parent node;
  mount_children context node children;
  node

let combobox ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?placeholder ?disabled ?disabled_signal ?on_press ?on_input ?on_submit ?on_dismiss ?on_press_detail ?on_pointer_down ?on_pointer_up ?on_context_menu (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.combobox context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
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
  apply_pointer_events context node ?on_press_detail ?on_pointer_down ?on_pointer_up ?on_context_menu ();
  attach context parent node;
  mount_children context node children;
  node

let dropdown_menu ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?anchor ?anchor_alignment ?anchor_offset ?on_press ?on_input ?on_submit ?on_dismiss (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.dropdown_menu context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
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

let popover ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?opacity ?opacity_signal ?at ?at_signal ?anchor ?anchor_alignment ?anchor_offset ?available_height ?available_height_signal ?role ?on_dismiss (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.popover context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.float_property context node Opacity) opacity;
  Option.iter (Lui_ui.float_property_signal context node Opacity) opacity_signal;
  Option.iter
    (fun (x, y) ->
      Lui_ui.float_property context node PopupX x;
      Lui_ui.float_property context node PopupY y)
    at;
  Option.iter
    (fun signal_ ->
      Lui_ui.float_property_signal context node PopupX
        (owned_map context fst signal_);
      Lui_ui.float_property_signal context node PopupY
        (owned_map context snd signal_))
    at_signal;
  Option.iter (Lui_ui.string_property context node AnchorValue) (Option.map anchor_value anchor);
  Option.iter (Lui_ui.string_property context node AnchorAlignmentValue) (Option.map anchor_alignment_value anchor_alignment);
  Option.iter (Lui_ui.float_property context node AnchorOffset) anchor_offset;
  Option.iter (Lui_ui.float_property context node AvailableHeight) available_height;
  Option.iter (Lui_ui.float_property_signal context node AvailableHeight) available_height_signal;
  Option.iter (Lui_ui.string_property context node RoleValue) (Option.map popover_role_value role);
  (match on_dismiss with
   | Some handler -> register_dismiss context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let context_menu ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?disabled ?disabled_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.context_menu context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  attach context parent node;
  mount_children context node children;
  node

let dialog ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?description ?description_signal ?on_dismiss (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.dialog context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
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

let sheet ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?detents ?detents_signal ?sizing ?sizing_signal ?on_dismiss (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.sheet context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node Detents) detents;
  Option.iter (Lui_ui.string_property_signal context node Detents) detents_signal;
  Option.iter (Lui_ui.string_property context node Sizing) sizing;
  Option.iter (Lui_ui.string_property_signal context node Sizing) sizing_signal;
  (match on_dismiss with
   | Some handler -> register_dismiss context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let tooltip ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?anchor ?anchor_alignment ?anchor_offset ?tooltip_delay (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.tooltip context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node AnchorValue) (Option.map anchor_value anchor);
  Option.iter (Lui_ui.string_property context node AnchorAlignmentValue) (Option.map anchor_alignment_value anchor_alignment);
  Option.iter (Lui_ui.float_property context node AnchorOffset) anchor_offset;
  Option.iter (Lui_ui.int_property context node TooltipDelay) tooltip_delay;
  attach context parent node;
  
  node

let toast ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?duration ?label ?toast_class ?on_dismiss (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.toast context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.int_property context node DurationValue) duration;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.string_property context node StyleClass) toast_class;
  (match on_dismiss with
   | Some handler -> register_dismiss context node handler
   | None -> ());
  attach context parent node;
  mount_children context node children;
  node

let file_picker ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?source ?request ?request_signal ?types ?types_signal ?multiple ?multiple_signal ?disabled ?disabled_signal ?completion ?completion_signal ?on_picked ?on_dismiss ?accept ?accept_signal ?directory ?directory_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.file_picker context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node PickerSource) (Option.map file_picker_source_value source);
  Option.iter
    (fun token ->
      Lui_ui.value_property context node PickerRequest
        (file_picker_token_wire_value token))
    request;
  Option.iter
    (fun source ->
      Lui_ui.value_property_signal context node PickerRequest
        (owned_map context
           (fun token -> file_picker_token_wire_value token)
           source))
    request_signal;
  Option.iter (Lui_ui.string_property context node PickerTypes) types;
  Option.iter (Lui_ui.string_property_signal context node PickerTypes) types_signal;
  Option.iter (Lui_ui.bool_property context node PickerMultiple) multiple;
  Option.iter (Lui_ui.bool_property_signal context node PickerMultiple) multiple_signal;
  Option.iter (Lui_ui.string_property context node PickerAccept) accept;
  Option.iter (Lui_ui.string_property_signal context node PickerAccept) accept_signal;
  Option.iter (Lui_ui.bool_property context node PickerDirectory) directory;
  Option.iter (Lui_ui.bool_property_signal context node PickerDirectory) directory_signal;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  Option.iter
    (fun token ->
      Lui_ui.value_property context node PickerCompletion
        (file_picker_token_wire_value token))
    completion;
  Option.iter
    (fun source ->
      Lui_ui.value_property_signal context node PickerCompletion
        (owned_map context
           (fun token -> file_picker_token_wire_value token)
           source))
    completion_signal;
  Option.iter (register_picked context node) on_picked;
  Option.iter (register_dismiss context node) on_dismiss;
  attach context parent node;
  mount_children context node children;
  node

let toolbar ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?orientation ?label ?toolbar_gap ?toolbar_class ?placement (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.toolbar context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node OrientationValue) (Option.map orientation_value orientation);
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.int_property context node Gap) toolbar_gap;
  Option.iter (Lui_ui.string_property context node StyleClass) toolbar_class;
  Option.iter (Lui_ui.string_property context node PlacementValue) placement;
  attach context parent node;
  mount_children context node children;
  node

let accordion ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?selected ?selected_signal ?accordion_height ?on_toggle ?on_context_menu (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.accordion context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.bool_property context node Selected) selected;
  Option.iter (Lui_ui.bool_property_signal context node Selected) selected_signal;
  Option.iter (Lui_ui.int_property context node HeightValue) accordion_height;
  (match on_toggle with
   | Some handler ->
     enable context node ToggleEnabled;
     register_toggle context node handler
   | None -> ());
  apply_pointer_events context node ?on_context_menu ();
  attach context parent node;
  mount_children context node children;
  node

let menu_item ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?icon ?icon_signal ?role ?variant ?size ?tree_level ?expanded ?selected ?checked ?selected_signal ?checked_signal ?disabled ?disabled_signal ?on_press ?on_input ?on_submit ?on_dismiss ?on_press_detail ?on_pointer_down ?on_pointer_up ?on_context_menu ?tooltip ?tooltip_signal ?shortcut_hint ?shortcut_hint_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.menu_item context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node InlineIconName) (Option.map icon_value icon);
  Option.iter (fun signal_ -> Lui_ui.string_property_signal context node InlineIconName (owned_map context icon_value signal_)) icon_signal;
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
  apply_pointer_events context node ?on_press_detail ?on_pointer_down ?on_pointer_up ?on_context_menu ();
  Option.iter (Lui_ui.string_property context node TooltipText) tooltip;
  Option.iter (Lui_ui.string_property_signal context node TooltipText) tooltip_signal;
  Option.iter (Lui_ui.string_property context node TooltipKeys) shortcut_hint;
  Option.iter (Lui_ui.string_property_signal context node TooltipKeys) shortcut_hint_signal;
  attach context parent node;
  mount_children context node children;
  node

let menu_trigger ?key ?accessibility_identifier ?accessibility_identifier_signal ?foreground ?foreground_signal ?style_class ?data_attrs ?data_attrs_signal ?text ?text_signal ?icon ?icon_signal ?label ?disabled ?disabled_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.menu_trigger context in
  Option.iter (Lui_ui.key context node) key;
  Option.iter (Lui_ui.string_property context node AccessibilityIdentifier) accessibility_identifier;
  Option.iter (Lui_ui.string_property_signal context node AccessibilityIdentifier) accessibility_identifier_signal;
  Option.iter (Lui_ui.string_property context node ForegroundValue) foreground;
  Option.iter (Lui_ui.string_property_signal context node ForegroundValue) foreground_signal;
  Option.iter (Lui_ui.string_property context node StyleClass) style_class;
  Option.iter
    (fun pairs ->
       Lui_ui.string_property context node DataAttrs
         (data_attrs_encode pairs))
    data_attrs;
  Option.iter
    (fun source ->
       Lui_ui.string_property_signal context node DataAttrs
         (owned_map context data_attrs_encode source))
    data_attrs_signal;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node InlineIconName) (Option.map icon_value icon);
  Option.iter (fun signal_ -> Lui_ui.string_property_signal context node InlineIconName (owned_map context icon_value signal_)) icon_signal;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  attach context parent node;
  mount_children context node children;
  node

let menu ?key ?accessibility_identifier ?foreground ?style_class ?data_attrs ?data_attrs_signal ?text
    ?text_signal ?icon ?icon_signal ?label ?disabled ?disabled_signal
    ?on_dismiss entries : t =
 fun context parent ->
  let host =
    menu_trigger ?key ?accessibility_identifier ?foreground ?style_class ?data_attrs ?data_attrs_signal
      ?text ?text_signal ?icon ?icon_signal ?label ?disabled
      ?disabled_signal [] context parent
  in
  ignore (dropdown_menu ?on_dismiss entries context (Some host));
  host

let submenu ?key ?text ?icon ?label ?disabled ?disabled_signal ?on_dismiss entries : t =
  menu ?key ?text ?icon ?label ?disabled ?disabled_signal ?on_dismiss entries

let list_item ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?icon ?icon_signal ?icon_placement ?role ?tree_level ?expanded ?expanded_signal ?selected ?selected_signal ?disabled ?disabled_signal ?on_press ?on_long_press ?on_double_press ?on_submit ?on_input ?on_toggle ?separator ?swipe_actions ?on_press_detail ?on_pointer_down ?on_pointer_up ?on_context_menu (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.list_item context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node KeyValue) key;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node InlineIconName) (Option.map icon_value icon);
  Option.iter (fun signal -> Lui_ui.string_property_signal context node InlineIconName (owned_map context icon_value signal)) icon_signal;
  Option.iter (Lui_ui.string_property context node IconPlacementValue) (Option.map icon_placement_value icon_placement);
  Option.iter (Lui_ui.string_property context node RoleValue) (Option.map role_value role);
  Option.iter (Lui_ui.int_property context node TreeLevel) tree_level;
  Option.iter (Lui_ui.bool_property context node Expanded) expanded;
  Option.iter (Lui_ui.bool_property_signal context node Expanded) expanded_signal;
  Option.iter (Lui_ui.bool_property context node Selected) selected;
  Option.iter (Lui_ui.bool_property_signal context node Selected) selected_signal;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  Option.iter (Lui_ui.string_property context node SeparatorValue)
    (Option.map separator_value separator);
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
  apply_pointer_events context node ?on_press_detail ?on_pointer_down ?on_pointer_up ?on_context_menu ();
  attach context parent node;
  mount_children context node children;
  Option.iter
    (fun actions ->
       let container = Lui_ui.swipe_actions context in
       attach context (Some node) container;
       mount_children context container actions)
    swipe_actions;
  node

let list_section ?key ?accessibility_identifier ?separator ?header ?footer
    (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.list_section context in
  Option.iter (Lui_ui.key context node) key;
  Option.iter (Lui_ui.string_property context node KeyValue) key;
  Option.iter
    (Lui_ui.string_property context node AccessibilityIdentifier)
    accessibility_identifier;
  Option.iter (Lui_ui.string_property context node SeparatorValue)
    (Option.map separator_value separator);
  attach context parent node;
  Option.iter
    (fun content ->
       let slot = Lui_ui.list_section_header context in
       attach context (Some node) slot;
       ignore (content context (Some slot)))
    header;
  mount_children context node children;
  Option.iter
    (fun content ->
       let slot = Lui_ui.list_section_footer context in
       attach context (Some node) slot;
       ignore (content context (Some slot)))
    footer;
  node

let swipe_actions ?key ?accessibility_identifier
    (children : swipe_action_el list) : t =
 fun context parent ->
  let node = Lui_ui.swipe_actions context in
  Option.iter (Lui_ui.key context node) key;
  Option.iter
    (Lui_ui.string_property context node AccessibilityIdentifier)
    accessibility_identifier;
  attach context parent node;
  mount_children context node children;
  node

let swipe_action ?key ?accessibility_identifier ?text ?text_signal ?icon
    ?icon_signal ?variant ?edge ?background ?disabled ?on_press
    ?on_press_detail ?on_pointer_down ?on_pointer_up (_children : nothing list) : swipe_action_el =
 fun context parent ->
  let node = Lui_ui.swipe_action context in
  Option.iter (Lui_ui.key context node) key;
  Option.iter
    (Lui_ui.string_property context node AccessibilityIdentifier)
    accessibility_identifier;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue)
    text_signal;
  Option.iter (Lui_ui.string_property context node InlineIconName)
    (Option.map icon_value icon);
  Option.iter
    (fun signal ->
       Lui_ui.string_property_signal context node InlineIconName
         (owned_map context icon_value signal))
    icon_signal;
  Option.iter (Lui_ui.string_property context node VariantValue)
    (Option.map variant_value variant);
  Option.iter (Lui_ui.string_property context node EdgeValue)
    (Option.map swipe_edge_value edge);
  Option.iter (Lui_ui.string_property context node BackgroundValue) background;
  Option.iter (Lui_ui.disabled context node) disabled;
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  apply_pointer_events context node ?on_press_detail ?on_pointer_down ?on_pointer_up ();
  attach context parent node;
  node

let avatar ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal ?image ?image_signal ?source_x ?source_y ?source_width ?source_height ?label (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context Avatar in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
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

let image ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?image ?image_signal ?url ?url_signal ?alt ?loading ?referrer_policy ?on_load ?source_x ?source_y ?source_width ?source_height ?label (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context Image in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.int_property context node ImageIdValue) image;
  Option.iter (Lui_ui.int_property_signal context node ImageIdValue) image_signal;
  Option.iter (Lui_ui.string_property context node UrlValue) url;
  Option.iter (Lui_ui.string_property_signal context node UrlValue) url_signal;
  Option.iter (Lui_ui.string_property context node AltValue) alt;
  Option.iter (Lui_ui.string_property context node LoadingValue) (Option.map image_loading_value loading);
  Option.iter (Lui_ui.string_property context node ReferrerPolicy) (Option.map referrer_policy_value referrer_policy);
  Option.iter (register_load context node) on_load;
  Option.iter (Lui_ui.float_property context node SourceX) source_x;
  Option.iter (Lui_ui.float_property context node SourceY) source_y;
  Option.iter (Lui_ui.float_property context node SourceWidth) source_width;
  Option.iter (Lui_ui.float_property context node SourceHeight) source_height;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;

  node

let media_surface ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?surface ?surface_signal ?label (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context MediaSurface in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.int_property context node SurfaceIdValue) surface;
  Option.iter (Lui_ui.int_property_signal context node SurfaceIdValue) surface_signal;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  
  node

let link ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?url ?url_signal ?target ?text ?text_signal ?icon ?icon_signal ?icon_placement ?label ?disabled ?disabled_signal (children : t list) : t =
 fun context parent ->
  let node = Lui_ui.create context Link in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node UrlValue) url;
  Option.iter (Lui_ui.string_property_signal context node UrlValue) url_signal;
  Option.iter (Lui_ui.string_property context node TargetValue) (Option.map link_target_value target);
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  Option.iter (Lui_ui.string_property context node InlineIconName) (Option.map icon_value icon);
  Option.iter (fun signal_ -> Lui_ui.string_property_signal context node InlineIconName (owned_map context icon_value signal_)) icon_signal;
  Option.iter (Lui_ui.string_property context node IconPlacementValue) (Option.map icon_placement_value icon_placement);
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  Option.iter (Lui_ui.disabled context node) disabled;
  Option.iter (Lui_ui.disabled_signal context node) disabled_signal;
  attach context parent node;
  mount_children context node children;
  node

let file_image ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?path ?path_signal ?max_pixel_size ?fit ?label ?on_press ?on_press_detail ?on_pointer_down ?on_pointer_up (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context FileImage in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node PathValue) path;
  Option.iter (Lui_ui.string_property_signal context node PathValue) path_signal;
  Option.iter (Lui_ui.int_property context node MaxPixelSize) max_pixel_size;
  Option.iter (Lui_ui.string_property context node ImageFitValue)
    (Option.map (function `fit -> "fit" | `fill -> "fill") fit);
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  apply_pointer_events context node ?on_press_detail ?on_pointer_down ?on_pointer_up ();
  attach context parent node;
  
  node

let file_preview ?key ?path ?path_signal ?accessibility_identifier ?accessibility_identifier_signal ?on_dismiss (_children : nothing list) : t =
 fun context parent ->
  let node = Lui_ui.create context FilePreview in
  Option.iter (Lui_ui.key context node) key;
  Option.iter (Lui_ui.string_property context node PathValue) path;
  Option.iter (Lui_ui.string_property_signal context node PathValue) path_signal;
  Option.iter (Lui_ui.string_property context node AccessibilityIdentifier) accessibility_identifier;
  Option.iter (Lui_ui.string_property_signal context node AccessibilityIdentifier) accessibility_identifier_signal;
  (match on_dismiss with
   | Some handler -> register_dismiss context node handler
   | None -> ());
  attach context parent node;
  
  node

let stepper ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?active ?active_signal ?label (children : step_el list) : t =
 fun context parent ->
  let node = Lui_ui.create context Stepper in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.int_property context node ActiveIndex) active;
  Option.iter (Lui_ui.int_property_signal context node ActiveIndex) active_signal;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let step ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?text ?text_signal (_children : nothing list) : step_el =
 fun context parent ->
  let node = Lui_ui.step context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node TextValue) text;
  Option.iter (Lui_ui.string_property_signal context node TextValue) text_signal;
  attach context parent node;
  
  node

let timeline ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?label (children : timeline_item_el list) : t =
 fun context parent ->
  let node = Lui_ui.timeline context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node AccessibilityLabel) label;
  attach context parent node;
  mount_children context node children;
  node

let timeline_item ?key ?gap ?main ?cross ?grow ?columns ?padding ?padding_horizontal ?padding_vertical ?background ?foreground ?border_color ?border_width ?corner_radius ?width ?height ?min_width ?max_width ?min_height ?max_height ?container_relative_frame ?container_relative_frame_inset ?accessibility_identifier ?accessibility_identifier_signal ?foreground_signal ?background_signal ?style_class ?data_attrs ?data_attrs_signal ?on_appear ?on_pointer_enter ?on_pointer_leave ?title ?title_signal ?description ?meta ?indicator ?icon ?icon_signal ?variant ?connector ?selected ?on_press ?on_press_detail ?on_pointer_down ?on_pointer_up (_children : nothing list) : timeline_item_el =
 fun context parent ->
  let node = Lui_ui.timeline_item context in
  apply_universal context node ~key ~gap ~main ~cross ~grow ~columns ~padding ~padding_horizontal ~padding_vertical ~background ~foreground ~border_color ~border_width ~corner_radius ~width ~height ~min_width ~max_width ~min_height ~max_height ~container_relative_frame ~container_relative_frame_inset ~accessibility_identifier ~accessibility_identifier_signal ~foreground_signal ~background_signal ~style_class ~data_attrs ~data_attrs_signal ~on_appear ~on_pointer_enter ~on_pointer_leave;
  Option.iter (Lui_ui.string_property context node TitleValue) title;
  Option.iter (Lui_ui.string_property_signal context node TitleValue) title_signal;
  Option.iter (Lui_ui.string_property context node DescriptionValue) description;
  Option.iter (Lui_ui.string_property context node MetaValue) meta;
  Option.iter (Lui_ui.string_property context node IndicatorValue) indicator;
  Option.iter (Lui_ui.string_property context node InlineIconName) (Option.map icon_value icon);
  Option.iter (fun signal_ -> Lui_ui.string_property_signal context node InlineIconName (owned_map context icon_value signal_)) icon_signal;
  Option.iter (Lui_ui.string_property context node VariantValue) (Option.map variant_value variant);
  Option.iter (Lui_ui.bool_property context node Connector) connector;
  Option.iter (Lui_ui.bool_property context node Selected) selected;
  (match on_press with
   | Some handler ->
     enable context node PressEnabled;
     register_press context node handler
   | None -> ());
  apply_pointer_events context node ?on_press_detail ?on_pointer_down ?on_pointer_up ();
  attach context parent node;
  
  node

let themed ?tokens ?tokens_signal ?mode ?mode_signal (element : t) : t =
 fun context parent ->
  let node = element context parent in
  Option.iter (Lui_ui.theme context node) tokens;
  Option.iter (Lui_ui.theme_signal context node) tokens_signal;
  Option.iter (Lui_ui.theme_mode context node) mode;
  Option.iter (Lui_ui.theme_mode_signal context node) mode_signal;
  node
