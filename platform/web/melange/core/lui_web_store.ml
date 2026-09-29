(* Backend-side retained mirror: tracks the runtime tree the way the LG
   retained.cljc store did — applying each patch op with validation, checking
   the whole graph after a batch, then recording the committed batch. *)

open Lui_protocol
open Lui_web_types

let create_store () =
  { retained_nodes = Hashtbl.create 64;
    retained_batches = [];
    retained_generation = 0 }

let find_child_index children child =
  let rec loop index rest =
    match rest with
    | [] -> None
    | candidate :: tail ->
        if candidate = child then Some index else loop (index + 1) tail
  in
  loop 0 children

let remove_at values removed_index =
  List.filteri (fun index _ -> index <> removed_index) values

let insert_at values inserted_index value =
  if inserted_index < 0 || inserted_index > List.length values then
    invalid_arg "child index is out of bounds";
  let rec loop index rest acc =
    match rest with
    | [] -> List.rev acc
    | head :: tail ->
        let acc = if index = inserted_index then value :: acc else acc in
        loop (index + 1) tail (head :: acc)
  in
  if inserted_index = List.length values then values @ [ value ]
  else loop 0 values []

let move_at values from_index to_index =
  match List.nth_opt values from_index with
  | None -> values
  | Some value ->
      let without = remove_at values from_index in
      insert_at without to_index value

let standard_kind current =
  match current.semantic_kind with
  | StandardSemantic kind -> Some kind
  | ExtensionSemantic _ -> None

let standard_kind_is current expected =
  match standard_kind current with
  | Some kind -> kind = expected
  | None -> false

(* MenuTrigger renders as a menu row (a submenu's trigger), so menu
   behaviour that matches MenuItem rows covers both kinds. *)
let menu_item_row current =
  match standard_kind current with
  | Some kind -> kind = MenuItem || kind = MenuTrigger
  | None -> false

let extension_identity current =
  match current.semantic_kind with
  | ExtensionSemantic (identifier, fingerprint) -> Some (identifier, fingerprint)
  | StandardSemantic _ -> None

(* [target] is a descendant-or-self of [root] iff walking the retained-parent
   chain from target reaches root. *)
let rec descendant nodes root target =
  if target = root then true
  else
    match Hashtbl.find_opt nodes target with
    | Some node ->
        (match node.retained_parent with
         | Some parent -> descendant nodes root parent
         | None -> false)
    | None -> false

let extension_schema registry identifier =
  match Lui_extension.schema registry identifier with
  | Some schema -> schema
  | None -> invalid_arg "unknown extension identifier"

let rec retained_child_supported registry nodes parent child =
  match child.semantic_kind with
  | ExtensionSemantic (child_identifier, _) ->
      if Lui_extension.is_tweak registry child_identifier then
        match child.retained_children with
        | [ inner_id ] ->
            (match Hashtbl.find_opt nodes inner_id with
             | Some inner -> retained_child_supported registry nodes parent inner
             | None -> false)
        | _ -> false
      else
        (match parent.semantic_kind with
         | StandardSemantic parent_kind ->
             Lui_extension.standard_container_supported parent_kind
         | ExtensionSemantic (parent_identifier, _) ->
             if Lui_extension.is_tweak registry parent_identifier then
               parent.retained_children = []
             else
               Lui_extension.identifier_allowed
                 (extension_schema registry parent_identifier)
                   .extension_child_identifiers
                 child_identifier)
  | StandardSemantic child_kind ->
      if child_kind = Root then false
      else
        (match parent.semantic_kind with
         | StandardSemantic parent_kind ->
             can_contain_children parent_kind
             && child_kind_supported parent_kind child_kind
         | ExtensionSemantic (parent_identifier, _) ->
             if Lui_extension.is_tweak registry parent_identifier then
               parent.retained_children = []
             else
               (extension_schema registry parent_identifier)
                 .extension_standard_children)

let unsupported_child_message parent child =
  match (parent.semantic_kind, child.semantic_kind) with
  | StandardSemantic parent_kind, StandardSemantic _ ->
      if not (can_contain_children parent_kind) then
        "parent cannot contain children"
      else if parent_kind = Table then "table can contain only table-row"
      else if parent_kind = TableRow then "table-row can contain only table-cell"
      else if parent_kind = Tree then "tree accepts only row containers"
      else "unsupported child kind"
  | _ -> "unsupported child kind"

let with_children node children = { node with retained_children = children }

let replace nodes node_id next = Hashtbl.replace nodes node_id next

let fetch nodes node_id what =
  match Hashtbl.find_opt nodes node_id with
  | Some node -> node
  | None -> invalid_arg ("unknown " ^ what)

let apply_create_node nodes platform_for node_id kind =
  if Hashtbl.mem nodes node_id then invalid_arg "node already exists";
  replace nodes node_id
    { platform_node = platform_for kind;
      semantic_kind = StandardSemantic kind;
      retained_parent = None;
      retained_properties = Property_map.empty;
      retained_extension_properties = String_map.empty;
      retained_children = [] }

let apply_create_extension nodes extension_platform_for registry node_id identifier fingerprint =
  if Hashtbl.mem nodes node_id then invalid_arg "node already exists";
  let schema = extension_schema registry identifier in
  let expected =
    if Lui_extension.is_tweak registry identifier then
      Lui_extension.tweak_fingerprint schema
    else Lui_extension.fingerprint schema
  in
  if fingerprint <> expected then invalid_arg "extension fingerprint mismatch";
  replace nodes node_id
    { platform_node = extension_platform_for node_id identifier;
      semantic_kind = ExtensionSemantic (identifier, fingerprint);
      retained_parent = None;
      retained_properties = Property_map.empty;
      retained_extension_properties = String_map.empty;
      retained_children = [] }

let apply_drop_node nodes node_id =
  let current = fetch nodes node_id "node" in
  if current.retained_parent <> None then
    invalid_arg "cannot drop an attached node"
  else if current.retained_children <> [] then
    invalid_arg "cannot drop a node with children"
  else Hashtbl.remove nodes node_id

let apply_set_prop nodes node_id property value =
  let current = fetch nodes node_id "node" in
  match standard_kind current with
  | Some kind ->
      if
        property_supported kind property
        && property_value_supported_for_kind kind property value
      then
        replace nodes node_id
          { current with
            retained_properties =
              Property_map.add property value current.retained_properties }
      else invalid_arg "unsupported property value"
  | None -> invalid_arg "standard property targets extension"

let apply_remove_prop nodes node_id property =
  let current = fetch nodes node_id "node" in
  match standard_kind current with
  | Some kind ->
      if property_supported kind property then
        replace nodes node_id
          { current with
            retained_properties =
              Property_map.remove property current.retained_properties }
      else invalid_arg "unsupported property"
  | None -> invalid_arg "standard property targets extension"

let apply_set_extension_prop nodes registry node_id property value =
  let current = fetch nodes node_id "node" in
  match current.semantic_kind with
  | ExtensionSemantic (identifier, _) ->
      let schema = extension_schema registry identifier in
      if not (Lui_extension.property_value_supported schema property value) then
        invalid_arg "unsupported extension property value";
      replace nodes node_id
        { current with
          retained_extension_properties =
            String_map.add property value current.retained_extension_properties }
  | StandardSemantic _ ->
      invalid_arg "extension property targets standard node"

let apply_remove_extension_prop nodes registry node_id property =
  let current = fetch nodes node_id "node" in
  match current.semantic_kind with
  | ExtensionSemantic (identifier, _) ->
      let schema = extension_schema registry identifier in
      if not (Lui_extension.property_supported schema property) then
        invalid_arg "unknown extension property";
      replace nodes node_id
        { current with
          retained_extension_properties =
            String_map.remove property current.retained_extension_properties }
  | StandardSemantic _ ->
      invalid_arg "extension property targets standard node"

let apply_insert_child nodes registry parent_id child_id index =
  let parent_node = fetch nodes parent_id "parent" in
  let child_node = fetch nodes child_id "child" in
  if not (retained_child_supported registry nodes parent_node child_node) then
    invalid_arg (unsupported_child_message parent_node child_node)
  else if descendant nodes child_id parent_id then
    invalid_arg "child insertion would create a cycle"
  else if child_node.retained_parent <> None then
    invalid_arg "child is already attached"
  else begin
    replace nodes parent_id
      (with_children parent_node
         (insert_at parent_node.retained_children index child_id));
    replace nodes child_id { child_node with retained_parent = Some parent_id }
  end

let apply_remove_child nodes parent_id child_id =
  let parent_node = fetch nodes parent_id "parent" in
  match find_child_index parent_node.retained_children child_id with
  | Some index ->
      let child_node = fetch nodes child_id "child" in
      replace nodes parent_id
        (with_children parent_node
           (remove_at parent_node.retained_children index));
      replace nodes child_id { child_node with retained_parent = None }
  | None -> invalid_arg "child is not attached to parent"

let apply_move_child nodes parent_id child_id index =
  let parent_node = fetch nodes parent_id "parent" in
  match find_child_index parent_node.retained_children child_id with
  | Some current_index ->
      replace nodes parent_id
        (with_children parent_node
           (move_at parent_node.retained_children current_index index))
  | None -> invalid_arg "child is not attached to parent"

(* Property writes to a node that was dropped earlier in the same batch (or
   by an earlier batch before its signal subscription was torn down) are moot;
   dropping them keeps one stale write from aborting the rest of the batch.
   Structural ops stay strict — a stale child/parent id there means a real
   reconcile bug. *)
let apply_op nodes platform_for extension_platform_for registry operation =
  match operation with
  | CreateNode (node, kind) -> apply_create_node nodes platform_for node kind
  | CreateExtension (node, identifier, fingerprint) ->
      apply_create_extension nodes extension_platform_for registry node
        identifier fingerprint
  | DropNode node -> apply_drop_node nodes node
  | SetProp (node, property, value) ->
      if Hashtbl.mem nodes node then
        apply_set_prop nodes node property value
  | RemoveProp (node, property) ->
      if Hashtbl.mem nodes node then apply_remove_prop nodes node property
  | SetExtensionProp (node, property, value) ->
      if Hashtbl.mem nodes node then
        apply_set_extension_prop nodes registry node property value
  | RemoveExtensionProp (node, property) ->
      if Hashtbl.mem nodes node then
        apply_remove_extension_prop nodes registry node property
  | InsertChild (parent, child, index) ->
      apply_insert_child nodes registry parent child index
  | RemoveChild (parent, child) -> apply_remove_child nodes parent child
  | MoveChild (parent, child, index) ->
      apply_move_child nodes parent child index

let unavailable_extension_platform _node _identifier =
  invalid_arg "extension registry is not configured"

let string_property_of properties property =
  match Property_map.find_opt property properties with
  | Some (StringValue value) -> value
  | _ -> ""

let node_properties_error current =
  let kind =
    match standard_kind current with
    | Some value -> value
    | None -> invalid_arg "expected standard node"
  in
  let properties = current.retained_properties in
  if not (surface_size_supported properties) then
    "surface size constraints conflict"
  else if kind = Button || kind = ToggleButton then
    let text = string_property_of properties TextValue in
    let label = string_property_of properties AccessibilityLabel in
    let icon = string_property_of properties InlineIconName in
    if text = "" && icon <> "" && label = "" then
      "icon-only button requires an accessibility label"
    else "button requires text or an accessibility label"
  else if kind = Icon then "icon requires a valid name"
  else "node properties conflict"

let metadata_child nodes child_id =
  match Hashtbl.find_opt nodes child_id with
  | Some current ->
      standard_kind_is current ContextMenu
      || standard_kind_is current SwipeActions
  | None -> false

let list_item_row_child nodes child_id =
  match Hashtbl.find_opt nodes child_id with
  | Some current -> standard_kind_is current ListItem
  | None -> false

let validate_list_item_content nodes current =
  if standard_kind_is current ListItem then begin
    let properties = current.retained_properties in
    let text = string_property_of properties TextValue in
    (* swipe-actions/context-menu children are metadata, not content; a
       disclosure row's nested list-items don't count as content either. *)
    let disclosure = Property_map.mem Expanded properties in
    let content_children =
      List.filter
        (fun child ->
          not (metadata_child nodes child)
          && not (disclosure && list_item_row_child nodes child))
        current.retained_children
    in
    if text <> "" && content_children <> [] then
      invalid_arg "list-item accepts text or children, not both";
    if text = "" && content_children = [] then
      invalid_arg "list-item requires text or children"
  end

let bool_property_true properties property =
  match Property_map.find_opt property properties with
  | Some (BoolValue true) -> true
  | _ -> false

let interactive_context_menu_host current =
  let properties = current.retained_properties in
  (match standard_kind current with
   | Some kind -> context_menu_host_kind kind
   | None -> false)
  || bool_property_true properties PressEnabled
  || bool_property_true properties DoublePressEnabled
  || bool_property_true properties ToggleEnabled
  || bool_property_true properties LongPressEnabled

let context_menu_child_has_nested nodes child kind =
  List.exists
    (fun nested_id ->
      match Hashtbl.find_opt nodes nested_id with
      | Some nested -> standard_kind_is nested kind
      | None -> false)
    child.retained_children

let validate_context_menu_child nodes child =
  let properties = child.retained_properties in
  let has_nested = context_menu_child_has_nested nodes child in
  if
    standard_kind_is child MenuItem
    && not (bool_property_true properties PressEnabled)
    && not (has_nested DropdownMenu)
  then invalid_arg "context-menu menu-item requires press support";
  if standard_kind_is child MenuItem && has_nested ContextMenu then
    invalid_arg "context-menu submenu must use dropdown-menu";
  if standard_kind_is child Divider then
    let allowed =
      Property_map.add OrientationValue (StringValue "horizontal")
        (Property_map.add StyleClass (StringValue "lui-separator")
           Property_map.empty)
    in
    if not (Property_map.is_empty properties || properties = allowed) then
      invalid_arg "context-menu separator accepts no attributes"

let validate_context_menu nodes current =
  let context_children =
    List.filter
      (fun child_id ->
        match Hashtbl.find_opt nodes child_id with
        | Some current -> standard_kind_is current ContextMenu
        | None -> false)
      current.retained_children
  in
  if List.length context_children > 1 then
    invalid_arg "host accepts at most one context-menu";
  if context_children <> [] && not (interactive_context_menu_host current) then
    invalid_arg "context-menu host must be interactive";
  if standard_kind_is current ContextMenu then begin
    (match current.retained_parent with
     | None -> invalid_arg "context-menu requires a direct host"
     | Some _ -> ());
    List.iter
      (fun child_id ->
        match Hashtbl.find_opt nodes child_id with
        | Some child -> validate_context_menu_child nodes child
        | None -> invalid_arg "unknown context-menu child")
      current.retained_children
  end

let validate_image_source current =
  match standard_kind current with
  | Some kind when kind = Avatar || kind = Image ->
      let properties = current.retained_properties in
      let label = if kind = Avatar then "avatar" else "image" in
      let present p = Property_map.mem p properties in
      let source_count =
        List.length
          (List.filter present [ SourceX; SourceY; SourceWidth; SourceHeight ])
      in
      if source_count > 0 && source_count < 4 then
        invalid_arg
          (label ^ " source crop requires all four coordinates");
      if source_count = 4 then begin
        let float_prop p fallback =
          match Property_map.find_opt p properties with
          | Some (FloatValue value) -> value
          | _ -> fallback
        in
        let x = float_prop SourceX (-1.0) in
        let y = float_prop SourceY (-1.0) in
        let width = float_prop SourceWidth 0.0 in
        let height = float_prop SourceHeight 0.0 in
        if x < 0.0 || y < 0.0 then
          invalid_arg
            (label ^ " source crop coordinates must be non-negative");
        if width <= 0.0 || height <= 0.0 then
          invalid_arg
            (label ^ " source crop dimensions must be positive")
      end
  | _ -> ()

let validate_media_resource current =
  match standard_kind current with
  | Some Image ->
      if not (Property_map.mem ImageIdValue current.retained_properties) then
        invalid_arg "image requires image"
  | Some MediaSurface ->
      if not (Property_map.mem SurfaceIdValue current.retained_properties) then
        invalid_arg "media-surface requires surface"
  | _ -> ()

let validate_progress_structure current =
  match standard_kind current with
  | Some Stepper ->
      if not (Property_map.mem ActiveIndex current.retained_properties) then
        invalid_arg "stepper requires active"
  | Some TimelineItem ->
      if not (Property_map.mem TitleValue current.retained_properties) then
        invalid_arg "timeline-item requires title"
  | Some NumberStepper ->
      if not (Property_map.mem ProgressValue current.retained_properties) then
        invalid_arg "number-stepper requires value"
  | _ -> ()

let child_kind_of nodes child_id =
  match Hashtbl.find_opt nodes child_id with
  | Some current ->
      (match standard_kind current with
       | Some kind -> kind
       | None -> invalid_arg "expected standard child")
  | None -> invalid_arg "unknown child"

let validate_input_group nodes current =
  match standard_kind current with
  | Some InputGroup ->
      let children = current.retained_children in
      if children = [] || List.length children > 2 then
        invalid_arg "input-group requires one textarea and optional actions";
      if child_kind_of nodes (List.hd children) <> Textarea then
        invalid_arg "input-group requires textarea first";
      if List.length children = 2
         && child_kind_of nodes (List.nth children 1) <> InputGroupActions
      then invalid_arg "input-group actions must follow textarea"
  | Some InputGroupActions ->
      (match current.retained_parent with
       | Some parent ->
           (match Hashtbl.find_opt nodes parent with
            | Some parent_node ->
                if not (standard_kind_is parent_node InputGroup) then
                  invalid_arg
                    "input-group-actions requires a direct input-group parent"
            | None -> invalid_arg "unknown input-group parent")
       | None ->
           invalid_arg
             "input-group-actions requires a direct input-group parent")
  | _ -> ()

let rec has_ancestor_kind nodes parent kind =
  match parent with
  | Some parent_id ->
      (match Hashtbl.find_opt nodes parent_id with
       | Some parent_node ->
           standard_kind_is parent_node kind
           || has_ancestor_kind nodes parent_node.retained_parent kind
       | None -> false)
  | None -> false

let validate_tree_item nodes current =
  if string_property_of current.retained_properties RoleValue = "treeitem"
     && not (has_ancestor_kind nodes current.retained_parent Tree)
  then invalid_arg "treeitem must be contained by a tree"

let validate_split current =
  if standard_kind_is current Split
     && List.length current.retained_children <> 2
  then invalid_arg "split requires exactly two children"

let validate_drawer current =
  if standard_kind_is current Drawer
     && List.length current.retained_children <> 2
  then invalid_arg "drawer requires exactly two children"

let validate_root current =
  if standard_kind_is current Root then begin
    if current.retained_parent <> None then
      invalid_arg "runtime root cannot have a parent";
    if List.length current.retained_children <> 1 then
      invalid_arg "runtime root requires exactly one child"
  end

let validate_standard_node nodes _registry current kind =
  if kind = Radio
     && not (has_ancestor_kind nodes current.retained_parent RadioGroup)
  then invalid_arg "radio must be contained by a radio-group";
  validate_list_item_content nodes current;
  validate_context_menu nodes current;
  validate_image_source current;
  validate_media_resource current;
  validate_progress_structure current;
  validate_input_group nodes current;
  validate_tree_item nodes current;
  validate_split current;
  validate_drawer current;
  validate_root current;
  if not (node_properties_supported kind current.retained_properties) then
    invalid_arg (node_properties_error current)

let validate_extension_node registry current identifier =
  if
    not
      (Lui_extension.properties_supported
         (extension_schema registry identifier)
         current.retained_extension_properties)
  then invalid_arg "extension properties are incomplete";
  if
    Lui_extension.is_tweak registry identifier
    && List.length current.retained_children <> 1
  then invalid_arg "platform tweak requires exactly one child"

let validate_nodes nodes registry =
  Hashtbl.iter
    (fun _node current ->
       match current.semantic_kind with
       | StandardSemantic kind ->
           validate_standard_node nodes registry current kind
       | ExtensionSemantic (identifier, _) ->
           validate_extension_node registry current identifier)
    nodes

let apply_operations nodes platform_for extension_platform_for registry batch =
  List.iter
    (fun op ->
       apply_op nodes platform_for extension_platform_for registry op)
    batch.ops;
  validate_nodes nodes registry

let commit_batch store platform_for extension_platform_for registry send_batch
    batch =
  let expected_generation = store.retained_generation + 1 in
  if expected_generation <> batch.generation then
    invalid_arg
      (Printf.sprintf "expected patch generation %d, received %d"
         expected_generation batch.generation);
  apply_operations store.retained_nodes platform_for extension_platform_for
    registry batch;
  if send_batch batch then begin
    store.retained_batches <- store.retained_batches @ [ batch ];
    store.retained_generation <- batch.generation;
    true
  end
  else invalid_arg "platform rejected patch batch"

let apply_batch_with store platform_for send_batch batch =
  commit_batch store platform_for unavailable_extension_platform
    (Lui_extension.registry ()) send_batch batch

let apply_batch_with_extensions store platform_for extension_platform_for
    registry send_batch batch =
  commit_batch store platform_for extension_platform_for registry send_batch
    batch

let apply_extension_batch store extension_platform_for registry batch =
  let unavailable_standard_platform _kind =
    invalid_arg "standard platform factory is not configured"
  in
  commit_batch store unavailable_standard_platform extension_platform_for
    registry (fun _batch -> true) batch

let apply_batch store platform_for batch =
  apply_batch_with store platform_for (fun _batch -> true) batch

let node store node_id = Hashtbl.find_opt store.retained_nodes node_id
let nodes store = store.retained_nodes

let platform_node store node_id =
  match node store node_id with
  | Some current -> Some current.platform_node
  | None -> None

let property store node_id property =
  match node store node_id with
  | Some current -> Property_map.find_opt property current.retained_properties
  | None -> None

let extension_identifier store node_id =
  match node store node_id with
  | Some current ->
      (match current.semantic_kind with
       | ExtensionSemantic (identifier, _) -> Some identifier
       | StandardSemantic _ -> None)
  | None -> None

let extension_property store node_id property =
  match node store node_id with
  | Some current ->
      String_map.find_opt property current.retained_extension_properties
  | None -> None

let children store node_id =
  match node store node_id with
  | Some current -> current.retained_children
  | None -> invalid_arg "unknown node"

let node_count store = Hashtbl.length store.retained_nodes
let batches store = store.retained_batches
let generation store = store.retained_generation

(* Shared queries that only read the mirror — used by every feature module. *)

let kind_of_store_node store node_id =
  match node store node_id with
  | Some current -> standard_kind current
  | None -> None

let dropdown_node store node_id =
  match node store node_id with
  | Some current -> standard_kind_is current DropdownMenu
  | None -> false

let modal_node store node_id =
  match node store node_id with
  | Some current ->
      (match standard_kind current with
       | Some kind -> modal_surface kind
       | None -> false)
  | None -> false

let toast_node store node_id =
  match node store node_id with
  | Some current -> standard_kind_is current Toast
  | None -> false

let context_menu_node store node_id =
  match node store node_id with
  | Some current -> standard_kind_is current ContextMenu
  | None -> false

let anchored_tooltip current =
  standard_kind_is current Tooltip
  && Property_map.mem AnchorValue current.retained_properties

let anchored_tooltip_node store node_id =
  match node store node_id with
  | Some current -> anchored_tooltip current
  | None -> false

let portal_surface_node store node_id =
  context_menu_node store node_id
  || dropdown_node store node_id
  || toast_node store node_id
  || anchored_tooltip_node store node_id
  || modal_node store node_id

let rec node_has_ancestor_kind store node_id kind =
  match node store node_id with
  | Some current ->
      (match current.retained_parent with
       | Some parent ->
           (match Hashtbl.find_opt store.retained_nodes parent with
            | Some parent_node ->
                standard_kind_is parent_node kind
                || node_has_ancestor_kind store parent kind
            | None -> false)
       | None -> false)
  | None -> false

let true_property renderer node prop =
  match property renderer.web_store node prop with
  | Some (BoolValue true) -> true
  | _ -> false

let enabled_node renderer node =
  match property renderer.web_store node Enabled with
  | Some (BoolValue false) -> false
  | _ -> true
let event_capability renderer node prop = true_property renderer node prop

let submit_on_enter renderer node = true_property renderer node SubmitOnEnter
let submit_enabled renderer node = true_property renderer node SubmitEnabled

let string_property renderer node prop =
  match property renderer.web_store node prop with
  | Some (StringValue value) -> value
  | _ -> ""

let int_property renderer node prop fallback =
  match property renderer.web_store node prop with
  | Some (IntValue value) -> value
  | _ -> fallback

let float_property renderer node prop fallback =
  match property renderer.web_store node prop with
  | Some (FloatValue value) -> value
  | _ -> fallback

let tooltip_delay renderer node = int_property renderer node TooltipDelay 600
let toast_duration renderer node = int_property renderer node DurationValue 5000

let selected_property renderer node =
  true_property renderer node Selected

let direct_toggle kind =
  match kind with
  | Checkbox | SwitchControl | Radio -> true
  | _ -> false

let button_like kind =
  match kind with
  | Button | ToggleButton | Toggle -> true
  | _ -> false

let treeitem renderer node =
  match property renderer.web_store node RoleValue with
  | Some (StringValue "treeitem") -> true
  | _ -> false

let rec tree_ancestor renderer node_id =
  match node renderer.web_store node_id with
  | Some current ->
      (match current.retained_parent with
       | Some parent ->
           (match node renderer.web_store parent with
            | Some parent_node ->
                if standard_kind_is parent_node Tree then Some parent
                else tree_ancestor renderer parent
            | None -> None)
       | None -> None)
  | None -> None
