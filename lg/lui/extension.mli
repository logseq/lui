(* ns lui.extension *)

type scalar_kind =
  | StringScalar
  | BoolScalar
  | IntScalar
  | FloatScalar

type extension_property_schema = { extension_property_name : string ; extension_property_kind : scalar_kind ; extension_property_required : bool ; extension_property_default : wire_value option }

type extension_event_field_schema = { extension_event_field_name : string ; extension_event_field_kind : scalar_kind ; extension_event_field_required : bool }

type extension_event_schema = { extension_event_name : string ; extension_event_fields : extension_event_field_schema Rrbvec.t }

type extension_component_schema = { extension_identifier : string ; extension_profiles : platform_profile Rrbvec.t ; extension_standard_children : bool ; extension_child_identifiers : string Rrbvec.t ; extension_properties : extension_property_schema Rrbvec.t ; extension_events : extension_event_schema Rrbvec.t }

type extension_registry = { extension_schemas : (string, extension_component_schema) Lg_runtime.Runtime_map.t ref ; extension_tweak_identifiers : (string, bool) Lg_runtime.Runtime_map.t ref ; extension_registry_frozen : bool ref }

val property : string -> scalar_kind -> bool -> wire_value option -> extension_property_schema

val event_field : string -> scalar_kind -> bool -> extension_event_field_schema

val event : string -> extension_event_field_schema Rrbvec.t -> extension_event_schema

val component : string -> platform_profile Rrbvec.t -> bool -> string Rrbvec.t -> extension_property_schema Rrbvec.t -> extension_event_schema Rrbvec.t -> extension_component_schema

val tweak : string -> platform_profile Rrbvec.t -> extension_property_schema Rrbvec.t -> extension_component_schema

val scalar_value_supported_ : scalar_kind -> wire_value -> bool

val scalar_kind_name : scalar_kind -> string

val operating_system_name : operating_system -> string

val host_name : host_kind -> string

val token : string -> string

val wire_value_token : wire_value -> string

val option_value_token : wire_value option -> string

val insert_sorted : string Rrbvec.t -> string -> string Rrbvec.t

val sorted_strings : string Rrbvec.t -> string Rrbvec.t

val profile_token : platform_profile -> string

val property_token : extension_property_schema -> string

val event_field_token : extension_event_field_schema -> string

val event_token : extension_event_schema -> string

val fingerprint : extension_component_schema -> string

val tweak_fingerprint : extension_component_schema -> string

val registry : unit -> extension_registry

val register_component_bang : extension_registry -> extension_component_schema -> bool

val register_tweak_bang : extension_registry -> extension_component_schema -> bool

val freeze_bang : extension_registry -> bool

val frozen_ : extension_registry -> bool

val schema : extension_registry -> string -> extension_component_schema option

val tweak_ : extension_registry -> string -> bool

val profile_supported_ : extension_component_schema -> platform_profile -> bool

val standard_container_supported_ : node_kind -> bool

val identifier_allowed_ : string Rrbvec.t -> string -> bool

val property_value_supported_ : extension_component_schema -> string -> wire_value -> bool

val property_supported_ : extension_component_schema -> string -> bool

val properties_supported_ : extension_component_schema -> (string, wire_value) Lg_runtime.Runtime_map.t -> bool

val event_payload_supported_ : extension_component_schema -> string -> (string, wire_value) Lg_runtime.Runtime_map.t -> bool

