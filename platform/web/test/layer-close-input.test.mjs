import assert from 'node:assert/strict'
import test from 'node:test'

const build = process.env.LUI_TEST_BUILD_DIR ?? '_build'
const modules = new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`, import.meta.url)
const [Layers, Overlay] = await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_layers.js', modules)),
  import(new URL('lui.web.dom/popup/lui_web_overlay.js', modules)),
])
const list = values => values.reduceRight((tl, hd) => ({hd, tl}), 0)
const element = (children = []) => {
  const attributes = new Map()
  return {
    style: {setProperty() {}},
    hasAttribute: name => attributes.has(name),
    setAttribute: (name, value) => attributes.set(name, value),
    removeAttribute: name => attributes.delete(name),
    contains(target) { return target === this || children.some(child => child.contains(target)) },
  }
}
const fixture = () => {
  const root = element(), registry = Layers.create()
  const document = {documentElement: root, addEventListener() {}, removeEventListener() {}}
  Layers.install(registry, document, () => false, target => target)
  const renderer = {web_layers: registry, web_document: document, web_host: root}
  const add = (id, owner, policy = 2) => {
    const content = element()
    Layers.register(registry, document, id, owner, undefined, content, list([content]),
      policy, () => {}, () => {}, () => {}, true, true)
    Overlay.refresh_modal_host_inert(renderer)
    return content
  }
  const close = id => {
    const token = Layers.close_layer(registry, document, id)
    Overlay.refresh_modal_host_inert(renderer)
    return token
  }
  return {root, registry, document, renderer, add, close}
}

test('closing the last modal releases host input and scrolling while retaining exit presence', () => {
  const f = fixture(), surface = f.add(1)
  assert.equal(f.root.hasAttribute('inert'), true)
  assert.equal(f.registry.scroll_lock_held, true)
  const token = f.close(1)
  assert.equal(Layers.is_present(f.registry, 1), true, 'Exit paint must remain mounted')
  assert.equal(surface.hasAttribute('inert'), true, 'The closing surface cannot accept input')
  assert.equal(f.root.hasAttribute('inert'), false, 'Background input is available at logical close')
  assert.equal(f.registry.scroll_lock_held, false, 'A visual-only exit cannot lock scrolling')
  Layers.finish_present(f.registry, f.document, 1, token)
  assert.equal(Layers.is_present(f.registry, 1), false)
})

test('closing a nested modal releases its parent without releasing the parent modal lock', () => {
  const f = fixture(), parent = f.add(1), child = f.add(2, 1)
  assert.equal(parent.hasAttribute('inert'), true)
  f.close(2)
  assert.equal(parent.hasAttribute('inert'), false)
  assert.equal(child.hasAttribute('inert'), true)
  assert.equal(f.root.hasAttribute('inert'), true)
  assert.equal(f.registry.scroll_lock_held, true)
  f.close(1)
  assert.equal(f.root.hasAttribute('inert'), false, 'Retiring descendants do not keep the host locked')
  assert.equal(f.registry.scroll_lock_held, false)
})

test('stale exit completion cannot release a newly opened or reopened modal', () => {
  const f = fixture()
  f.add(1)
  const stale = f.close(1)
  f.add(2)
  Layers.finish_present(f.registry, f.document, 1, stale)
  Overlay.refresh_modal_host_inert(f.renderer)
  assert.equal(f.root.hasAttribute('inert'), true)
  assert.equal(f.registry.scroll_lock_held, true)
  const staleSecond = f.close(2)
  Layers.open_layer(f.registry, f.document, 2)
  Layers.finish_present(f.registry, f.document, 2, staleSecond)
  Overlay.refresh_modal_host_inert(f.renderer)
  assert.equal(Layers.is_open(f.registry, 2), true)
  assert.equal(Layers.is_present(f.registry, 2), true)
  assert.equal(f.root.hasAttribute('inert'), true)
})

test('anchored sibling portals share transitive ownership only through live parent surfaces', () => {
  const external = element(), row = element(), nextRow = element(), field = element()
  const parent = element([row]), picker = element([nextRow]), nested = element([field])
  const registry = Layers.create(), dismissed = [], closed = []
  const document = {addEventListener() {}, removeEventListener() {}}
  const descendant = () => false, targetElement = target => target
  Layers.install(registry, document, descendant, targetElement)
  const add = (id, content, trigger) => Layers.register(registry, document, id, undefined,
    trigger, content, list([content]), 0,
    () => { dismissed.push(id); Layers.close_layer(registry, document, id) },
    () => closed.push(id), () => {}, true, true)
  const focus = target => Layers.dispatch_focus(registry, descendant, targetElement, {target})
  add(1, parent, external)
  add(2, picker, row)
  add(3, nested, nextRow)
  focus(field)
  Layers.dispatch_pointer(registry, descendant, targetElement, {target: field})
  assert.deepEqual(dismissed, [], 'Focus and pointer input in a nested sibling portal stay owned')
  const roots = new Set()
  for (let rest = Layers.focus_roots(registry, 1); rest; rest = rest.tl) roots.add(rest.hd)
  assert.deepEqual(roots, new Set([parent, picker, nested]),
    'The focus scope includes the complete portal chain')
  Layers.dispatch_key(registry, {key: 'Escape', defaultPrevented: false, isComposing: false,
    stopImmediatePropagation() {}, preventDefault() {}})
  assert.deepEqual(dismissed, [3], 'Escape closes only the topmost child')
  assert.equal(Layers.is_open(registry, 1), true)
  assert.equal(Layers.is_open(registry, 2), true)
  assert.equal(Layers.owns_target(registry, 1, field), false, 'Exit presence grants no ownership')
  Layers.open_layer(registry, document, 3)
  const otherRow = element(), otherParent = element([otherRow])
  add(4, otherParent, external)
  Layers.reconcile_trigger(registry, document, 2, otherRow)
  assert.equal(Layers.owns_target(registry, 1, field), false, 'Rebinding drops the old anchor owner')
  assert.equal(Layers.owns_target(registry, 4, field), true, 'Rebinding transfers the full chain')
  Layers.remove(registry, document, 4)
  assert.equal(Layers.is_open(registry, 2), false, 'Unmount closes anchored descendants')
  assert.equal(Layers.is_open(registry, 3), false)
  assert.deepEqual(new Set(closed), new Set([2, 3]))
  Layers.reconcile_trigger(registry, document, 2, row)
  Layers.open_layer(registry, document, 2)
  Layers.open_layer(registry, document, 3)
  dismissed.length = 0
  focus(element())
  assert.deepEqual(dismissed, [3, 2, 1], 'Unrelated outside focus still dismisses every menu layer')
  add(1, parent, external)
  add(2, picker, external)
  assert.equal(Layers.owns_target(registry, 1, nextRow), false,
    'A shared external trigger alone does not establish parent ownership')
})
