import assert from 'node:assert/strict'
import {once} from 'node:events'
import test, {before, after} from 'node:test'
import {createStaticServer} from '../../../tooling/serve_web.mjs'
import {createPlaywrightSession} from './playwright-session.mjs'

let server, session, page, origin, errors=[]
before(async()=>{
 session=await createPlaywrightSession();page=session.page;page.setDefaultTimeout(5000)
 page.on('pageerror',error=>errors.push(error.message))
 server=createStaticServer(new URL('../../../',import.meta.url).pathname);server.listen(0,'127.0.0.1');await once(server,'listening')
 origin=`http://127.0.0.1:${server.address().port}`
})
after(async()=>{await session?.close();if(server?.listening){const closed=once(server,'close');server.close();await closed}})
const frames=()=>page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))))
const root=()=>page.locator('.lui-virtual-list')
const row=key=>page.locator(`[data-vrow="${key}"]`)
async function open(extension=false){
 errors=[];await page.goto(`${origin}/platform/web/test/fixtures/virtual-rows-regression.html${extension?'?extension=1':''}`)
 await page.waitForFunction(()=>window.probe||window.fixtureError)
 assert.equal(await page.evaluate(()=>window.fixtureError),undefined)
}
async function settledAt(index){
 await page.waitForFunction(index=>{
  const state=window.probe.state(), r=document.querySelector(`[data-vrow="${index}"]`),root=document.querySelector('.lui-virtual-list')
  return state.last&&state.last.first<=index&&state.last.last>index&&r&&Math.abs(r.getBoundingClientRect().top-root.getBoundingClientRect().top)<2
 },index)
 assert.deepEqual(errors,[])
}
async function jump(index){await page.evaluate(index=>window.probe.jump(index),index);await settledAt(index)}
async function bounded(){const state=await page.evaluate(()=>window.probe.state());assert.ok(state.retainedRows<=20,JSON.stringify(state));assert.ok(state.nodes<=90,JSON.stringify(state));return state}

test('100k logical rows retain only the requested window and preserve full scroll extent',async()=>{
 await open();assert.ok(await root().evaluate(node=>node.scrollHeight)>3190000,'scroll extent covers the logical 100k source, not only mounted children')
 await page.waitForFunction(()=>window.probe.requests.length>0)
 await bounded();await jump(99980);await bounded()
 assert.equal(await row(0).count(),0)
 const requests=await page.evaluate(()=>window.probe.requests.length);await frames();await frames()
 assert.equal(await page.evaluate(()=>window.probe.requests.length),requests,'settled windows do not feed back indefinitely')
 await root().hover()
 // Firefox bounds a wheel event to roughly one viewport even for a large delta.
 for(let step=0;step<3;step++){await page.mouse.wheel(0,640);await frames()}
 await page.waitForFunction(()=>window.probe.state().last.last===100000)
 await bounded()
})

test('missing materialized rows occupy geometry until the source acknowledges the requested window',async()=>{
 await open();await page.evaluate(()=>window.probe.pause());await page.evaluate(()=>window.probe.jump(70000))
 await page.waitForFunction(()=>window.probe.state().last.first>69000)
 assert.equal(await row(70000).count(),0)
 assert.ok(await root().evaluate(node=>node.scrollHeight)>3190000)
 await page.evaluate(()=>window.probe.resume());await settledAt(70000);await bounded()
 assert.ok(await page.evaluate(()=>window.probe.events.some(event=>event.TAG===10&&event._2==='succeeded')))
})

test('focus pins edited rows and releases them after blur without losing controlled values',async()=>{
 await open();const editor=page.locator('#editor-2');await editor.fill('Persistent edit');await page.waitForFunction(()=>window.probe.values.get(2)==='Persistent edit')
 const retained=await editor.evaluate(node=>{window.retainedEditor=node;return node.id})
 await jump(50000)
 assert.equal(await editor.evaluate(node=>node===window.retainedEditor&&document.activeElement===node),true)
 assert.equal(await editor.inputValue(),'Persistent edit')
 assert.equal(retained,'editor-2');await bounded()
 const visible=await page.evaluate(()=>window.probe.events.filter(event=>event.TAG===11).at(-1));assert.ok(visible._1>49000,'VisibleRange excludes the offscreen focus pin')
 await page.locator('#outside').focus();await page.waitForFunction(()=>!document.querySelector('#editor-2'))
 await jump(2);assert.equal(await editor.inputValue(),'Persistent edit')
 assert.equal(await editor.evaluate(node=>node===window.retainedEditor),false)
})

test('a held pointer retains its source row independently of keyboard focus',async()=>{
 await open();await page.locator('#outside').focus()
 const target=page.locator('[data-hold="2"]'),box=await target.boundingBox()
 await page.mouse.move(box.x+3,box.y+3);await page.mouse.down();await jump(40000)
 assert.equal(await row(2).count(),1)
 assert.equal(await page.evaluate(()=>!!document.activeElement.closest('[data-vrow="2"]')),false)
 await page.mouse.up();await page.waitForFunction(()=>!document.querySelector('[data-vrow="2"]'))
 await bounded()
})

test('composition remains pinned after focus moves until compositionend',async()=>{
 await open();const editor=page.locator('#editor-2');await editor.focus()
 await editor.dispatchEvent('compositionstart',{data:'你'});await page.locator('#outside').focus();await jump(45000)
 assert.equal(await row(2).count(),1)
 await editor.dispatchEvent('compositionend',{data:'你'})
 await page.waitForFunction(()=>!document.querySelector('[data-vrow="2"]'));await bounded()
})

test('a portaled popup pins its owner and closing it releases the row',async()=>{
 await open();await page.locator('#menu-2').click();await page.locator('#popup-editor').waitFor()
 assert.equal(await page.locator('#popup-editor').evaluate(node=>!!node.closest('.lui-virtual-list')),false)
 await jump(55000);assert.equal(await row(2).count(),1);await page.locator('#popup-editor').fill('Still editable')
 assert.equal(await page.locator('#popup-editor').inputValue(),'Still editable')
 await page.keyboard.press('Escape');await page.locator('#outside').focus()
 await page.waitForFunction(()=>!document.querySelector('[data-vrow="2"]'));await bounded()
})

test('source revisions preserve the visible row and fractional offset through variable-height prepends',async()=>{
 await open();await page.evaluate(()=>window.probe.variable());await jump(1000)
 await root().hover();await page.mouse.wheel(0,13);await frames()
 const anchor=await root().evaluate(root=>{const top=root.getBoundingClientRect().top;const row=[...root.querySelectorAll('[data-vrow]')].find(row=>row.getBoundingClientRect().bottom>top);return{key:Number(row.dataset.vrow),top:row.getBoundingClientRect().top}})
 await page.evaluate(()=>window.probe.prepend(27))
 await page.waitForFunction(anchor=>{const node=document.querySelector(`[data-vrow="${anchor.key}"]`);return node&&Math.abs(node.getBoundingClientRect().top-anchor.top)<2},anchor)
 await bounded();assert.equal(await page.evaluate(()=>window.probe.state().last.generation),3)
})

test('resize, DOM recovery and empty source reissue current windows without stale geometry',async()=>{
 await open();await jump(6000);const before=await page.evaluate(()=>window.probe.state().last)
 await page.evaluate(()=>window.probe.resize(96));await page.waitForFunction(before=>window.probe.state().last.last-window.probe.state().last.first<before.last-before.first,before)
 const requests=await page.evaluate(()=>window.probe.state().requests);await page.evaluate(()=>window.probe.recover());await page.waitForFunction(before=>window.probe.state().requests>before,requests)
 await page.evaluate(()=>window.probe.shrink(0));await page.waitForFunction(()=>window.probe.state().retainedRows===0&&window.probe.state().last.first===0&&window.probe.state().last.last===0)
 assert.equal(await root().evaluate(node=>node.scrollTop),0);assert.equal(await root().locator('[data-vrow]').count(),0)
 const visible=await page.evaluate(()=>window.probe.events.filter(event=>event.TAG===11).at(-1));assert.deepEqual([visible._1,visible._2],[0,-1])
 assert.deepEqual(errors,[])
})


test('sparse scroll intents distinguish superseded, landed and missing logical targets',async()=>{
 await open();await page.evaluate(()=>window.probe.pause())
 const first=await page.evaluate(()=>window.probe.jump(80000))
 await page.waitForFunction(()=>window.probe.state().last.first>79000)
 const second=await page.evaluate(()=>window.probe.jump(85000))
 await page.waitForFunction(first=>window.probe.events.some(event=>event.TAG===10&&event._1===first&&event._2==='cancelled'),first)
 await page.evaluate(()=>window.probe.resume());await settledAt(85000)
 await page.waitForFunction(second=>window.probe.events.some(event=>event.TAG===10&&event._1===second&&event._2==='succeeded'),second)
 const missing=await page.evaluate(()=>window.probe.jump(100001))
 await page.waitForFunction(missing=>window.probe.events.some(event=>event.TAG===10&&event._1===missing&&event._2==='missing-target'),missing)
 await bounded();assert.deepEqual(errors,[])
})


const invalidMetadata=[
 ['missing total count',[['virtual-total-count',null]]],
 ['missing generation',[['virtual-generation',null]]],
 ['missing indices',[['virtual-indices',null]]],
 ['noncanonical spacing',[['virtual-indices','[0, 1,2,3,4,5,6,7,8]']]],
 ['duplicate index',[['virtual-indices','[0,1,2,3,4,5,6,7,7]']]],
 ['unsorted indices',[['virtual-indices','[0,1,2,3,4,5,6,8,7]']]],
 ['negative index',[['virtual-indices','[-1,1,2,3,4,5,6,7,8]']]],
 ['too few indices',[['virtual-indices','[]']]],
 ['index outside total',[['virtual-indices','[0,1,2,3,4,5,6,7,100000]']]],
 ['negative count',[['virtual-total-count',-1]]],
 ['zero generation',[['virtual-generation',0]]],
 ['scroll index outside total',[['virtual-scroll-index',100000]]],
 ['invalid missing-target sentinel',[['virtual-scroll-index',-2]]],
 ['scroll index without sparse mode',[['virtual-total-count',null],['virtual-generation',null],['virtual-indices',null]]],
]
for(const[name,changes]of invalidMetadata)test(`sparse metadata rejects ${name} atomically`,async()=>{
 await open();await page.waitForFunction(()=>window.probe.requests.length>0)
 const before=await page.locator('#editor-2').inputValue()
 const rejected=await page.evaluate(changes=>window.probe.invalid(changes),changes)
 assert.notEqual(rejected,false,'invalid final sparse relationship must reject the entire batch')
 assert.equal(await page.locator('#editor-2').inputValue(),before,'preceding control edit rolled back')
 assert.ok(await root().evaluate(node=>node.scrollHeight)>3190000)
 assert.deepEqual(errors,[])
})

test('sparse metadata validates at the final batch boundary rather than operation order',async()=>{
 await open();await page.waitForFunction(()=>window.probe.requests.length>0)
 await page.evaluate(()=>window.probe.appendMetadataFirst())
 assert.equal(await page.evaluate(()=>window.probe.rows.has(100)),true)
 assert.deepEqual(errors,[])
})


test('extension-root rows use parent sparse metadata without standard property writes',async()=>{
 await open(true);await page.waitForFunction(()=>window.probe.requests.length>0);await jump(72000)
 assert.equal(await row(72000).getAttribute('data-extension-row'),'true')
 assert.equal(await row(0).count(),0);await bounded();assert.deepEqual(errors,[])
})


test('switching through eager mode reissues the current sparse window for the new source',async()=>{
 await open();await page.waitForFunction(()=>window.probe.requests.length>0)
 const before=await page.evaluate(()=>window.probe.requests.length)
 await page.evaluate(()=>window.probe.rebind())
 await page.waitForFunction(before=>window.probe.requests.length>before,before)
 await bounded();assert.deepEqual(errors,[])
})
