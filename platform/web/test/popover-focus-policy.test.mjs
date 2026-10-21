import assert from 'node:assert/strict'
import test from 'node:test'

const build = process.env.LUI_TEST_BUILD_DIR ?? '_build'
const modules = new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`, import.meta.url)
const [Store, Protocol, Schema, Tables, Menu, Layers, Props] = await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js', modules)),
  import(new URL('lui/lui_protocol.js', modules)),
  import(new URL('lui/lui_wire_schema.js', modules)),
  import(new URL('melange/hashtbl.js', modules)),
  import(new URL('lui.web.dom/popup/lui_web_menu.js', modules)),
  import(new URL('lui.web.dom/core/lui_web_layers.js', modules)),
  import(new URL('lui.web.dom/render/lui_web_props.js', modules)),
])
const list = values => values.reduceRight((tl, hd) => ({hd, tl}), 0)
const named = (values, nameOf, name) => {
  for (let rest = values; rest; rest = rest.tl) if (nameOf(rest.hd) === name) return rest.hd
  throw new Error(`Unknown schema value: ${name}`)
}
const kind = name => named(Schema.all_node_kinds, Schema.node_kind_name, name)
const prop = name => named(Schema.all_properties, Schema.property_name, name)
const wire = value => ({TAG: 0, _0: value})
const element = (children = []) => {
  const attributes = new Map(), styles = new Map()
  return {
    style: {setProperty: (key, value) => styles.set(key, value)},
    children: {item: index => children[index] ?? null, length: children.length},
    setAttribute: (key, value) => attributes.set(key, value),
    getAttribute: key => attributes.get(key) ?? null,
    removeAttribute: key => attributes.delete(key),
    contains(target) { return target === this || children.some(child => child.contains(target)) },
  }
}
const fixture = (role, placement) => {
  const field = element(), surface = element([field]), positioner = element([surface]), outside = element()
  const document = {addEventListener() {}, removeEventListener() {}}
  const store = Store.create_store(), layers = Layers.create(), dismissed = []
  const renderer = {web_store: store, web_document: document, web_layers: layers,
    web_cleanups: Tables.create(undefined, 4), web_event_handler: {contents: event => dismissed.push(event._0)}}
  let generation = 0
  const apply = ops => assert.equal(Store.apply_batch(store,
    name => name === kind('popover') ? positioner : element(),
    {generation: ++generation, ops: list(ops)}), true)
  apply([Protocol.create_node_op(1, kind('column')), Protocol.create_node_op(2, kind('popover')),
    Protocol.insert_child_op(1, 2, 0),
    ...(role ? [Protocol.set_prop_op(2, prop('role'), wire(role))] : []),
    ...(placement === 'anchor' ? [Protocol.set_prop_op(2, prop('anchor'), wire('below'))]
      : ['x', 'y'].map(name => Protocol.set_prop_op(2, prop(name), {TAG: 3, _0: 10})))])
  const descendant = (_ancestor, _child) => false, targetElement = target => target
  Layers.install(layers, document, descendant, targetElement)
  Menu.attach_popover_events(renderer, 2, positioner)
  Layers.open_layer(layers, document, 2)
  return {dismissed,
    focus: target => Layers.dispatch_focus(layers, descendant, targetElement, {target}),
    pointer: target => Layers.dispatch_pointer(layers, descendant, targetElement, {target}),
    escape: () => Layers.dispatch_key(layers, {key: 'Escape', defaultPrevented: false,
      isComposing: false, stopImmediatePropagation() {}, preventDefault() {}}),
    role: value => {
      apply([value ? Protocol.set_prop_op(2, prop('role'), wire(value)) : Protocol.remove_prop_op(2, prop('role'))])
      if (value) Props.apply_property(renderer, () => {}, 2, kind('popover'), positioner, prop('role'), wire(value))
      else Props.remove_property(renderer, () => {}, 2, kind('popover'), positioner, prop('role'))
    }, field, outside}
}

for (const placement of ['anchor', 'point']) {
  test(`${placement} form popover survives keyboard focus outside but dismisses on outside pointer and Escape`, () => {
    const f = fixture('dialog', placement)
    f.focus(f.field)
    f.focus(f.outside)
    assert.deepEqual(f.dismissed, [], 'Tab out must preserve the nonmodal form')
    f.pointer(f.field)
    assert.deepEqual(f.dismissed, [])
    f.pointer(f.outside)
    assert.deepEqual(f.dismissed, [2])
    f.escape()
    assert.deepEqual(f.dismissed, [2, 2])
  })

  for (const role of ['menu', undefined]) test(`${placement} ${role ?? 'default'} popover still dismisses on focus outside`, () => {
    const f = fixture(role, placement)
    f.focus(f.field)
    assert.deepEqual(f.dismissed, [])
    f.focus(f.outside)
    assert.deepEqual(f.dismissed, [2])
  })

  test(`${placement} retained popover follows role changes and removal`, () => {
    const f = fixture('menu', placement)
    f.role('dialog')
    f.focus(f.outside)
    assert.deepEqual(f.dismissed, [])
    f.role('menu')
    f.focus(f.outside)
    assert.deepEqual(f.dismissed, [2])
    f.role('dialog')
    f.role(undefined)
    f.focus(f.outside)
    assert.deepEqual(f.dismissed, [2, 2])
  })
}

const focusHandoffFixture = () => {
  const registry = Layers.create(), document = {defaultView: null,
    addEventListener() {}, removeEventListener() {}}
  const node = (tag, parent = null) => {
    const children = [], attributes = new Map()
    const result = {tagName: tag, ownerDocument: document, parentElement: parent,
      style: {setProperty() {}},
      hasAttribute: name => attributes.has(name),
      getAttribute: name => attributes.get(name) ?? null,
      setAttribute: (name, value) => attributes.set(name, value),
      removeAttribute: name => attributes.delete(name),
      matches: () => false, isSameNode(other) { return this === other },
      contains(other) { return this === other || children.some(child => child.contains(other)) },
      focus() { document.activeElement = this }}
    if (parent) parent.children.push(result)
    result.children = children
    return result
  }
  const root = node('HTML'), body = node('BODY', root), trigger = node('BUTTON', body)
  const surface = node('DIV', body), invoked = node('BUTTON', surface), outside = node('INPUT', body)
  Object.assign(document, {documentElement: root, body, activeElement: invoked})
  Layers.install(registry, document, () => false, target => target)
  const renderer = {web_layers: registry, web_document: document,
    web_modal_return_focus: {contents: invoked}}
  const add = (id, content, target) => Layers.register(registry, document, id,
    undefined, target, content, list([content]), 1, () => {}, () => {}, () => {}, true, true)
  add(1, surface, trigger)
  const close = (id, content) => {
    Layers.close_layer(registry, document, id)
    Menu.restore_dropdown_focus(renderer, id, content)
  }
  return {registry, document, renderer, trigger, surface, invoked, outside, node, add, close}
}
const nextTask = () => new Promise(resolve => setTimeout(resolve, 0))

test('a closing action popover hands its surviving trigger to the replacement surface', async () => {
  const f = focusHandoffFixture()
  f.close(1, f.surface)
  assert.equal(f.renderer.web_modal_return_focus.contents, f.trigger,
    'the replacement must not capture an action in the retiring surface')
  const replacement = f.node('DIV', f.document.body), field = f.node('INPUT', replacement)
  f.add(2, replacement, f.renderer.web_modal_return_focus.contents)
  f.renderer.web_modal_return_focus.contents = undefined
  f.document.activeElement = field
  await nextTask()
  assert.equal(f.document.activeElement, field, 'the old close must preserve replacement focus')
  Layers.remove(f.registry, f.document, 1)
  f.close(2, replacement)
  await nextTask()
  assert.equal(f.document.activeElement, f.trigger, 'Escape can return to the surviving trigger')
})

test('popover handoff preserves an unrelated invoker and deliberate outside focus', async () => {
  const f = focusHandoffFixture()
  f.renderer.web_modal_return_focus.contents = f.outside
  f.document.activeElement = f.outside
  f.close(1, f.surface)
  assert.equal(f.renderer.web_modal_return_focus.contents, f.outside)
  await nextTask()
  assert.equal(f.document.activeElement, f.outside)
})

test('closing without a pending invocation restores focus without inventing a handoff', async () => {
  const f = focusHandoffFixture()
  f.renderer.web_modal_return_focus.contents = undefined
  f.close(1, f.surface)
  assert.equal(f.renderer.web_modal_return_focus.contents, undefined)
  await nextTask()
  assert.equal(f.document.activeElement, f.trigger)
})
