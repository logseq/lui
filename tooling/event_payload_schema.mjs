export function callbackContract(schema, constructor, parameter) {
  constructor = schema.slotConstructors?.[constructor]?.constructor ?? constructor;
  const name = schema.eventCallbackOverrides?.[constructor]?.[parameter] ?? parameter;
  return schema.eventCallbacks?.[name];
}

export function validateCallbackEvents(schema) {
  const events = new Set(schema.events.map(event => event.lg));
  for (const { events: accepted } of Object.values(schema.eventCallbacks)) {
    for (const event of accepted) {
      if (!events.has(event)) throw new Error(`unknown callback event ${event}`);
    }
  }
}

export function renderEventPayloads(schema) {
  validateCallbackEvents(schema);
  const events = new Map(schema.events.map(event =>
    [event.lg, event.fields.slice(1).map(field => field.replace(/^:/, ''))]));
  const records = schema.eventPayloadRecords;
  const variants = schema.eventPayloadVariants;
  const fields = (name) => {
    const record = records[name];
    const types = events.get(record.event);
    if (!types || types.length !== record.fields.length) throw new Error(`invalid event record ${name}`);
    return record.fields.map((field, index) => [field, types[index]]);
  };
  const declarations = [
    'type pointer_detail = Lui_protocol.pointer_detail',
    ...Object.keys(records).map(name =>
      `type ${name} = { ${fields(name).map(([field, type]) => `${field} : ${type}`).join('; ')} }`),
    ...Object.entries(variants).map(([name, cases]) =>
      `type ${name} = ${Object.values(cases).map(({constructor, record}) =>
        constructor + (record ? ` of ${record}` : '')).join(' | ')}`),
  ].join('\n');
  const implementations = [], signatures = [];
  for (const [name, {payload, events: accepted}] of Object.entries(schema.eventCallbacks)) {
    const cases = accepted.map(event => {
      const types = events.get(event);
      let names, value;
      if (payload === 'unit') { names = types.map(() => '_'); value = '()'; }
      else if (records[payload]) {
        if (records[payload].event !== event) throw new Error(`incompatible callback record ${name}`);
        names = fields(payload).map(([field]) => field);
        value = `{ ${names.join('; ')} }`;
      } else if (variants[payload]) {
        const entry = variants[payload][event];
        if (!entry) throw new Error(`unknown callback variant ${name}.${event}`);
        names = entry.record ? fields(entry.record).map(([field]) => field) : [];
        if (names.length !== types.length) throw new Error(`incompatible callback variant ${name}.${event}`);
        value = entry.constructor + (entry.record ? ` { ${names.join('; ')} }` : '');
      } else {
        if (types.length !== 1 || types[0] !== payload) throw new Error(`incompatible callback scalar ${name}`);
        names = ['value']; value = 'value';
      }
      const guards = payload === 'unit' ? [] : types.flatMap((type, index) => {
        const field = names[index];
        if (type === 'float') return [`Float.is_finite ${field}`];
        if (type === 'pointer_detail') return [
          `Float.is_finite ${field}.Lui_protocol.x`, `Float.is_finite ${field}.Lui_protocol.y`];
        return [];
      });
      const pattern = types.length ? `(_, ${names.join(', ')})` : '_';
      return `  | Lui_protocol.${event} ${pattern}${guards.length ? ` when ${guards.join(' && ')}` : ''} -> Some (${value})`;
    });
    signatures.push(`val ${name} : Lui_protocol.event -> ${payload} option`);
    implementations.push(`let ${name} : Lui_protocol.event -> ${payload} option = function\n${cases.join('\n')}\n  | _ -> None`);
  }
  const header = '(* Generated from schema/components.json. Do not edit by hand. *)\n\n';
  return {
    implementation: header + declarations + '\n\n' + implementations.join('\n\n') + '\n',
    signature: header + declarations + '\n\n' + signatures.join('\n') + '\n',
  };
}
