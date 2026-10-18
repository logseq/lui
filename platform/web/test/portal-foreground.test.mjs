import assert from 'node:assert/strict'
import test from 'node:test'

const build = process.env.LUI_TEST_BUILD_DIR ?? '_build'
const modules = new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`, import.meta.url)
const [Store, Protocol, Schema, Tables, Props] = await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js', modules)),
  import(new URL('lui/lui_protocol.js', modules)),
  import(new URL('lui/lui_wire_schema.js', modules)),
  import(new URL('melange/hashtbl.js', modules)),
  import(new URL('lui.web.dom/render/lui_web_props.js', modules)),
])
const list = items => items.reduceRight((tl, hd) => ({hd, tl}), 0)
const named = (values, nameOf, name) => {
  for (let rest = values; rest; rest = rest.tl) if (nameOf(rest.hd) === name) return rest.hd
  throw new Error(`Unknown schema value: ${name}`)
}
const kind = name => named(Schema.all_node_kinds, Schema.node_kind_name, name)
const prop = name => named(Schema.all_properties, Schema.property_name, name)
const wire = value => ({TAG: 0, _0: value})
const element = (children = []) => {
  const styles = new Map(), writes = []
  return {styles, writes, style: {
    getPropertyValue: name => styles.get(name) ?? '',
    setProperty: (name, value) => {writes.push(name); styles.set(name, value)},
  },
    children: {item: index => children[index] ?? null}, parentElement: null}
}

for (const name of ['dialog', 'drawer', 'sheet', 'dropdown-menu', 'popover', 'context-menu', 'tooltip', 'toast']) {
  test(`${name} inherits logical foreground across portal updates and reparenting`, () => {
    const surface = element(), child = element(), wrapper = element()
    surface.children = {item: index => index === 0 ? child : null}
    surface.parentElement = wrapper
    const modal = ['dialog', 'drawer', 'sheet'].includes(name)
    const transport = modal ? wrapper : surface
    const store = Store.create_store()
    const renderer = {web_store: store, web_portal_nodes: Tables.create(undefined, 4)}
    let generation = 0
    const apply = ops => assert.equal(Store.apply_batch(store, id => id === kind(name) ? surface : element(),
      {generation: ++generation, ops: list(ops)}), true)
    const set = (id, value) => Protocol.set_prop_op(id, prop('foreground'), wire(value))
    apply([Protocol.create_node_op(1, kind('column')), Protocol.create_node_op(2, kind('column')),
      Protocol.create_node_op(3, kind(name)), Protocol.create_node_op(4, kind('column')),
      Protocol.insert_child_op(1, 2, 0), Protocol.insert_child_op(2, 3, 0),
      Protocol.insert_child_op(1, 4, 1), set(1, 'var(--body-ink)'),
      ...(['dialog', 'drawer', 'sheet', 'tooltip'].includes(name) ? [Protocol.set_prop_op(3, prop('text'), wire('Content'))] : []),
      Protocol.set_prop_op(2, prop('press-enabled'), {TAG: 1, _0: true}),
      Protocol.set_prop_op(4, prop('press-enabled'), {TAG: 1, _0: true}),
      ...(name === 'drawer' ? [Protocol.create_node_op(5, kind('text')), Protocol.create_node_op(6, kind('text')),
        Protocol.insert_child_op(3, 5, 0), Protocol.insert_child_op(3, 6, 1)] : []),
      ...(name === 'tooltip' ? [Protocol.set_prop_op(3, prop('anchor'), wire('below'))] : [])])
    // The renderer's mounted portal index avoids scanning ordinary content on every batch.
    Tables.replace(renderer.web_portal_nodes, 3, surface)
    const refresh = () => Props.refresh_portal_foregrounds(renderer)
    refresh()
    assert.match(transport.styles.get('color') ?? '', /var\(--body-ink\)/)
    const writes = transport.writes.length
    for (let index = 0; index < 20; index++) refresh()
    assert.equal(transport.writes.length, writes, 'Unchanged portal ink must not invalidate browser styles')
    apply([set(2, '#123456')]); refresh()
    assert.match(transport.styles.get('color'), /#123456/)
    apply([Protocol.remove_prop_op(2, prop('foreground'))]); refresh()
    assert.match(transport.styles.get('color'), /var\(--body-ink\)/)
    if (name !== 'context-menu') {
      const exiting = transport.styles.get('color')
      apply([Protocol.remove_child_op(2, 3)]); refresh()
      assert.equal(transport.styles.get('color'), exiting, 'An exiting portal retains its captured logical ink')
      apply([Protocol.insert_child_op(2, 3, 0)]); refresh()
    }
    apply([set(4, '#abcdef'), Protocol.remove_child_op(2, 3), Protocol.insert_child_op(4, 3, 0)]); refresh()
    assert.match(transport.styles.get('color'), /#abcdef/)
    if (Protocol.property_supported(kind(name), prop('foreground'))) {
      apply([set(3, '#fedcba')])
      Props.apply_property(renderer, () => {}, 3, kind(name), surface, prop('foreground'), wire('#fedcba'))
      const painted = ['dropdown-menu', 'popover'].includes(name) ? child : surface
      const explicit = painted.styles.get('color')
      refresh()
      assert.equal(painted.styles.get('color'), explicit, 'Explicit surface contrast remains authoritative')
      apply([Protocol.remove_prop_op(3, prop('foreground'))])
      Props.remove_property(renderer, () => {}, 3, kind(name), surface, prop('foreground'))
      refresh()
      assert.match(transport.styles.get('color'), /#abcdef/)
    }
    apply([Protocol.remove_prop_op(4, prop('foreground')), Protocol.remove_prop_op(1, prop('foreground'))]); refresh()
    assert.equal(transport.styles.get('color'), '', 'Removing logical ink restores host inheritance')
    assert.equal(child.styles.get('color') ?? '', '', 'Transport inheritance adds no child color override')
  })
}
