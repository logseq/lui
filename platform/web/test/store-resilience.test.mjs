import assert from "node:assert/strict"
import { access } from "node:fs/promises"
import test from "node:test"

// Exercises the compiled web retained store directly (the same store the
// Electron host runs). Requires `dune build` — the module is emitted by the
// examples/components/web melange.emit target.
const storeUrl = new URL(
  "../../../_build/default/examples/components/web/lui-components-web/node_modules/lui.web.dom/core/lui_web_store.js",
  import.meta.url,
)

const Store = await import(storeUrl).catch(() => null)

// patch_op / wire_value / node_kind tags follow declaration order in
// src/lui_protocol.ml (checked against the emitted switch in
// lui_web_store.js).
const list = (...items) => items.reduceRight((tl, hd) => ({ hd, tl }), 0)
const batch = (generation, ops) => ({ generation, ops: list(...ops) })
const createNode = (id, kind) => ({ TAG: 0, _0: id, _1: kind })
const setProp = (id, prop, value) => ({ TAG: 3, _0: id, _1: prop, _2: value })
const insertChild = (parent, child, index) => ({
  TAG: 7,
  _0: parent,
  _1: child,
  _2: index,
})
const stringValue = (text) => ({ TAG: 0, _0: text })
const Button = 17
const TextValue = 0

const platform = () => ({})
const invalidArgument = (messagePart) => (error) =>
  typeof error?._1 === "string" && error._1.includes(messagePart)

test("rejected batch consumes its generation, next batch still applies", async (t) => {
  if (!Store) return t.skip("run `dune build` to emit the web store")
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

test("mid-batch op failure rolls back earlier ops", async (t) => {
  if (!Store) return t.skip("run `dune build` to emit the web store")
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

test("stale batch is dropped without replaying; gap batch applies best-effort", async (t) => {
  if (!Store) return t.skip("run `dune build` to emit the web store")
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
