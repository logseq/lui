import * as Protocol from "lui/lui_protocol.js"
import * as Schema from "lui/lui_wire_schema.js"

function namedValues(values, nameOf) {
  const entries = []
  for (let rest = values; rest; rest = rest.tl) {
    entries.push([nameOf(rest.hd), rest.hd])
  }
  return new Map(entries)
}

export { Protocol }
export const properties = namedValues(Schema.all_properties, Schema.property_name)
export const kinds = namedValues(Schema.all_node_kinds, Schema.node_kind_name)
