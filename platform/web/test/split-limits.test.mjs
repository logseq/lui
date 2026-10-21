import assert from 'node:assert/strict'
import test from 'node:test'

const build = process.env.LUI_TEST_BUILD_DIR ?? '_build'
const modules = new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`, import.meta.url)
const [Store, Protocol, Schema, Split] = await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js', modules)),
  import(new URL('lui/lui_protocol.js', modules)),
  import(new URL('lui/lui_wire_schema.js', modules)),
  import(new URL('lui.web.dom/widgets/lui_web_split.js', modules)),
])
const list = items => items.reduceRight((tl, hd) => ({hd, tl}), 0)
const named = (values, nameOf, name) => {
  for (let rest = values; rest; rest = rest.tl) if (nameOf(rest.hd) === name) return rest.hd
  throw new Error(`Unknown schema value: ${name}`)
}
const property = name => named(Schema.all_properties, Schema.property_name, name)
const kind = name => named(Schema.all_node_kinds, Schema.node_kind_name, name)
const set = (id, name, value) => Protocol.set_prop_op(id, property(name), {TAG: 2, _0: value})

test('split geometry honors both pane maximums, updates and removal', () => {
  const store = Store.create_store(), renderer = {web_store: store}
  let generation = 0
  const apply = ops => Store.apply_batch(store, () => ({}), {generation: ++generation, ops: list(ops)})
  apply([Protocol.create_node_op(1, kind('split')), Protocol.create_node_op(2, kind('box')),
    Protocol.create_node_op(3, kind('box')), Protocol.insert_child_op(1, 2, 0), Protocol.insert_child_op(1, 3, 1),
    set(1, 'gap', 3), set(2, 'min-width', 100), set(3, 'min-width', 150),
    set(2, 'max-width', 400), set(3, 'max-width', 700)])
  const constrain = value => Split.effective_fraction(Split.split_geometry(renderer, 1, {clientWidth: 1003}), value)
  assert.equal(constrain(0.01), 0.3)
  assert.equal(constrain(0.9), 0.4)
  assert.equal(constrain(0.35), 0.35)
  apply([Protocol.remove_prop_op(2, property('max-width'))])
  assert.equal(constrain(0.9), 0.85)
  apply([set(2, 'max-width', 300)])
  assert.equal(constrain(0.9), 0.3)
  apply([set(2, 'max-width', 200), set(3, 'max-width', 300)])
  assert.equal(constrain(0.9), 0.4, 'An overlarge track shares infeasible maximums proportionally')
  apply([Protocol.remove_prop_op(2, property('max-width')), Protocol.remove_prop_op(3, property('max-width')),
    set(2, 'min-width', 600), set(3, 'min-width', 900)])
  assert.equal(constrain(0.9), 0.4, 'Existing infeasible minimum behavior stays proportional')
})

const floatSet = (id, name, value) => Protocol.set_prop_op(id, property(name), {TAG: 3, _0: value})
const element = children => ({
  style: {values: new Map(), setProperty(name, value) { this.values.set(name, value) }},
  attributes: new Map(), setAttribute(name, value) {this.attributes.set(name, value)},
  children: {item: index => children[index] ?? null},
})

test('fixed-width split retains pixels while its parent resizes and can collapse below drag minima', () => {
  const store = Store.create_store(), renderer = {web_store: store}
  Store.apply_batch(store, () => ({}), {generation: 1, ops: list([
    Protocol.create_node_op(1, kind('split')), Protocol.create_node_op(2, kind('box')),
    Protocol.create_node_op(3, kind('box')), Protocol.insert_child_op(1, 2, 0), Protocol.insert_child_op(1, 3, 1),
    set(1, 'gap', 3), floatSet(1, 'first-pane-width', 246), set(2, 'min-width', 240),
  ])})
  const first = element([]), second = element([]), panes = element([first, second]), divider = element([])
  const root = element([panes, divider])
  const constructing = element([element([]), element([])])
  constructing.clientWidth = 1440
  assert.doesNotThrow(() => Split.render_split(renderer, 1, constructing, 246, false),
    'Split properties can be applied before its pane children are attached')
  for (const width of [1440, 1200, 1000, 800]) {
    root.clientWidth = width
    Split.render_split(renderer, 1, root, 246, false)
    assert.match(panes.style.values.get('grid-template-columns'), /246px/, 'The first track is expressed in pixels')
    assert.match(divider.style.values.get('left'), /246px/, 'The divider follows the same pixel track')
    assert.equal(first.style.values.get('grid-column'), '1', 'The first pane keeps its track when positioned outside flow')
    assert.equal(second.style.values.get('grid-column'), '2', 'The second pane must not auto-place into a collapsed first track')
    for (const pane of [first, second]) assert.equal(pane.style.values.get('grid-row'), '1')
  }
  Split.render_split(renderer, 1, root, 0, true)
  assert.match(panes.style.values.get('grid-template-columns'), /0px/, 'Controlled closure reaches zero despite its drag minimum')
  assert.equal(first.style.values.get('min-width'), '0px')
  assert.equal(first.style.values.get('overflow'), 'hidden')
  Store.apply_batch(store, () => root, {generation: 2, ops: list([
    Protocol.remove_prop_op(1, property('first-pane-width')), floatSet(1, 'value', 0),
  ])})
  Split.render_split(renderer, 1, root, 0, false)
  assert.equal(panes.style.values.get('grid-template-columns'), 'minmax(0, 0fr) minmax(0, 1fr)', 'Fractional zero is a collapsed pane, matching native')

})

const Hash = await import(new URL('melange/hashtbl.js', modules))

test('zero-width split handles keep controlled layout and disable all divider input', () => {
  const store = Store.create_store(), events = [], listeners = new Map(), input = new Map()
  const panes = element([element([]), element([])]), divider = element([]), root = element([panes, divider])
  root.clientWidth = 1000
  root.getBoundingClientRect = () => ({left: 0, width: 1000})
  divider.addEventListener = (key, fn) => input.set(key, fn)
  const renderer = {web_store: store,
    web_document: {addEventListener: (key, fn) => listeners.set(key, fn), removeEventListener() {}},
    web_splits: Hash.create(undefined, 4), web_cleanups: Hash.create(undefined, 4),
    web_event_handler: {contents: event => events.push(event)}}
  let generation = 0
  const apply = ops => Store.apply_batch(store, () => root, {generation: ++generation, ops: list(ops)})
  assert.doesNotThrow(() => apply([
    Protocol.create_node_op(1, kind('split')), Protocol.create_node_op(2, kind('box')),
    Protocol.create_node_op(3, kind('box')), Protocol.insert_child_op(1, 2, 0), Protocol.insert_child_op(1, 3, 1),
    set(1, 'gap', 0), floatSet(1, 'first-pane-width', 246), set(1, 'resize-handle-width', 0),
  ]), 'A controlled split must accept a zero-width handle')
  const previous = globalThis.ResizeObserver
  globalThis.ResizeObserver = class {observe() {} disconnect() {}}
  const down = () => input.get('mousedown')({button: 0, clientX: 246, preventDefault() {}})
  const move = () => listeners.get('mousemove')({clientX: 266})
  const key = value => input.get('keydown')({key: value, preventDefault() {}})
  try {
    Split.reconcile_split(renderer, 1, root, 246)
    Split.attach_split_events(renderer, 1, root)
    assert.match(panes.style.values.get('grid-template-columns'), /246px/)
    assert.equal(divider.style.values.get('display'), 'none')
    assert.equal(divider.attributes.get('tabindex'), '-1')
    assert.equal(divider.attributes.get('aria-hidden'), 'true')
    down(); move()
    for (const value of ['ArrowLeft', 'ArrowRight', 'Home', 'End']) key(value)
    assert.equal(events.length, 0, 'A hidden divider cannot emit pointer or keyboard resize events')
    apply([set(1, 'resize-handle-width', 3)])
    Split.render_split(renderer, 1, root, 246, false)
    assert.notEqual(divider.style.values.get('display'), 'none')
    assert.equal(divider.attributes.get('tabindex'), '0')
    assert.equal(divider.attributes.get('aria-hidden'), 'false')
    key('ArrowRight')
    assert.equal(events.at(-1)._1, 296)
    Split.reconcile_split(renderer, 1, root, 246)
    down()
    apply([set(1, 'resize-handle-width', 0)])
    Split.render_split(renderer, 1, root, 246, false)
    const count = events.length
    move()
    assert.equal(events.length, count, 'Hiding the divider cancels a captured drag')
    apply([set(1, 'resize-handle-width', 3)])
    move()
    assert.equal(events.length, count, 'Showing the divider cannot revive an old drag')
  } finally {globalThis.ResizeObserver = previous}
})

test('pixel split drag and keyboard use pixel events, clamp endpoints and retain active animation on parent resize', () => {
  const store = Store.create_store(), events = [], listeners = new Map()
  const document = {addEventListener: (key, fn) => listeners.set(key, fn), removeEventListener() {}}
  const renderer = {web_store: store, web_document: document, web_splits: Hash.create(undefined, 4),
    web_cleanups: Hash.create(undefined, 4), web_event_handler: {contents: event => events.push(event)}}
  Store.apply_batch(store, () => root, {generation: 1, ops: list([
    Protocol.create_node_op(1, kind('split')), Protocol.create_node_op(2, kind('box')),
    Protocol.create_node_op(3, kind('box')), Protocol.insert_child_op(1, 2, 0), Protocol.insert_child_op(1, 3, 1),
    set(1, 'gap', 3), floatSet(1, 'first-pane-width', 246), set(1, 'resize-duration', 300),
    set(2, 'min-width', 240), set(2, 'max-width', 460),
  ])})
  const panes = element([element([]), element([])]), divider = element([]), root = element([panes, divider])
  const input = new Map()
  divider.addEventListener = (key, fn) => input.set(key, fn)
  root.clientWidth = 1003
  root.getBoundingClientRect = () => ({left: 0, width: root.clientWidth})
  let observeResize
  const previousObserver = globalThis.ResizeObserver
  globalThis.ResizeObserver = class {constructor(fn) {observeResize = fn} observe() {} disconnect() {}}
  try {
    Split.reconcile_split(renderer, 1, root, 246)
    Split.reconcile_split(renderer, 1, root, 300)
    Split.reconcile_split(renderer, 1, root, 300)
    assert.equal(panes.style.values.get('transition-property'), 'grid-template-columns',
      'An unchanged controlled update does not cancel the running transition')
    Split.reconcile_split(renderer, 1, root, 246)
    Split.attach_split_events(renderer, 1, root)
    const key = key => input.get('keydown')({key, preventDefault() {}})
    key('ArrowRight')
    assert.equal(events.at(-1)._1, 296)
    key('Home')
    assert.equal(events.at(-1)._1, 240, 'Home reaches the drag minimum')
    key('End')
    assert.equal(events.at(-1)._1, 460, 'End reaches the drag maximum')
    input.get('mousedown')({button: 0, clientX: 461.5, preventDefault() {}})
    listeners.get('mousemove')({clientX: 301.5})
    assert.equal(events.at(-1)._1, 300)
    listeners.get('mousemove')({clientX: -100})
    assert.equal(events.at(-1)._1, 240, 'Dragging past the left edge reaches the minimum')
    listeners.get('mouseup')({})
    Split.render_split(renderer, 1, root, 246, true)
    root.clientWidth = 900
    observeResize([])
    assert.equal(panes.style.values.get('transition-property'), 'grid-template-columns', 'Parent resize keeps a fixed-width transition running')
  } finally {
    globalThis.ResizeObserver = previousObserver
  }
})


test('overlay split handles keep zero layout gap, authored hit geometry and pointer grab offsets', () => {
  for (const name of ['resize-handle-width', 'resize-handle-offset']) {
    assert.ok(Array.from(function* () {for (let p = Schema.all_properties; p; p = p.tl) yield Schema.property_name(p.hd)}()).includes(name),
      `The shared split protocol must expose ${name}`)
  }
  for (const offset of [0.5, 2.5]) {
    for (const grip of [-1.4, 0, 1.4]) {
      const store = Store.create_store(), events = [], listeners = new Map(), input = new Map()
      const panes = element([element([]), element([])]), divider = element([]), root = element([panes, divider])
      root.clientWidth = 1000
      root.getBoundingClientRect = () => ({left: 0, width: 1000})
      divider.addEventListener = (key, fn) => input.set(key, fn)
      const renderer = {web_store: store, web_document: {addEventListener: (key, fn) => listeners.set(key, fn), removeEventListener() {}},
        web_splits: Hash.create(undefined, 4), web_cleanups: Hash.create(undefined, 4),
        web_event_handler: {contents: event => events.push(event)}}
      Store.apply_batch(store, () => root, {generation: 1, ops: list([
        Protocol.create_node_op(1, kind('split')), Protocol.create_node_op(2, kind('box')),
        Protocol.create_node_op(3, kind('box')), Protocol.insert_child_op(1, 2, 0), Protocol.insert_child_op(1, 3, 1),
        set(1, 'gap', 0), floatSet(1, 'first-pane-width', 246), set(1, 'resize-handle-width', 3),
        floatSet(1, 'resize-handle-offset', offset),
      ])})
      const previous = globalThis.ResizeObserver
      globalThis.ResizeObserver = class {observe() {} disconnect() {}}
      try {
        Split.reconcile_split(renderer, 1, root, 246)
        Split.attach_split_events(renderer, 1, root)
        assert.equal(panes.style.values.get('column-gap'), '0px')
        assert.equal(divider.style.values.get('width'), '3px')
        const x = 246 + offset + grip
        input.get('mousedown')({button: 0, clientX: x, preventDefault() {}})
        listeners.get('mousemove')({clientX: x})
        assert.equal(events.at(-1)?._1 ?? 246, 246, 'Grabbing any point must not shift the split')
        listeners.get('mousemove')({clientX: x + 20})
        assert.ok(Math.abs(events.at(-1)._1 - 266) < 1e-8, 'Dragging preserves the pointer grab offset')
        listeners.get('mouseup')({})
        input.get('keydown')({key: 'ArrowRight', preventDefault() {}})
        assert.ok(Math.abs(events.at(-1)._1 - 316) < 1e-8, 'Keyboard resizing uses the whole divider-free track')
        Store.apply_batch(store, () => root, {generation: 2, ops: list([
          Protocol.remove_prop_op(1, property('resize-handle-width')),
          Protocol.remove_prop_op(1, property('resize-handle-offset')), set(1, 'gap', 9),
        ])})
        Split.render_split(renderer, 1, root, 246, false)
        assert.equal(divider.style.values.get('width'), '9px', 'Removing authored handle geometry restores the gap-sized handle')
      } finally {globalThis.ResizeObserver = previous}
    }
  }
})


test('split updates preserve explicit pane overflow and restore clipping after removal', () => {
  const store = Store.create_store(), renderer = {web_store: store}
  const first = element([]), second = element([]), panes = element([first, second]), divider = element([])
  const root = element([panes, divider]); root.clientWidth = 1000
  let generation = 0
  const apply = ops => Store.apply_batch(store, () => root, {generation: ++generation, ops: list(ops)})
  const overflow = value => Protocol.set_prop_op(2, property('overflow'), {TAG: 0, _0: value})
  apply([Protocol.create_node_op(1, kind('split')), Protocol.create_node_op(2, kind('box')),
    Protocol.create_node_op(3, kind('box')), Protocol.insert_child_op(1, 2, 0), Protocol.insert_child_op(1, 3, 1),
    overflow('visible')])
  for (const value of [0.5, 0, 1, 0.7]) {
    Split.render_split(renderer, 1, root, value, true)
    assert.equal(first.style.values.get('overflow'), 'visible', 'A viewport drawer may extend beyond its pane')
    assert.equal(second.style.values.get('overflow'), 'hidden', 'Unauthored panes retain default clipping')
  }
  apply([overflow('auto')]); Split.render_split(renderer, 1, root, 0.7, false)
  assert.equal(first.style.values.get('overflow'), 'auto')
  apply([Protocol.remove_prop_op(2, property('overflow'))]); Split.render_split(renderer, 1, root, 0.7, false)
  assert.equal(first.style.values.get('overflow'), 'hidden')
})
