import assert from 'node:assert/strict'
import test from 'node:test'

const build = process.env.LUI_TEST_BUILD_DIR ?? '_build'
const modules = new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`, import.meta.url)
const [Store, Protocol, Schema, Tables, Menu, Layers, Nodes] = await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js', modules)),
  import(new URL('lui/lui_protocol.js', modules)),
  import(new URL('lui/lui_wire_schema.js', modules)),
  import(new URL('melange/hashtbl.js', modules)),
  import(new URL('lui.web.dom/popup/lui_web_menu.js', modules)),
  import(new URL('lui.web.dom/core/lui_web_layers.js', modules)),
  import(new URL('lui.web.dom/nodes/lui_web_nodes.js', modules)),
])
const list = values => values.reduceRight((tl, hd) => ({hd, tl}), 0)
const named = (values, nameOf, name) => {
  for (let rest = values; rest; rest = rest.tl) if (nameOf(rest.hd) === name) return rest.hd
  throw new Error(`Unknown schema value: ${name}`)
}
const kind = name => named(Schema.all_node_kinds, Schema.node_kind_name, name)
const prop = name => named(Schema.all_properties, Schema.property_name, name)

function fixture(role = 'menu', empty = false) {
  const document = {addEventListener() {}, removeEventListener() {}}, activated = [], dismissed = []
  const element = (id, children = []) => {
    const attrs = new Map()
    return {children: {item: index => children[index] ?? null}, style: {setProperty() {}},
      textContent: id === 4 ? 'Rename' : 'Delete',
      getAttribute: name => attrs.get(name) ?? null,
      setAttribute: (name, value) => attrs.set(name, value), removeAttribute: name => attrs.delete(name),
      addEventListener() {}, removeEventListener() {},
      contains(target) { return target === this || children.some(child => child.contains(target)) },
      isSameNode(target) { return target === this },
      focus() { document.activeElement = this }, click() { activated.push(id) }}
  }
  const elements = new Map(Array.from({length: 9}, (_, index) => [index + 1, element(index + 1)]))
  document.activeElement = element(-1)
  elements.set(2, element(2, [element(0)]))
  const store = Store.create_store(), layers = Layers.create()
  const renderer = {web_store: store, web_document: document, web_layers: layers,
    web_cleanups: Tables.create(undefined, 4), web_event_handler: {contents: event => dismissed.push(event._0)}}
  let generation = 0, platform
  const apply = ops => assert.equal(Store.apply_batch(store, () => platform,
    {generation: ++generation, ops: list(ops)}), true)
  for (const [id, name] of [[1, 'column'], [2, 'popover'], [3, 'column'], [4, 'menu-item'],
    [5, 'row'], [6, 'menu-item'], [7, 'menu-item'], [8, 'popover'], [9, 'menu-item']]) {
    platform = elements.get(id)
    apply([Protocol.create_node_op(id, kind(name)),
      ...(name === 'menu-item'
        ? [Protocol.set_prop_op(id, prop('text'), {TAG: 0, _0: id === 4 ? 'Rename' : 'Delete'})] : [])])
    Nodes.dom_node(renderer, id)
  }
  const parents = empty ? [[1, 2, 0]] : [[1, 2, 0], [2, 3, 0], [3, 4, 0], [3, 5, 1],
    [5, 6, 0], [5, 7, 1], [3, 8, 2], [8, 9, 0]]
  apply([...parents.map(([parent, child, index]) => Protocol.insert_child_op(parent, child, index)),
    Protocol.set_prop_op(2, prop('role'), {TAG: 0, _0: role}),
    Protocol.set_prop_op(6, prop('enabled'), {TAG: 1, _0: false})])
  Layers.install(layers, document, () => false, target => target)
  Menu.attach_popover_events(renderer, 2, elements.get(2))
  Layers.open_layer(layers, document, 2)
  const key = (key, options = {}) => {
    const event = {key, target: document.activeElement, defaultPrevented: false, isComposing: false,
      preventDefault() { this.defaultPrevented = true }, stopImmediatePropagation() {}, ...options}
    Layers.dispatch_key(layers, event)
    return event.defaultPrevented
  }
  return {key, activated, dismissed, focused: () => document.activeElement,
    element: id => elements.get(id), dispose: () => Tables.find_opt(renderer.web_cleanups, 2)()}
}

test('menu popovers navigate wrapped rows and activate with Enter without entering nested popups', () => {
  const f = fixture()
  assert.equal(f.key('ArrowDown'), true)
  assert.equal(f.focused(), f.element(4))
  f.key('Enter')
  assert.deepEqual(f.activated, [4])
  f.key('ArrowDown')
  assert.equal(f.focused(), f.element(7), 'disabled rows are skipped')
  f.key('ArrowDown')
  assert.equal(f.focused(), f.element(4), 'nested popup rows are excluded')
  f.key('End')
  assert.equal(f.focused(), f.element(7))
  f.key('Home')
  assert.equal(f.focused(), f.element(4))
  f.key('d')
  assert.equal(f.focused(), f.element(7))
  f.key('Escape')
  assert.deepEqual(f.dismissed, [2])
  f.dispose()
})

test('empty menu popovers leave navigation and activation unhandled', () => {
  const f = fixture('menu', true)
  assert.equal(f.key('ArrowDown'), false)
  f.key('Enter')
  assert.deepEqual(f.activated, [])
  f.dispose()
})

test('dialog popovers and composing input do not route menu keys', () => {
  const dialog = fixture('dialog')
  assert.equal(dialog.key('ArrowDown'), false)
  dialog.key('Enter')
  assert.deepEqual(dialog.activated, [])
  dialog.dispose()
  const menu = fixture()
  assert.equal(menu.key('ArrowDown', {isComposing: true}), false)
  menu.key('Enter', {isComposing: true})
  assert.deepEqual(menu.activated, [])
  menu.dispose()
})
