import assert from 'node:assert/strict'
import test from 'node:test'
import {setTimeout as sleep} from 'node:timers/promises'

const build=process.env.LUI_TEST_BUILD_DIR??'_build'
const modules=new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`,import.meta.url)
const [App,Ui,Clock,Protocol,WebClock]=await Promise.all([
  import(new URL('lui/lui_app.js',modules)),
  import(new URL('lui/lui_ui.js',modules)),
  import(new URL('lui/lui_clock.js',modules)),
  import(new URL('lui/lui_protocol.js',modules)),
  import(new URL('lui.web.dom/core/lui_web_clock.js',modules)),
])

test('drive_clock fires view timers from browser timeouts',async()=>{
  const backend={backend_profile:Protocol.generic_profile(),apply_batch:()=>true}
  const view=(_context,model,send)=>(context,_parent)=>{
    Ui.after(context,20,()=>send(1))
    Ui.every(context,1000,()=>{})
    return Ui.column(context)
  }
  const app=App.create(undefined,undefined,backend,0,(model,step)=>model+step,view)
  try{
  assert.ok(App.start(app))
  App.flush(app)
  WebClock.drive(app)
  const clock=App.clock(app)
  assert.equal(Clock.pending(clock),2)
  await sleep(80)
  assert.equal(Clock.pending(clock),1,'the one-shot timer fired from its timeout')
  assert.ok(Clock.now(clock)>=20)
  assert.equal(App.model(app),1,'the timer action reached the reducer')
  }finally{App.dispose(app)}
})
