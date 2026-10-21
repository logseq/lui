import assert from 'node:assert/strict'
import test from 'node:test'
import {readFile} from 'node:fs/promises'

const build=process.env.LUI_TEST_BUILD_DIR??'_build'
const modules=new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`,import.meta.url)
const [Store,Protocol,Schema,Events,Tables]=await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js',modules)),
  import(new URL('lui/lui_protocol.js',modules)),
  import(new URL('lui/lui_wire_schema.js',modules)),
  import(new URL('lui.web.dom/events/lui_web_events.js',modules)),
  import(new URL('melange/hashtbl.js',modules)),
])
const schema=JSON.parse(await readFile(new URL('../../../schema/components.json',import.meta.url)))
const press=schema.events.findIndex(event=>event.lg==='Press')
const find=(list,nameOf,name)=>{
  for(let rest=list;rest;rest=rest.tl)if(nameOf(rest.hd)===name)return rest.hd
  throw Error(`Missing schema entry ${name}`)
}
const kind=find(Schema.all_node_kinds,Schema.node_kind_name,'link')
const property=name=>find(Schema.all_properties,Schema.property_name,name)
const list=values=>values.reduceRight((tl,hd)=>({hd,tl}),0)

function fixture(){
  const store=Store.create_store(),events=[],listeners=new Map()
  const element={setAttribute(){},addEventListener(name,callback){listeners.set(name,callback)}}
  const renderer={web_store:store,web_event_handler:{contents:event=>{events.push(event);return true}},
    web_context_hosts:Tables.create(undefined,4),web_pointer_cleanups:Tables.create(undefined,4),
    web_document:{},web_appear_pending:Tables.create(undefined,4),web_appear_seen:Tables.create(undefined,4),
    web_appear_timer:{contents:undefined}}
  let generation=0
  const apply=ops=>Store.apply_batch(store,()=>element,{generation:++generation,ops:list(ops)})
  apply([Protocol.create_node_op(1,kind)])
  const set=(name,value)=>apply([Protocol.set_prop_op(1,property(name),{TAG:1,_0:value})])
  const remove=name=>apply([Protocol.remove_prop_op(1,property(name))])
  Events.attach_events(renderer,1,kind,element)
  const send=(name,fields={})=>{
    events.length=0;let prevented=false
    listeners.get(name)?.({button:0,key:'',detail:1,metaKey:false,ctrlKey:false,altKey:false,shiftKey:false,
      ...fields,preventDefault(){prevented=true}})
    return {prevented,events:events.map(event=>({tag:event.TAG,node:event._0}))}
  }
  return {set,remove,send}
}

test('URL-only links keep browser navigation and disabled links prevent it',()=>{
  const f=fixture()
  assert.deepEqual(f.send('click'),{prevented:false,events:[]})
  f.set('enabled',false)
  assert.deepEqual(f.send('click'),{prevented:true,events:[]})
  f.remove('enabled')
  assert.deepEqual(f.send('click'),{prevented:false,events:[]})
})

test('Link actions own primary activation and retain their listener across capability changes',()=>{
  const f=fixture(),activation={prevented:true,events:[{tag:press,node:1}]}
  assert.doesNotThrow(()=>f.set('press-enabled',true))
  assert.deepEqual(f.send('click'),activation)
  for(const modifier of ['metaKey','ctrlKey','shiftKey','altKey'])
    assert.deepEqual(f.send('click',{[modifier]:true}),activation)
  assert.deepEqual(f.send('click',{button:1}),{prevented:false,events:[]})
  assert.deepEqual(f.send('keydown',{key:'Enter'}),activation)
  assert.deepEqual(f.send('keydown',{key:' '}),{prevented:false,events:[]})
  f.set('enabled',false)
  assert.deepEqual(f.send('click'),{prevented:true,events:[]})
  f.set('enabled',true);f.remove('press-enabled')
  assert.deepEqual(f.send('click'),{prevented:false,events:[]})
  assert.deepEqual(f.send('keydown',{key:'Enter'}),{prevented:false,events:[]})
  f.set('press-enabled',true)
  assert.deepEqual(f.send('click'),activation)
})
