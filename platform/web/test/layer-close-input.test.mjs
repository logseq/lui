import assert from 'node:assert/strict'
import test from 'node:test'

const build = process.env.LUI_TEST_BUILD_DIR ?? '_build'
const modules = new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`, import.meta.url)
const [Layers, Overlay] = await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_layers.js', modules)),
  import(new URL('lui.web.dom/popup/lui_web_overlay.js', modules)),
])
const list = values => values.reduceRight((tl, hd) => ({hd, tl}), 0)
const element = () => {
  const attributes = new Map()
  return {
    style: {setProperty() {}},
    hasAttribute: name => attributes.has(name),
    setAttribute: (name, value) => attributes.set(name, value),
    removeAttribute: name => attributes.delete(name),
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
