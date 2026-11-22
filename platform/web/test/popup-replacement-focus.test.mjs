import assert from 'node:assert/strict'
import {once} from 'node:events'
import {readFile} from 'node:fs/promises'
import test from 'node:test'
import {createStaticServer} from '../../../tooling/serve_web.mjs'
import {createPlaywrightSession} from './playwright-session.mjs'

test('a replacement form survives its invoking menu closing and restoring focus', async () => {
  const source = await readFile(new URL('./fixtures/point-menu-regression.html', import.meta.url), 'utf8')
  const html = source.slice(0, source.indexOf('<script type="module">')) + `<script type="module">
    import * as Web from 'lui.web.dom/shell/lui_web.js';
    import {Protocol, properties, kinds} from '/platform/web/test/fixtures/protocol-fixture.mjs';
    const host = document.querySelector('#host'), renderer = Web.create(undefined, undefined, host);
    const backend = Web.backend(renderer), handlers = new Map();
    const list = xs => xs.reduceRight((tl, hd) => ({hd, tl}), 0);
    let id = 0, generation = 0, ops = [], menu, form;
    const records = new Map();
    function create(kind, parent, props = {}) {
      const node = ++id;
      ops.push(Protocol.create_node_op(node, kinds.get(kind)));
      records.set(node, {parent, children: []});
      for (const [name, value] of Object.entries(props))
        ops.push(Protocol.set_prop_op(node, properties.get(name),
          {TAG: typeof value === 'string' ? 0 : 1, _0: value}));
      if (parent) {
        const children = records.get(parent).children;
        ops.push(Protocol.insert_child_op(parent, node, children.length));
        children.push(node);
      }
      return node;
    }
    function drop(node) {
      const parent = records.get(node).parent;
      ops.push(Protocol.remove_child_op(parent, node), Protocol.detach_subtree_op(node));
      records.get(parent).children = records.get(parent).children.filter(id => id !== node);
    }
    function flush() {
      if (ops.length) { const current = ops; ops = []; backend.apply_batch({generation: ++generation, ops: list(current)}); }
    }
    const root = create('column', null), filter = create('button', root,
      {text: 'Filter', 'press-enabled': true, 'accessibility-identifier': 'filter'});
    const popup = {'anchor': 'below', 'anchor-target': 'filter', transition: 'opacity 150ms ease, transform 150ms ease'};
    handlers.set(filter, () => {
      menu = create('popover', root, {...popup, role: 'menu', 'accessibility-identifier': 'options'});
      const between = create('button', menu, {text: 'Between', 'press-enabled': true});
      handlers.set(between, () => {
        form = create('popover', root, {...popup, 'accessibility-identifier': 'between-form'});
        const start = create('button', form, {text: 'Start date', 'press-enabled': true});
        handlers.set(start, () => window.picked++);
        handlers.set(form, () => drop(form));
        drop(menu);
      });
    });
    window.picked = 0;
    Web.set_event_handler(renderer, event => {
      if (event.TAG === 0 || event.TAG === 7) { handlers.get(event._0)?.(); flush(); }
      return true;
    });
    flush(); Web.mount(renderer, root, host);
  </script>`
  const server = createStaticServer(new URL('../../../', import.meta.url).pathname)
  server.listen(0, '127.0.0.1')
  await once(server, 'listening')
  const session = await createPlaywrightSession()
  try {
    const page = session.page
    await page.route('**/__replacement', route => route.fulfill({contentType: 'text/html', body: html}))
    await page.goto(`http://127.0.0.1:${server.address().port}/__replacement`)
    await page.getByRole('button', {name: 'Filter', exact: true}).click()
    await page.waitForTimeout(600)
    await page.getByRole('button', {name: 'Between', exact: true}).click()
    await page.waitForTimeout(1000)
    assert.equal(await page.locator('#options').count(), 0)
    assert.equal(await page.getByRole('button', {name: 'Start date'}).isVisible(), true)
    await page.getByRole('button', {name: 'Start date'}).click()
    assert.equal(await page.evaluate(() => window.picked), 1)
    await page.mouse.click(1200, 800)
    await page.waitForFunction(() => !document.querySelector('#between-form'))
  } finally {
    await session.close()
    await new Promise(resolve => server.close(resolve))
  }
})
