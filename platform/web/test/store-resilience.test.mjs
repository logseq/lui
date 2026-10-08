import assert from "node:assert/strict"
import test from "node:test"

// Exercise the compiled retained store and use its matching protocol
// constructors. Requires `opam exec -- dune build @web` before running.
const modulesUrl = new URL(
  "../../../_build/default/examples/components/web/lui-components-web/node_modules/",
  import.meta.url,
)
const [Store, Protocol, Schema] = await Promise.all([
  import(new URL("lui.web.dom/core/lui_web_store.js", modulesUrl)),
  import(new URL("lui/lui_protocol.js", modulesUrl)),
  import(new URL("lui/lui_wire_schema.js", modulesUrl)),
])

function schemaValue(values, nameOf, name) {
  for (let rest = values; rest; rest = rest.tl) {
    if (nameOf(rest.hd) === name) return rest.hd
  }
  throw new Error(`unknown schema value: ${name}`)
}

const list = (...items) => items.reduceRight((tl, hd) => ({ hd, tl }), 0)
const batch = (generation, ops) => ({ generation, ops: list(...ops) })
const createNode = Protocol.create_node_op
const setProp = Protocol.set_prop_op
const insertChild = Protocol.insert_child_op
const stringValue = (text) => ({ TAG: 0, _0: text })
const Button = schemaValue(Schema.all_node_kinds, Schema.node_kind_name, "button")
const TextValue = schemaValue(Schema.all_properties, Schema.property_name, "text")

const platform = () => ({})
const invalidArgument = (messagePart) => (error) =>
  typeof error?._1 === "string" && error._1.includes(messagePart)

test("rejected batch consumes its generation, next batch still applies", () => {
  const store = Store.create_store()

  // A button with no text or accessibility label fails batch validation.
  assert.throws(
    () => Store.apply_batch(store, platform, batch(1, [createNode(1, Button)])),
    invalidArgument("button requires text or an accessibility label"),
  )
  // Consumed on receipt: the generation must not lag behind the runtime.
  assert.equal(Store.generation(store), 1)

  // Previously this wedged on "expected patch generation 1, received 2".
  assert.equal(
    Store.apply_batch(
      store,
      platform,
      batch(2, [
        createNode(2, Button),
        setProp(2, TextValue, stringValue("ok")),
      ]),
    ),
    true,
  )
  assert.equal(Store.generation(store), 2)
  assert.notEqual(Store.node(store, 2), undefined)
})

test("mid-batch op failure rolls back earlier ops", () => {
  const store = Store.create_store()

  assert.throws(
    () =>
      Store.apply_batch(
        store,
        platform,
        batch(1, [
          createNode(1, Button),
          setProp(1, TextValue, stringValue("ok")),
          insertChild(99, 1, 0),
        ]),
      ),
    invalidArgument("unknown parent"),
  )
  // Full rollback, matching the Apple store: node 1 does not linger.
  assert.equal(Store.node(store, 1), undefined)
  assert.equal(Store.generation(store), 1)

  assert.equal(
    Store.apply_batch(
      store,
      platform,
      batch(2, [
        createNode(2, Button),
        setProp(2, TextValue, stringValue("ok")),
      ]),
    ),
    true,
  )
})

test("stale batch is dropped without replaying; gap batch applies best-effort", () => {
  const store = Store.create_store()

  assert.equal(
    Store.apply_batch(
      store,
      platform,
      batch(1, [
        createNode(1, Button),
        setProp(1, TextValue, stringValue("ok")),
      ]),
    ),
    true,
  )

  // A redelivered generation is dropped, not applied twice.
  assert.equal(
    Store.apply_batch(
      store,
      platform,
      batch(1, [createNode(9, Button)]),
    ),
    false,
  )
  assert.equal(Store.generation(store), 1)
  assert.equal(Store.node(store, 9), undefined)

  // A forward gap (generations consumed by earlier dropped batches) still
  // applies — ops that reference dropped nodes fail per-op instead.
  assert.equal(
    Store.apply_batch(
      store,
      platform,
      batch(5, [
        createNode(5, Button),
        setProp(5, TextValue, stringValue("ok")),
      ]),
    ),
    true,
  )
  assert.equal(Store.generation(store), 5)
})
