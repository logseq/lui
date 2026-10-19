import assert from 'node:assert/strict'
import test from 'node:test'

// DOMRect is a browser primitive; the positioner is exercised under node:test.
globalThis.DOMRect ??= class {
  constructor(x, y, width, height) {
    Object.assign(this, {x, y, width, height, left: x, top: y,
      right: x + width, bottom: y + height})
  }
}

const build = process.env.LUI_TEST_BUILD_DIR ?? '_build'
const modules = new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`, import.meta.url)
const [Store, Protocol, Schema, Nodes, Position] = await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js', modules)),
  import(new URL('lui/lui_protocol.js', modules)),
  import(new URL('lui/lui_wire_schema.js', modules)),
  import(new URL('lui.web.dom/nodes/lui_web_nodes.js', modules)),
  import(new URL('lui.web.dom/popup/lui_web_position.js', modules)),
])
const list = values => values.reduceRight((tl, hd) => ({hd, tl}), 0)
const named = (values, nameOf, name) => {
  for (let rest = values; rest; rest = rest.tl) if (nameOf(rest.hd) === name) return rest.hd
  throw new Error(`Unknown schema value: ${name}`)
}
const kind = name => named(Schema.all_node_kinds, Schema.node_kind_name, name)
const prop = name => named(Schema.all_properties, Schema.property_name, name)
const element = (bounds, children = []) => {
  const styles = new Map(), attributes = new Map()
  return {
    styles, attributes, isConnected: true,
    style: {setProperty: (key, value) => styles.set(key, value)},
    children: {item: index => children[index] ?? null, length: children.length},
    getBoundingClientRect: () => ({...bounds, left: bounds.x, top: bounds.y,
      right: bounds.x + bounds.width, bottom: bounds.y + bounds.height}),
    setAttribute: (key, value) => attributes.set(key, value),
    getAttribute: key => attributes.get(key) ?? null,
    removeAttribute: key => attributes.delete(key),
    isSameNode(other) { return this === other },
    closest(selector) { return selector === '[inert]' && attributes.has('inert') ? this : null },
  }
}

test('a portal popover uses its retained target for alignment, tracking and availability', () => {
  const viewport = {clientWidth: 640, clientHeight: 720}
  const anchorBounds = {x: 500, y: 80, width: 24, height: 24}
  const target = element(anchorBounds)
  const popup = element({x: 0, y: 0, width: 234, height: 178})
  const positioner = element({x: 0, y: 0, width: 234, height: 178}, [popup])
  positioner.setAttribute('data-anchor', 'below')
  positioner.setAttribute('data-anchor-alignment', 'end')
  positioner.setAttribute('data-anchor-offset', '4')
  let targetPresent = true
  const document = {defaultView: null, documentElement: viewport,
    getElementById: id => id === 'filter-trigger' && targetPresent ? target : null}
  const store = Store.create_store()
  const renderer = {web_store: store, web_document: document}
  const set = (id, name, value) => Protocol.set_prop_op(id, prop(name), {TAG: 0, _0: value})
  assert.equal(Store.apply_batch(store, name => name === kind('popover') ? positioner : element({x: 0, y: 0, width: 0, height: 0}), {
    generation: 1,
    ops: list([Protocol.create_node_op(1, kind('column')), Protocol.create_node_op(2, kind('box')),
      Protocol.create_node_op(3, kind('popover')), Protocol.insert_child_op(1, 2, 0),
      Protocol.insert_child_op(1, 3, 1), set(2, 'accessibility-identifier', 'filter-trigger'),
      set(3, 'anchor', 'below'), set(3, 'anchor-target', 'filter-trigger'),
      set(3, 'anchor-alignment', 'end'),
      Protocol.set_prop_op(3, prop('anchor-offset'), {TAG: 3, _0: 4})]),
  }), true)
  assert.equal(Nodes.dropdown_anchor_node(renderer, 3), target)
  const check = (x, y, side) => {
    Position.position_popover(renderer, 3)
    assert.equal(positioner.styles.get('left'), `${x}px`)
    assert.equal(positioner.styles.get('top'), `${y}px`)
    assert.equal(positioner.attributes.get('data-side'), side)
    assert.equal(popup.styles.get('transform'), undefined)
  }
  check(290, 108, 'below')
  Object.assign(anchorBounds, {x: 300, y: 250})
  check(90, 278, 'below')
  viewport.clientHeight = 400
  check(90, 68, 'above')
  target.setAttribute('inert', '')
  assert.equal(Position.anchored(renderer, 3), false)
  target.removeAttribute('inert')
  targetPresent = false
  target.isConnected = false
  assert.equal(Position.anchored(renderer, 3), false)
})

for (const side of ['above', 'below', 'left', 'right']) {
  for (const alignment of ['start', 'end']) {
    test(`popover ${side}/${alignment} cross-axis offsets update and clear before viewport clamping`, () => {
      const viewport = {clientWidth: 640, clientHeight: 480}
      const anchor = element({x: 100, y: 100, width: 80, height: 32})
      const popup = element({x: 0, y: 0, width: 60, height: 40})
      const positioner = element({x: 0, y: 0, width: 60, height: 40}, [popup])
      const document = {defaultView: null, documentElement: viewport}
      const store = Store.create_store(), renderer = {web_store: store, web_document: document}
      const set = (name, value) => Protocol.set_prop_op(2, prop(name), value)
      let generation = 0
      const apply = ops => assert.equal(Store.apply_batch(store,
        name => name === kind('popover') ? positioner : anchor,
        {generation: ++generation, ops: list(ops)}), true)
      apply([Protocol.create_node_op(1, kind('box')), Protocol.create_node_op(2, kind('popover')),
        Protocol.insert_child_op(1, 2, 0), set('anchor', {TAG: 0, _0: side}),
        set('anchor-alignment', {TAG: 0, _0: alignment})])
      positioner.setAttribute('data-anchor', side)
      positioner.setAttribute('data-anchor-alignment', alignment)
      const vertical = side === 'above' || side === 'below'
      const anchorSize = vertical ? 80 : 32, popupSize = vertical ? 60 : 40
      const base = alignment === 'end' ? 100 + anchorSize - popupSize : 100
      const check = offset => {
        Position.position_popover(renderer, 2)
        const expected = Math.max(8, Math.min(base + (alignment === 'end' ? -offset : offset),
          (vertical ? viewport.clientWidth : viewport.clientHeight) - popupSize - 8))
        assert.equal(positioner.styles.get(vertical ? 'left' : 'top'), `${expected}px`)
      }
      check(0)
      for (const offset of [5.5, -5.5, 1000, -1000]) {
        apply([set('anchor-alignment-offset', {TAG: 3, _0: offset})])
        check(offset)
      }
      apply([Protocol.remove_prop_op(2, prop('anchor-alignment-offset'))])
      check(0)
      viewport.clientWidth = 480
      viewport.clientHeight = 360
      check(0)
    })
  }
}


test('a frozen rectangle keeps a replacement picker anchored after its option unmounts', () => {
  const viewport = {clientWidth: 1280, clientHeight: 720}
  const popup = element({x: 0, y: 0, width: 310, height: 342})
  const positioner = element({x: 0, y: 0, width: 310, height: 342}, [popup])
  positioner.setAttribute('data-anchor', 'below')
  positioner.setAttribute('data-anchor-alignment', 'center')
  const document = {defaultView: null, documentElement: viewport,
    getElementById: () => null}
  const store = Store.create_store(), renderer = {web_store: store, web_document: document}
  const rectProperty = (() => {
    for (let rest = Schema.all_properties; rest; rest = rest.tl)
      if (Schema.property_name(rest.hd) === 'anchor-rect') return rest.hd
    return undefined
  })()
  assert.notEqual(rectProperty, undefined, 'the host must accept a frozen rectangle anchor')
  let generation = 0
  const rect = value => Protocol.set_prop_op(2, rectProperty, {TAG: 0, _0: value})
  const apply = ops => Store.apply_batch(store, () => positioner,
    {generation: ++generation, ops: list(ops)})
  assert.equal(apply([Protocol.create_node_op(1, kind('column')),
    Protocol.create_node_op(2, kind('popover')), Protocol.insert_child_op(1, 2, 0),
    Protocol.set_prop_op(2, prop('anchor'), {TAG: 0, _0: 'below'}),
    rect('961.5 341.953125 208 20')]), true)
  assert.equal(Position.anchored(renderer, 2), true)
  const check = (x, y, side) => {
    Position.position_popover(renderer, 2)
    assert.equal(positioner.styles.get('left'), `${x}px`)
    assert.equal(positioner.styles.get('top'), `${y}px`)
    assert.equal(positioner.attributes.get('data-side'), side)
  }
  check(910.5, 361.953125, 'below')
  viewport.clientHeight = 500
  check(910.5, 8, 'above')
  viewport.clientWidth = 600
  check(282, 8, 'above')
  assert.equal(apply([rect('30 80 40 20')]), true)
  viewport.clientHeight = 720
  check(8, 100, 'below')
  for (const malformed of ['0 0 -1 2', '0 0 1 -2', 'nan 0 1 2', '0 infinity 1 2',
    '0 0 1', '0 0 1 2 3']) assert.throws(() => apply([rect(malformed)]))
  assert.throws(() => apply([Protocol.set_prop_op(2, prop('anchor-target'),
    {TAG: 0, _0: 'a-live-target'})]), 'live and frozen anchors are exclusive')
  assert.throws(() => apply([Protocol.set_prop_op(2, prop('popup-x'), {TAG: 3, _0: 3}),
    Protocol.set_prop_op(2, prop('popup-y'), {TAG: 3, _0: 4})]))
})
