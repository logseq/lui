import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const defaultManifest = resolve(repository, 'schema/components.json');

function argumentValue(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}

function unique(entries, field, label) {
  const seen = new Set();
  for (const entry of entries) {
    const value = entry[field];
    if (typeof value !== 'string' || value.length === 0) {
      fail(`${label} must be non-empty`);
    }
    if (seen.has(value)) fail(`duplicate ${label}: ${value}`);
    seen.add(value);
  }
}

function validate(schema) {
  if (schema.schemaVersion !== 1) fail('unsupported component schema version');
  if (!schema.reference || typeof schema.reference.revision !== 'string') {
    fail('component schema requires a pinned reference revision');
  }
  for (const field of ['publicElements', 'nodeKinds', 'properties', 'events']) {
    if (!Array.isArray(schema[field])) fail(`${field} must be an array`);
  }
  unique(schema.publicElements, 'name', 'public element name');
  unique(schema.nodeKinds, 'lg', 'node-kind LG name');
  unique(schema.nodeKinds, 'wire', 'node-kind wire name');
  unique(schema.nodeKinds, 'dart', 'node-kind Dart name');
  unique(schema.nodeKinds, 'swift', 'node-kind Swift name');
  unique(schema.properties, 'lg', 'property LG name');
  unique(schema.properties, 'wire', 'property wire name');
  unique(schema.properties, 'swift', 'property Swift name');
  unique(schema.events, 'lg', 'event LG name');

  const statuses = new Set(['supported', 'partial', 'pending']);
  for (const element of schema.publicElements) {
    if (!statuses.has(element.status)) {
      fail(`invalid public element status for ${element.name}: ${element.status}`);
    }
  }
}

function generatedHeader(prefix) {
  return `${prefix} Generated from schema/components.json. Do not edit by hand.\n`;
}

function chunks(values, size) {
  const result = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}

function mungeType(name) {
  return name.split('/').pop().replace(/-/g, '_');
}

function mungeValue(name) {
  return name.replace(/-/g, '_').replace(/!/g, '_bang').replace(/\?/g, '_');
}

function ocamlFieldType(source) {
  return mungeType(source.replace(/^:/, ''));
}

function renderProtocolSignature(schema) {
  const variant = (name, ctors) =>
    `type ${name} =\n${ctors.map((c) => `  | ${c}`).join('\n')}`;
  const nodeKinds = schema.nodeKinds.map(({ lg }) => lg);
  const properties = schema.properties.map(({ lg }) => lg);
  const events = schema.events
    .map(({ lg, fields }) =>
      fields.length === 0 ? lg : `${lg} of ${fields.map(ocamlFieldType).join(' * ')}`)
    .join('\n  | ');
  return `${'(* Generated from schema/components.json. Do not edit by hand. *)\n'}

type node_kind =
${nodeKinds.map((k) => `  | ${k}`).join('\n')}

type operating_system =
  | GenericOS
  | WebOS
  | MacOS
  | IOS
  | AndroidOS
  | LinuxOS
  | WindowsOS

type host_kind =
  | GenericHost
  | WebHost
  | SwiftUIHost
  | FlutterHost

type platform_profile = {
  profile_os : operating_system;
  profile_host : host_kind;
}

type property =
${properties.map((p) => `  | ${p}`).join('\n')}

module Property_map : Map.S with type key = property

module String_map : Map.S with type key = string
module Int_map : Map.S with type key = int

type wire_value =
  | StringValue of string
  | BoolValue of bool
  | IntValue of int
  | FloatValue of float

type event =
  | ${events}
  | ExtensionEvent of int * string * string * wire_value String_map.t

type patch_op =
  | CreateNode of int * node_kind
  | CreateExtension of int * string * string
  | DropNode of int
  | SetProp of int * property * wire_value
  | RemoveProp of int * property
  | SetExtensionProp of int * string * wire_value
  | RemoveExtensionProp of int * string
  | InsertChild of int * int * int
  | RemoveChild of int * int
  | MoveChild of int * int * int

type patch_batch = {
  generation : int;
  ops : patch_op list;
}

type backend = {
  backend_profile : platform_profile;
  apply_batch : patch_batch -> bool;
}

val profile : operating_system -> host_kind -> platform_profile
val generic_profile : unit -> platform_profile
val event_node : event -> int
val modal_surface : node_kind -> bool
val tree_row_kind : node_kind -> bool
val context_menu_host_kind : node_kind -> bool
val context_menu_leaf_host_kind : node_kind -> bool
val event_supported : node_kind -> event -> bool
val true_property : wire_value Property_map.t -> property -> bool
val treeitem_properties : wire_value Property_map.t -> bool
val event_supported_for_properties : node_kind -> wire_value Property_map.t -> event -> bool
val container_relative_frame_supported : string -> bool
val orientation_supported : string -> bool
val control_size_supported : string -> bool
val button_variant_supported : string -> bool
val icon_placement_supported : string -> bool
val built_in_icon_name_supported : string -> bool
val is_slug_char : char -> bool
val slug_segment : string -> bool
val custom_icon_name_supported : string -> bool
val icon_name_supported : string -> bool
val main_alignment_supported : string -> bool
val cross_alignment_supported : string -> bool
val horizontal_container : node_kind -> bool
val common_property_supported : node_kind -> property -> bool
val property_supported : node_kind -> property -> bool
val is_finite : float -> bool
val property_value_supported : property -> wire_value -> bool
val property_value_supported_for_kind : node_kind -> property -> wire_value -> bool
val int_property : wire_value Property_map.t -> property -> int -> int
val float_property : wire_value Property_map.t -> property -> float -> float
val size_axis_supported : wire_value Property_map.t -> property -> property -> property -> bool
val surface_size_supported : wire_value Property_map.t -> bool
val string_property_or : wire_value Property_map.t -> property -> string -> string
val string_property_nonempty : wire_value Property_map.t -> property -> bool
val float_property_of : wire_value Property_map.t -> property -> float -> float
val node_properties_supported : node_kind -> wire_value Property_map.t -> bool
val can_contain_children : node_kind -> bool
val child_kind_supported : node_kind -> node_kind -> bool
val create_node_op : int -> node_kind -> patch_op
val create_extension_op : int -> string -> string -> patch_op
val drop_node_op : int -> patch_op
val set_prop_op : int -> property -> wire_value -> patch_op
val remove_prop_op : int -> property -> patch_op
val set_extension_prop_op : int -> string -> wire_value -> patch_op
val remove_extension_prop_op : int -> string -> patch_op
val insert_child_op : int -> int -> int -> patch_op
val remove_child_op : int -> int -> patch_op
val move_child_op : int -> int -> int -> patch_op
`;
}

function renderOCamlWire(schema) {
  const kindCases = schema.nodeKinds
    .map(({ lg, wire }) => `  | ${lg} -> "${wire}"`)
    .join('\n');
  const propertyCases = schema.properties
    .map(({ lg, wire }) => `  | ${lg} -> "${wire}"`)
    .join('\n');
  return `${'(* Generated from schema/components.json. Do not edit by hand. *)\n'}

open Lui_protocol

let node_kind_name kind =
  match kind with
${kindCases}

let standard_node_name name =
  match name with
${schema.nodeKinds.map(({ wire }) => `  | "${wire}" -> true`).join('\n')}
  | _ -> false

let property_name property =
  match property with
${propertyCases}
`;
}

function renderOCamlWireSignature() {
  return `${'(* Generated from schema/components.json. Do not edit by hand. *)\n'}

open Lui_protocol

val node_kind_name : node_kind -> string
val standard_node_name : string -> bool
val property_name : property -> string
`;
}

function renderSwift(schema) {
  const nodeKinds = schema.nodeKinds
    .map(({ swift, wire }) => `    case ${swift} = "${wire}"`)
    .join('\n');
  const properties = schema.properties
    .map(({ swift, wire }) => `    case ${swift} = "${wire}"`)
    .join('\n');
  return `${generatedHeader('//')}import Foundation

enum LUINodeKind: String, Decodable, Equatable {
${nodeKinds}
}

enum LUIProperty: String, Decodable, Hashable {
${properties}
}
`;
}

function renderDart(schema) {
  const enumCases = schema.nodeKinds.map(({ dart }) => `  ${dart},`).join('\n');
  const decoderCases = schema.nodeKinds
    .map(({ dart, wire }) => `    '${wire}' => _NodeKind.${dart},`)
    .join('\n');
  return `${generatedHeader('//')}part of 'lui_flutter_backend.dart';

enum _NodeKind {
${enumCases}
}

_NodeKind _decodeNodeKind(Object? value) {
  if (value is! String) {
    throw const LUIBackendException('kind must be a string');
  }
  return switch (value) {
${decoderCases}
    _ => throw const LUIBackendException('unknown node kind'),
  };
}
`;
}

function artifacts(schema) {
  return new Map([
    ['src/lui_protocol.mli', renderProtocolSignature(schema)],
    ['src/lui_wire_schema.ml', renderOCamlWire(schema)],
    ['src/lui_wire_schema.mli', renderOCamlWireSignature()],
    ['platform/apple/Sources/LUIAppleBackend/LUIWireSchema.swift', renderSwift(schema)],
    ['platform/flutter/lib/lui_wire_schema.g.dart', renderDart(schema)],
  ]);
}

const manifestPath = resolve(argumentValue('--manifest') ?? defaultManifest);
let schema;
try {
  schema = JSON.parse(readFileSync(manifestPath, 'utf8'));
} catch (error) {
  fail(`cannot read component schema: ${error.message}`);
}
validate(schema);

if (process.argv.includes('--validate')) process.exit(0);

if (process.argv.includes('--summary')) {
  const byStatus = (status) => schema.publicElements
    .filter((element) => element.status === status)
    .map((element) => element.name);
  process.stdout.write(`${JSON.stringify({
    referenceRevision: schema.reference.revision,
    excluded: schema.reference.excluded,
    supported: byStatus('supported'),
    partial: byStatus('partial'),
    pending: byStatus('pending'),
  })}\n`);
  process.exit(0);
}

const generated = artifacts(schema);
if (process.argv.includes('--check')) {
  const stale = [];
  for (const [relativePath, expected] of generated) {
    try {
      if (readFileSync(resolve(repository, relativePath), 'utf8') !== expected) {
        stale.push(relativePath);
      }
    } catch {
      stale.push(relativePath);
    }
  }
  if (stale.length > 0) fail(`stale generated component schema: ${stale.join(', ')}`);
  process.exit(0);
}

for (const [relativePath, contents] of generated) {
  writeFileSync(resolve(repository, relativePath), contents);
}
