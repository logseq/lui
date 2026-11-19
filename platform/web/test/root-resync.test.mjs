import assert from 'node:assert/strict'
import {registerHooks} from 'node:module'
import test from 'node:test'

const build = process.env.LUI_TEST_BUILD_DIR ?? '_build'
const modules = new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`, import.meta.url)
const resolution = registerHooks({resolve(specifier, context, nextResolve) {
  return nextResolve(specifier, specifier === '@tanstack/virtual-core'
    ? {...context, parentURL: import.meta.url} : context)
}})
const [Store, Protocol, Schema, Apply, Tables, Lazy] = await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js', modules)),
  import(new URL('lui/lui_protocol.js', modules)),
  import(new URL('lui/lui_wire_schema.js', modules)),
  import(new URL('lui.web.dom/shell/lui_web_apply.js', modules)),
  import(new URL('melange/hashtbl.js', modules)),
  import(new URL('melange/camlinternalLazy.js', modules)),
])
resolution.deregister()
const list = values => values.reduceRight((tl, hd) => ({hd, tl}), 0)
let column
for (let rest = Schema.all_node_kinds; rest; rest = rest.tl) {
  if (Schema.node_kind_name(rest.hd) === 'column') column = rest.hd
}
const element = () => ({
  parentElement: null, setAttribute() {}, removeAttribute() {},
  addEventListener() {}, removeEventListener() {},
})

test('authoritative recreation reattaches a mounted root but not an unmounted or reparented node', () => {
  for (const state of ['mounted', 'unmounted', 'reparented']) {
    const store = Store.create_store()
    const renderer = {web_store: store}
    for (const name of ['web_mounted_roots', 'web_focus_within_observers',
      'web_pointer_cleanups', 'web_context_hosts', 'web_cleanups']) {
      renderer[name] = Tables.create(undefined, 4)
    }
    const host = {children: [], appendChild(node) {
      this.children.push(node); node.parentElement = this
    }}
    Store.apply_batch(store, element, {generation: 1,
      ops: list([Protocol.create_node_op(1, column)])})
    const previous = Lazy.force(Store.node(store, 1).platform_node)
    if (state !== 'unmounted') {
      Tables.replace(renderer.web_mounted_roots, 1, host)
      host.appendChild(previous)
    }
    const create = Protocol.create_node_op(1, column)
    Store.apply_batch(store, element, {generation: 2, ops: list([
      Protocol.detach_subtree_op(1), create,
      ...(state === 'reparented'
        ? [Protocol.create_node_op(2, column), Protocol.insert_child_op(2, 1, 0)] : []),
    ])})
    host.children = []
    previous.parentElement = null
    Apply.apply_dom_op(renderer, () => undefined, () => list([]),
      Apply.new_effects(), () => true, create)
    const recreated = Lazy.force(Store.node(store, 1).platform_node)
    assert.notEqual(recreated, previous)
    assert.deepEqual(host.children, state === 'mounted' ? [recreated] : [])
  }
})
