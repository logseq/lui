(* Extension component and tweak schemas: declaration, fingerprints, and
   the registry the runtime validates against. *)

open Lui_protocol

type scalar_kind =
  | StringScalar
  | BoolScalar
  | IntScalar
  | FloatScalar

type extension_property_schema = {
  extension_property_name : string;
  extension_property_kind : scalar_kind;
  extension_property_required : bool;
  extension_property_default : wire_value option;
}

type extension_event_field_schema = {
  extension_event_field_name : string;
  extension_event_field_kind : scalar_kind;
  extension_event_field_required : bool;
}

type extension_event_schema = {
  extension_event_name : string;
  extension_event_fields : extension_event_field_schema list;
}

type extension_component_schema = {
  extension_identifier : string;
  extension_profiles : platform_profile list;
  extension_standard_children : bool;
  extension_child_identifiers : string list;
  extension_properties : extension_property_schema list;
  extension_events : extension_event_schema list;
}

type extension_registry = {
  extension_schemas : (string, extension_component_schema) Hashtbl.t;
  extension_tweak_identifiers : (string, bool) Hashtbl.t;
  extension_registry_frozen : bool ref;
}

let is_slug_char c = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')

let valid_name value =
  let n = String.length value in
  n > 0
  && is_slug_char value.[0]
  && is_slug_char value.[n - 1]
  &&
  let rec loop index =
    if index = n then true
    else if is_slug_char value.[index] then loop (index + 1)
    else value.[index] = '-' && is_slug_char value.[index + 1]
         && loop (index + 1)
  in
  loop 0

let scalar_value_supported kind value =
  match (kind, value) with
  | StringScalar, StringValue _ -> true
  | BoolScalar, BoolValue _ -> true
  | IntScalar, IntValue _ -> true
  | FloatScalar, FloatValue number ->
    number = number && number <> infinity && number <> neg_infinity
  | _ -> false

let property name kind required default =
  if not (valid_name name) then
    invalid_arg "invalid extension property name";
  (match default with
  | Some value ->
    if not (scalar_value_supported kind value) then
      invalid_arg "invalid extension property default"
  | None -> ());
  {
    extension_property_name = name;
    extension_property_kind = kind;
    extension_property_required = required;
    extension_property_default = default;
  }

let event_field name kind required =
  if not (valid_name name) then
    invalid_arg "invalid extension event field name";
  {
    extension_event_field_name = name;
    extension_event_field_kind = kind;
    extension_event_field_required = required;
  }

let duplicate_by_name values name_of =
  let rec loop index seen =
    if index = List.length values then false
    else
      let name = name_of (List.nth values index) in
      if List.mem name seen then true else loop (index + 1) (name :: seen)
  in
  loop 0 []

let event name fields =
  if not (valid_name name) then invalid_arg "invalid extension event name";
  if
    duplicate_by_name fields (fun field -> field.extension_event_field_name)
  then invalid_arg "duplicate extension event field";
  { extension_event_name = name; extension_event_fields = fields }

let component identifier profiles standard_children child_identifiers
    properties events =
  if not (valid_name identifier) then
    invalid_arg "invalid extension identifier";
  List.iter
    (fun child ->
       if not (valid_name child) then
         invalid_arg "invalid extension child identifier")
    child_identifiers;
  if duplicate_by_name child_identifiers Fun.id then
    invalid_arg "duplicate extension child identifier";
  if
    duplicate_by_name properties (fun p -> p.extension_property_name)
  then invalid_arg "duplicate extension property";
  if duplicate_by_name events (fun e -> e.extension_event_name) then
    invalid_arg "duplicate extension event";
  {
    extension_identifier = identifier;
    extension_profiles = profiles;
    extension_standard_children = standard_children;
    extension_child_identifiers = child_identifiers;
    extension_properties = properties;
    extension_events = events;
  }

let tweak identifier profiles properties =
  component identifier profiles true [] properties []

let scalar_kind_name kind =
  match kind with
  | StringScalar -> "string"
  | BoolScalar -> "bool"
  | IntScalar -> "int"
  | FloatScalar -> "float"

let operating_system_name operating_system =
  match operating_system with
  | GenericOS -> "generic"
  | WebOS -> "web"
  | MacOS -> "macos"
  | IOS -> "ios"
  | AndroidOS -> "android"
  | LinuxOS -> "linux"
  | WindowsOS -> "windows"

let host_name host =
  match host with
  | GenericHost -> "generic"
  | WebHost -> "web"
  | SwiftUIHost -> "swiftui"
  | FlutterHost -> "flutter"

let token value = string_of_int (String.length value) ^ ":" ^ value

let wire_value_token value =
  match value with
  | StringValue text -> "s" ^ token text
  | BoolValue enabled -> if enabled then "b1" else "b0"
  | IntValue number -> "i" ^ string_of_int number
  | FloatValue number -> "f" ^ string_of_float number

let option_value_token value =
  match value with
  | Some current -> "some:" ^ wire_value_token current
  | None -> "none"

let sorted_strings values = List.sort String.compare values

let profile_token profile =
  operating_system_name profile.profile_os ^ "/"
  ^ host_name profile.profile_host

let property_token schema =
  token schema.extension_property_name
  ^ ":"
  ^ scalar_kind_name schema.extension_property_kind
  ^ ":"
  ^ (if schema.extension_property_required then "required" else "optional")
  ^ ":" ^ option_value_token schema.extension_property_default

let event_field_token schema =
  token schema.extension_event_field_name
  ^ ":"
  ^ scalar_kind_name schema.extension_event_field_kind
  ^ ":"
  ^ if schema.extension_event_field_required then "required" else "optional"

let event_token schema =
  let fields =
    sorted_strings
      (List.map event_field_token schema.extension_event_fields)
  in
  token schema.extension_event_name ^ "[" ^ String.concat "," fields ^ "]"

let fingerprint schema =
  let profiles = sorted_strings (List.map profile_token schema.extension_profiles) in
  let children = sorted_strings schema.extension_child_identifiers in
  let properties =
    sorted_strings (List.map property_token schema.extension_properties)
  in
  let events = sorted_strings (List.map event_token schema.extension_events) in
  "lui-extension-v1|" ^ token schema.extension_identifier ^ "|profiles:"
  ^ String.concat "," profiles
  ^ "|standard-children:"
  ^ (if schema.extension_standard_children then "1" else "0")
  ^ "|children:"
  ^ String.concat "," (List.map token children)
  ^ "|properties:"
  ^ String.concat "," properties ^ "|events:" ^ String.concat "," events

let tweak_fingerprint schema =
  let profiles =
    sorted_strings (List.map profile_token schema.extension_profiles)
  in
  let properties =
    sorted_strings (List.map property_token schema.extension_properties)
  in
  "lui-tweak-v1|" ^ token schema.extension_identifier ^ "|profiles:"
  ^ String.concat "," profiles
  ^ "|properties:" ^ String.concat "," properties

let registry () =
  {
    extension_schemas = Hashtbl.create 16;
    extension_tweak_identifiers = Hashtbl.create 16;
    extension_registry_frozen = ref false;
  }

let register_component registry schema =
  if !(registry.extension_registry_frozen) then
    invalid_arg "extension registry is frozen";
  let identifier = schema.extension_identifier in
  if Lui_wire_schema.standard_node_name identifier then
    invalid_arg "extension shadows a standard element";
  if Hashtbl.mem registry.extension_schemas identifier then
    invalid_arg "extension identifier is already registered";
  Hashtbl.replace registry.extension_schemas identifier schema

let register_tweak registry schema =
  if !(registry.extension_registry_frozen) then
    invalid_arg "extension registry is frozen";
  let identifier = schema.extension_identifier in
  if Lui_wire_schema.standard_node_name identifier then
    invalid_arg "tweak shadows a standard element";
  if Hashtbl.mem registry.extension_schemas identifier then
    invalid_arg "extension identifier is already registered";
  if
    (not schema.extension_standard_children)
    || schema.extension_child_identifiers <> []
    || schema.extension_events <> []
  then invalid_arg "invalid tweak schema";
  Hashtbl.replace registry.extension_schemas identifier schema;
  Hashtbl.replace registry.extension_tweak_identifiers identifier true

let freeze registry =
  if not !(registry.extension_registry_frozen) then begin
    Hashtbl.iter
      (fun _identifier schema ->
         List.iter
           (fun child ->
              if not (Hashtbl.mem registry.extension_schemas child) then
                invalid_arg "unknown extension child schema")
           schema.extension_child_identifiers)
      registry.extension_schemas;
    registry.extension_registry_frozen := true
  end

let frozen registry = !(registry.extension_registry_frozen)

let schema registry identifier =
  Hashtbl.find_opt registry.extension_schemas identifier

let is_tweak registry identifier =
  Hashtbl.mem registry.extension_tweak_identifiers identifier

let profile_supported schema profile =
  List.exists (fun current -> current = profile) schema.extension_profiles

let standard_container_supported kind =
  match kind with
  | Root | Row | Column | Grid | Stack | Panel | Card | Box | Scroll
  | ListContainer | VirtualList | ListItem | Dialog | Sheet | Accordion
  | Resizable | Split | Drawer | Alert | Bubble -> true
  | _ -> false

let identifier_allowed identifiers identifier = List.mem identifier identifiers

let property_schema schema name =
  List.find_opt
    (fun current -> name = current.extension_property_name)
    schema.extension_properties

let property_value_supported schema name value =
  match property_schema schema name with
  | Some current -> scalar_value_supported current.extension_property_kind value
  | None -> false

let property_supported schema name =
  match property_schema schema name with
  | Some _ -> true
  | None -> false

let properties_supported schema values =
  String_map.for_all
    (fun name value -> property_value_supported schema name value)
    values
  && List.for_all
       (fun property ->
          if property.extension_property_required
             && (not (String_map.mem property.extension_property_name values))
             && property.extension_property_default = None
          then false
          else true)
       schema.extension_properties

let event_schema schema name =
  List.find_opt
    (fun current -> name = current.extension_event_name)
    schema.extension_events

let event_field_schema schema name =
  List.find_opt
    (fun current -> name = current.extension_event_field_name)
    schema.extension_event_fields

let required_event_fields_present schema values =
  List.for_all
    (fun field ->
       if field.extension_event_field_required
          && not (String_map.mem field.extension_event_field_name values)
       then false
       else true)
    schema.extension_event_fields

let event_payload_supported schema name values =
  match event_schema schema name with
  | Some current ->
    required_event_fields_present current values
    && String_map.for_all
         (fun field_name value ->
            match event_field_schema current field_name with
            | Some field ->
              scalar_value_supported field.extension_event_field_kind value
            | None -> false)
         values
  | None -> false
