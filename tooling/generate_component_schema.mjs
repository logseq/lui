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

function renderProtocol(schema) {
  const nodeKinds = schema.nodeKinds.map(({ lg }) => `  (${lg})`).join('\n');
  const properties = schema.properties.map(({ lg }) => `  (${lg})`).join('\n');
  const events = schema.events
    .map(({ lg, fields }) => `  (${[lg, ...fields].join(' ')})`)
    .join('\n');
  return `${generatedHeader(';;')}(ns lui.protocol)

(type-variant node-kind
${nodeKinds})

(type-variant operating-system
  (GenericOS)
  (WebOS)
  (MacOS)
  (IOS)
  (AndroidOS)
  (LinuxOS)
  (WindowsOS))

(type-variant host-kind
  (GenericHost)
  (WebHost)
  (SwiftUIHost)
  (FlutterHost))

(type-record platform-profile
  (profile-os :operating-system)
  (profile-host :host-kind))

(type-variant property
${properties})

(type-variant wire-value
  (StringValue :string)
  (BoolValue :bool)
  (IntValue :int)
  (FloatValue :float))

(type-variant event
${events})

(type-variant patch-op
  (CreateNode :int :node-kind)
  (DropNode :int)
  (SetProp :int :property :wire-value)
  (InsertChild :int :int :int)
  (RemoveChild :int :int)
  (MoveChild :int :int :int))

(type-record patch-batch
  (generation :int)
  (ops :vector<patch-op>))

(type-record backend
  (backend-profile :platform-profile)
  (apply-batch :fn<patch-batch;bool>))

(signature lui.protocol/profile
  :fn<operating-system;host-kind;platform-profile>)
(signature lui.protocol/generic-profile :fn<platform-profile>)
(signature lui.protocol/event-node :fn<event;int>)
(signature lui.protocol/event-supported? :fn<node-kind;event;bool>)
(signature lui.protocol/orientation-supported? :fn<string;bool>)
(signature lui.protocol/control-size-supported? :fn<string;bool>)
(signature lui.protocol/button-variant-supported? :fn<string;bool>)
(signature lui.protocol/icon-placement-supported? :fn<string;bool>)
(signature lui.protocol/icon-name-supported? :fn<string;bool>)
(signature lui.protocol/main-alignment-supported? :fn<string;bool>)
(signature lui.protocol/cross-alignment-supported? :fn<string;bool>)
(signature lui.protocol/property-supported? :fn<node-kind;property;bool>)
(signature lui.protocol/property-value-supported?
  :fn<property;wire-value;bool>)
(signature lui.protocol/int-property
  :fn<map<property;wire-value>;property;int;int>)
(signature lui.protocol/surface-size-supported?
  :fn<map<property;wire-value>;bool>)
(signature lui.protocol/node-properties-supported?
  :fn<node-kind;map<property;wire-value>;bool>)
(signature lui.protocol/can-contain-children? :fn<node-kind;bool>)
(signature lui.protocol/create-node-op :fn<int;node-kind;patch-op>)
(signature lui.protocol/drop-node-op :fn<int;patch-op>)
(signature lui.protocol/set-prop-op
  :fn<int;property;wire-value;patch-op>)
(signature lui.protocol/insert-child-op :fn<int;int;int;patch-op>)
(signature lui.protocol/remove-child-op :fn<int;int;patch-op>)
(signature lui.protocol/move-child-op :fn<int;int;int;patch-op>)
`;
}

function renderLGWire(schema) {
  const imports = chunks(
    [...schema.nodeKinds, ...schema.properties].map(({ lg }) => lg),
    6,
  ).map((line) => line.join(' ')).join('\n                     ');
  const kindCases = schema.nodeKinds
    .map(({ lg, wire }) => `    ${lg} "${wire}"`)
    .join('\n');
  const propertyCases = schema.properties
    .map(({ lg, wire }) => `    ${lg} "${wire}"`)
    .join('\n');
  return `${generatedHeader(';;')}(ns lui.wire-schema
  (:require [lui.protocol :refer [${imports}]]))

(defn node-kind-name [kind]
  (match kind
${kindCases}))

(defn property-name [property]
  (match property
${propertyCases}))
`;
}

function renderLGWireSignature() {
  return `${generatedHeader(';;')}(ns lui.wire-schema)

(signature lui.wire-schema/node-kind-name :fn<node-kind;string>)
(signature lui.wire-schema/property-name :fn<property;string>)
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
    ['lg/lui/protocol.lgi', renderProtocol(schema)],
    ['lg/lui/wire_schema.cljc', renderLGWire(schema)],
    ['lg/lui/wire_schema.lgi', renderLGWireSignature()],
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
