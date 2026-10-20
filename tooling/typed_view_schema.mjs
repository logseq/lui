// The supported signature grammar is deliberately closed: API changes that
// cannot be represented must fail generation rather than weaken admission.
function uncomment(source) {
  let result = '', depth = 0;
  for (let i = 0; i < source.length; i++) {
    if (source.slice(i, i + 2) === '(*') { depth++; i++; }
    else if (depth && source.slice(i, i + 2) === '*)') { depth--; i++; }
    else if (!depth || source[i] === '\n') result += source[i];
  }
  if (depth) throw new Error('unterminated OCaml signature comment');
  return result;
}

function split(source, delimiter) {
  const parts = [];
  let depth = 0, start = 0;
  for (let i = 0; i < source.length; i++) {
    if ('(['.includes(source[i])) depth++;
    if (')]'.includes(source[i])) depth--;
    if (depth < 0) throw new Error('unbalanced typed view signature');
    if (!depth && source.startsWith(delimiter, i)) {
      parts.push(source.slice(start, i).trim().replace(/\s+/g, ' '));
      i += delimiter.length - 1;
      start = i + 1;
    }
  }
  if (depth) throw new Error('unbalanced typed view signature');
  parts.push(source.slice(start).trim().replace(/\s+/g, ' '));
  return parts;
}

const quote = JSON.stringify;
const list = (entries) => `[${entries.join('; ')}]`;
const wireName = (name) => name.replace(/_/g, '-');
const aliases = {
  as_: ['as'], label: ['accessibility-label'], disabled: ['enabled'],
  shortcut_hint: ['tooltip-keys'], kind: ['input-type'], fit: ['image-fit'],
  first_width: ['first-pane-width'], point_size: ['width', 'height'],
  resizable_width: ['width'], accordion_height: ['height'],
  toolbar_gap: ['gap'], toolbar_class: ['style-class'], toast_class: ['style-class'],
  list_marker: ['list-style'], at: ['x', 'y'],
  level: ['heading-level'],
};

export const typedViewSignature = `
type view_value =
  | ViewString | ViewBool | ViewInt | ViewFloat
  | ViewEnum of string list
  | ViewIcon of string list
  | ViewToken | ViewAttributes | ViewFloatTuple of int

type view_children = ViewList of string | ViewArguments of string list

type 'property view_contract = {
  view_result : string;
  view_children : view_children;
  view_properties : ('property * view_value * bool) list;
  view_events : string list;
  view_slots : (string * string * bool) list;
}
`;

export function typedViewSchema(schema, signature, implementation, {extension = false} = {}) {
  const source = uncomment(signature).replace(/Lui_elements\.t\b/g, 't');
  const declarations = [...source.matchAll(/^val (\w+)\s*:\s*([\s\S]*?)(?=^(?:val|type|module|exception|include|class|external)\b|$(?![\s\S]))/gm)];
  const functions = new Map(declarations.map(([, name, body]) => [name, split(body, '->')]));
  const types = new Map([...source.matchAll(/^type (\w+)\s*=\s*(\[[\s\S]*?\])/gm)]
    .map(([, name, body]) => [name, split(body.slice(1, -1), '|')]));
  const converters = new Map([...uncomment(implementation).matchAll(/\blet \w+\s*:\s*(\w+)\s*->\s*string\s*=\s*function\b([\s\S]*?)(?=^let\b|$(?![\s\S]))/gm)]
    .map(([, type, body]) => [type, new Map([...body.matchAll(/\|\s*`(\w+)\s*->\s*"([^"\\]*)"/g)].map(([, tag, value]) => [tag, value]))]));
  const domains = new Map();
  function enumValues(type, stack = []) {
    if (stack.includes(type)) throw new Error(`recursive view type ${type}`);
    const members = types.get(type);
    if (!members) throw new Error(`unknown typed view domain ${type}`);
    return members.flatMap((member) => {
      if (/^\w+$/.test(member)) return enumValues(member, [...stack, type]);
      if (type === 'icon' && member === '`app of string') return [];
      const match = /^`(\w+)$/.exec(member);
      const value = match && converters.get(type)?.get(match[1]);
      if (value === undefined) throw new Error(`no canonical wire encoding for ${type}: ${member}`);
      return [value];
    });
  }
  function domain(type) {
    const primitives = {string: 'ViewString', bool: 'ViewBool', int: 'ViewInt', float: 'ViewFloat',
      'file_picker_token': 'ViewToken', '(string * string) list': 'ViewAttributes',
      '(float * float * float * float)': '(ViewFloatTuple 4)'};
    if (primitives[type]) return primitives[type];
    if (type.startsWith('[') && type.endsWith(']')) {
      const values = split(type.slice(1, -1), '|').map((member) => {
        const match = /^`(\w+)$/.exec(member);
        const encodings = match && [...implementation.matchAll(/\|\s*`(\w+)\s*->\s*"([^"\\]*)"/g)]
          .filter(([, tag]) => tag === match[1]).map(([, , value]) => value);
        if (!encodings?.length || new Set(encodings).size !== 1) throw new Error(`unknown inline variant encoding: ${member}`);
        return encodings[0];
      });
      return `(ViewEnum ${list(values.map(quote))})`;
    }
    if (!domains.has(type)) {
      const values = enumValues(type);
      if (!values.length) throw new Error(`empty typed view domain ${type}`);
      domains.set(type, `${type === 'icon' ? 'ViewIcon' : 'ViewEnum'} ${list(values.map(quote))}`);
    }
    return `view_${type}`;
  }
  const properties = new Map(schema.properties.map(({wire, lg}) => [wire, lg]));
  const results = new Set(['t', ...[...source.matchAll(/^type (\w+_el)\s*$/gm)].map(([, name]) => name)]);
  const contracts = [];
  for (const {wire, lg} of schema.nodeKinds) {
    if (!extension && ['root', 'list-section-header', 'list-section-footer'].includes(wire)) {
      contracts.push(`  | ${lg} -> None`);
      continue;
    }
    const name = wire === 'switch' ? 'switch_' : wire.replace(/-/g, '_');
    const args = functions.get(name);
    if (!args) throw new Error(`no typed constructor for ${wire}`);
    const result = args.at(-1);
    if (!results.has(result)) throw new Error(`unknown result type ${wire}: ${result}`);
    const props = new Map(), events = new Set(), slots = [], children = [];
    for (const argument of args.slice(0, -1)) {
      const match = /^(\??)(\w+):(.*)$/.exec(argument);
      if (!match) { children.push(argument); continue; }
      const [, optional, label, type] = match;
      if (extension && label === 'key') {
        if (type !== 'string' || !optional) throw new Error(`unknown extension key type: ${wire}`);
        continue;
      }
      // These constructor conveniences encode into the independently typed
      // data_attrs argument, not dedicated wire properties.
      if (wire === 'virtual-list' && ['overscan', 'item_extent'].includes(label)) {
        if (type !== (label === 'overscan' ? 'int' : 'float')) throw new Error(`unknown virtualization argument ${label}`);
        continue;
      }
      if (label.endsWith('_signal')) {
        const base = label.slice(0, -7);
        const normalized = (type) => type.replace(/^\(([^()]*)\)$/, '$1');
        const valueType = normalized(type.replace(/ Signal.signal$/, ''));
        if (!args.some((arg) => {
          const value = new RegExp(`^\\??${base}:(.*)$`).exec(arg);
          return value && normalized(value[1]) === valueType;
        })) {
          throw new Error(`signal without matching typed value: ${wire}.${label}`);
        }
        continue;
      }
      if (label.startsWith('on_')) {
        if (!(extension ? /^\(\w+ -> unit\)$/.test(type) : type === '(Lui_protocol.event -> unit)')) throw new Error(`unknown event type: ${wire}.${label}`);
        const event = label.slice(3);
        for (const value of ((!extension && {value_changed: ['value'], navigate: ['navigate-previous', 'navigate-next', 'navigation-key'],
          press: ['press', 'press-modifiers']}[event]) || [wireName(event)])) events.add(value);
        continue;
      }
      const structural = /^(t|\w+_el)( list)?$/.exec(type);
      if (structural) {
        if (!optional) throw new Error(`required named element slot: ${wire}.${label}`);
        slots.push(`(${quote(wireName(label))}, ${quote(structural[1])}, ${!!structural[2]})`);
        continue;
      }
      const names = extension ? [wireName(label)] : label === 'value' && type === 'string' ? ['text'] : aliases[label] ?? [wireName(label)];
      for (const propName of names) {
        const property = extension ? quote(propName) : properties.get(propName);
        if (!property) throw new Error(`no wire property for typed argument: ${wire}.${label}`);
        const value = domain(label === 'at' ? 'float' : type);
        const previous = props.get(property);
        if (previous && previous.value !== value) throw new Error(`conflicting typed property ${wire}.${propName}`);
        props.set(property, {value, required: !optional || previous?.required === true});
      }
    }
    if (!extension && result === 't') {
      const alignment = functions.get('align');
      if (!alignment || alignment.length !== 3 || alignment[1] !== 't' || alignment[2] !== 't') {
        throw new Error('unknown typed alignment modifier');
      }
      props.set(properties.get('alignment'), {value: domain(alignment[0]), required: false});
    }
    let childType;
    if (children.length === 1 && /^(t|nothing|\w+_el) list$/.test(children[0])) {
      childType = `ViewList ${quote(children[0].slice(0, -5))}`;
    } else if (children.length && children.every((child) => results.has(child))) {
      childType = `ViewArguments ${list(children.map(quote))}`;
    } else throw new Error(`unknown typed children: ${wire}: ${children.join(' -> ')}`);
    contracts.push(`  | ${lg} -> Some {
      view_result = ${quote(result)};
      view_children = ${childType};
      view_properties = ${list([...props].map(([property, {value, required}]) => `(${property}, ${value}, ${required})`))};
      view_events = ${list([...events].map(quote))};
      view_slots = ${list(slots)};
    }`);
  }
  return `${extension ? '' : typedViewSignature}
${[...domains].map(([name, value]) => `let view_${name} = ${value}`).join('\n')}

let ${extension ? 'extension_view_contract' : 'view_contract'} = function
${contracts.join('\n')}
${extension ? '  | _ -> None\n' : ''}
`;
}
