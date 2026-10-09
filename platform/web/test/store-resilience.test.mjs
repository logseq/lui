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


const Column = schemaValue(Schema.all_node_kinds, Schema.node_kind_name, "column")
const Text = schemaValue(Schema.all_node_kinds, Schema.node_kind_name, "text")
const VirtualList = schemaValue(Schema.all_node_kinds, Schema.node_kind_name, "virtual-list")
const { performance } = await import("node:perf_hooks")
const DomExtension = await import(new URL("lui.web.dom/extensions/lui_web_dom_ext.js", modulesUrl))

test("DOM extension events preserve false target and modifier fields", () => {
  const result = JSON.parse(DomExtension.json_of_event("change", {
    target: { checked: false, value: "", id: "input" },
    shiftKey: false, ctrlKey: false, isComposing: false,
  }))
  assert.equal(result.checked, false)
  assert.equal(result.shiftKey, false)
  assert.equal(result.ctrlKey, false)
  assert.equal(result.isComposing, false)
  assert.equal(result.value, "")
})

test("local Web updates scale with the affected tree rather than unrelated nodes", () => {
  function measure(count) {
    const store = Store.create_store()
    Store.apply_batch(store, platform, batch(1,
      Array.from({ length: count }, (_, i) => createNode(i + 1, Text))))
    let generation = 1
    const update = () => Store.apply_batch(store, platform, batch(++generation,
      [setProp(1, TextValue, stringValue(String(generation)))]))
    for (let i = 0; i < 40; i++) update()
    const start = performance.now()
    for (let i = 0; i < 100; i++) update()
    return performance.now() - start
  }
  const small = measure(1000), large = measure(20000)
  assert.ok(large < small * 6 + 5, `local update grows with unrelated nodes: ${small}ms -> ${large}ms`)
})

test("flat Web child mounting scales subquadratically", () => {
  function measure(count) {
    const store = Store.create_store()
    const operations = [createNode(1, VirtualList)]
    for (let i = 0; i < count; i++) operations.push(createNode(i + 2, Text), insertChild(1, i + 2, i))
    const start = performance.now()
    Store.apply_batch(store, platform, batch(1, operations))
    let actual = 0
    for (let rest = Store.children(store, 1); rest; rest = rest.tl) actual++
    assert.equal(actual, count)
    return performance.now() - start
  }
  measure(200)
  const small = measure(1000), large = measure(8000)
  assert.ok(large < small * 14 + 20, `flat mounting is quadratic: ${small}ms -> ${large}ms`)
})

test("a text edit does not revalidate a wide ordinary ancestor", () => {
  const measure = count => {
    const store = Store.create_store()
    const operations = [createNode(1, Column)]
    for (let i = 0; i < count; i++) operations.push(createNode(i + 2, Text), insertChild(1, i + 2, i))
    Store.apply_batch(store, platform, batch(1, operations))
    let generation = 1
    const update = () => Store.apply_batch(store, platform, batch(++generation,
      [setProp(2, TextValue, stringValue(String(generation)))]))
    for (let i = 0; i < 30; i++) update()
    const start = performance.now()
    for (let i = 0; i < 150; i++) update()
    return performance.now() - start
  }
  const small = measure(100), large = measure(10000)
  assert.ok(large < small * 6 + 5, `ordinary ancestor rescans siblings: ${small}ms -> ${large}ms`)
})

test("removing a required child through a reparent still validates its former parent", () => {
  const store = Store.create_store()
  const Root = schemaValue(Schema.all_node_kinds, Schema.node_kind_name, "root")
  Store.apply_batch(store, platform, batch(1, [createNode(1, Root), createNode(2, Column),
    createNode(3, Column), insertChild(1, 2, 0)]))
  assert.throws(() => Store.apply_batch(store, platform, batch(2, [Protocol.remove_child_op(1, 2), insertChild(3, 2, 0)])),
    invalidArgument("runtime root requires exactly one child"))
  assert.equal(Store.node(store, 2).retained_parent, 1)
})

test("wide Web child reordering scales subquadratically", () => {
  const measure = count => {
    const store = Store.create_store()
    const ops = [createNode(1, Column)]
    for (let index = 0; index < count; index++)
      ops.push(createNode(index + 2, Text), insertChild(1, index + 2, index))
    Store.apply_batch(store, platform, batch(1, ops))
    const moves = Array.from({ length: count - 1 }, (_, index) =>
      Protocol.move_child_op(1, count + 1 - index, index))
    const start = performance.now()
    Store.apply_batch(store, platform, batch(2, moves))
    const elapsed = performance.now() - start
    const children = []
    for (let rest = Store.children(store, 1); rest; rest = rest.tl) children.push(rest.hd)
    assert.deepEqual(children, Array.from({ length: count }, (_, index) => count + 1 - index))
    return elapsed
  }
  measure(200)
  const small = measure(1000), large = measure(8000)
  assert.ok(large < small * 14 + 20, `wide moves are quadratic: ${small}ms -> ${large}ms`)
})
