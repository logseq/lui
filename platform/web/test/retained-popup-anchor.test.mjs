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
const [Store, Protocol, Schema, Nodes, Position, Tracking] = await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js', modules)),
  import(new URL('lui/lui_protocol.js', modules)),
  import(new URL('lui/lui_wire_schema.js', modules)),
  import(new URL('lui.web.dom/nodes/lui_web_nodes.js', modules)),
  import(new URL('lui.web.dom/popup/lui_web_position.js', modules)),
  import(new URL('lui.web.dom/popup/lui_web_popup_tracking.js', modules)),
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
  check(651.5, 150, 'left')
  viewport.clientWidth = 600
  check(282, 150, 'left')
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


test('configured popup clearance follows resize, property updates and removal', () => {
  const viewport = {clientWidth: 640, clientHeight: 932}
  const anchor = element({x: 64, y: 96, width: 120, height: 32})
  const popup = element({x: 0, y: 0, width: 226, height: 288})
  const positioner = element({x: 0, y: 0, width: 226, height: 288}, [popup])
  positioner.getBoundingClientRect = () => {
    const width = Math.min(226, parseFloat(popup.styles.get('--lui-popup-available-width')))
    const height = Math.min(288, parseFloat(popup.styles.get('--lui-popup-available-height')))
    return {x: 0, y: 0, width, height, left: 0, top: 0, right: width, bottom: height}
  }
  positioner.setAttribute('data-anchor', 'below')
  positioner.setAttribute('data-anchor-offset', '4')
  const document = {defaultView: null, documentElement: viewport}
  const store = Store.create_store(), renderer = {web_store: store, web_document: document}
  let generation = 0
  const set = (name, value) => Protocol.set_prop_op(2, prop(name), value)
  const apply = ops => assert.equal(Store.apply_batch(store,
    name => name === kind('popover') ? positioner : anchor,
    {generation: ++generation, ops: list(ops)}), true)
  apply([Protocol.create_node_op(1, kind('box')), Protocol.create_node_op(2, kind('popover')),
    Protocol.insert_child_op(1, 2, 0), set('anchor', {TAG: 0, _0: 'below'}),
    set('anchor-offset', {TAG: 3, _0: 4}), set('collision-padding', {TAG: 3, _0: 5})])
  const check = (height, left, top, side, available) => {
    viewport.clientHeight = height
    Position.position_popover(renderer, 2)
    assert.equal(positioner.styles.get('left'), `${left}px`)
    assert.equal(positioner.styles.get('top'), `${top}px`)
    assert.equal(positioner.attributes.get('data-side'), side)
    assert.equal(popup.styles.get('--lui-popup-available-height'), `${available}px`)
  }
  // 932px still fits below. Shorter viewports cannot fit either vertical side,
  // so the popup moves to the right, matching popup collision fallback.
  for (const row of [
    [932, 64, 132, 'below', 795],
    [329, 188, 36, 'right', 319],
    [220, 188, 5, 'right', 210],
    [932, 64, 132, 'below', 795],
  ]) check(...row)
  apply([set('collision-padding', {TAG: 3, _0: 12})])
  check(220, 188, 12, 'right', 196)
  apply([Protocol.remove_prop_op(2, prop('collision-padding'))])
  check(220, 188, 8, 'right', 204)
  for (const value of [-1, NaN, Infinity, -Infinity]) {
    assert.throws(() => apply([set('collision-padding', {TAG: 3, _0: value})]))
  }
})


test('dropdown roots flip alignment and stay on the preferred axis', () => {
  const viewport = {clientWidth: 400, clientHeight: 400}
  const anchorBounds = {x: 280, y: 40, width: 80, height: 32}
  const popupBounds = {x: 0, y: 0, width: 180, height: 40}
  const anchor = element(anchorBounds)
  const popup = element(popupBounds)
  const positioner = element(popupBounds, [popup])
  positioner.setAttribute('data-anchor', 'below')
  positioner.setAttribute('data-anchor-alignment', 'start')
  const document = {defaultView: null, documentElement: viewport}
  const store = Store.create_store(), renderer = {web_store: store, web_document: document}
  const set = (name, value) => Protocol.set_prop_op(2, prop(name), value)
  assert.equal(Store.apply_batch(store,
    name => name === kind('dropdown-menu') ? positioner : anchor,
    {generation: 1, ops: list([Protocol.create_node_op(1, kind('box')),
      Protocol.create_node_op(2, kind('dropdown-menu')), Protocol.insert_child_op(1, 2, 0),
      set('anchor', {TAG: 0, _0: 'below'}),
      set('anchor-alignment', {TAG: 0, _0: 'start'})])}), true)
  Position.position_dropdown(renderer, 2)
  assert.equal(positioner.attributes.get('data-side'), 'below')
  assert.equal(positioner.styles.get('left'), '180px')
  assert.equal(positioner.styles.get('top'), '72px')

  viewport.clientHeight = 120
  anchorBounds.x = 160
  popupBounds.width = 100
  popupBounds.height = 100
  positioner.getBoundingClientRect = () => ({
    x: 0, y: 0, width: popupBounds.width, height: popupBounds.height,
    left: 0, top: 0, right: popupBounds.width, bottom: popupBounds.height,
  })
  Position.position_dropdown(renderer, 2)
  assert.equal(positioner.attributes.get('data-side'), 'below')
  assert.equal(popup.styles.get('--lui-popup-available-height'), '40px')
  assert.equal(positioner.styles.get('top'), '12px')
})


test('a nested menu falls back to the perpendicular end when neither side fits', () => {
  const viewport = {clientWidth: 200, clientHeight: 600}
  const anchor = element({x: 80, y: 40, width: 40, height: 24})
  const popup = element({x: 0, y: 0, width: 160, height: 80})
  const positioner = element({x: 0, y: 0, width: 160, height: 80}, [popup])
  positioner.setAttribute('data-anchor', 'right')
  positioner.setAttribute('data-anchor-alignment', 'start')
  positioner.setAttribute('data-submenu', '')
  const document = {defaultView: null, documentElement: viewport}
  const store = Store.create_store(), renderer = {web_store: store, web_document: document}
  const set = (name, value) => Protocol.set_prop_op(2, prop(name), value)
  assert.equal(Store.apply_batch(store,
    name => name === kind('dropdown-menu') ? positioner : anchor,
    {generation: 1, ops: list([Protocol.create_node_op(1, kind('box')),
      Protocol.create_node_op(2, kind('dropdown-menu')), Protocol.insert_child_op(1, 2, 0),
      set('anchor', {TAG: 0, _0: 'right'}),
      set('anchor-alignment', {TAG: 0, _0: 'start'})])}), true)
  Position.position_dropdown(renderer, 2)
  assert.equal(positioner.attributes.get('data-side'), 'below')
  assert.equal(positioner.styles.get('top'), '64px')
  assert.equal(positioner.styles.get('left'), '32px')
})


test('side measurement preserves scroll instead of clamping it to the temporary viewport cap', () => {
  const viewport = {clientWidth: 1280, clientHeight: 300}
  const anchor = element({x: 1210, y: 8, width: 32, height: 32})
  // Wider than either horizontal side, so popup collision stays on the
  // vertical axis and the side cap still has to restore the scroll offset.
  const popup = element({x: 0, y: 0, width: 1400, height: 255})
  const positioner = element({x: 0, y: 0, width: 1400, height: 255}, [popup])
  const height = () => Math.min(339, parseFloat(popup.styles.get('--lui-popup-available-height')))
  const bounds = () => ({x: 0, y: 0, left: 0, top: 0, right: 1400,
    bottom: height(), width: 1400, height: height()})
  positioner.getBoundingClientRect = bounds
  popup.getBoundingClientRect = bounds
  popup.styles.set('--lui-popup-available-height', '255px')
  let scrollTop = 84
  Object.defineProperty(popup, 'scrollTop', {
    get: () => scrollTop,
    set: value => { scrollTop = Math.max(0, Math.min(value, 339 - height())) },
  })
  popup.scrollLeft = 0
  popup.style.setProperty = (key, value) => {
    popup.styles.set(key, value)
    // CSS layout clamps a scroll offset whenever its viewport expands.
    if (key === '--lui-popup-available-height') popup.scrollTop = scrollTop
  }
  positioner.setAttribute('data-anchor', 'below')
  const document = {defaultView: null, documentElement: viewport}
  const store = Store.create_store(), renderer = {web_store: store, web_document: document}
  const set = (name, value) => Protocol.set_prop_op(2, prop(name), value)
  assert.equal(Store.apply_batch(store, name => name === kind('popover') ? positioner : anchor,
    {generation: 1, ops: list([Protocol.create_node_op(1, kind('box')),
      Protocol.create_node_op(2, kind('popover')), Protocol.insert_child_op(1, 2, 0),
      set('anchor', {TAG: 0, _0: 'below'}), set('collision-padding', {TAG: 3, _0: 5})])}), true)
  for (let repeat = 0; repeat < 3; repeat++) {
    Position.position_popover(renderer, 2)
    assert.equal(popup.scrollTop, 84, 'measurement must retain the reachable final row')
  }
  viewport.clientHeight = 720
  Position.position_popover(renderer, 2)
  assert.equal(popup.scrollTop, 0, 'a final larger viewport still clamps normally')
  viewport.clientHeight = 300
  Position.position_popover(renderer, 2)
  assert.equal(popup.scrollTop, 0)
})


test('popup content scrolling does not schedule positioning but anchor scrolling still does', () => {
  const oldResize = globalThis.ResizeObserver, oldMutation = globalThis.MutationObserver
  globalThis.ResizeObserver = globalThis.MutationObserver = class {
    observe() {}
    disconnect() {}
  }
  const frames = new Map(), documentListeners = new Map(), windowListeners = new Map()
  let nextFrame = 0, updates = 0
  const window = {visualViewport: null,
    requestAnimationFrame: callback => { frames.set(++nextFrame, callback); return nextFrame },
    cancelAnimationFrame: id => frames.delete(id),
    addEventListener: (name, callback) => windowListeners.set(name, callback),
    removeEventListener: (name, callback) => { if (windowListeners.get(name) === callback) windowListeners.delete(name) },
  }
  const document = {defaultView: window,
    addEventListener: (name, callback) => documentListeners.set(name, callback),
    removeEventListener: (name, callback) => { if (documentListeners.get(name) === callback) documentListeners.delete(name) },
  }
  const nestedScroller = {}, ancestorScroller = {}
  const positioner = element({x: 0, y: 0, width: 256, height: 255})
  const popup = {...positioner, clientHeight: 253,
    querySelector: () => null, addEventListener() {}, removeEventListener() {},
    contains: target => target === popup || target === nestedScroller,
  }
  const flush = () => { const pending = [...frames.values()]; frames.clear(); for (const callback of pending) callback(0) }
  try {
    Tracking.start(true, document, positioner, popup, positioner, () => true,
      () => { updates++ }, () => assert.fail('the retained popup is valid'), undefined)
    flush()
    assert.equal(updates, 1)
    for (const target of [popup, nestedScroller]) {
      documentListeners.get('scroll')({target})
      assert.equal(frames.size, 0, 'scrolling popup content must not restart measurement')
    }
    documentListeners.get('scroll')({target: ancestorScroller})
    flush()
    assert.equal(updates, 2, 'scrolling the anchor container still repositions')
    windowListeners.get('resize')({target: window})
    flush()
    assert.equal(updates, 3, 'window resizing still repositions')
  } finally {
    Tracking.stop(positioner)
    globalThis.ResizeObserver = oldResize
    globalThis.MutationObserver = oldMutation
  }
  assert.equal(documentListeners.size, 0)
  assert.equal(windowListeners.size, 0)
  assert.equal(frames.size, 0)
})
