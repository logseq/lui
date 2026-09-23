#!/usr/bin/env node
// Generate a typed OCaml extension API from an extension schema JSON file.
//
// Extensions are otherwise stringly: raw identifiers, hand-built
// Lui_extension schemas, and untyped Lui_ui.extension_property / on_event
// plumbing. Given a schema file this emits a module where every component
// gets a Lui_elements constructor whose arguments map 1:1 onto the declared
// properties (required properties become labeled ~args), every event gets a
// decoded record type and a typed ?on_<event> handler, and the registry is
// assembled and frozen in one place.
//
// Input JSON:
// {
//   "profiles": {
//     "apple": [{"os": "macos", "host": "swiftui"}, ...]
//   },
//   "components": [{
//     "identifier": "apple-map",
//     "profiles": "apple",                  // key into "profiles", or inline array
//     "standardChildren": false,
//     "children": ["apple-map-marker"],     // extension identifiers allowed as children
//     "properties": [
//       {"name": "latitude", "kind": "float", "required": true}
//     ],
//     "events": [
//       {"name": "region-change",
//        "fields": [{"name": "latitude", "kind": "float", "required": true}]}
//     ]
//   }],
//   "tweaks": [{"identifier": "gallery-accent", "profiles": "apple",
//               "properties": []}]
// }
//
// kind: "string" | "bool" | "int" | "float"
// os: "generic" | "web" | "macos" | "ios" | "android" | "linux" | "windows"
// host: "generic" | "web" | "swiftui" | "flutter"
//
// Usage: node tooling/generate_extension_api.mjs --schema <file.json> \
//        --out <Module.ml> [--mli <Module.mli>]

import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

function argumentValue(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}

const scalarKinds = {
  string: { ctor: 'StringScalar', ocaml: 'string', wire: 'StringValue' },
  bool: { ctor: 'BoolScalar', ocaml: 'bool', wire: 'BoolValue' },
  int: { ctor: 'IntScalar', ocaml: 'int', wire: 'IntValue' },
  float: { ctor: 'FloatScalar', ocaml: 'float', wire: 'FloatValue' },
};

const osNames = {
  generic: 'GenericOS', web: 'WebOS', macos: 'MacOS', ios: 'IOS',
  android: 'AndroidOS', linux: 'LinuxOS', windows: 'WindowsOS',
};

const hostNames = {
  generic: 'GenericHost', web: 'WebHost', swiftui: 'SwiftUIHost',
  flutter: 'FlutterHost',
};

const munge = (name) => name.replace(/-/g, '_');
const recordType = (ident, event) => `${munge(ident)}_${munge(event)}`;

function validate(spec) {
  const ids = new Set();
  for (const entry of [...(spec.components ?? []), ...(spec.tweaks ?? [])]) {
    if (typeof entry.identifier !== 'string' || entry.identifier.length === 0) {
      fail('every component/tweak needs an identifier');
    }
    if (ids.has(entry.identifier)) {
      fail(`duplicate extension identifier ${entry.identifier}`);
    }
    ids.add(entry.identifier);
  }
  const kinds = new Set(Object.keys(scalarKinds));
  for (const comp of spec.components ?? []) {
    for (const prop of comp.properties ?? []) {
      if (!kinds.has(prop.kind)) {
        fail(`${comp.identifier}.${prop.name}: unknown scalar kind ${prop.kind}`);
      }
    }
    for (const event of comp.events ?? []) {
      for (const field of event.fields ?? []) {
        if (!kinds.has(field.kind)) {
          fail(`${comp.identifier}.${event.name}.${field.name}: unknown scalar kind ${field.kind}`);
        }
      }
    }
    for (const child of comp.children ?? []) {
      if (!ids.has(child)) {
        fail(`${comp.identifier}: unknown child extension ${child}`);
      }
    }
  }
}

function profileExpr(spec, entry) {
  const ref = entry.profiles ?? 'default';
  const list = typeof ref === 'string' ? (spec.profiles ?? {})[ref] : ref;
  if (!Array.isArray(list)) {
    fail(`${entry.identifier}: unknown profiles reference ${ref}`);
  }
  const items = list.map(({ os, host }) => {
    if (!osNames[os]) fail(`${entry.identifier}: unknown os ${os}`);
    if (!hostNames[host]) fail(`${entry.identifier}: unknown host ${host}`);
    return `{ Lui_protocol.profile_os = ${osNames[os]}; Lui_protocol.profile_host = ${hostNames[host]} }`;
  });
  return `[ ${items.join('; ')} ]`;
}

function propSchemaExpr(prop) {
  const kind = scalarKinds[prop.kind];
  const required = prop.required === true ? 'true' : 'false';
  const def = prop.default === undefined
    ? 'None'
    : `Some (Lui_protocol.${kind.wire} ${JSON.stringify(prop.default.value)})`;
  return `Lui_extension.property ${JSON.stringify(prop.name)} Lui_extension.${kind.ctor} ${required} ${def}`;
}

function eventSchemaExpr(event) {
  const fields = (event.fields ?? []).map((field) =>
    `Lui_extension.event_field ${JSON.stringify(field.name)} Lui_extension.${scalarKinds[field.kind].ctor} ${field.required === true}`
  );
  return `Lui_extension.event ${JSON.stringify(event.name)} [ ${fields.join('; ')} ]`;
}

function schemaDecl(spec, comp) {
  if (comp.tweak === true) {
    return `let ${munge(comp.identifier)}_schema =
  Lui_extension.tweak ${JSON.stringify(comp.identifier)} ${profileExpr(spec, comp)}
    [ ${(comp.properties ?? []).map(propSchemaExpr).join('; ')} ]`;
  }
  return `let ${munge(comp.identifier)}_schema =
  Lui_extension.component ${JSON.stringify(comp.identifier)} ${profileExpr(spec, comp)}
    ${comp.standardChildren === true}
    [ ${(comp.children ?? []).map((c) => JSON.stringify(c)).join('; ')} ]
    [ ${(comp.properties ?? []).map(propSchemaExpr).join('; ')} ]
    [ ${(comp.events ?? []).map(eventSchemaExpr).join('; ')} ]`;
}

function eventRecord(comp, event) {
  const fields = (event.fields ?? []).map((f) =>
    `  ${munge(f.name)} : ${scalarKinds[f.kind].ocaml}${f.required === true ? '' : ' option'};`
  );
  return `type ${recordType(comp.identifier, event.name)} = {
  event_node : int;
${fields.join('\n')}
}`;
}

function eventDecoder(comp, event) {
  const name = recordType(comp.identifier, event.name);
  const fields = event.fields ?? [];
  const lookups = fields.map((f) => `String_map.find_opt ${JSON.stringify(f.name)} values`);
  const pattern = fields.map((f) =>
    f.required === true
      ? `Some (${scalarKinds[f.kind].wire} ${munge(f.name)})`
      : `${munge(f.name)}_opt`
  );
  // Optional fields must still decode only their own scalar kind.
  const guard = fields.map((f) =>
    f.required === true
      ? ''
      : `(match ${munge(f.name)}_opt with Some (${scalarKinds[f.kind].wire} _) | None -> true | _ -> false)`
  ).filter(Boolean);
  const bindings = fields.map((f) =>
    f.required === true
      ? `      ${munge(f.name)} = ${munge(f.name)};`
      : `      ${munge(f.name)} = (match ${munge(f.name)}_opt with Some (${scalarKinds[f.kind].wire} value) -> Some value | _ -> None);`
  );
  return `let decode_${name} = function
  | ExtensionEvent (node, identifier, event_name, values)
    when String.equal event_name ${JSON.stringify(event.name)}
         && String.equal identifier ${JSON.stringify(comp.identifier)} ->
    (match (${lookups.join(', ')}) with
     | (${pattern.join(', ')})${guard.length ? ` when ${guard.join(' && ')}` : ''} ->
       Some {
         event_node = node;
${bindings.join('\n')}
       }
     | _ -> None)
  | _ -> None`;
}

function mountImpl(spec, comp) {
  const name = munge(comp.identifier);
  const props = comp.properties ?? [];
  const events = comp.events ?? [];
  const args = [
    '?key',
    ...props.map((p) => (p.required === true ? `~${munge(p.name)}` : `?${munge(p.name)}`)),
    ...props.map((p) => `?${munge(p.name)}_signal`),
    ...events.map((e) => `?on_${munge(e.name)}`),
  ];
  const takesChildren =
    comp.standardChildren === true || (comp.children ?? []).length > 0;
  const childrenArg = takesChildren ? '(children : Lui_elements.t list)' : '()';
  const childrenDecl = takesChildren ? 'Lui_elements.t list' : 'unit';

  const setters = props.map((p) => {
    const kind = scalarKinds[p.kind];
    const n = munge(p.name);
    const arg = p.required === true ? `(Some ${n})` : n;
    return `  Option.iter
    (fun value ->
       Lui_ui.extension_property context node ${JSON.stringify(p.name)}
         (${kind.wire} value))
    ${arg};
  Option.iter
    (fun signal ->
       Lui_ui.extension_property_signal context node ${JSON.stringify(p.name)}
         (Signal.map (fun value -> ${kind.wire} value) signal))
    ${n}_signal;`;
  });

  const handlers = events.map((e) => {
    const n = recordType(comp.identifier, e.name);
    return `  Option.iter
    (fun handler ->
       Lui_ui.on_event context node (fun raw ->
         match decode_${n} raw with
         | Some event -> handler event
         | None -> ()))
    on_${munge(e.name)};`;
  });

  const childrenMount = takesChildren
    ? '  Lui_elements.mount_children context node children;'
    : '';

  const params = [
    '?key:string',
    ...props.map((p) =>
      p.required === true
        ? `${munge(p.name)}:${scalarKinds[p.kind].ocaml}`
        : `?${munge(p.name)}:${scalarKinds[p.kind].ocaml}`),
    ...props.map((p) => `?${munge(p.name)}_signal:${scalarKinds[p.kind].ocaml} Signal.signal`),
    ...events.map((e) => `?on_${munge(e.name)}:(${recordType(comp.identifier, e.name)} -> unit)`),
  ];

  return {
    impl: `let ${name} ${args.join(' ')} ${childrenArg} : Lui_elements.t =
 fun context parent ->
  let node = Lui_ui.extension context ${JSON.stringify(comp.identifier)} in
  Option.iter (Lui_ui.key context node) key;
${setters.join('\n')}
${handlers.join('\n')}
  (match parent with
   | Some parent -> Lui_ui.append context parent node
   | None -> ());
${childrenMount}
  node`,
    decl: `val ${name} : ${params.join(' -> ')} -> ${childrenDecl} -> Lui_elements.t`,
  };
}

function render(spec) {
  validate(spec);
  const components = spec.components ?? [];
  const tweaks = (spec.tweaks ?? []).map((t) => ({ ...t, tweak: true }));
  const mounts = components.map((comp) => mountImpl(spec, comp));
  const allSchemas = [...components, ...tweaks];
  const registrations = [
    ...components.map((comp) =>
      `  Lui_extension.register_component registry ${munge(comp.identifier)}_schema;`),
    ...tweaks.map((t) =>
      `  Lui_extension.register_tweak registry ${munge(t.identifier)}_schema;`),
  ];

  const records = components
    .flatMap((comp) => (comp.events ?? []).map((e) => eventRecord(comp, e)))
    .join('\n\n');
  const decoders = components
    .flatMap((comp) => (comp.events ?? []).map((e) => eventDecoder(comp, e)))
    .join('\n\n');
  const schemas = allSchemas.map((entry) => schemaDecl(spec, entry)).join('\n\n');

  const ml = `(* Generated by tooling/generate_extension_api.mjs. Do not edit by hand. *)

open Lui_protocol

${records}

${decoders}

${schemas}

let registry () =
  let registry = Lui_extension.registry () in
${registrations.join('\n')}
  Lui_extension.freeze registry;
  registry

${mounts.map((m) => m.impl).join('\n\n')}
`;

  const mli = `(* Generated by tooling/generate_extension_api.mjs. Do not edit by hand. *)

${records}

${mounts.map((m) => m.decl).join('\n')}

val registry : unit -> Lui_extension.extension_registry
`;
  return { ml, mli };
}

const schemaPath = argumentValue('--schema');
const outPath = argumentValue('--out');
if (!schemaPath || !outPath) fail('usage: --schema <file.json> --out <Module.ml> [--mli <Module.mli>]');
const mliPath = argumentValue('--mli');

let spec;
try {
  spec = JSON.parse(readFileSync(resolve(schemaPath), 'utf8'));
} catch (error) {
  fail(`cannot read extension schema: ${error.message}`);
}

const { ml, mli } = render(spec);
writeFileSync(resolve(outPath), ml);
if (mliPath) writeFileSync(resolve(mliPath), mli);
process.stdout.write(`generated ${resolve(outPath)}${mliPath ? ` and ${resolve(mliPath)}` : ''}\n`);
