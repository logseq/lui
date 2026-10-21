import assert from 'node:assert/strict'
import test from 'node:test'

const build=process.env.LUI_TEST_BUILD_DIR??'_build'
const modules=new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`,import.meta.url)
const [Store,Protocol,Schema,Props]=await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js',modules)),
  import(new URL('lui/lui_protocol.js',modules)),
  import(new URL('lui/lui_wire_schema.js',modules)),
  import(new URL('lui.web.dom/render/lui_web_props.js',modules)),
])
const named=(values,nameOf,name)=>{
  for(let rest=values;rest;rest=rest.tl)if(nameOf(rest.hd)===name)return rest.hd
  throw Error(`Unknown schema value: ${name}`)
}
const height=named(Schema.all_properties,Schema.property_name,'height')
const list=values=>values.reduceRight((tl,hd)=>({hd,tl}),0)
for(const name of ['input','text-field','search-field'])test(`${name} supports explicit natural height without replacing its DOM node`,()=>{
  const kind=named(Schema.all_node_kinds,Schema.node_kind_name,name),styles=new Map()
  const element={style:{setProperty:(key,value)=>styles.set(key,value)}}
  const store=Store.create_store(),renderer={web_store:store}
  let generation=0
  const apply=ops=>Store.apply_batch(store,()=>element,{generation:++generation,ops:list(ops)})
  apply([Protocol.create_node_op(1,kind)])
  const set=value=>{
    apply([Protocol.set_prop_op(1,height,value)])
    Props.apply_property(renderer,()=>{},1,kind,element,height,value)
  }
  set({TAG:2,_0:40});assert.equal(styles.get('height'),'40px')
  set({TAG:0,_0:'auto'});assert.equal(styles.get('height'),'auto')
  set({TAG:2,_0:0});assert.equal(styles.get('height'),'0px')
  set({TAG:0,_0:'auto'});assert.equal(styles.get('height'),'auto')
  apply([Protocol.remove_prop_op(1,height)])
  Props.remove_property(renderer,()=>{},1,kind,element,height)
  assert.equal(styles.get('height'),'','Removal restores the component recipe')
  for(const value of ['inherit','AUTO','33.5px',''])
    assert.throws(()=>set({TAG:0,_0:value}),`reject unsupported height ${value}`)
})

const width=named(Schema.all_properties,Schema.property_name,'width')
for(const name of ['box','row','column'])test(`${name} switches between pixel and natural width without replacing its DOM node`,()=>{
  const kind=named(Schema.all_node_kinds,Schema.node_kind_name,name),styles=new Map()
  const element={style:{setProperty:(key,value)=>styles.set(key,value)}}
  const store=Store.create_store(),renderer={web_store:store}
  let generation=0
  const apply=ops=>Store.apply_batch(store,()=>element,{generation:++generation,ops:list(ops)})
  apply([Protocol.create_node_op(1,kind)])
  const set=value=>{
    apply([Protocol.set_prop_op(1,width,value)])
    Props.apply_property(renderer,()=>{},1,kind,element,width,value)
  }
  for(const value of [120,'auto',0,'auto']){
    set({TAG:typeof value==='string'?0:2,_0:value})
    assert.equal(styles.get('width'),typeof value==='string'?value:`${value}px`)
  }
  apply([Protocol.remove_prop_op(1,width)])
  Props.remove_property(renderer,()=>{},1,kind,element,width)
  assert.equal(styles.get('width'),'')
  for(const value of ['inherit','AUTO','33.5px',''])
    assert.throws(()=>set({TAG:0,_0:value}),`reject unsupported width ${value}`)
})
