(* UI-facing surface: the rendering context plus thin node and property
   helpers on top of the runtime. *)

open Lui_protocol

type ui_context = {
  ui_application : Lui_runtime.application;
  ui_scheduler : Signal.scheduler;
  ui_scope : Signal.scope;
  ui_state_scope : Signal.scope;
  ui_state_scopes : (string, Signal.scope) Hashtbl.t;
  ui_active_state_paths : (string, bool) Hashtbl.t;
  ui_state_path : string;
  ui_profile : platform_profile;
}

let make_context application scope state_scope state_scopes
    active_state_paths state_path =
  {
    ui_application = application;
    ui_scheduler = application.Lui_runtime.runtime_scheduler;
    ui_scope = scope;
    ui_state_scope = state_scope;
    ui_state_scopes = state_scopes;
    ui_active_state_paths = active_state_paths;
    ui_state_path = state_path;
    ui_profile =
      application.Lui_runtime.runtime_backend.backend_profile;
  }

let context application scope =
  make_context application scope scope (Hashtbl.create 16)
    (Hashtbl.create 16) ""

let context_with_state_scope application scope state_scope =
  make_context application scope state_scope (Hashtbl.create 16)
    (Hashtbl.create 16) ""

let context_with_state_registry application scope state_scope state_scopes
    active_state_paths =
  make_context application scope state_scope state_scopes
    active_state_paths ""

let child_context parent name =
  let scope = Signal.child_scope name parent.ui_scope in
  let path = parent.ui_state_path ^ "/" ^ name in
  let state_scopes = parent.ui_state_scopes in
  let active_state_paths = parent.ui_active_state_paths in
  let state_scope =
    match Hashtbl.find_opt state_scopes path with
    | Some existing -> existing
    | None ->
      let created = Signal.child_scope name parent.ui_state_scope in
      Hashtbl.replace state_scopes path created;
      created
  in
  Hashtbl.replace active_state_paths path true;
  make_context parent.ui_application scope state_scope state_scopes
    active_state_paths path

let node_kind context node =
  Lui_runtime.require_standard_node_kind context.ui_application node

let profile context = context.ui_profile

let platform context = context.ui_profile.profile_os

let host context = context.ui_profile.profile_host

let extension context identifier =
  Lui_runtime.create_extension_node context.ui_application identifier

let platform_tweak context identifier =
  Lui_runtime.create_tweak_node context.ui_application identifier

let key context node key =
  Lui_runtime.set_reload_key context.ui_application node key

let extension_property context node property value =
  Lui_runtime.set_extension_prop context.ui_application node property
    value

let extension_property_signal context node property source =
  ignore
    (Lui_runtime.bind_extension_prop context.ui_scope
       context.ui_application node property source)

let create context kind = Lui_runtime.create_node context.ui_application kind

let row context = create context Row
let column context = create context Column
let grid context = create context Grid
let stack context = create context Stack
let panel context = create context Panel
let card context = create context Card
let alert context = create context Alert
let bubble context = create context Bubble
let box context = create context Box
let scroll context = create context Scroll
let list context = create context ListContainer
let virtual_list context = create context VirtualList
let tabs context = create context Tabs
let bottom_tabs context = create context BottomTabs
let bottom_tab context = create context BottomTab
let button_group context = create context ButtonGroup
let toggle_group context = create context ToggleGroup
let breadcrumb context = create context Breadcrumb
let pagination context = create context Pagination
let table context = create context Table
let table_row context = create context TableRow
let table_cell context = create context TableCell
let tree context = create context Tree
let resizable context = create context Resizable
let drawer context = create context Drawer
let status_bar context = create context StatusBar
let toolbar context = create context Toolbar
let spacer context = create context Spacer
let spinner context = create context Spinner
let text_field context = create context TextField
let secure_field context = create context SecureField
let input context = create context Input
let search_field context = create context SearchField
let textarea context = create context Textarea
let select context = create context Select
let combobox context = create context Combobox
let dropdown_menu context = create context DropdownMenu
let context_menu context = create context ContextMenu
let dialog context = create context Dialog
let sheet context = create context Sheet
let tooltip context = create context Tooltip
let toast context = create context Toast
let accordion context = create context Accordion
let menu_item context = create context MenuItem
let list_item context = create context ListItem
let avatar context = create context Avatar
let image context = create context Image
let media_surface context = create context MediaSurface
let stepper context = create context Stepper
let step context = create context Step
let timeline context = create context Timeline
let timeline_item context = create context TimelineItem
let input_group context = create context InputGroup
let input_group_actions context = create context InputGroupActions
let button context = create context Button
let toggle_button context = create context ToggleButton
let toggle context = create context Toggle
let radio_group context = create context RadioGroup
let radio context = create context Radio
let checkbox context = create context Checkbox
let switch_control context = create context SwitchControl

let bind_float_prop context node property source =
  ignore
    (Lui_runtime.bind_prop context.ui_scope context.ui_application node
       property
       (Signal.own_signal context.ui_scope
          (Signal.map (fun value -> FloatValue value) source)))

let split context source =
  let node = create context Split in
  bind_float_prop context node ProgressValue source;
  node

let split_literal context value =
  let node = create context Split in
  Lui_runtime.set_prop context.ui_application node ProgressValue
    (FloatValue value);
  node

let icon context name =
  let node = create context Icon in
  Lui_runtime.set_prop context.ui_application node IconName
    (StringValue name);
  node

let text context text =
  let node = create context Text in
  Lui_runtime.set_prop context.ui_application node TextValue
    (StringValue text);
  node

let heading context level text =
  let node = create context Heading in
  Lui_runtime.set_prop context.ui_application node HeadingLevel
    (IntValue level);
  Lui_runtime.set_prop context.ui_application node TextValue
    (StringValue text);
  node

let bind_string_prop context node property source =
  ignore
    (Lui_runtime.bind_prop context.ui_scope context.ui_application node
       property
       (Signal.own_signal context.ui_scope
          (Signal.map (fun text -> StringValue text) source)))

let heading_value context level source =
  let node = create context Heading in
  Lui_runtime.set_prop context.ui_application node HeadingLevel
    (IntValue level);
  ignore
    (Lui_runtime.bind_prop context.ui_scope context.ui_application node
       TextValue source);
  node

let heading_signal context level source =
  heading_value context level
    (Signal.own_signal context.ui_scope
       (Signal.map (fun text -> StringValue text) source))

let paragraph context text =
  let node = create context Paragraph in
  Lui_runtime.set_prop context.ui_application node TextValue
    (StringValue text);
  node

let paragraph_value context source =
  let node = create context Paragraph in
  ignore
    (Lui_runtime.bind_prop context.ui_scope context.ui_application node
       TextValue source);
  node

let paragraph_signal context source =
  paragraph_value context
    (Signal.own_signal context.ui_scope
       (Signal.map (fun text -> StringValue text) source))

let label context text =
  let node = create context Label in
  Lui_runtime.set_prop context.ui_application node TextValue
    (StringValue text);
  node

let label_value context source =
  let node = create context Label in
  ignore
    (Lui_runtime.bind_prop context.ui_scope context.ui_application node
       TextValue source);
  node

let label_signal context source =
  label_value context
    (Signal.own_signal context.ui_scope
       (Signal.map (fun text -> StringValue text) source))

let text_value context source =
  let node = create context Text in
  ignore
    (Lui_runtime.bind_prop context.ui_scope context.ui_application node
       TextValue source);
  node

let text_signal context source =
  text_value context
    (Signal.own_signal context.ui_scope
       (Signal.map (fun text -> StringValue text) source))

let slider context source =
  let node = create context Slider in
  bind_float_prop context node ProgressValue source;
  node

let slider_literal context value =
  let node = create context Slider in
  Lui_runtime.set_prop context.ui_application node ProgressValue
    (FloatValue value);
  node

let string_property context node property value =
  Lui_runtime.set_prop context.ui_application node property
    (StringValue value)

let string_property_signal context node property source =
  bind_string_prop context node property source

let bool_property context node property value =
  Lui_runtime.set_prop context.ui_application node property
    (BoolValue value)

let bool_property_signal context node property source =
  ignore
    (Lui_runtime.bind_prop context.ui_scope context.ui_application node
       property
       (Signal.own_signal context.ui_scope
          (Signal.map (fun value -> BoolValue value) source)))

let float_property context node property value =
  Lui_runtime.set_prop context.ui_application node property
    (FloatValue value)

let float_property_signal context node property source =
  ignore
    (Lui_runtime.bind_prop context.ui_scope context.ui_application node
       property
       (Signal.own_signal context.ui_scope
          (Signal.map (fun value -> FloatValue value) source)))

let int_property_signal context node property source =
  ignore
    (Lui_runtime.bind_prop context.ui_scope context.ui_application node
       property
       (Signal.own_signal context.ui_scope
          (Signal.map (fun value -> IntValue value) source)))

let int_property context node property value =
  Lui_runtime.set_prop context.ui_application node property
    (IntValue value)

let disabled context node disabled =
  bool_property context node Enabled (not disabled)

let disabled_signal context node source =
  ignore
    (Lui_runtime.bind_prop context.ui_scope context.ui_application node
       Enabled
       (Signal.own_signal context.ui_scope
          (Signal.map (fun disabled -> BoolValue (not disabled)) source)))

let checked_signal context node source =
  bool_property_signal context node Checked source

let text_property context node text =
  Lui_runtime.set_prop context.ui_application node TextValue
    (StringValue text)

let text_property_signal context node source =
  bind_string_prop context node TextValue source

let on_event context node callback =
  Lui_runtime.on_event context.ui_scope context.ui_application node
    callback

let progress context source =
  let node = create context Progress in
  bind_float_prop context node ProgressValue source;
  node

let progress_literal context value =
  let node = create context Progress in
  Lui_runtime.set_prop context.ui_application node ProgressValue
    (FloatValue value);
  node

let separator context orientation =
  let node = create context Divider in
  Lui_runtime.set_prop context.ui_application node OrientationValue
    (StringValue orientation);
  node

let size context node size =
  Lui_runtime.set_prop context.ui_application node SizeValue
    (StringValue size)

let style_class context node class_name =
  Lui_runtime.set_prop context.ui_application node StyleClass
    (StringValue class_name)

let append context parent child =
  Lui_runtime.insert_child context.ui_application parent child
    (Lui_runtime.child_count context.ui_application parent)

let gap context node gap = int_property context node Gap gap
let main context node alignment = string_property context node MainAlignment alignment
let cross context node alignment = string_property context node CrossAlignment alignment
let grow context node grow = float_property context node GrowValue grow
let columns context node columns = int_property context node GridColumns columns
let padding context node padding = int_property context node PaddingValue padding
let padding_horizontal context node padding =
  int_property context node PaddingHorizontal padding
let padding_vertical context node padding =
  int_property context node PaddingVertical padding
let background context node color = string_property context node BackgroundValue color
let foreground context node color = string_property context node ForegroundValue color
let border_color context node color = string_property context node BorderColorValue color
let border_width context node width = int_property context node BorderWidth width
let corner_radius context node radius = int_property context node CornerRadius radius
let width context node width = int_property context node WidthValue width
let height context node height = int_property context node HeightValue height
let min_width context node width = int_property context node MinWidth width
let max_width context node width = int_property context node MaxWidth width
let min_height context node height = int_property context node MinHeight height
let max_height context node height = int_property context node MaxHeight height
let container_relative_frame context node axes =
  string_property context node ContainerRelativeFrameValue axes
let container_relative_frame_inset context node inset =
  int_property context node ContainerRelativeFrameInset inset
let placeholder context node placeholder =
  string_property context node PlaceholderValue placeholder
let accessibility_label context node label =
  string_property context node AccessibilityLabel label
let accessibility_identifier context node identifier =
  string_property context node AccessibilityIdentifier identifier
